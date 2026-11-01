#!/usr/bin/env bash
# 由 apply.sh 在内核 common/ 目录下 source，补上 SUSFS 主补丁"头部 hunk 失配"造成的缺声明。
#
# 为什么单独放一个文件：
#   上游 ab5f5fa(2026-09-11, "simplify SUSFS compatibility fixes") 把这批修复从 apply.sh 删掉了，
#   因为上游只构建它测试过的子版本。本仓库会构建上游没测的子版本(例如 android13-5.15.206 / 2026-06)，
#   那里 namespace.c / task_mmu.c / base.c / memory.c / exec.c 开头的 hunk 仍会失配，
#   不补 susfs_def.h 与相关 extern 就会编译失败 (implicit declaration of SUSFS_IS_INODE_SUS_MAP 等)。
#   单独成文件，以后同步上游时 apply.sh 再被改写也不会把它冲掉。
#
# 每一段都是幂等的：只有在"源码已经用到 SUSFS 符号、却没有 susfs_def.h"时才注入，
# 能干净打上补丁的内核不受影响。依赖 apply.sh 里的 ANDROID_VERSION / KERNEL_VERSION。

fix_namespace_susfs_mount_decls() {
  local label="$1"
  local marker_pattern="$2"

  if ! grep -q "$marker_pattern" ./fs/namespace.c; then
    return
  fi

  if ! grep -qF '#include <linux/susfs_def.h>' ./fs/namespace.c; then
    echo "检测到 ${label} namespace.c 缺少 susfs_def.h，注入声明..."
    if grep -qF '#include <linux/mnt_idmapping.h>' ./fs/namespace.c; then
      sed -i '/#include <linux\/mnt_idmapping.h>/a #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n#include <linux\/susfs_def.h>\n#endif' ./fs/namespace.c
    elif grep -qF '#include <linux/shmem_fs.h>' ./fs/namespace.c; then
      sed -i '/#include <linux\/shmem_fs.h>/a #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n#include <linux\/susfs_def.h>\n#endif' ./fs/namespace.c
    else
      sed -i '0,/^#include /s//#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n#include <linux\/susfs_def.h>\n#endif\n&/' ./fs/namespace.c
    fi
  fi

  if ! grep -q 'extern bool susfs_is_current_ksu_domain' ./fs/namespace.c; then
    echo "检测到 ${label} namespace.c 缺少 SUSFS mount extern，注入声明..."
    sed -i '/#include "internal.h"/a \\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\nextern bool susfs_is_current_ksu_domain(void);\nextern struct static_key_true susfs_is_sdcard_android_data_not_decrypted;\n\n#define CL_COPY_MNT_NS BIT(25)\n\n#endif' ./fs/namespace.c
  fi
}

# Android 13 - 5.15 修复
if [[ "$ANDROID_VERSION" == "android13" && "$KERNEL_VERSION" == "5.15" ]]; then
  # 修复 5.15 LTS: task_mmu.c 头部 hunk 失配，导致 SUSFS 宏缺少声明
  if grep -q 'SUSFS_IS_INODE_SUS_MAP\|SUSFS_IS_INODE_OPEN_REDIRECT' ./fs/proc/task_mmu.c && ! grep -qF '#include <linux/susfs_def.h>' ./fs/proc/task_mmu.c; then
    if grep -qF '#include <linux/pkeys.h>' ./fs/proc/task_mmu.c; then
      sed -i '/#include <linux\/pkeys.h>/a #if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux\/susfs_def.h>\n#endif' ./fs/proc/task_mmu.c
    elif grep -qF '#include <linux/uaccess.h>' ./fs/proc/task_mmu.c; then
      sed -i '/#include <linux\/uaccess.h>/a #if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux\/susfs_def.h>\n#endif' ./fs/proc/task_mmu.c
    else
      sed -i '0,/^#include /s//#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux\/susfs_def.h>\n#endif\n&/' ./fs/proc/task_mmu.c
    fi
    echo "已修复 Android 13 5.15 task_mmu.c 缺少 susfs_def.h 问题"
  fi
  # 修复 5.15 LTS: namespace.c 头部 hunk 失配，导致 SUSFS mount 符号缺少声明
  fix_namespace_susfs_mount_decls "Android 13 5.15" 'DEFAULT_KSU_MNT_ID\|VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT\|CL_COPY_MNT_NS'
