#!/usr/bin/env bash
# Build script — POCO C85 5G (dew) custom GKI kernel
# Integrates: ReSukiSU + SUSFS4KSU + AnyKernel3
# Kernel   : GKI android15-6.6 via AOSP repo sync (Bazel/Kleaf build)
# Boot     : Proper boot.img header_version 4 + AVB footer (mkbootimg)
#
# KEY FIX vs previous build.sh:
#   Old: git clone kernel + make Image → raw Image flashed directly (bootloop)
#   New: repo sync full AOSP workspace + Bazel → proper boot.img (correct)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Configurable ──────────────────────────────────────────────────────────────
# android15-6.6-89 = kernel 6.6.89, os_patch 2025-06 — matches stock HyperOS
ANDROID_VERSION="${ANDROID_VERSION:-android15}"
KERNEL_VERSION="${KERNEL_VERSION:-6.6}"
SUB_LEVEL="${SUB_LEVEL:-89}"
OS_PATCH_LEVEL="${OS_PATCH_LEVEL:-2025-06}"

ENABLE_SUSFS="${ENABLE_SUSFS:-true}"
ENABLE_ZRAM="${ENABLE_ZRAM:-true}"
ENABLE_BBG="${ENABLE_BBG:-false}"
ENABLE_KPM="${ENABLE_KPM:-false}"
LTO="${LTO:-thin}"

JOBS="${JOBS:-$(nproc)}"

# ── Derived paths ──────────────────────────────────────────────────────────────
CONFIG="${ANDROID_VERSION}-${KERNEL_VERSION}-${SUB_LEVEL}"
KERNEL_ROOT="${SCRIPT_DIR}/${CONFIG}"
DEFCONFIG="${KERNEL_ROOT}/common/arch/arm64/configs/gki_defconfig"
AK3_DIR="${SCRIPT_DIR}/AnyKernel3"
SUSFS_DIR="${SCRIPT_DIR}/susfs4ksu"
SUKISU_PATCH_DIR="${SCRIPT_DIR}/SukiSU_patch"
BUILD_TOOLS_DIR="${SCRIPT_DIR}/kernel-build-tools"
MKBOOTIMG_DIR="${SCRIPT_DIR}/mkbootimg"
REPO_DIR="${SCRIPT_DIR}/git-repo"
REPO_BIN="${REPO_DIR}/repo"
AVBTOOL="${BUILD_TOOLS_DIR}/linux-x86/bin/avbtool"
MKBOOTIMG_PY="${MKBOOTIMG_DIR}/mkbootimg.py"
BOOT_SIGN_KEY="${BUILD_TOOLS_DIR}/linux-x86/share/avb/testkey_rsa2048.pem"

