# Dew Kernel for POCO C85 5G (`dew`)

This repository records the **tested BakaSU + SUSFS v2.3.0 GKI 6.6.118** kernel for POCO C85 5G. The tested phone runs the existing ProjectInfinity-X Android 16 GSI with unchanged EEA vendor `OS3.0.301.0.WBNEUXM`. The kernel's release string is `6.6.118-android15-8-ge56cf6b09cca-ab15511674-4k`, matching the stock vendor module ABI. The AnyKernel3 package patches the active slot's `boot` image; it does not replace vendor, `vendor_boot`, or the GSI.

Only this firmware/GSI combination and **slot A** have been tested. A successful recovery flash alone does not establish that Android will boot. Check the device codename, current slot, and firmware before proceeding.

## Downloads

The [v6.6.118-20261010 release](https://github.com/0xra0/Dew_Kernel/releases/tag/v6.6.118-20261010) contains:

- [BakaSU-dew-GKI6.6.118-SUSFS-AnyKernel3-20261010.zip](https://github.com/0xra0/Dew_Kernel/releases/download/v6.6.118-20261010/BakaSU-dew-GKI6.6.118-SUSFS-AnyKernel3-20261010.zip) — the recovery-flashable kernel tested on the phone.
- [BakaSU-v4.2.0-rc3-dew-local-arm64-v8a.apk](https://github.com/0xra0/Dew_Kernel/releases/download/v6.6.118-20261010/BakaSU-v4.2.0-rc3-dew-local-arm64-v8a.apk) — the matching manager APK. Its local signing certificate is accepted by this kernel.
- [ASSET_SHA256SUMS](https://github.com/0xra0/Dew_Kernel/releases/download/v6.6.118-20261010/ASSET_SHA256SUMS) — SHA-256 hashes for both assets.

Verify downloads with `sha256sum -c ASSET_SHA256SUMS` in the directory containing all three files. The release record at [releases/dew-bakasu-20261010/README.md](releases/dew-bakasu-20261010/README.md) contains source revisions, patches, checksums, validation, and the tested backup path.

## Install on the tested setup

1. Confirm the phone is `dew`, the bootloader is unlocked, Android boots normally, and the vendor is still `OS3.0.301.0.WBNEUXM`. Back up important data. In Android, run `adb shell getprop ro.product.device`, `adb shell getprop ro.vendor.build.fingerprint`, and `adb reboot bootloader`; in bootloader fastboot, run `fastboot devices` and `fastboot getvar current-slot`. Record the slot.
2. Keep a **known-working backup of that slot's `boot` partition** before changing the kernel. The backup referenced in the release record is from one tested phone's `boot_a`; it is not a universal image. Keep a matching stock firmware boot image available for rollback.
3. Boot the working OrangeFox r2 recovery for this phone. Use its **Install** screen to choose the downloaded AnyKernel3 ZIP (or its ADB Sideload screen with `adb sideload BakaSU-dew-GKI6.6.118-SUSFS-AnyKernel3-20261010.zip`). Wait for `Done!` and `Process ended with no errors` before rebooting to System. The ZIP is for recovery, **not** `fastboot flash`, and recovery flashing still changes the active slot's `boot` image.
4. Once Android fully boots, install the matching APK with `adb install -r BakaSU-v4.2.0-rc3-dew-local-arm64-v8a.apk` or Android's package installer. Open BakaSU and confirm it reports **Working**, driver **v4.2.0-rc3 (35222/5)**, and **SUSFS v2.3.0**. If Android fails to boot, restore the saved boot image before trying another package.

Do not use fastbootd for a `boot` or `vendor_boot` rollback. Do not flash the kernel ZIP or the backup image to `vendor_boot`. No userdata wipe is needed to reverse this kernel change.

### Rollback after a kernel boot loop

Enter **bootloader fastboot** with Power + Volume Down, connect USB, and check `fastboot devices` and `fastboot getvar current-slot`. For the tested phone **only if the active slot is still `a`**, restore its known-working slot-A backup:

```sh
fastboot flash boot_a /mnt/sata/dew-kernel-20261010/BakaSU-kernel-update/boot_a-working-before-BakaSU.img
fastboot reboot
```

For another phone or slot, use **that phone and slot's own** known-working `boot` image. If the current slot differs from the one recorded before installation, determine why before writing anything. A module-related boot loop may be recoverable through BakaSU module safe mode (press and release Volume Down at least three times after the first boot screen), then remove the offending module.

## Build the kernel from source

The repository's `build.sh` now uses **pinned** revisions, not moving upstream branches. The [release directory](releases/dew-bakasu-20261010/) stores the exact tracked-source patches and added files for the tested build. These are the important inputs:

| Component | Pinned source |
| --- | --- |
| Android GKI/Kleaf | `common-android15-6.6-2026-01`; `kernel/common` commit `3b2ca55a1d9636b971b6110ec760604f12a36af0` |
| BakaSU kernel | `Baka-SU/BakaSU` commit `5b76b884c75f729a220bb317aa4a4fc78f0e0e9c` |
| SUSFS | `gki-android15-6.6` commit `a0f9c59e2243f8a5db955f4ad1686d5e0ad26e1a`; its tested source is captured in `common-added-files.tar.gz` |
| AnyKernel3 | `osm0sis/AnyKernel3` commit `020dfeccf9d7e962a48400fc94d3e451df92eead` plus [packaging/anykernel.sh](packaging/anykernel.sh) |

Use a Linux x86-64 build host with sufficient disk space (the Android/Kleaf checkout and build cache take many gigabytes), `git`, Google's `repo` launcher, `python3`, `tar`, `rsync`, `zip`, `unzip`, `sha256sum`, and the tools Kleaf installs through its manifest. Network access is needed for a fresh checkout. The script leaves existing checkouts in place and stops if a pinned Git revision does not match; it never silently upgrades the stock vendor or changes the GSI.

```sh
git clone https://github.com/0xra0/Dew_Kernel.git
cd Dew_Kernel
repo --version                 # install Google's repo launcher first if absent
./build.sh prepare             # sync pinned Android source, apply recorded patches
./build.sh build               # Kleaf //common:kernel_aarch64_dist, stamped thin LTO
./build.sh package             # create a local recovery ZIP with the tested dew installer script
```

The default work and output directories are `.build/dew-6.6.118/workspace` and `.build/dew-6.6.118/output`. They can be placed on another disk:

```sh
WORKSPACE=/mnt/sata/dew-build/workspace OUTPUT=/mnt/sata/dew-build/output ./build.sh all
```

The script checks the built `Image` for the exact stock-compatible release string before packaging and checks the ZIP archive. The new ZIP is named `BakaSU-dew-GKI6.6.118-SUSFS-AnyKernel3-local.zip`. **A rebuild is a new binary, not the phone-tested release asset**; compare its ABI and test it with a rollback image before using it. Do not flash a raw Kleaf `Image` or a newly generated standalone `boot.img` to this phone.

### Building the manager APK

The released APK is the tested manager. Its source is the same pinned BakaSU revision with [BakaSU-manager.patch](releases/dew-bakasu-20261010/BakaSU-manager.patch). The manager uses Android Gradle, Rust/Cargo, Android SDK/NDK, and a signing key. For an independent build, apply that patch to a separate checkout, use the Gradle tasks in the pinned BakaSU `manager/` source, then sign with **your own** key. A differently signed APK will not be accepted by the shipped kernel's local-signature entry and may not upgrade the installed package. To use another signing key, rebuild the kernel with its matching manager certificate and install the APK according to Android's package-signature rules. The signing private key is not in this repository.