fi

# Android 14 - 6.1 修复
if [[ "$ANDROID_VERSION" == "android14" && "$KERNEL_VERSION" == "6.1" ]]; then
  if grep -q 'susfs_is_current_proc_umounted\|SUSFS_IS_INODE_SUS_MAP\|SUSFS_IS_INODE_OPEN_REDIRECT' ./fs/proc/base.c && ! grep -qF '#include <linux/susfs_def.h>' ./fs/proc/base.c; then
    if grep -qF '#include <linux/dma-buf.h>' ./fs/proc/base.c; then
      sed -i '/#include <linux\/dma-buf.h>/a #if defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux\/susfs_def.h>\n#endif' ./fs/proc/base.c
    else
      sed -i '/#include <linux\/cpufreq_times.h>/a #if defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux\/susfs_def.h>\n#endif' ./fs/proc/base.c
    fi
  fi
  # 修复 6.1 LTS: namespace.c 头部 hunk 失配，导致 SUSFS mount 符号缺少声明
  fix_namespace_susfs_mount_decls "Android 14 6.1" 'DEFAULT_KSU_MNT_ID\|susfs_mnt_id_ida'
fi

# Android 15 - 6.6 修复
if [[ "$ANDROID_VERSION" == "android15" && "$KERNEL_VERSION" == "6.6" ]]; then
  # 修复 6.6.50~6.6.97: fs/proc/base.c 头部 hunk 失配，导致 susfs_def.h 漏打
  if grep -q 'AS_FLAGS_SUS_MAP\|susfs_is_current_proc_umounted\|SUSFS_IS_INODE_SUS_MAP\|SUSFS_IS_INODE_OPEN_REDIRECT' ./fs/proc/base.c && ! grep -qF 'susfs_def.h' ./fs/proc/base.c; then
    if ! grep -qF '#include <linux/dma-buf.h>' ./fs/proc/base.c; then
      sed -i '/#include <linux\/cpufreq_times.h>/a #include <linux\/dma-buf.h>' ./fs/proc/base.c
    fi
    sed -i '/#include <linux\/dma-buf.h>/a #endif' ./fs/proc/base.c
    sed -i '/#include <linux\/dma-buf.h>/a #include <linux\/susfs_def.h>' ./fs/proc/base.c
    sed -i '/#include <linux\/dma-buf.h>/a #if defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)' ./fs/proc/base.c
  fi
  # 修复 6.6 早期分支: memory.c 头部上下文缺少 zswap.h，导致 SUSFS 头文件 hunk 漏打
  if grep -q 'SUSFS_IS_INODE_SUS_MAP' ./mm/memory.c && ! grep -qF '#include <linux/susfs_def.h>' ./mm/memory.c; then
    if grep -qF '#include <linux/zswap.h>' ./mm/memory.c; then
      sed -i '/#include <linux\/zswap.h>/a #ifdef CONFIG_KSU_SUSFS_SUS_MAP\n#include <linux\/susfs_def.h>\n#endif' ./mm/memory.c
    else
      sed -i '/#include <linux\/sched\/sysctl.h>/a #ifdef CONFIG_KSU_SUSFS_SUS_MAP\n#include <linux\/susfs_def.h>\n#endif' ./mm/memory.c
    fi
  fi
fi

# Android 16 - 6.12 修复
if [[ "$ANDROID_VERSION" == "android16" && "$KERNEL_VERSION" == "6.12" ]]; then
  # 修复 6.12.58+: exec.c 头部上下文变化导致 SUSFS 补丁漏掉 susfs_def.h
  if grep -q 'susfs_is_current_proc_umounted' ./fs/exec.c && ! grep -qF '#include <linux/susfs_def.h>' ./fs/exec.c; then
    if grep -qF '#include <linux/dma-buf.h>' ./fs/exec.c; then
      sed -i '/#include <linux\/dma-buf.h>/a #ifdef CONFIG_KSU_SUSFS\n#include <linux\/susfs_def.h>\n#endif' ./fs/exec.c
    else
      sed -i '/#include <linux\/ksm.h>/a #ifdef CONFIG_KSU_SUSFS\n#include <linux\/susfs_def.h>\n#endif' ./fs/exec.c
    fi
    echo "已修复 exec.c 缺少 susfs_def.h 问题"
  fi
fi