# ── Logging ────────────────────────────────────────────────────────────────────
info()  { printf '\033[1;36m[INFO]\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
err()   { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }
step()  { printf '\n\033[1;35m━━ %s ━━\033[0m\n' "$*"; }

# ── Clean command ──────────────────────────────────────────────────────────────
if [[ "${1:-}" == "clean" ]]; then
    step "Cleaning build artifacts"
    for d in "$KERNEL_ROOT" "$AK3_DIR" "$SUSFS_DIR" "$SUKISU_PATCH_DIR" \
              "$BUILD_TOOLS_DIR" "$MKBOOTIMG_DIR" "$REPO_DIR"; do
        [[ -d "$d" ]] && info "Removing $(basename "$d") ..." && rm -rf "$d"
    done
    for zip in "${SCRIPT_DIR}"/ReSukiSU_*.zip; do
        [[ -f "$zip" ]] && info "Removing $(basename "$zip")" && rm -f "$zip"
    done
    [[ -f "${SCRIPT_DIR}/build.log" ]] && rm -f "${SCRIPT_DIR}/build.log"
    ok "Clean complete"
    exit 0
fi

# ── 1. System dependencies ─────────────────────────────────────────────────────
step "System dependencies"
MISSING=()
for cmd in git curl python3 openssl zip; do
    command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done
[[ ${#MISSING[@]} -gt 0 ]] && err "Missing: ${MISSING[*]} — install with your package manager"
ok "All required tools present"

# ── 2. AOSP build tools (avbtool, mkbootimg) ──────────────────────────────────
step "AOSP build tools"
AOSP_BRANCH="main-kernel-build-2024"
if [[ ! -x "${BUILD_TOOLS_DIR}/linux-x86/bin/avbtool" ]]; then
    info "Cloning kernel/prebuilts/build-tools ..."
    git clone https://android.googlesource.com/kernel/prebuilts/build-tools \
        -b "$AOSP_BRANCH" --depth=1 "$BUILD_TOOLS_DIR"
else
    info "build-tools already present"
fi
if [[ ! -f "${MKBOOTIMG_DIR}/mkbootimg.py" ]]; then
    info "Cloning platform/system/tools/mkbootimg ..."
    git clone https://android.googlesource.com/platform/system/tools/mkbootimg \
        -b "$AOSP_BRANCH" --depth=1 "$MKBOOTIMG_DIR"
else
    info "mkbootimg already present"
fi

# Generate a fresh RSA signing key (AVB requires signed boot images)
info "Generating AVB signing key ..."
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$BOOT_SIGN_KEY" 2>/dev/null
ok "Build tools ready"

# ── 3. repo binary ─────────────────────────────────────────────────────────────
step "repo tool"
if [[ ! -x "$REPO_BIN" ]]; then
    info "Downloading repo ..."
    mkdir -p "$REPO_DIR"
    curl -LSs https://storage.googleapis.com/git-repo-downloads/repo -o "$REPO_BIN"
    chmod 0755 "$REPO_BIN"
fi
ok "repo ready: $("$REPO_BIN" --version 2>&1 | head -1)"

# ── 4. Auxiliary repos (AnyKernel3, SUSFS, SukiSU_patch) ──────────────────────
step "Auxiliary repos"

if [[ ! -d "$AK3_DIR/.git" ]]; then
    info "Cloning WildKernels/AnyKernel3 (gki-2.0) ..."
    git clone https://github.com/WildKernels/AnyKernel3.git -b gki-2.0 "$AK3_DIR"
else
    info "AnyKernel3 already cloned — updating ..."
    git -C "$AK3_DIR" pull --ff-only || true
fi

SUSFS_BRANCH="gki-${ANDROID_VERSION}-${KERNEL_VERSION}"
if [[ ! -d "$SUSFS_DIR/.git" ]]; then
    info "Cloning susfs4ksu (branch: $SUSFS_BRANCH) ..."
    git clone https://gitlab.com/simonpunk/susfs4ksu.git -b "$SUSFS_BRANCH" "$SUSFS_DIR"
else
    info "susfs4ksu already cloned"
fi

if [[ ! -d "$SUKISU_PATCH_DIR/.git" ]]; then
    info "Cloning ShirkNeko/SukiSU_patch (LZ4K + patches) ..."
    git clone https://github.com/ShirkNeko/SukiSU_patch.git "$SUKISU_PATCH_DIR"
else
    info "SukiSU_patch already cloned — updating ..."
    git -C "$SUKISU_PATCH_DIR" pull --ff-only || true
fi

ok "Auxiliary repos ready"

# ── 5. Kernel source via repo ──────────────────────────────────────────────────
step "Kernel source (android${KERNEL_VERSION}-${OS_PATCH_LEVEL})"
mkdir -p "$KERNEL_ROOT"

FORMATTED_BRANCH="${ANDROID_VERSION}-${KERNEL_VERSION}-${OS_PATCH_LEVEL}"

if [[ ! -d "${KERNEL_ROOT}/.repo" ]]; then
    info "repo init: common-${FORMATTED_BRANCH} ..."
    pushd "$KERNEL_ROOT" > /dev/null
    git config --global user.name  "BuildBot" 2>/dev/null || true
    git config --global user.email "build@local" 2>/dev/null || true
    "$REPO_BIN" init --depth=1 \
        -u https://android.googlesource.com/kernel/manifest \
        -b "common-${FORMATTED_BRANCH}" \
        --repo-rev=v2.16

    # Handle deprecated branches (older patch levels)
    REMOTE_BRANCH=$(git ls-remote https://android.googlesource.com/kernel/common \
        "${FORMATTED_BRANCH}" 2>/dev/null || true)
    if grep -q "deprecated" <<< "$REMOTE_BRANCH" 2>/dev/null; then
        warn "Branch is deprecated — adjusting manifest ..."
        sed -i "s/\"${FORMATTED_BRANCH}\"/\"deprecated\/${FORMATTED_BRANCH}\"/g" \
            .repo/manifests/default.xml
    fi
    popd > /dev/null
else
    info "repo already initialised"
fi

if [[ ! -f "${KERNEL_ROOT}/common/Makefile" ]]; then
    info "repo sync (this will take a while — downloading ~3-5 GB) ..."
    pushd "$KERNEL_ROOT" > /dev/null
    "$REPO_BIN" --trace sync -c -j"$JOBS" --no-tags --fail-fast
    popd > /dev/null
else
    info "Kernel source already synced"
fi

ok "Kernel source ready"

# ── 6. Integrate ReSukiSU ─────────────────────────────────────────────────────
step "ReSukiSU"
if [[ ! -d "${KERNEL_ROOT}/KernelSU" ]]; then
    info "Running ReSukiSU setup.sh ..."
    pushd "$KERNEL_ROOT" > /dev/null
    curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" \
        | bash -s main
    popd > /dev/null
else
    info "ReSukiSU already integrated"
fi

KSU_VER=$(grep -rh "KERNELSU_VERSION\|KSU_VERSION" \
    "${KERNEL_ROOT}/KernelSU/kernel/"*.h \
    "${KERNEL_ROOT}/KernelSU/kernel/Kbuild" 2>/dev/null \
    | grep -oE '[0-9]{4,}' | head -1 || echo "unknown")
ok "ReSukiSU v${KSU_VER} integrated"

# Patch manager signing certs to accept locally debug-signed manager APK.
# The upstream manager_sign.h only contains the official release cert hash.
# Our local build is signed with the Android debug keystore, so we add its
# cert hash alongside the official one so both APKs are accepted.
MANAGER_SIGN_H="${KERNEL_ROOT}/KernelSU/kernel/manager/manager_sign.h"
APK_SIGN_C="${KERNEL_ROOT}/KernelSU/kernel/manager/apk_sign.c"

if ! grep -q "EXPECTED_SIZE_RESUKISU_OFFICIAL" "$MANAGER_SIGN_H" 2>/dev/null; then
    info "Patching manager_sign.h to accept debug-signed APK ..."
    sed -i 's|// ReSukiSU/ReSukiSU|// ReSukiSU/ReSukiSU (official release signing cert)\n#define EXPECTED_SIZE_RESUKISU_OFFICIAL 0x377\n#define EXPECTED_HASH_RESUKISU_OFFICIAL "d3469712b6214462764a1d8d3e5cbe1d6819a0b629791b9f4101867821f1df64"\n\n// ReSukiSU local debug build (Android debug keystore)|' "$MANAGER_SIGN_H"
    sed -i 's|#define EXPECTED_SIZE_RESUKISU 0x377|#define EXPECTED_SIZE_RESUKISU 0x2E8|' "$MANAGER_SIGN_H"
    sed -i 's|#define EXPECTED_HASH_RESUKISU "d3469712b6214462764a1d8d3e5cbe1d6819a0b629791b9f4101867821f1df64"|#define EXPECTED_HASH_RESUKISU "1cf4a4e49a0124ad677dc1c2ec046df2110a681afeffa2c2e72431938a2503a1"|' "$MANAGER_SIGN_H"
fi

if ! grep -q "EXPECTED_SIZE_RESUKISU_OFFICIAL" "$APK_SIGN_C" 2>/dev/null; then
    info "Patching apk_sign.c to include official cert as fallback ..."
    sed -i 's|{ EXPECTED_SIZE_RESUKISU, EXPECTED_HASH_RESUKISU }, /\* ReSukiSU/ReSukiSU \*/|{ EXPECTED_SIZE_RESUKISU, EXPECTED_HASH_RESUKISU }, /* ReSukiSU local debug build */\n    { EXPECTED_SIZE_RESUKISU_OFFICIAL, EXPECTED_HASH_RESUKISU_OFFICIAL }, /* ReSukiSU official release */|' "$APK_SIGN_C"
fi

# ── 7. Apply SUSFS patches ────────────────────────────────────────────────────
step "SUSFS4KSU patches"
if [[ "$ENABLE_SUSFS" == "true" ]]; then
    pushd "${KERNEL_ROOT}/common" > /dev/null

    SUSFS_PATCH="${SUSFS_DIR}/kernel_patches/50_add_susfs_in_gki-${ANDROID_VERSION}-${KERNEL_VERSION}.patch"
    [[ -f "$SUSFS_PATCH" ]] || err "SUSFS patch not found: $SUSFS_PATCH"

    # Copy SUSFS source files
    cp -f "${SUSFS_DIR}/kernel_patches/fs/"*    ./fs/
    cp -f "${SUSFS_DIR}/kernel_patches/include/linux/"* ./include/linux/

    # Fix android15-6.6 context: base.c needs dma-buf.h before susfs_def.h
    if [[ "$ANDROID_VERSION" == "android15" && "$KERNEL_VERSION" == "6.6" ]]; then
        SUB_INT="${SUB_LEVEL//[!0-9]/9999}"
        if [[ "$SUB_INT" -le 92 ]] && ! grep -qF '#include <linux/dma-buf.h>' fs/proc/base.c; then
            sed -i '/^#include <linux\/cpufreq_times.h>$/a #include <linux\/dma-buf.h>' fs/proc/base.c
        fi
    fi

    # Apply main SUSFS patch — detect by hook presence, not reverse-patch check
    if grep -q "ksu_handle_setresuid" "${KERNEL_ROOT}/common/kernel/sys.c" 2>/dev/null; then
        info "SUSFS patch already applied"
    else
        info "Applying SUSFS patch ..."
        patch -p1 --fuzz=3 --no-backup-if-mismatch --batch < "$SUSFS_PATCH" || true
    fi

    # Inject susfs_def.h into base.c if patch missed it (android15-6.6 specific)
    if [[ "$ANDROID_VERSION" == "android15" && "$KERNEL_VERSION" == "6.6" ]]; then
        if grep -q 'SUSFS_IS_INODE_SUS_MAP\|susfs_is_current_proc_umounted\|SUSFS_IS_INODE_OPEN_REDIRECT' \
               fs/proc/base.c && ! grep -qF 'susfs_def.h' fs/proc/base.c; then
            info "Injecting susfs_def.h into base.c ..."
            sed -i '/#include <linux\/dma-buf.h>/a #endif' fs/proc/base.c
            sed -i '/#include <linux\/dma-buf.h>/a #include <linux\/susfs_def.h>' fs/proc/base.c
            sed -i '/#include <linux\/dma-buf.h>/a #if defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)' fs/proc/base.c
        fi
    fi

    # ReSukiSU has built-in SUSFS support — no KSU-side patch needed
    popd > /dev/null
    ok "SUSFS patches applied"
else
    info "SUSFS disabled — skipping"
fi

# ── 8. 69_hide_stuff patch ────────────────────────────────────────────────────
step "69_hide_stuff (KSU/root hiding in /proc/maps)"
HIDE_PATCH="${SUKISU_PATCH_DIR}/69_hide_stuff.patch"
pushd "${KERNEL_ROOT}/common" > /dev/null
if [[ -f "$HIDE_PATCH" ]]; then
    if grep -q "show_vma_header_prefix_fake" fs/proc/task_mmu.c 2>/dev/null; then
        info "69_hide_stuff already applied"
    else
        info "Applying 69_hide_stuff ..."
        patch -p1 -F3 --no-backup-if-mismatch -d . < "$HIDE_PATCH" || \
            warn "69_hide_stuff: some hunks failed (may need review)"
    fi
else
    warn "69_hide_stuff.patch not found — skipping"
fi
popd > /dev/null

# ── 9. ZRAM LZ4K ─────────────────────────────────────────────────────────────
step "ZRAM LZ4K"
if [[ "$ENABLE_ZRAM" == "true" ]]; then
    pushd "${KERNEL_ROOT}/common" > /dev/null

    LZ4K_SRC="${SUKISU_PATCH_DIR}/other/zram/lz4k"
    LZ4K_OPLUS_SRC="${SUKISU_PATCH_DIR}/other/zram/lz4k_oplus"
    ZRAM_PATCH_DIR="${SUKISU_PATCH_DIR}/other/zram/zram_patch/${KERNEL_VERSION}"

    [[ -d "$LZ4K_SRC" ]] || err "LZ4K sources missing — re-clone with: rm -rf ${SUKISU_PATCH_DIR}"

    if ! grep -q "CONFIG_CRYPTO_LZ4K" include/linux/lz4k.h 2>/dev/null; then
        info "Copying LZ4K sources ..."
        cp -r "${LZ4K_SRC}/include/linux/"* include/linux/
        cp -r "${LZ4K_SRC}/lib/"*           lib/
        cp -r "${LZ4K_SRC}/crypto/"*        crypto/
        cp -rn "${LZ4K_OPLUS_SRC}"          lib/lz4k_oplus 2>/dev/null || true
    else
        info "LZ4K sources already present"
    fi

    for p in "${ZRAM_PATCH_DIR}/lz4kd.patch" "${ZRAM_PATCH_DIR}/lz4k_oplus.patch"; do
        [[ -f "$p" ]] || continue
        name="$(basename "$p")"
        if patch -p1 --dry-run --silent --batch -R < "$p" >/dev/null 2>&1; then
            info "  Already applied: $name"
        else
            info "  Applying: $name ..."
            patch -p1 -F3 --no-backup-if-mismatch --batch < "$p" || true
        fi
    done

    # Wire lz4k_oplus Kconfig into lib/Kconfig (patch may fail silently, so be explicit)
    if ! grep -qF 'lz4k_oplus/Kconfig' lib/Kconfig 2>/dev/null; then
        echo 'source "lib/lz4k_oplus/Kconfig"' >> lib/Kconfig
        info "  Wired lib/lz4k_oplus/Kconfig into lib/Kconfig"
    fi

    # Config-gate lz4k_oplus to avoid unconditional directory walk
    if grep -qF "obj-y += lz4k_oplus/" lib/Makefile 2>/dev/null; then
        sed -i 's|obj-y += lz4k_oplus/|obj-$(CONFIG_CRYPTO_LZ4K_OPLUS) += lz4k_oplus/|' lib/Makefile
    fi

    popd > /dev/null
    ok "ZRAM LZ4K ready"
else
    info "ZRAM disabled — skipping"
fi

# ── 10. Baseband-guard (optional) ────────────────────────────────────────────
step "Baseband-guard"
if [[ "$ENABLE_BBG" == "true" ]]; then
    pushd "${KERNEL_ROOT}/common" > /dev/null
    if [[ ! -d "Baseband-guard/.git" ]]; then
        info "Cloning Baseband-guard ..."
        git clone --depth=1 https://github.com/vc-teahouse/Baseband-guard Baseband-guard
    fi
    bash Baseband-guard/setup.sh
    popd > /dev/null
    ok "Baseband-guard integrated"
else
    info "Baseband-guard disabled — skipping (ENABLE_BBG=true to enable)"
fi

# ── 11. Patch Bazel/Kleaf build system ───────────────────────────────────────
step "Bazel build system patches"
pushd "${KERNEL_ROOT}" > /dev/null

# Disable strict GKI ABI checks (we're building a custom kernel)
sed -i 's/BUILD_SYSTEM_DLKM=1/BUILD_SYSTEM_DLKM=0/' \
    common/build.config.gki.aarch64 2>/dev/null || true
sed -i '/MODULES_ORDER=android\/gki_aarch64_modules/d' \
    common/build.config.gki.aarch64 2>/dev/null || true
sed -i '/KMI_SYMBOL_LIST_STRICT_MODE/d' \
    common/build.config.gki.aarch64 2>/dev/null || true
sed -i 's/check_defconfig//' \
    common/build.config.gki 2>/dev/null || true

# Remove protected exports list check from Bazel
sed -i '/^[[:space:]]*"protected_exports_list"[[:space:]]*:[[:space:]]*"android\/abi_gki_protected_exports_aarch64",$/d' \
    common/BUILD.bazel 2>/dev/null || true
sed -i '/kmi_symbol_list_strict_mode/d' \
    common/BUILD.bazel 2>/dev/null || true
rm -rf common/android/abi_gki_protected_exports_* 2>/dev/null || true

# Remove -maybe-dirty suffix from Kleaf stamp (keeps version string clean)
sed -i "/stable_scmversion_cmd/s/-maybe-dirty//g" \
    build/kernel/kleaf/impl/stamp.bzl 2>/dev/null || true

popd > /dev/null
ok "Build system patched"

# ── 12. Version string ────────────────────────────────────────────────────────
step "Kernel version string"
pushd "${KERNEL_ROOT}/common" > /dev/null

# Produce: 6.6.89-android15-8-g<hash>-ab<rand>
# This matches HyperOS VINTF which requires "android15-8" in the version string.
KMI_TAG="android15-8"
GHASH=$(git rev-parse --verify HEAD | cut -c1-13)
BID="ab$((RANDOM % 90000000 + 10000000))"
SUFFIX="-${KMI_TAG}-g${GHASH}-${BID}"

info "Kernel version will be: ${KERNEL_VERSION}.${SUB_LEVEL}${SUFFIX}"

# Patch setlocalversion: remove all echo-KERNELVERSION lines (handles re-runs safely)
# then append our fixed version string. config_localversion (-4k) is kept so
# the string stays under the 64-char utsrelease limit and identifies page size.
sed -i '/echo.*\$.*KERNELVERSION/d' ./scripts/setlocalversion
printf 'echo "${KERNELVERSION}%s${config_localversion}"\n' "${SUFFIX}" >> ./scripts/setlocalversion

popd > /dev/null
ok "Version string set"

# ── 13. Kernel configuration ──────────────────────────────────────────────────
step "Kernel configuration"

# Backup original defconfig so we can diff it to build a Bazel fragment
cp "$DEFCONFIG" "${DEFCONFIG}.orig"

# Write all custom configs to defconfig
{
    # ReSukiSU
    echo "CONFIG_KSU=y"

    # KPM (Kernel Patch Module) — ReSukiSU supports this
    [[ "$ENABLE_KPM" == "true" ]] && echo "CONFIG_KPM=y"

    # Tmpfs ACL (needed by KernelSU module system)
    echo "CONFIG_TMPFS_XATTR=y"
    echo "CONFIG_TMPFS_POSIX_ACL=y"

    # BBR + network (TCP_CONG_ADVANCED does not exist in android15-6.6 GKI Kconfig)
    echo "CONFIG_TCP_CONG_BBR=y"
    echo "CONFIG_NET_SCH_FQ=y"
    echo "CONFIG_IP_NF_TARGET_TTL=y"
    echo "CONFIG_IP6_NF_TARGET_HL=y"
    echo "CONFIG_IP6_NF_MATCH_HL=y"

    # BBG
    [[ "$ENABLE_BBG" == "true" ]] && echo "CONFIG_BBG=y"

} >> "$DEFCONFIG"

if [[ "$ENABLE_SUSFS" == "true" ]]; then
    cat >> "$DEFCONFIG" << 'EOF'
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
EOF
    # Note: AUTO_ADD_* and TRY_UMOUNT configs are not present in gki-android15-6.6
    # branch of susfs4ksu — Bazel fragment validation would reject them.
fi

if [[ "$ENABLE_ZRAM" == "true" ]]; then
    cat >> "$DEFCONFIG" << 'EOF'
CONFIG_ZSMALLOC=y
CONFIG_CRYPTO_LZ4HC=y
CONFIG_CRYPTO_LZ4K=y
CONFIG_CRYPTO_LZ4KD=y
CONFIG_CRYPTO_842=y
CONFIG_CRYPTO_LZ4K_OPLUS=y
CONFIG_ZRAM_WRITEBACK=y
EOF
    # CONFIG_MODULE_SIG_FORCE=n omitted: not in GKI Kconfig, Bazel rejects =n fragments
    # CONFIG_ZRAM is already =m in gki_defconfig; switch to =y
    sed -i 's/CONFIG_ZRAM=m/CONFIG_ZRAM=y/' "$DEFCONFIG" 2>/dev/null || \
        echo "CONFIG_ZRAM=y" >> "$DEFCONFIG"

    # Remove zram.ko and zsmalloc.ko from GKI module list (now built-in)
    sed -i 's/"drivers\/block\/zram\/zram\.ko",//g; s/"mm\/zsmalloc\.ko",//g' \
        "${KERNEL_ROOT}/common/modules.bzl" 2>/dev/null || true
fi

# Extract the diff between original and modified defconfig as a Bazel fragment.
# Bazel's --defconfig_fragment applies these configs on top of gki_defconfig
# without modifying gki_defconfig itself, which prevents check_defconfig failures.
FRAG="${KERNEL_ROOT}/common/arch/arm64/configs/ksu.fragment"
diff "${DEFCONFIG}.orig" "$DEFCONFIG" | grep '^>' | sed 's/^> //; s/^[[:space:]]*//' > "$FRAG" || true

# Restore original defconfig — Bazel will merge via the fragment
cp "${DEFCONFIG}.orig" "$DEFCONFIG"

info "Fragment written: $(wc -l < "$FRAG") config entries"
info "Fragment contents:"
cat "$FRAG"

ok "Kernel configured"

# ── 14. Build with Bazel ──────────────────────────────────────────────────────
step "Building kernel via Bazel (${JOBS} jobs)"
BUILD_START=$(date +%s)

pushd "$KERNEL_ROOT" > /dev/null

FRAG_FLAG=""
[[ -s "$FRAG" ]] && FRAG_FLAG="--defconfig_fragment=//common:arch/arm64/configs/ksu.fragment"

set +e
# --config=stamp switches workspace_status_command to workspace_status.sh which
# calls workspace_status_stamp.py — that script reads SOURCE_DATE_EPOCH and emits
# STABLE_SOURCE_DATE_EPOCH into the build, which Kleaf uses for KBUILD_BUILD_TIMESTAMP.
# Without --config=stamp the default workspace_status_common.sh never runs stamp.py
# and SOURCE_DATE_EPOCH is ignored, leaving the kernel timestamp at epoch (1970).
SOURCE_DATE_EPOCH=$(date +%s) \
tools/bazel build \
    --disk_cache="${HOME}/.cache/bazel" \
    --config=fast \
    --config=stamp \
    "--lto=${LTO}" \
    $FRAG_FLAG \
    //common:kernel_aarch64_dist 2>&1 | tee "${SCRIPT_DIR}/build.log"
BUILD_STATUS=${PIPESTATUS[0]}
set -e

popd > /dev/null

BUILD_SECS=$(( $(date +%s) - BUILD_START ))
[[ "$BUILD_STATUS" -eq 0 ]] || err "Build failed (exit ${BUILD_STATUS}) — see build.log"

# Bazel output location for android14/15
KERNEL_IMAGE="${KERNEL_ROOT}/bazel-bin/common/kernel_aarch64/Image"
[[ -f "$KERNEL_IMAGE" ]] || err "Image not found: ${KERNEL_IMAGE}"

ok "Kernel built in ${BUILD_SECS}s — $(du -h "$KERNEL_IMAGE" | cut -f1)"

# Print the actual version string baked into the kernel
strings "$KERNEL_IMAGE" | grep 'Linux version' | head -1

# ── 15. Create boot.img ───────────────────────────────────────────────────────
step "Creating boot.img (header_version 4 + AVB)"

BOOTIMGS_DIR="${SCRIPT_DIR}/bootimgs"
mkdir -p "$BOOTIMGS_DIR"
cp "$KERNEL_IMAGE" "${BOOTIMGS_DIR}/Image"

pushd "$BOOTIMGS_DIR" > /dev/null

# Compress variants
gzip -n -k -f -9 Image > Image.gz 2>/dev/null || gzip -kf Image
cp "${KERNEL_ROOT}/bazel-bin/common/kernel_aarch64/Image.lz4" Image.lz4 2>/dev/null || true

BOOT_PARTITION_SIZE=$(( 64 * 1024 * 1024 ))   # 64 MiB standard GKI boot partition

for variant in "" "-gz" "-lz4"; do
    case "$variant" in
        "")    KFILE="Image" ;;
        "-gz") KFILE="Image.gz" ;;
        "-lz4") KFILE="Image.lz4" ;;
    esac
    [[ -f "$KFILE" ]] || continue

    OUTFILE="boot${variant}.img"
    # header_version 4: android13+ GKI boot format (no ramdisk in boot partition)
    python3 "$MKBOOTIMG_PY" \
        --header_version 4 \
        --kernel "$KFILE" \
        --output "$OUTFILE"
    "$AVBTOOL" add_hash_footer \
        --partition_name boot \
        --partition_size "$BOOT_PARTITION_SIZE" \
        --image "$OUTFILE" \
        --algorithm SHA256_RSA2048 \
        --key "$BOOT_SIGN_KEY"
    info "  Created: $OUTFILE ($(du -h "$OUTFILE" | cut -f1))"
done

popd > /dev/null

DATE=$(date +%Y%m%d-%H%M)
STAG="ReSukiSU"
[[ "$ENABLE_SUSFS" == "true" ]] && STAG="${STAG}-SUSFS"
[[ "$ENABLE_ZRAM"  == "true" ]] && STAG="${STAG}-ZRAM"
[[ "$ENABLE_BBG"   == "true" ]] && STAG="${STAG}-BBG"
[[ "$ENABLE_KPM"   == "true" ]] && STAG="${STAG}-KPM"

BOOT_IMG="${SCRIPT_DIR}/${STAG}_v${KSU_VER}_dew_GKI6.6_${DATE}.img"
cp "${BOOTIMGS_DIR}/boot.img" "$BOOT_IMG"

ok "boot.img: $(basename "$BOOT_IMG") ($(du -h "$BOOT_IMG" | cut -f1))"

# ── 16. AnyKernel3 zip ───────────────────────────────────────────────────────
step "AnyKernel3 package"

# Install our custom anykernel.sh
cp "${SCRIPT_DIR}/anykernel/anykernel3.sh" "${AK3_DIR}/anykernel.sh"
cp "${BOOTIMGS_DIR}/Image" "${AK3_DIR}/Image"

ZIPNAME="${STAG}_v${KSU_VER}_dew_GKI6.6_${DATE}.zip"
pushd "$AK3_DIR" > /dev/null
zip -r9 "${SCRIPT_DIR}/${ZIPNAME}" . -x "*.git*" README.md "*placeholder*" >/dev/null
popd > /dev/null

ok "AnyKernel3 zip: ${ZIPNAME} ($(du -h "${SCRIPT_DIR}/${ZIPNAME}" | cut -f1))"

# ── Done ─────────────────────────────────────────────────────────────────────
step "Complete"
info "Kernel version : ${KERNEL_VERSION}.${SUB_LEVEL}${SUFFIX}"
info "boot.img       : ${BOOT_IMG}"
info "AnyKernel3 zip : ${SCRIPT_DIR}/${ZIPNAME}"
info ""
info "Flash via OrangeFox:"
info "  fastboot flash boot_a ${BOOT_IMG}  (or use AnyKernel3 via recovery)"
info ""
info "After boot:"
info "  Install ReSukiSU Manager: https://github.com/ReSukiSU/ReSukiSU/releases"
info "  Install SUSFS module    : https://github.com/sidex15/ksu_module_susfs"
info ""
info "Env overrides for next run:"
info "  SUB_LEVEL=89              — kernel patch sub-level (89 = stock match)"
info "  OS_PATCH_LEVEL=2025-06    — AOSP patch date (must match SUB_LEVEL)"
info "  ENABLE_SUSFS=false        — disable SUSFS"
info "  ENABLE_ZRAM=false         — disable LZ4K ZRAM"
info "  ENABLE_BBG=true           — enable Baseband-guard"
info "  ENABLE_KPM=true           — enable Kernel Patch Module"
info "  LTO=none                  — faster build, larger kernel"
info "  JOBS=8                    — limit parallel jobs"
