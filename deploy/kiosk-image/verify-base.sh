#!/bin/bash
# Read-only check of a prepared BendCNC base image.
set -euo pipefail
IMG=${1:?img}
L=$(losetup -fP --show -r "$IMG"); trap 'umount /mnt/v 2>/dev/null||true; losetup -d $L' EXIT
mkdir -p /mnt/v; mount -o ro ${L}p1 /mnt/v
sgdisk -p "$IMG" 2>/dev/null | tail -3 || true
blkid ${L}p2
dd if=/mnt/v/boot/uInitrd-6.1.99-vendor-rk35xx bs=64 skip=1 status=none | zcat | cpio -t 2>/dev/null > /tmp/ls.txt
echo "initrd files: $(wc -l < /tmp/ls.txt)"
grep -cE 'overlayroot' /tmp/ls.txt | sed 's/^/overlayroot entries: /'
grep -cE 'plymouth' /tmp/ls.txt | sed 's/^/plymouth entries: /'
grep -E 'panfrost|rockchipdrm' /tmp/ls.txt | head -3
grep -E '/data' /mnt/v/etc/fstab; grep '^cnc:' /mnt/v/etc/passwd
cat /mnt/v/etc/hostname; ls /mnt/v/etc/netplan
ls /mnt/v/etc/systemd/system/multi-user.target.wants | grep -E 'NetworkManager|avahi|ssh'
du -sh /mnt/v 2>/dev/null; df -h /mnt/v | tail -1
