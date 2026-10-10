# POCO C85 (`dew`) BakaSU kernel build, 2026-10-10

This records the build installed on the existing ProjectInfinity-X Android 16 GSI with unchanged EEA vendor `OS3.0.301.0.WBNEUXM`. The stock-compatible GKI base remains `6.6.118-android15-8-ge56cf6b09cca-ab15511674-4k`. The boot image was installed to slot A through OrangeFox using AnyKernel3; no vendor, `vendor_boot`, or GSI partition was changed.

## Local artifacts

The complete build workspace, source checkouts, logs, packages, and rollback image are stored outside Git at `/mnt/sata/dew-kernel-20261010/`. The principal files are:

- `BakaSU-dew-GKI6.6.118-SUSFS-AnyKernel3-20261010.zip` — flashable kernel package.
- `BakaSU-kernel-update/BakaSU-v4.2.0-rc3-dew-local-arm64-v8a.apk` — manager built with the local signing certificate.
- `BakaSU-kernel-update/boot_a-working-before-BakaSU.img` — exact 64 MiB pre-flash rollback image for slot A only.
- `BakaSU-kernel-update/README.md` — build and validation notes.

See `SHA256SUMS` before using any package or backup. The kernel booted successfully with BakaSU driver v4.2.0-rc3 (35222/5) and SUSFS v2.3.0. Android boot, the unchanged vendor fingerprint, module foundation, and manager status were checked after installation.

## Source record

- GKI common base: `3b2ca55a1d9636b971b6110ec760604f12a36af0`, with `common.patch` and `common-added-files.tar.gz` applied. The archive preserves the added files and the `drivers/kernelsu` symlink; the temporary `gki_defconfig.orig` is omitted.
- BakaSU / KernelSU base: `5b76b884c75f729a220bb317aa4a4fc78f0e0e9c`, with `KernelSU.patch` for the local manager signature.
- BakaSU manager source: the same base, with `BakaSU-manager.patch` for manager compatibility fixes.
- Earlier ReSukiSU manager source: `9d0ff6aea9e25fc7dd26f4643175a41f68375e5e`, with `ReSukiSU-manager.patch` retained for provenance.
- SUSFS source and Bazel build details are in the local `BakaSU-kernel-update/` workspace and its README.

These patches record the exact tested source changes; some upstream SUSFS/ZRAM patch lines contain whitespace errors, which are preserved to match the installed build. This release record does not replace the existing `build.sh` workflow.

## Rollback

If a later kernel change causes a boot loop, enter bootloader fastboot (not fastbootd), verify the active slot is still `a`, and flash the saved image:

```sh
fastboot flash boot_a /mnt/sata/dew-kernel-20261010/BakaSU-kernel-update/boot_a-working-before-BakaSU.img
fastboot reboot
```

Do not flash that slot-A backup to another slot without first checking the device state.
