#!/bin/bash
# Read-only checks of a built BendCNC SD image (run in a privileged container).
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
IMG=${1:?img}
L=$(losetup -fP --show -r "$IMG"); R=/mnt/vr; D=/mnt/vd
trap 'umount $R $D 2>/dev/null; losetup -d $L' EXIT
mkdir -p $R $D; mount -o ro ${L}p1 $R; mount -o ro ${L}p2 $D
fail=0
t() { if bash -c "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
RU=$(blkid -s UUID -o value ${L}p1); DU=$(blkid -s UUID -o value ${L}p2)
t root-uuid       "grep -q '^rootdev=UUID=$RU' $R/boot/armbianEnv.txt"
t fstab           "grep -q 'UUID=$RU / ' $R/etc/fstab && grep -q 'UUID=$DU /data ' $R/etc/fstab"
t uboot           "cmp -s -n 16777216 <(dd if=$IMG bs=1M count=16 status=none) <(dd if=$IMG bs=1M count=16 status=none) && [ \$(dd if=$IMG bs=512 skip=64 count=8 status=none | tr -d '\\0' | wc -c) -gt 0 ]"
t no-app          "! [ -e $D/bendcnc-qt ] && ! [ -e $D/bendcnc-qt-state/bendcnc-installed ]"
t setup-wizard    "[ -x $R/usr/lib/bendcnc/bendcnc-setup ] && [ -x $R/usr/lib/bendcnc/bendcnc-install.sh ] && [ -d $R/usr/lib/bendcnc/runtime ] && [ -x $R/usr/local/sbin/bendcnc-setup-launch ]"
t wifi-connect    "[ -x $R/usr/local/sbin/bendcnc-wifi-connect ] && grep -qx 'cnc ALL=(root) NOPASSWD: /usr/local/sbin/bendcnc-wifi-connect' $R/etc/sudoers.d/bendcnc-install && ! grep -q \$(printf '\r') $R/usr/local/sbin/bendcnc-wifi-connect"
t dns-resolved    "[ \"\$(readlink $R/etc/resolv.conf)\" = ../run/systemd/resolve/stub-resolv.conf ] && [ -L $R/etc/systemd/system/multi-user.target.wants/systemd-resolved.service -o -L $R/etc/systemd/system/sysinit.target.wants/systemd-resolved.service ]"
t setup-sudoers   "[ \$(stat -c %a $R/etc/sudoers.d/bendcnc-install) = 440 ]"
t firmware-v1.1   "echo 'c9c3564be37c300f864b8aab22a6ad2b7a9e9a20a95474504dadb6aaad0b8426  $D/bendcnc-firmware/approved-original-v1.1.bin' | sha256sum -c --quiet"
t bendcnc-fw      "echo '23298ce3d7ebcb986496b3e4cfc972769f51fb81787bd2b4e12966e9b901720c  $D/bendcnc-qt-state/firmware/bendcnc-v1.3.bin' | sha256sum -c --quiet && grep -q 'BENDCNC v1.3' $D/bendcnc-qt-state/firmware/firmware-catalog.json"
t fw-no-ls        "! grep -a -q -i 'LS-BEND' $D/bendcnc-qt-state/firmware/bendcnc-v1.3.bin"
t only-two-fw     "[ \$(find $D -name '*.bin' | wc -l) = 2 ]"
t no-license      "! find $D/bendcnc-qt-state/config -name License.conf | grep -q ."
t firstboot       "[ -L $R/etc/systemd/system/multi-user.target.wants/bendcnc-firstboot.service ]"
t kiosk-gated     "[ -L $R/etc/systemd/system/multi-user.target.wants/bendcnc-qt-kiosk.service ] && grep -q 'ConditionPathExists=/data/bendcnc-qt-state/bendcnc-installed' $R/etc/systemd/system/bendcnc-qt-kiosk.service.d/10-bendcnc-installed.conf"
t services        "for s in NetworkManager avahi-daemon ssh bendcnc-growdata bendcnc-hostkeys; do [ -L $R/etc/systemd/system/multi-user.target.wants/\$s.service ] || exit 1; done"
t overlayroot     "grep -q '^overlayroot=\"tmpfs:recurse=0\"' $R/etc/overlayroot.conf"
t no-host-keys    "! ls $R/etc/ssh/ssh_host_* >/dev/null 2>&1 && [ ! -s $R/etc/machine-id ]"
t no-dev-keys     "! [ -s $R/home/cnc/.ssh/authorized_keys ] && ! [ -s $R/root/.ssh/authorized_keys ]"
t no-wifi-creds   "! grep -rl 'psk=' $R/etc/NetworkManager/system-connections 2>/dev/null | grep -q ."
t sudoers-perms   "[ \$(stat -c %a $R/etc/sudoers.d) = 750 ] || [ \$(stat -c %a $R/etc/sudoers.d) = 755 ]; ! find $R/etc/sudoers.d -type f ! -perm 0440 | grep -q ."
t splash          "[ -f $R/usr/share/plymouth/themes/bendcnc/bendcnc.plymouth ] && [ -f $R/boot/boot.bmp ]"
t demo-program    "[ -f '$D/bendcnc-qt-state/imports/Channel Bracket.bend' ] && grep -q '\"name\": \"Channel Bracket\"' $D/bendcnc-qt-state/data/BendCNC/BendCNC/current/programs.json && ! grep -q '\"name\": \"SM1\"' $D/bendcnc-qt-state/data/BendCNC/BendCNC/current/programs.json"
t hostname        "[ \$(cat $R/etc/hostname) = bendcnc ]"
t cnc-user        "grep -q '^cnc:x:1000:1000' $R/etc/passwd"
t no-legacy-name  "[ \"\$(cd $R/etc/systemd/system && ls *-qt-kiosk.service)\" = bendcnc-qt-kiosk.service ]"
t splash-theme    "[ ! -f $R/etc/plymouth/plymouthd.conf ] || grep -q '^Theme=bendcnc' $R/etc/plymouth/plymouthd.conf"
echo "RESULT fail=$fail"
exit $fail
