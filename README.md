# Dew Kernel

Custom GKI 6.6 kernel for **POCO C85 5G (dew)** — MediaTek MT6768

## Features

- **ReSukiSU** — KernelSU fork with enhanced root management
- **SUSFS4KSU** — Filesystem-level root hiding (GKI android15-6.6 branch)
- **ZRAM LZ4K** — Improved compression for better memory efficiency
- Accepts both debug-signed and officially-signed ReSukiSU manager APK

## Device

| Property | Value |
|----------|-------|
| Device | POCO C85 5G |
| Codename | dew |
| SoC | MediaTek MT6768 |
| Kernel | android15-6.6 (GKI 2.0) |
| Boot image header | v4 |

## Installation

1. Download the latest `.zip` from [Releases](../../releases)
2. Boot into custom recovery (e.g. OrangeFox)
3. Flash the zip
4. Reboot
5. Install the [ReSukiSU Manager APK](https://github.com/ReSukiSU/ReSukiSU/releases)
6. Open the manager — root should be available

> **Note:** This kernel requires an unlocked bootloader.

## Build

```bash
git clone https://github.com/0xra0/Dew_Kernel
cd Dew_Kernel
bash build.sh
```

The script will automatically:
- Sync android15-6.6-89 kernel source via `repo`
- Clone ReSukiSU, SUSFS4KSU, AnyKernel3, and toolchain
- Apply all patches
- Build with Bazel/Kleaf
- Package a flashable AnyKernel3 zip

## Components

| Component | Source |
|-----------|--------|
| Kernel source | android15-6.6 (GKI) |
| Root | [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) |
| Root hiding | [SUSFS4KSU](https://github.com/simonpunk/susfs4ksu) |
| Flasher | [AnyKernel3](https://github.com/osm0sis/AnyKernel3) |
