#!/bin/bash
# Read-only audit of the BendCNC customer base image.
set -uo pipefail
IMG=${1:-/output/BendCNC-OrangePi3B.img}
apt-get update -qq >/dev/null && apt-get install -y -qq gdisk binutils-aarch64-linux-gnu >/dev/null
loop() { local a b; a=$(sgdisk -i "$1" "$IMG" | awk '/First sector:/{print $3}'); b=$(sgdisk -i "$1" "$IMG" | awk '/Last sector:/{print $3}')
         losetup -r --find --show --offset $((a*512)) --sizelimit $(((b-a+1)*512)) "$IMG"; }
R=/mnt/r; D=/mnt/d; mkdir -p $R $D
mount -o ro "$(loop 1)" $R && mount -o ro "$(loop 2)" $D || exit 2
fail=0
t() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
t setup-bin       '[ -x $R/usr/lib/bendcnc/bendcnc-setup ] && aarch64-linux-gnu-readelf -h $R/usr/lib/bendcnc/bendcnc-setup | grep -q AArch64'
t installer       '[ -x $R/usr/lib/bendcnc/bendcnc-install.sh ] && bash -n $R/usr/lib/bendcnc/bendcnc-install.sh'
t runtime-qt      'ls $R/usr/lib/bendcnc/runtime/usr/lib/aarch64-linux-gnu/libQt6Quick.so.6* >/dev/null'
t runtime-qml     '[ -d $R/usr/lib/bendcnc/runtime/usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/Controls/Basic ]'
t firstboot-on    '[ -L $R/etc/systemd/system/multi-user.target.wants/bendcnc-firstboot.service ]'
t kiosk-gated     '[ -L $R/etc/systemd/system/multi-user.target.wants/bendcnc-qt-kiosk.service ] && grep -qx ConditionPathExists=/data/bendcnc-qt-state/bendcnc-installed $R/etc/systemd/system/bendcnc-qt-kiosk.service.d/10-bendcnc-installed.conf'
t sudoers         '[ "$(stat -c %a $R/etc/sudoers.d/bendcnc-install)" = 440 ] && ! grep -q $'"'"'\r'"'"' $R/etc/sudoers.d/bendcnc-install'
t launcher-lf     '! grep -q $'"'"'\r'"'"' $R/usr/local/sbin/bendcnc-setup-launch $R/etc/systemd/system/bendcnc-firstboot.service'
t no-world-write  '[ -z "$(find $R -xdev \( -path $R/proc -o -path $R/sys -o -path $R/dev \) -prune -o -perm -0002 ! -type l ! -perm -1000 -print)" ]'
t nm-wired-600    '[ "$(stat -c %a%u $R/etc/NetworkManager/system-connections/BendCNC-Wired-DHCP.nmconnection)" = 6000 ]'
t hostkeys-svc    '[ -L $R/etc/systemd/system/ssh.service.wants/bendcnc-hostkeys.service ] && [ -x $R/usr/local/sbin/bendcnc-hostkeys ] && bash -n $R/usr/local/sbin/bendcnc-hostkeys'
t dhcp-hostname   'grep -qx "ipv4.dhcp-hostname=bendcnc" $R/etc/NetworkManager/conf.d/60-bendcnc-hostname.conf && [ "$(cat $R/etc/hostname)" = bendcnc ]'
t no-app          '[ ! -e $D/bendcnc-qt ]'
t no-stamp        '[ ! -e $D/bendcnc-qt-state/bendcnc-installed ]'
t only-sm1        '[ "$(ls $D/bendcnc-qt-state/data)" = BendCNC ] && [ "$(grep -o "\"name\": \"[^\"]*N1\"" $D/bendcnc-qt-state/data/BendCNC/BendCNC/current/programs.json | wc -l)" = 0 ] && grep -q "\"name\": \"SM1\"" $D/bendcnc-qt-state/data/BendCNC/BendCNC/current/programs.json && [ "$(ls $D/bendcnc-qt-state/imports/*.bcbend)" = "$D/bendcnc-qt-state/imports/SM1.bcbend" ]'
t tty-udev        'grep -q ttyACM $R/etc/udev/rules.d/70-bendcnc-kiosk.rules'
t wifi-persist    '[ -x $R/usr/local/sbin/bendcnc-netpersist ] && [ -L $R/etc/systemd/system/NetworkManager.service.wants/bendcnc-netpersist.service ] && ! grep -q $(printf "\r") $R/usr/local/sbin/bendcnc-netpersist'
t silent-boot     'grep -q "^console=serial" $R/boot/armbianEnv.txt && grep -q "quiet splash" $R/boot/armbianEnv.txt && [ "$(readlink $R/etc/systemd/system/getty@tty1.service)" = /dev/null ]'
t no-hostkeys     '! ls $R/etc/ssh/ssh_host_* >/dev/null 2>&1'
t machine-id-empty '[ ! -s $R/etc/machine-id ]'
t no-wifi-secrets '[ -z "$(find $R/etc/NetworkManager/system-connections -type f ! -name BendCNC-Wired-DHCP.nmconnection)" ]'
t no-text-hdmi    'grep -q "fbcon=vc:2-6" $R/boot/armbianEnv.txt && ! grep -q "console=tty1" $R/boot/armbianEnv.txt'
t grow-data      '[ -x $R/usr/local/sbin/bendcnc-growdata ] && [ -L $R/etc/systemd/system/multi-user.target.wants/bendcnc-growdata.service ] && [ -x $R/sbin/sfdisk ] && [ -x $R/sbin/resize2fs ] && ! grep -q $(printf "\r") $R/usr/local/sbin/bendcnc-growdata'
t fb-splash      '[ -x $R/usr/local/sbin/bendcnc-fbsplash ] && [ -s $R/usr/share/bendcnc/splash.bgrx.z ] && [ -L $R/etc/systemd/system/sysinit.target.wants/bendcnc-fbsplash.service ] && [ -x $R/usr/bin/python3 ] && ! grep -q $(printf "\r") $R/usr/local/sbin/bendcnc-fbsplash'
t no-jar         '[ ! -e $D/bendcnc.jar ]'
t install-tools   '[ -x $R/usr/bin/zstd ] && [ -x $R/usr/bin/curl ] && [ -x $R/usr/bin/openssl ]'
t pubkey          'grep -q 8wWHEiwJ2wtykgiP9RNIfiZAu5y8CKNA $R/usr/lib/bendcnc/bendcnc-install.sh'
t flasher         '[ -x $R/usr/local/sbin/bendcnc-flash-firmware ] && bash -n $R/usr/local/sbin/bendcnc-flash-firmware && ! grep -q $'"'"'\r'"'"' $R/usr/local/sbin/bendcnc-flash-firmware'
t dfu-util        '[ -x $R/usr/local/sbin/dfu-util ] && aarch64-linux-gnu-readelf -h $R/usr/local/sbin/dfu-util | grep -q AArch64'
t flasher-sudoers '[ "$(stat -c %a $R/etc/sudoers.d/bendcnc-firmware-flash)" = 440 ] && grep -qx "cnc ALL=(root) NOPASSWD: /usr/local/sbin/bendcnc-flash-firmware --queue" $R/etc/sudoers.d/bendcnc-firmware-flash'
t fw-original     '[ "$(sha256sum $D/bendcnc-firmware/approved-original-v1.1.bin | cut -d" " -f1)" = c9c3564be37c300f864b8aab22a6ad2b7a9e9a20a95474504dadb6aaad0b8426 ]'
umount $D $R
exit $fail
