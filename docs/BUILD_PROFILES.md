# Build profiles

This repo can build a lot of KernelSU-family roots (SukiSU, BakaSU,
Official KernelSU, SukiSU-Next, legacy pinned SukiSU snapshots...) across
five Android/kernel branches, each with its own matrix of optional
patches. The existing per-branch workflows (`kernel-a13-5-15.yml` etc.)
expose most of that as `workflow_dispatch` inputs, but their **sublevel
matrix is hardcoded in the YAML** — every dispatch builds ~20 sublevels
whether you want them or not.

**`build-profile.yml`** exists to build exactly one named, saved target
instead. A profile is a plain `key=value` file in `config/profiles/`.
Pick one from the `profile` dropdown on that workflow's "Run workflow"
page (or trigger it from `console.html`), and it builds only that.

## Why this exists

Before this, getting a single accurate build meant: trimming the matrix
by hand on a throwaway branch, re-deriving the right sublevel/variant/
manager-compat combination from scratch, and never saving any of it.
Profiles make that work durable and reusable — write it once, anyone
(human or AI) can read the profile file and know exactly what a given
build target needs, without archaeology through git history or GitHub
Actions logs.

## Profile file format

See `config/profiles/exia-206.yml` for a fully worked, validated example.
Keys map directly to `build.yml`'s `workflow_call` inputs (see that file
for the authoritative list and defaults) plus two profile-only keys:

- `stock_defconfig` — path to a saved `/proc/config.gz` dump (decompressed)
  for this target, or empty. If set, `build-profile.yml` copies it to
  `config/stock_defconfig` before calling `build.yml`, which makes the
  built kernel's own `/proc/config.gz` mimic the real device instead of
  a generic GKI defconfig. **Only pullable from a device while it's still
  on its stock, unmodified kernel** — there's no recovering this after
  flashing, so grab it early if you're setting up a profile for a new
  device.
- `source_ref` — pins `kernel/common` to an exact upstream tag (e.g.
  `android13-5.15-2026-06_r3`), instead of relying on `os_patch_level`
  resolving to *some* revision of that month (which can land on a
  different, slightly newer `_rN` than the one a specific stock kernel
  was actually built from). To find the right tag for a real device:
  take the `g<hash>` fragment from `cat /proc/version` or the kernel
  version string in `getprop ro.build.fingerprint`-adjacent output, then
  `git ls-remote --tags https://android.googlesource.com/kernel/common`
  and find the tag whose dereferenced commit starts with that hash.

## Manager/kernel compatibility — the thing that actually matters

This is the root cause of "I flashed it but root/module options don't
show, only Home tab" — documented here because it's non-obvious and easy
to get backwards.

SukiSU-Ultra's manager app does **not** do a "kernel version >= minimum"
check. Its `Natives.kt` (`isFullFeatured()`) requires
`kernelUAPIVersion == managerUAPIVersion` — an **exact equality**. This is
a small protocol integer (`KERNEL_SU_UAPI_VERSION` in `uapi/supercall.h`,
currently `6`), separate from the big cosmetic version numbers you see in
variant names like `SukiSU(40726)`. If the kernel's build is older than
the point that protocol field was introduced, or just meaningfully older
than whatever commit the installed manager APK was built from, the
manager silently collapses to Home-tab-only instead of erroring — easy to
mistake for a flashing/patch problem when it's actually a source mismatch.

**Practical rule:** keep `kernelsu_variant=SukiSU` unpinned (tracks the
`builtin` branch HEAD) so it stays in sync with whatever manager APK is
currently installed, *unless* a specific upstream regression forces a
temporary pin — and if you do pin one, note the date/reason in the
profile file like `exia-206.yml` does, so a future build doesn't
accidentally stay pinned past the point the regression was fixed.

BakaSU is a structurally different project (own repo, own manager APK,
own versionCode formula) — whether it has the same strict equality gate
hasn't been checked yet. Verify against `Baka-SU/BakaSU`'s own manager
source before assuming it behaves like SukiSU's.

## Disguised/spoofed manager apps (random package name) not getting recognized at all

Separate issue from the UAPI version gate above, and easy to confuse with it: a manager APK built by the
`Manager-spoofed` pipeline (package name randomized to 3-4 random words, see `SukiSU-Ultra/SukiSU-Ultra`'s
`build-manager.yml` "Run randomizer" step) can show "No SukiSU kernel detected / preview mode" even on a
perfectly correct, matching-UAPI kernel. Root (`su`) still works fine in this state — it's specifically the
app's own "am I the manager" check that fails, a different code path from plain root.

