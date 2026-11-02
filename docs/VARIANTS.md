# KernelSU variant comparison

What each `kernelsu_variant` choice (in `kernel-a*.yml` / `kernel-custom.yml` dispatch forms, and the
`kernelsu_variant` key in a [build profile](BUILD_PROFILES.md)) actually gets you. GitHub's own "Run
workflow" form only shows one short description line per field — it can't show this table inline, so it's
kept here and linked from the workflow's description instead.

Sourced directly from each project's own `docs/README.md` (2026-11-02), plus this repo's `build.yml` for
what's actually wired up on the build side (a feature existing upstream doesn't mean this repo's pipeline
exposes it).

| | **SukiSU** (`SukiSU-Ultra/SukiSU-Ultra`, `main`/`builtin` branch) | **BakaSU** (`Baka-SU/BakaSU`, formerly ReSukiSU) | **Official** (`tiann/KernelSU`) |
|---|---|---|---|
| Relationship | Fork of KernelSU, independently maintained | Downstream of KernelSU, "personal changes" fork | Upstream original |
| Root/su | Kernel-based `su` + App Profile (per-app root cage) | Same, + App Profile | Same |
| Module system | Classic KernelSU modules | **Metamodules** — a newer pluggable systemless-mod infrastructure | Classic modules |
| SUSFS | Built-in SUSFS management + one-click root hiding + themeable manager | SUSFS backport down to kernel **4.3+** (wider low-version support than SukiSU) | Not built in (this repo layers SUSFS on separately for every variant) |
| KPM (loadable kernel patch modules) | **Yes** — primary focus, actively developed (`ShirkNeko/SukiSU_KernelPatch_patch`) | Not listed as a feature upstream. **This repo's build script still attempts it for BakaSU** (same code path as SukiSU) but will hard-fail the build (`exit 1`) if the cloned BakaSU source doesn't declare `CONFIG_KPM` that day — treat as "maybe, unverified" rather than relying on it | **No** — explicitly excluded from the KPM code path in this repo's `build.yml` |
| Manager flexibility | One manager app, tightly version-matched (`kernelUAPIVersion == managerUAPIVersion`, see [BUILD_PROFILES.md](BUILD_PROFILES.md#manager-kernel-compatibility--the-thing-that-actually-matters)) | **Multi-manager support**: can use the Official KernelSU manager or KOWSU's manager as an alternative to its own — potentially less brittle than SukiSU's single-manager signature lock, not yet tested against this repo's spoofed-manager issue | Official manager only |
| Hook modes | Not separately documented (SUSFS inline hooks when SUSFS is on) | Three explicit modes: Tracepoint Syscall Redirect (GKI2 only), Manual Hook (kernel 3.4–6.18, most compatible), SUSFS Inline Hook | Tracepoint-based |
| Non-GKI / old kernel support | 4.14+ manual build; 3.4–3.18 with extra backports | 3.4+ manual build | Varies |

## What this repo's build pipeline actually enforces

- `kernelsu_variant` choices wired up in `build.yml`: `Official`, `SukiSU`, `SukiSU(40726)`, `SukiSU(40548)`
  (two maintainer-pinned old SukiSU+SUSFS commit pairs — see [BUILD_PROFILES.md](BUILD_PROFILES.md) for why
  pinned builds can miss newer protocol fields like `uapi_version`), `BakaSU`, `Next` (KernelSU-Next, present
  in the dropdown but commented out in `kernel-a13-5-15.yml` as of 2026-11-02).
- KPM (`use_kpm: enabled`) is attempted for `SukiSU*`, `BakaSU`, `Next` — never `Official`.
- SUSFS gets layered onto every variant separately by this repo (cloned from `ShirkNeko/susfs4ksu` for
  `SukiSU`, `simonpunk/susfs4ksu` otherwise) — it is not a variant-exclusive feature here, unlike how the
  upstream README copy above frames it as "built into SukiSU."

## Picking a variant

- Matching an existing manager app you already have installed and like → match that app's project
  (SukiSU manager ↔ `SukiSU` variant, BakaSU manager ↔ `BakaSU` variant). Mixing them (e.g. BakaSU kernel +
  SukiSU manager) is untested here.
- Want KPM, reliably → `SukiSU` (unpinned). Treat `BakaSU` + KPM as experimental until actually built and
  confirmed.
- Building for an older/non-GKI device → `BakaSU` has the deepest backport range (SUSFS to 4.3+, manual-hook
  mode down to 3.4).
- See [BUILD_PROFILES.md](BUILD_PROFILES.md) for the manager/kernel UAPI-version gate and the disguised/spoofed
  manager fix — both documented against `SukiSU`; re-verify against `BakaSU`'s own manager source
  (`kernel/manager/` in `Baka-SU/BakaSU`) before assuming identical behavior, since it's a separate codebase.

## "Manager shows preview mode / root options missing" — two different causes, don't conflate them

Both are fully written up in [BUILD_PROFILES.md](BUILD_PROFILES.md), linked here because this is where people
compare variants and land first:

1. **[Manager/kernel UAPI version mismatch](BUILD_PROFILES.md#manager-kernel-compatibility--the-thing-that-actually-matters)**
   — the manager requires `kernelUAPIVersion == managerUAPIVersion` exactly. Happens with old pinned kernel
   builds (e.g. `SukiSU(40726)`/`SukiSU(40548)`) against a current manager APK.
2. **[Disguised/spoofed manager package-name issue](BUILD_PROFILES.md#disguised-spoofed-manager-apps-random-package-name-not-getting-recognized-at-all)**
   — a *correctly matching* kernel still won't recognize a randomly-renamed manager app by default, because
   the kernel's manager-scan only checks apps named exactly `com.sukisu.ultra` unless the `dynamic_manager`
   extension is explicitly enabled on-device, and even then it locks onto the first validly-signed APK it
   finds — stale duplicate spoofed installs from past sessions can silently keep winning. Confirmed fixed
   2026-11-01; full on-device procedure in the linked section.
