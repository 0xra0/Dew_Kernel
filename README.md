# Dew Kernel for POCO C85 5G (`dew`)

The current tested release is **BakaSU + SUSFS v2.3.0 on GKI 6.6.118**, built for the existing ProjectInfinity-X Android 16 GSI and unchanged EEA vendor `OS3.0.301.0.WBNEUXM`. It replaces only the kernel in the active `boot` partition through AnyKernel3. It does not update the vendor or GSI.

## Download

Get both files from [v6.6.118-20261010](https://github.com/0xra0/Dew_Kernel/releases/tag/v6.6.118-20261010):

- [BakaSU-dew-GKI6.6.118-SUSFS-AnyKernel3-20261010.zip](https://github.com/0xra0/Dew_Kernel/releases/download/v6.6.118-20261010/BakaSU-dew-GKI6.6.118-SUSFS-AnyKernel3-20261010.zip) — recovery flashable kernel.
- [BakaSU-v4.2.0-rc3-dew-local-arm64-v8a.apk](https://github.com/0xra0/Dew_Kernel/releases/download/v6.6.118-20261010/BakaSU-v4.2.0-rc3-dew-local-arm64-v8a.apk) — matching manager, signed with the certificate accepted by this kernel.
- [ASSET_SHA256SUMS](https://github.com/0xra0/Dew_Kernel/releases/download/v6.6.118-20261010/ASSET_SHA256SUMS) — checksums for both downloads.

This package was tested on **slot A** with the stock-compatible kernel release string `6.6.118-android15-8-ge56cf6b09cca-ab15511674-4k`. The BakaSU driver is v4.2.0-rc3 (35222/5). The phone booted Android after the OrangeFox flash and the manager reported working root and SUSFS. Other firmware, vendor versions, and slots have not been tested.

## Install

1. Keep a backup of your current slot's `boot` image for rollback. Check the active slot before flashing.
2. Boot OrangeFox recovery and flash the ZIP. Confirm it reports success.
3. Reboot Android, then install the matching APK and open BakaSU Manager.

The [release record](releases/dew-bakasu-20261010/README.md) has build details and the tested slot-A rollback procedure. Its local `boot_a` backup belongs to the tested phone and is **not** a universal image for other devices. Do not flash this kernel to `vendor_boot` or use fastbootd for the recovery ZIP.

## Source and build

The [release record](releases/dew-bakasu-20261010/README.md) includes the source revisions, patches, and added files for the tested 6.6.118 build. The repository's `build.sh` is an older ReSukiSU workflow; it does not reproduce this BakaSU release as-is.

| Component | Source |
|-----------|--------|
| GKI kernel | Android `android15-6.6` |
| Root | BakaSU / KernelSU source recorded in the release |
| Root hiding | [SUSFS4KSU](https://github.com/simonpunk/susfs4ksu) |
| Recovery flasher | [AnyKernel3](https://github.com/osm0sis/AnyKernel3) |
