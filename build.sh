#!/usr/bin/env bash
# Rebuild the tested POCO C85 5G (dew) GKI 6.6.118 kernel from pinned source.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE="$ROOT/releases/dew-bakasu-20261010"
WORKSPACE="${WORKSPACE:-$ROOT/.build/dew-6.6.118/workspace}"
OUTPUT="${OUTPUT:-$ROOT/.build/dew-6.6.118/output}"
KSU="$WORKSPACE/KernelSU"
COMMON="$WORKSPACE/common"
AK3="$WORKSPACE/AnyKernel3-dew"
COMMON_REV=3b2ca55a1d9636b971b6110ec760604f12a36af0
KSU_REV=5b76b884c75f729a220bb317aa4a4fc78f0e0e9c
AK3_REV=020dfeccf9d7e962a48400fc94d3e451df92eead
EXPECTED_RELEASE=6.6.118-android15-8-ge56cf6b09cca-ab15511674-4k

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "missing command: $1"; }
require_rev() {
    local actual
    actual="$(git -C "$1" rev-parse HEAD 2>/dev/null)" || die "not a Git checkout: $1"
    [[ "$actual" == "$2" ]] || die "$1 is at $actual; expected $2. Use a clean workspace."
}
apply_recorded_patch() {
    local dir="$1" patch="$2"
    if git -C "$dir" apply --reverse --check --whitespace=nowarn "$patch" 2>/dev/null; then
        echo "Already applied: $patch"
    else
        git -C "$dir" apply --check --whitespace=nowarn "$patch" || die "patch does not match pinned source: $patch"
        git -C "$dir" apply --whitespace=nowarn "$patch"
    fi
}

prepare() {
    need git; need tar
    [[ -f "$RELEASE/common.patch" ]] || die "release patches missing from $RELEASE"
    mkdir -p "$WORKSPACE" "$OUTPUT"
    if [[ ! -d "$WORKSPACE/.repo" ]]; then
        local repo_bin="${REPO_BIN:-$(command -v repo || true)}"
        [[ -n "$repo_bin" ]] || die "install Google's repo tool or set REPO_BIN"
        (cd "$WORKSPACE" && "$repo_bin" init -u https://android.googlesource.com/kernel/manifest -b common-android15-6.6-2026-01 && "$repo_bin" sync -c -j"${JOBS:-4}" --no-tags --fail-fast)
    fi
    [[ -d "$COMMON/.git" ]] || die "common source missing after repo sync"
    if [[ "$(git -C "$COMMON" rev-parse HEAD)" != "$COMMON_REV" ]]; then
        git -C "$COMMON" diff --quiet && git -C "$COMMON" diff --cached --quiet || die "common source has local edits; use a clean workspace"
        git -C "$COMMON" checkout --detach "$COMMON_REV" || die "pinned common commit is unavailable; fetch its AOSP branch"
    fi
    require_rev "$COMMON" "$COMMON_REV"
    if [[ ! -d "$KSU/.git" ]]; then
        git clone https://github.com/Baka-SU/BakaSU.git "$KSU"
        git -C "$KSU" checkout --detach "$KSU_REV"
    fi
    require_rev "$KSU" "$KSU_REV"
    apply_recorded_patch "$KSU" "$RELEASE/KernelSU.patch"
    apply_recorded_patch "$COMMON" "$RELEASE/common.patch"
    # Archive contains the fragment, SUSFS/LZ4K source, and drivers/kernelsu symlink.
    tar -xzf "$RELEASE/common-added-files.tar.gz" -C "$COMMON"
    [[ "$(readlink "$COMMON/drivers/kernelsu")" == ../../KernelSU/kernel ]] || die "KernelSU source link is wrong"
    [[ -f "$COMMON/arch/arm64/configs/ksu.fragment" ]] || die "Kleaf fragment missing"
    if [[ ! -d "$AK3/.git" ]]; then
        git clone https://github.com/osm0sis/AnyKernel3.git "$AK3"
        git -C "$AK3" checkout --detach "$AK3_REV"
    fi
    require_rev "$AK3" "$AK3_REV"
    echo "Pinned source and release patches are ready at $WORKSPACE"
}

build() {
    need strings; need tee
    prepare
    [[ -x "$WORKSPACE/tools/bazel" ]] || die "Kleaf tools/bazel missing; repo sync may be incomplete"
    (cd "$WORKSPACE" && PATH="$WORKSPACE/.repo/repo:$PATH" tools/bazel build \
        --config=fast --config=stamp --lto=thin \
        --defconfig_fragment=//common:arch/arm64/configs/ksu.fragment \
        //common:kernel_aarch64_dist) 2>&1 | tee "$OUTPUT/build.log"
    local img="$WORKSPACE/bazel-bin/common/kernel_aarch64/Image"
    [[ -s "$img" ]] || die "Kleaf did not produce Image"
    strings "$img" | grep -F "Linux version $EXPECTED_RELEASE " >/dev/null || die "Image has unexpected release string"
    echo "Built $img"
}

package() {
    need zip; need unzip; need sha256sum; need rsync
    local img="${KERNEL_IMAGE:-$WORKSPACE/bazel-bin/common/kernel_aarch64/Image}"
    [[ -s "$img" ]] || die "build Image first (or set KERNEL_IMAGE to a validated Image)"
    strings "$img" | grep -F "Linux version $EXPECTED_RELEASE " >/dev/null || die "Image does not match tested vendor ABI release"
    require_rev "$AK3" "$AK3_REV"
    mkdir -p "$OUTPUT/package"
    # Copy the exact pinned template files; never modify the source checkout.
    rsync -a --exclude=.git/ "$AK3/" "$OUTPUT/package/"
    cp "$ROOT/packaging/anykernel.sh" "$OUTPUT/package/anykernel.sh"
    cp "$img" "$OUTPUT/package/Image"
    local zipfile="$OUTPUT/BakaSU-dew-GKI6.6.118-SUSFS-AnyKernel3-local.zip"
    rm -f "$zipfile"
    (cd "$OUTPUT/package" && zip -qr9 "$zipfile" . -x 'README.md' '.github/*')
    unzip -tq "$zipfile" >/dev/null
    sha256sum "$zipfile"
    echo "Built $zipfile; verify on dew before flashing. It is not the tested release binary."
}

case "${1:-}" in
    prepare) prepare ;;
    build) build ;;
    package) package ;;
    all) build; package ;;
    *) echo "Usage: WORKSPACE=/path/to/workspace OUTPUT=/path/to/output $0 {prepare|build|package|all}" >&2; exit 2 ;;
esac
