#!/bin/bash
# BendCNC: turn the Armbian Jammy minimal image into the base expected by
# customize-image.sh (root p1 + /data p2, cnc user, NetworkManager, overlayroot,
# plymouth, avahi, mesa). Runs inside a privileged ubuntu:22.04 container:
#   docker run --rm --privileged -v "$PWD:/work" ubuntu:22.04 bash /work/prepare-base.sh IN.img OUT.img
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
IN=${1:?input img}; OUT=${2:?output img}
ROOT_MB=${ROOT_MB:-3072}; DATA_MB=${DATA_MB:-512}
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq qemu-user-static binfmt-support parted gdisk e2fsprogs fdisk kpartx >/dev/null
update-binfmts --enable qemu-aarch64 || true
[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || { echo "no qemu-aarch64 binfmt"; exit 1; }

cp --sparse=always "$IN" "$OUT"
start=$(sfdisk -d "$OUT" | awk -F'[=,]' '/start=/{gsub(/ /,"",$2); print $2; exit}')
total_mb=$(( start / 2048 + ROOT_MB + DATA_MB + 4 ))
truncate -s ${total_mb}M "$OUT"
sgdisk -e "$OUT"
guid=$(sgdisk -i 1 "$OUT" | awk '/unique GUID/{print $4}')
name=$(sgdisk -i 1 "$OUT" | sed -n "s/^Partition name: '\(.*\)'/\1/p")
code=$(sgdisk -i 1 "$OUT" | awk '/Partition GUID code/{print $4}')
end1=$(( start + ROOT_MB * 2048 - 1 ))
sgdisk -d 1 -n 1:$start:$end1 -t 1:$code -u 1:$guid -c 1:"$name" "$OUT"
sgdisk -n 2:$(( end1 + 1 )):0 -t 2:8300 -c 2:bendcnc-data "$OUT"
sgdisk -p "$OUT"

LOOP=$(losetup -fP --show "$OUT")
trap 'umount -R /mnt/r 2>/dev/null || true; losetup -d $LOOP 2>/dev/null || true' EXIT
partprobe "$LOOP" || true
[ -b ${LOOP}p2 ] || { kpartx -a "$LOOP"; }
P1=${LOOP}p1; P2=${LOOP}p2
e2fsck -fy "$P1" || true
resize2fs "$P1"
mkfs.ext4 -q -F -L bendcnc-data "$P2"
DATA_UUID=$(blkid -s UUID -o value "$P2")

mkdir -p /mnt/r; mount "$P1" /mnt/r
for d in dev dev/pts proc sys; do mount --bind /$d /mnt/r/$d; done
cp /usr/bin/qemu-aarch64-static /mnt/r/usr/bin/
mv /mnt/r/etc/resolv.conf /mnt/r/etc/resolv.conf.bendcnc 2>/dev/null || true
cp /etc/resolv.conf /mnt/r/etc/resolv.conf

cat > /mnt/r/tmp/inside.sh <<EOF
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  network-manager wpasupplicant iw overlayroot plymouth plymouth-label \
  avahi-daemon libnss-mdns zstd openssh-server sudo policykit-1 udisks2 python3 \
  libgl1-mesa-dri libegl1 libegl-mesa0 libgles2 libgbm1 libinput10 libinput-bin \
  libmtdev1 libxkbcommon0 libxkbcommon-x11-0 fontconfig fonts-dejavu-core fonts-ubuntu
# Replace systemd-networkd/netplan with NetworkManager
rm -f /etc/netplan/*.yaml
printf 'network:\n  version: 2\n  renderer: NetworkManager\n' > /etc/netplan/01-network-manager.yaml
chmod 600 /etc/netplan/01-network-manager.yaml
systemctl disable systemd-networkd.service systemd-networkd-wait-online.service 2>/dev/null || true
systemctl enable NetworkManager avahi-daemon ssh
# cnc user (uid 1000), password must be changed by bendcnc-setup / firstboot
id cnc >/dev/null 2>&1 || useradd -m -u 1000 -s /bin/bash cnc
for g in tty disk uucp dialout sudo audio video plugdev users systemd-journal input render netdev; do
  getent group \$g >/dev/null && usermod -aG \$g cnc; done
echo 'cnc:bendcnc' | chpasswd; passwd -e cnc
passwd -l root
# Drop Armbian first-login wizard
rm -f /root/.not_logged_in_yet
systemctl disable armbian-firstlogin.service 2>/dev/null || true
echo bendcnc > /etc/hostname
sed -i 's/^127.0.1.1.*/127.0.1.1 bendcnc/' /etc/hosts
grep -q '^verbosity' /boot/armbianEnv.txt || echo 'verbosity=1' >> /boot/armbianEnv.txt
sed -i 's/^bootlogo=.*/bootlogo=true/' /boot/armbianEnv.txt
grep -q '^bootlogo' /boot/armbianEnv.txt || echo 'bootlogo=true' >> /boot/armbianEnv.txt
echo 'UUID=$DATA_UUID /data ext4 defaults,noatime,nofail 0 2' >> /etc/fstab
mkdir -p /data
# Read-only root: tmpfs overlay; /data stays writable (same as production press).
sed -i 's/^overlayroot=.*/overlayroot="tmpfs:recurse=0"/' /etc/overlayroot.conf
grep -q '^overlayroot=' /etc/overlayroot.conf || echo 'overlayroot="tmpfs:recurse=0"' >> /etc/overlayroot.conf
apt-get clean; rm -rf /var/lib/apt/lists/*
# Rebuild initramfs (overlayroot + plymouth hooks) and uInitrd
update-initramfs -u -k all
EOF
chroot /mnt/r bash /tmp/inside.sh
rm -f /mnt/r/tmp/inside.sh /mnt/r/usr/bin/qemu-aarch64-static
rm -f /mnt/r/etc/resolv.conf
[ -e /mnt/r/etc/resolv.conf.bendcnc ] || [ -L /mnt/r/etc/resolv.conf.bendcnc ] && mv /mnt/r/etc/resolv.conf.bendcnc /mnt/r/etc/resolv.conf
ls -la /mnt/r/boot/uInitrd* /mnt/r/boot/armbianEnv.txt
cat /mnt/r/boot/armbianEnv.txt
sync; umount -R /mnt/r
losetup -d "$LOOP"; trap - EXIT
sha256sum "$OUT" | tee "$OUT.sha256"