Root cause, confirmed 2026-11-01 by reading `kernel/manager/throne_tracker.c` + `apk_sign.c` and
`kernel/extension/dynamic_sig_fallback.c` in `SukiSU-Ultra/SukiSU-Ultra`:

- The kernel hardcodes trusted manager signing-certificate SHA-256 hashes (`apk_sign.c`'s `apk_sign_keys[]`,
  one per supported root project). A spoofed APK's signature is still one of these valid hashes — spoofing
  only renames the package, it doesn't re-sign with a different key.
- But `track_throne()`'s default path only ever *checks* an app's signature if that app's package name
  exactly equals the compile-time constant `KSU_PACKAGE_NAME` (`kernel/Makefile`, defaults to
  `com.sukisu.ultra`; this repo's `build.yml` never overrides it). A randomly-named spoofed app is skipped
  before its signature is ever examined.
- There's a disabled-by-default kernel extension, `dynamic_manager` (the "signature fallback"), made for
  exactly this: it re-scans `/data/app` and crowns *any* app with a trusted signature, regardless of package
  name.

**Fix procedure** (do all of this, in order — skipping any step leaves it broken):

1. Make sure the plain, un-spoofed manager (`com.sukisu.ultra`) is **not installed**. If it is, remove it —
   `track_throne()` always prefers an exact `KSU_PACKAGE_NAME` match when one exists and never even attempts
   the fallback scan in that case.
2. `adb shell su -c "/data/adb/ksu/bin/ksud extension set dynamic_manager 1"` then
   `... ksud extension save` — `set` alone does not survive reboot despite the extension claiming
   `persist=1`; `save` writes it to `/data/adb/ksu/.extension_config`.
3. Re-run the scan: `adb shell su -c "/data/adb/ksu/bin/ksud post-fs-data"` (or just reboot).
4. **The scan locks onto the first validly-signed APK it finds under `/data/app` and caches that choice
   permanently** ("manager uid=X still installed, skip search!" in dmesg on every later run) — so any other
   old spoofed manager APK from a previous build/session, still installed, will win the race if the kernel
   happens to enumerate it first. Find and uninstall every other app sharing the SukiSU signing cert before
   expecting the current one to get picked. To see exactly what got crowned and why:
   `adb shell su -c "dmesg | grep -iE 'sig_fallback|crowning|manager uid'"`.
5. Force-stop and relaunch the manager app. It should now show "Built-in — Working — Version: <ksuVer>".

None of this needs a kernel rebuild — it's entirely on-device, post-flash configuration. `ksud debug
set-manager <pkg>` looks like a shortcut for steps 1-4 but requires `CONFIG_KSU_DEBUG`, deliberately not
enabled in a production kernel build — don't reach for it as the "real" fix.

## Known pitfalls (hit and fixed 2026-11-01, keep an eye out for recurrence)

1. **Floating `lts`/`X` sublevel can drift ahead of SUSFS's patch base.**
   `ShirkNeko/susfs4ksu`'s `gki-android13-5.15` branch gets rebased onto a
   specific upstream tag periodically (its commit messages say which). If
   you build against the live `lts` branch and it has moved past that
   rebase point, the SUSFS patch's hunks against `fs/namespace.c` /
   `fs/proc/task_mmu.c` can fail outright, producing
   `implicit declaration of function 'SUSFS_IS_INODE_SUS_MAP'` compile
   errors. A fixed, real sublevel (via `sub_level`/`os_patch_level`, ideally
   pinned further with `source_ref`) doesn't have this problem.
2. **Old pinned SukiSU commits can predate the `uapi_version` protocol
   field entirely** (see manager-compatibility section above) — don't
   reach for `config/SukiSU(40726).config` / `SukiSU(40548).config` or a
   stale `config/config` pin as a "safe" fallback without checking what
   regression they were for and whether it's still relevant.
3. The per-branch kernel workflows' matrices are hardcoded and build
   everything on every dispatch — always use `build-profile.yml` (or a
   deliberately trimmed throwaway branch, if a profile doesn't fit) for a
   single targeted build, not the full matrix workflows.

## Adding a new profile

1. Copy `config/profiles/exia-206.yml` as a starting point.
2. Fill in the real values for the new target (device, variant, sublevel
   — see the `source_ref` section above for finding an exact tag).
3. If it's for a physical device, pull `/proc/config.gz` from it *while
   still on its stock kernel* and save it under `config/stock/`, then
   point `stock_defconfig` at that path.
4. Add the profile's filename (without `.yml`) to the `profile` dropdown
   `options:` list in `.github/workflows/build-profile.yml`.
5. Note anything non-obvious you had to figure out (regressions worked
   around, manager compat quirks, why a particular sublevel) directly in
   the profile file's header comment — that's what makes the next build
   not require re-deriving everything from scratch.
