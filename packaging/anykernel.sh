# AnyKernel3 Ramdisk Mod Script
# osm0sis @ xda-developers
#
# Device   : Xiaomi POCO C85 5G (codename: dew)
# Kernel   : BakaSU GKI 6.6 + SUSFS
# Partition: /dev/block/by-name/boot  (GKI 2.0 — kernel-only boot image)
# SoC      : MediaTek MT6768

## AnyKernel setup
properties() { '
kernel.string=BakaSU GKI 6.6 Kernel for POCO C85 5G (dew)
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=dew
device.name2=dew_global
device.name3=POCO_C85
device.name4=dew_in
device.name5=
supported.versions=14-16
supported.patchlevels=
'; }

# GKI 2.0 A/B device — boot partition, slot handled automatically
BLOCK=/dev/block/by-name/boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

## AnyKernel methods (DO NOT CHANGE)
. tools/ak3-core.sh;

## GKI: only replace the kernel Image, leave ramdisk untouched
split_boot;
flash_boot;
## end
