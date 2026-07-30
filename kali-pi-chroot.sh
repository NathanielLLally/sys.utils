#!/bin/bash
# chroot into a Kali Linux (RaspPi 3B+) SD card - run as root on the host
# Usage: ./kali-pi-chroot.sh /dev/sdX        (whole disk, partitions sdX1/sdX2)
#     or ./kali-pi-chroot.sh /path/to/image.img
set -euo pipefail

TARGET="${1:?usage: $0 <device|image>}"
MNT="/mnt/kali-pi-root"
BOOT="$MNT/boot"

cleanup() {
    set +e
    umount "$BOOT" 2>/dev/null
    umount "$MNT/dev/pts" 2>/dev/null
    umount "$MNT/dev" 2>/dev/null
    umount "$MNT/proc" 2>/dev/null
    umount "$MNT/sys" 2>/dev/null
    umount "$MNT" 2>/dev/null
    [[ -n "${LOOPDEV:-}" ]] && losetup -d "$LOOPDEV" 2>/dev/null
    true
}
trap cleanup EXIT

# resolve partitions
if [[ -b "$TARGET" ]]; then
    if [[ "$TARGET" =~ (mmcblk|nvme|loop)[0-9]+$ ]]; then
        BOOTPART="${TARGET}p1"
        ROOTPART="${TARGET}p2"
    else
        BOOTPART="${TARGET}1"
        ROOTPART="${TARGET}2"
    fi
elif [[ -f "$TARGET" ]]; then
    LOOPDEV=$(losetup --show -fP "$TARGET")
    BOOTPART="${LOOPDEV}p1"
    ROOTPART="${LOOPDEV}p2"
else
    echo "not a block device or file: $TARGET" >&2
    exit 1
fi

mkdir -p "$MNT"
mount "$ROOTPART" "$MNT"
mount "$BOOTPART" "$BOOT"

# detect target arch from the rootfs's own /bin/bash (or /bin/ls) and pick matching qemu interpreter
QEMU_BIN=""
for probe in bin/bash bin/ls; do
    [[ -f "$MNT/$probe" ]] || continue
    ARCH_STR=$(file -b "$MNT/$probe")
    if [[ "$ARCH_STR" == *"ARM aarch64"* ]]; then
        QEMU_BIN=qemu-aarch64-static
    elif [[ "$ARCH_STR" == *"ARM,"* || "$ARCH_STR" == *" ARM "* ]]; then
        QEMU_BIN=qemu-arm-static
    fi
    [[ -n "$QEMU_BIN" ]] && break
done
[[ -n "$QEMU_BIN" ]] || { echo "could not determine rootfs architecture" >&2; exit 1; }

if [[ "$(uname -m)" != "arm"* && "$(uname -m)" != "aarch64" ]]; then
    command -v "$QEMU_BIN" >/dev/null || { echo "install qemu-user-static: apt install qemu-user-static binfmt-support"; exit 1; }
    cp "$(command -v "$QEMU_BIN")" "$MNT/usr/bin/"
fi

# bind mounts
mount --bind /dev "$MNT/dev"
mount --bind /dev/pts "$MNT/dev/pts"
mount -t proc proc "$MNT/proc"
mount -t sysfs sys "$MNT/sys"

# preserve resolv.conf for network inside chroot
cp -L /etc/resolv.conf "$MNT/etc/resolv.conf" 2>/dev/null || true

echo "chrooting into $MNT (arch: $QEMU_BIN) ..."
chroot "$MNT" "/usr/bin/$QEMU_BIN" /bin/bash

# cleanup runs automatically via trap on exit
