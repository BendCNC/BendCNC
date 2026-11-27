#!/bin/bash
set -euo pipefail

export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export DEBIAN_FRONTEND=noninteractive

# Public BendCNC image: prepared Armbian base (prepare-base.sh) + app bundle
# (deploy/arm64/build-arm64.sh). No license, no setup wizard.
BASE_IMAGE=${BASE_IMAGE:-/input/bendcnc-base.img}
QT_BUNDLE=${QT_BUNDLE:-/input/bendcnc-qt-arm64.tar}
WORK_IMAGE=${WORK_IMAGE:-/work/BendCNC-Qt-Kiosk-customized.img}
OUTPUT_IMAGE=${OUTPUT_IMAGE:-/output/BendCNC-Qt-Kiosk-Minimal-OrangePi3B.img}
OVERLAY=${OVERLAY:-/source/rootfs-overlay}
MANIFEST=${MANIFEST:-/output/BendCNC-Qt-Kiosk-Minimal-OrangePi3B.manifest.txt}

apt-get update -qq
apt-get install -y -qq --no-install-recommends e2fsprogs gdisk util-linux ca-certificates rsync cpio gzip u-boot-tools

[[ -f "$BASE_IMAGE" ]] || { echo "Missing base image: $BASE_IMAGE" >&2; exit 2; }
[[ -f "$QT_BUNDLE" ]] || { echo "Missing Qt bundle: $QT_BUNDLE" >&2; exit 3; }
[[ -d "$OVERLAY" ]] || { echo "Missing rootfs overlay: $OVERLAY" >&2; exit 4; }
mkdir -p "$(dirname "$OUTPUT_IMAGE")"
mkdir -p "$(dirname "$WORK_IMAGE")"
rm -f "$WORK_IMAGE" "$OUTPUT_IMAGE"
cp --reflink=auto --sparse=always "$BASE_IMAGE" "$WORK_IMAGE"

P1_START=$(sgdisk -i 1 "$WORK_IMAGE" | awk '/First sector:/{print $3}')
P1_END=$(sgdisk -i 1 "$WORK_IMAGE" | awk '/Last sector:/{print $3}')
P2_START=$(sgdisk -i 2 "$WORK_IMAGE" | awk '/First sector:/{print $3}')
P2_END=$(sgdisk -i 2 "$WORK_IMAGE" | awk '/Last sector:/{print $3}')
P1_LOOP=$(losetup --find --show --offset "$((P1_START * 512))" --sizelimit "$(((P1_END-P1_START+1)*512))" "$WORK_IMAGE")
P2_LOOP=$(losetup --find --show --offset "$((P2_START * 512))" --sizelimit "$(((P2_END-P2_START+1)*512))" "$WORK_IMAGE")
ROOT_MNT=/mnt/bendcnc-root
DATA_MNT=/mnt/bendcnc-data
cleanup() {
    set +e
    mountpoint -q "$DATA_MNT" && umount "$DATA_MNT"
    mountpoint -q "$ROOT_MNT" && umount "$ROOT_MNT"
    [[ -n "${P2_LOOP:-}" ]] && losetup -d "$P2_LOOP" 2>/dev/null
    [[ -n "${P1_LOOP:-}" ]] && losetup -d "$P1_LOOP" 2>/dev/null
}
trap cleanup EXIT
mkdir -p "$ROOT_MNT" "$DATA_MNT"
e2fsck -f -y "$P1_LOOP" >/dev/null || true
e2fsck -f -y "$P2_LOOP" >/dev/null || true
mount "$P1_LOOP" "$ROOT_MNT"
mount "$P2_LOOP" "$DATA_MNT"

# The base image may carry an older kiosk under another prefix (detected from
# its <prefix>-qt-kiosk.service); drop every artifact of that prefix so only
# bendcnc-* units, helpers and paths remain.
for unit in "$ROOT_MNT"/etc/systemd/system/*-qt-kiosk.service; do
    [[ -e "$unit" ]] || continue
    OLD=$(basename "$unit" -qt-kiosk.service)
    [[ "$OLD" == bendcnc || -z "$OLD" ]] && continue
    find "$ROOT_MNT/etc" "$ROOT_MNT/usr/local" "$ROOT_MNT/home/cnc" -depth -iname "*${OLD}*" -exec rm -rf {} + 2>/dev/null || true
    find "$DATA_MNT" -maxdepth 1 -iname "*${OLD}*" -exec rm -rf {} + 2>/dev/null || true
done

install -d -o 1000 -g 1000 "$DATA_MNT/bendcnc-qt" "$DATA_MNT/bendcnc-qt-state"
tar --numeric-owner -xf "$QT_BUNDLE" -C "$DATA_MNT/bendcnc-qt"
install -d -o 1000 -g 1000 "$DATA_MNT/bendcnc-qt-state/imports"
# The portable bundle carries libgbm for generic hosts, but this kiosk must use
# the board image's libgbm and DRI driver as one Mesa build. Mixing the bundled
# Mesa libgbm with the system Panfrost DRI driver is rejected at runtime with
# "DRI driver not from this Mesa build" and prevents EGLFS from opening DRM.
rm -f "$DATA_MNT/bendcnc-qt/runtime/usr/lib/aarch64-linux-gnu/libgbm.so.1" \
    "$DATA_MNT/bendcnc-qt/runtime/usr/lib/aarch64-linux-gnu/libgbm.so.1.0.0"
chown -R 1000:1000 "$DATA_MNT/bendcnc-qt" "$DATA_MNT/bendcnc-qt-state"
chmod 0755 "$DATA_MNT/bendcnc-qt/prototype"

# Overlay sources live on a Windows bind mount where everything reads as 0777.
# `cp -a` propagated that onto system dirs (/etc/sudoers.d, /usr, ...), which
# made sudo refuse every rule ("/etc/sudoers.d is world writable") and broke
# the first-boot installer. Copy as root:root 0644/0755 and never alter the
# metadata of directories that already exist in the base image.
overlay_copy() { # $1 = overlay root
    tar -C "$1" --numeric-owner --owner=0 --group=0 --mode='u=rwX,go=rX,a-st' -cf - . \
        | tar -C "$ROOT_MNT" --no-overwrite-dir -xf -
    (cd "$1" && find . -type d ! -name .) | while read -r d; do chmod go-w "$ROOT_MNT/$d"; done
    (cd "$1" && find . -type f) | while read -r f; do
        grep -Iq . "$ROOT_MNT/$f" && sed -i 's/\r$//' "$ROOT_MNT/$f"  # text: force LF
        case "$f" in ./usr/local/sbin/*) chmod 0755 "$ROOT_MNT/$f" ;; *) chmod 0644 "$ROOT_MNT/$f" ;; esac
    done
}
overlay_copy "$OVERLAY"

# BendCNC boot splash: replace the base image's vendor Plymouth theme (rootfs
# and the copy embedded in the initramfs) and the U-Boot boot.bmp.
BRAND=/source/branding
VENDOR_THEME=$(sed -n 's/^Theme=//p' "$ROOT_MNT/etc/plymouth/plymouthd.conf" 2>/dev/null | head -n1 || true)
[[ -n "$VENDOR_THEME" ]] || VENDOR_THEME=$(grep -o -m1 'themes/[^/]*/' "$ROOT_MNT/var/lib/dpkg/alternatives/default.plymouth" 2>/dev/null | cut -d/ -f2 || true)
[[ -n "$VENDOR_THEME" ]] || VENDOR_THEME=$(readlink "$ROOT_MNT/etc/alternatives/default.plymouth" 2>/dev/null | sed -n 's#.*/themes/\([^/]*\)/.*#\1#p' || true)
echo "vendor plymouth theme: ${VENDOR_THEME:-none}"
[[ "$VENDOR_THEME" == bendcnc ]] && VENDOR_THEME=
install_splash_theme() { # $1 = root of a filesystem tree containing plymouth
    local t="$1/usr/share/plymouth/themes"
    [[ -n "$VENDOR_THEME" ]] && rm -rf "${t:?}/$VENDOR_THEME"
    install -d "$t/bendcnc"
    install -m 0644 "$BRAND/loading.png" "$t/bendcnc/loading.png"
    sed -e 's/^Name=.*/Name=BendCNC/;s/^Description=.*/Description=BendCNC/' \
        -e 's#^ImageDir=.*#ImageDir=/usr/share/plymouth/themes/bendcnc#' \
        -e 's#^ScriptFile=.*#ScriptFile=/usr/share/plymouth/themes/bendcnc/bendcnc.script#' \
        "$BRAND/theme.plymouth" > "$t/bendcnc/bendcnc.plymouth"
    install -m 0644 "$BRAND/theme.script" "$t/bendcnc/bendcnc.script"
    if [[ -L "$t/default.plymouth" ]]; then
        ln -sf /usr/share/plymouth/themes/bendcnc/bendcnc.plymouth "$1/etc/alternatives/default.plymouth" 2>/dev/null || true
        [[ -e "$1/etc/alternatives/default.plymouth" ]] || ln -sf bendcnc/bendcnc.plymouth "$t/default.plymouth"
    else
        cp "$t/bendcnc/bendcnc.plymouth" "$t/default.plymouth"
    fi
    [[ -f "$1/etc/plymouth/plymouthd.conf" ]] && sed -i 's/^Theme=.*/Theme=bendcnc/' "$1/etc/plymouth/plymouthd.conf"
    return 0
}
install_splash_theme "$ROOT_MNT"
[[ -n "$VENDOR_THEME" ]] && sed -i "s#/usr/share/plymouth/themes/$VENDOR_THEME/$VENDOR_THEME.plymouth#/usr/share/plymouth/themes/bendcnc/bendcnc.plymouth#" \
    "$ROOT_MNT/var/lib/dpkg/alternatives/default.plymouth" 2>/dev/null || true
install -m 0664 "$BRAND/boot.bmp" "$ROOT_MNT/boot/boot.bmp"
for uinitrd in "$ROOT_MNT"/boot/uInitrd-*; do
    [[ -f "$uinitrd" && ! -L "$uinitrd" ]] || continue
    ver=${uinitrd##*/uInitrd-}
    IRD=$(mktemp -d)
    dd if="$uinitrd" bs=64 skip=1 status=none | gzip -dc | (cd "$IRD" && cpio -idm --quiet)
    install_splash_theme "$IRD"
    (cd "$IRD" && find . | LC_ALL=C sort | cpio -o -H newc --quiet | gzip -9n) > /work/initrd.new
    install -m 0644 /work/initrd.new "$ROOT_MNT/boot/initrd.img-$ver"
    mkimage -A arm64 -O linux -T ramdisk -C gzip -n uInitrd -d /work/initrd.new "$uinitrd" >/dev/null
    rm -rf "$IRD" /work/initrd.new
done
[[ -z "$VENDOR_THEME" ]] || ! grep -rl "$VENDOR_THEME" "$ROOT_MNT/usr/share/plymouth" "$ROOT_MNT/etc/plymouth" "$ROOT_MNT/etc/alternatives" 2>/dev/null | grep -q . || {
    echo "Vendor splash remnants remain" >&2; exit 10; }
# Network name used by the Fusion add-in (bendcnc / bendcnc.local).
echo bendcnc > "$ROOT_MNT/etc/hostname"
# Read-only root (tmpfs overlay); /data stays writable.
if [[ -f "$ROOT_MNT/etc/overlayroot.conf" ]]; then
    sed -i '/^overlayroot=/d' "$ROOT_MNT/etc/overlayroot.conf"
    echo 'overlayroot="tmpfs:recurse=0"' >> "$ROOT_MNT/etc/overlayroot.conf"
fi
sed -i 's/\borangepi3b\b/bendcnc/g' "$ROOT_MNT/etc/hosts"
# mDNS (bendcnc.local) via Avahi. arm64 debs fetched from the press with
# apt-get download (debs/avahi); unpacked offline and configured by hand
# because maintainer scripts cannot run in this amd64 container.
# The prepared base already installs avahi-daemon with apt; the offline deb
# path below only runs for bases that lack it.
AVAHI_DEBS=/source/debs/avahi
[[ -x "$ROOT_MNT/usr/sbin/avahi-daemon" ]] || { ls "$AVAHI_DEBS"/avahi-daemon_*_arm64.deb >/dev/null 2>&1 || { echo "Missing Avahi debs in $AVAHI_DEBS" >&2; exit 11; }; }
[[ -x "$ROOT_MNT/usr/sbin/avahi-daemon" ]] || for deb in "$AVAHI_DEBS"/*.deb; do
    # Extract aside and merge with --keep-dirlinks: a direct `dpkg-deb -x` into
    # the merged-usr rootfs replaces the /lib -> usr/lib symlink with a real
    # directory and breaks the dynamic loader.
    rm -rf /work/avahi-x && mkdir -p /work/avahi-x
    dpkg-deb -x "$deb" /work/avahi-x
    rsync -a --keep-dirlinks /work/avahi-x/ "$ROOT_MNT/"
    {   dpkg-deb -f "$deb" | grep -v '^$'
        echo "Status: install ok installed"; echo; } > /work/avahi-status.part
    pkg=$(dpkg-deb -f "$deb" Package)
    awk -v p="Package: $pkg" 'BEGIN{RS="";ORS="\n\n"} $0 !~ "^"p"\n"' "$ROOT_MNT/var/lib/dpkg/status" > /work/dpkg-status.new
    cat /work/avahi-status.part >> /work/dpkg-status.new
    cat /work/dpkg-status.new > "$ROOT_MNT/var/lib/dpkg/status"
    dpkg-deb -c "$deb" | awk '{print substr($6,2)}' | sed 's#/$##;s#^$#/.#' \
        > "$ROOT_MNT/var/lib/dpkg/info/$pkg:arm64.list" 2>/dev/null || true
done
rm -rf /work/avahi-status.part /work/dpkg-status.new /work/avahi-x
grep -q '^avahi:' "$ROOT_MNT/etc/group" || groupadd -R "$ROOT_MNT" --system avahi
grep -q '^avahi:' "$ROOT_MNT/etc/passwd" || useradd -R "$ROOT_MNT" --system -g avahi \
    --no-create-home --home-dir /run/avahi-daemon --shell /usr/sbin/nologin avahi
sed -i 's/^#\?host-name=.*/host-name=bendcnc/' "$ROOT_MNT/etc/avahi/avahi-daemon.conf"
grep -q 'mdns4_minimal' "$ROOT_MNT/etc/nsswitch.conf" || \
    sed -i '/^hosts:/s/ dns/ mdns4_minimal [NOTFOUND=return] dns/' "$ROOT_MNT/etc/nsswitch.conf"
mkdir -p "$ROOT_MNT/etc/systemd/system/sockets.target.wants" "$ROOT_MNT/etc/systemd/system/multi-user.target.wants"
ln -sf /lib/systemd/system/avahi-daemon.service "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/avahi-daemon.service"
ln -sf /lib/systemd/system/avahi-daemon.socket "$ROOT_MNT/etc/systemd/system/sockets.target.wants/avahi-daemon.socket"
ln -sf /lib/systemd/system/avahi-daemon.service "$ROOT_MNT/etc/systemd/system/dbus-org.freedesktop.Avahi.service"
# Do not ship Wi-Fi credentials inherited from the production card. The test
# appliance starts with credential-free wired DHCP; Wi-Fi can be provisioned
# explicitly on the destination device later.
find "$ROOT_MNT/etc/NetworkManager/system-connections" -maxdepth 1 -type f \
    ! -name 'BendCNC-Wired-DHCP.nmconnection' -delete
chmod 0755 "$ROOT_MNT/usr/local/sbin/bendcnc-kiosk-preflight" \
    "$ROOT_MNT/usr/local/sbin/bendcnc-kiosk-launch" \
    "$ROOT_MNT/usr/local/sbin/bendcnc-wifi-init"
chmod 0600 "$ROOT_MNT/etc/NetworkManager/system-connections/BendCNC-Wired-DHCP.nmconnection"
chmod 0644 "$ROOT_MNT/etc/polkit-1/rules.d/49-bendcnc-networkmanager.rules" \
    "$ROOT_MNT/etc/polkit-1/rules.d/49-bendcnc-power.rules"

# Keep the desktop stack installed for forensic rollback, but prevent it from
# owning DRM in the kiosk candidate. Recovery is available through SSH and the
# original Java SD card remains untouched.
ln -sf /dev/null "$ROOT_MNT/etc/systemd/system/display-manager.service"
rm -f "$ROOT_MNT/etc/systemd/system/graphical.target.wants/gdm3.service"
rm -f "$ROOT_MNT/etc/systemd/system/graphical.target.wants/gdm.service"
mkdir -p "$ROOT_MNT/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/bendcnc-qt-kiosk.service \
    "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/bendcnc-qt-kiosk.service"
ln -sf /etc/systemd/system/bendcnc-wifi-init.service \
    "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/bendcnc-wifi-init.service"
ln -sf /lib/systemd/system/multi-user.target "$ROOT_MNT/etc/systemd/system/default.target"

# Customer image: no app installed; the first-boot wizard (welcome, EULA,
# email verification) registers the machine and downloads the app. The wizard
# runs on its own copy of the Qt runtime so the app install can replace /data.
if true; then
    SETUP_DIR=${SETUP_DIR:-/input/setup}
    [[ -x "$SETUP_DIR/bendcnc-setup" && -f "$SETUP_DIR/bendcnc-install.sh" ]] || {
        echo "Missing ARM64 bendcnc-setup in $SETUP_DIR" >&2; exit 7; }
    install -d "$ROOT_MNT/usr/lib/bendcnc"
    cp -a "$DATA_MNT/bendcnc-qt/runtime" "$ROOT_MNT/usr/lib/bendcnc/runtime"
    chown -R 0:0 "$ROOT_MNT/usr/lib/bendcnc/runtime"
    install -m 0755 "$SETUP_DIR/bendcnc-setup" "$ROOT_MNT/usr/lib/bendcnc/bendcnc-setup"
    install -m 0755 "$SETUP_DIR/bendcnc-install.sh" "$ROOT_MNT/usr/lib/bendcnc/bendcnc-install.sh"
    overlay_copy /source/rootfs-overlay-customer
    chmod 0755 "$ROOT_MNT/usr/local/sbin/bendcnc-setup-launch" "$ROOT_MNT/usr/local/sbin/bendcnc-wifi-connect"
    chmod 0440 "$ROOT_MNT/etc/sudoers.d/bendcnc-install"
    chmod 0755 "$ROOT_MNT/usr/local/sbin/bendcnc-netpersist"
    chmod 0644 "$ROOT_MNT/etc/systemd/system/bendcnc-netpersist.service"
    mkdir -p "$ROOT_MNT/etc/systemd/system/NetworkManager.service.wants"
    ln -sf /etc/systemd/system/bendcnc-netpersist.service \
        "$ROOT_MNT/etc/systemd/system/NetworkManager.service.wants/bendcnc-netpersist.service"
    # First boot: grow /data (last partition) to the full SD card.
    sed -i 's/\r$//' "$ROOT_MNT/usr/local/sbin/bendcnc-growdata" "$ROOT_MNT/etc/systemd/system/bendcnc-growdata.service"
    chmod 0755 "$ROOT_MNT/usr/local/sbin/bendcnc-growdata"
    chmod 0644 "$ROOT_MNT/etc/systemd/system/bendcnc-growdata.service"
    mkdir -p "$ROOT_MNT/etc/systemd/system/multi-user.target.wants"
    ln -sf /etc/systemd/system/bendcnc-growdata.service \
        "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/bendcnc-growdata.service"
    rm -f "$DATA_MNT/.bendcnc-grown"
    # Framebuffer splash: Plymouth starts before the VOP2 CRTC exists and stays
    # black; this draws on fb0 in parallel without delaying boot.
    install -D -m 0644 /source/branding/splash.bgrx.z "$ROOT_MNT/usr/share/bendcnc/splash.bgrx.z"
    sed -i 's/\r$//' "$ROOT_MNT/usr/local/sbin/bendcnc-fbsplash" "$ROOT_MNT/etc/systemd/system/bendcnc-fbsplash.service"
    chmod 0755 "$ROOT_MNT/usr/local/sbin/bendcnc-fbsplash"
    chmod 0644 "$ROOT_MNT/etc/systemd/system/bendcnc-fbsplash.service"
    mkdir -p "$ROOT_MNT/etc/systemd/system/sysinit.target.wants"
    ln -sf /etc/systemd/system/bendcnc-fbsplash.service \
        "$ROOT_MNT/etc/systemd/system/sysinit.target.wants/bendcnc-fbsplash.service"
    # Supervised firmware flasher: same contract as install-orange-pi-flasher.sh.
    FLASHER=${FLASHER:-/input/flasher}
    [[ $(sha256sum "$FLASHER/approved-original-v1.1.bin" | cut -d' ' -f1) == c9c3564be37c300f864b8aab22a6ad2b7a9e9a20a95474504dadb6aaad0b8426 ]] || {
        echo "ORIGINAL firmware hash mismatch" >&2; exit 8; }
    [[ $(sha256sum "$FLASHER/dfu-util_0.9-1_arm64.deb" | cut -d' ' -f1) == c0eba51656cdfa66a464a5ee647782a5277daa0c0ddb6f24d70b9c6676645523 ]] || {
        echo "dfu-util package hash mismatch" >&2; exit 8; }
    bash -n "$FLASHER/bendcnc-flash-firmware"
    DFU_TMP=$(mktemp -d)
    dpkg-deb -x "$FLASHER/dfu-util_0.9-1_arm64.deb" "$DFU_TMP"
    install -o 0 -g 0 -m 0755 "$DFU_TMP/usr/bin/dfu-util" "$ROOT_MNT/usr/local/sbin/dfu-util"
    rm -rf "$DFU_TMP"
    install -o 0 -g 0 -m 0755 "$FLASHER/bendcnc-flash-firmware" "$ROOT_MNT/usr/local/sbin/bendcnc-flash-firmware"
    install -d -o 0 -g 0 -m 0755 "$DATA_MNT/bendcnc-firmware" "$DATA_MNT/bendcnc-firmware/logs"
    install -o 0 -g 0 -m 0644 "$FLASHER/approved-original-v1.1.bin" "$DATA_MNT/bendcnc-firmware/approved-original-v1.1.bin"
# BendCNC press firmware, offered in Settings > Machine firmware by any app
# version (press catalog dir survives app installs/updates).
BFW_SHA=23298ce3d7ebcb986496b3e4cfc972769f51fb81787bd2b4e12966e9b901720c
[[ $(sha256sum "$FLASHER/bendcnc-v1.3.bin" | cut -d' ' -f1) == "$BFW_SHA" ]] || {
    echo "BendCNC firmware hash mismatch" >&2; exit 8; }
FWCAT="$DATA_MNT/bendcnc-qt-state/firmware"
install -d -o 1000 -g 1000 -m 0755 "$FWCAT"
install -o 1000 -g 1000 -m 0644 "$FLASHER/bendcnc-v1.3.bin" "$FWCAT/bendcnc-v1.3.bin"
cat > "$FWCAT/firmware-catalog.json" <<EOF
{"schema":1,"images":[{"id":"current","kind":"current","title":"BENDCNC","version":"v1.3",
"description":"BendCNC press firmware","expectedVersion":"[BENDCNC v1.3]",
"label":"bendcnc-v1.3","file":"bendcnc-v1.3.bin","sha256":"$BFW_SHA",
"size":$(stat -c %s "$FLASHER/bendcnc-v1.3.bin"),"autoRollback":true}]}
EOF
chown 1000:1000 "$FWCAT/firmware-catalog.json"
    printf '%s\n' STATE=IDLE JOB_ID=none TARGET_HASH=none APPLIED_HASH=none ROLLBACK=0 MESSAGE=not_started UPDATED_UTC=unknown \
        > "$DATA_MNT/bendcnc-firmware/status.env"
    chmod 0644 "$DATA_MNT/bendcnc-firmware/status.env"
    printf '%s\n' 'cnc ALL=(root) NOPASSWD: /usr/local/sbin/bendcnc-flash-firmware --queue' \
        > "$ROOT_MNT/etc/sudoers.d/bendcnc-firmware-flash"
    chmod 0440 "$ROOT_MNT/etc/sudoers.d/bendcnc-firmware-flash"
    [[ -x "$ROOT_MNT/usr/bin/zstd" ]] || { echo "zstd missing in image (needed by installer/updater)" >&2; exit 9; }
    # In-app updater (same contract as deploy-arm64/install-app-updater.sh).
    install -o 0 -g 0 -m 0755 "$FLASHER/bendcnc-app-update" "$ROOT_MNT/usr/local/sbin/bendcnc-app-update"
    printf '%s\n' 'cnc ALL=(root) NOPASSWD: /usr/local/sbin/bendcnc-app-update queue, /usr/local/sbin/bendcnc-app-update status' \
        > "$ROOT_MNT/etc/sudoers.d/bendcnc-app-update"
    chmod 0440 "$ROOT_MNT/etc/sudoers.d/bendcnc-app-update"
    CNC_UID=$(awk -F: '$1=="cnc"{print $3}' "$ROOT_MNT/etc/passwd")
    CNC_GID=$(awk -F: '$1=="cnc"{print $4}' "$ROOT_MNT/etc/passwd")
    [[ -n "$CNC_UID" ]] || { echo "cnc user missing in image" >&2; exit 9; }
    install -d -m 0755 -o "$CNC_UID" -g "$CNC_GID" "$DATA_MNT/bendcnc-updates"
    # Upload-only CAD import account (same contract as install-cad-import-access.sh).
    install -o 0 -g 0 -m 0755 "$FLASHER/bendcnc-import-shell" "$ROOT_MNT/usr/local/sbin/bendcnc-import-shell"
    install -o 0 -g 0 -m 0755 "$FLASHER/bendcnc-import-keys" "$ROOT_MNT/usr/local/sbin/bendcnc-import-keys"
    grep -q '^bendimport:' "$ROOT_MNT/etc/passwd" || \
        useradd -R "$ROOT_MNT" --system --no-create-home --home-dir /nonexistent --shell /bin/bash bendimport
    usermod -R "$ROOT_MNT" -L bendimport
    usermod -R "$ROOT_MNT" -a -G bendimport cnc
    IMPORT_GID=$(awk -F: '$1=="bendimport"{print $3}' "$ROOT_MNT/etc/group")
    install -d -m 0755 -o 0 -g 0 "$ROOT_MNT/etc/bendcnc"
    : > "$ROOT_MNT/etc/bendcnc/import_authorized_keys"
    chmod 0644 "$ROOT_MNT/etc/bendcnc/import_authorized_keys"
    install -d -m 2775 -o "$CNC_UID" -g "$IMPORT_GID" "$DATA_MNT/bendcnc-qt-state/imports"
    chmod 2775 "$DATA_MNT/bendcnc-qt-state/imports"
    chown "$CNC_UID:$IMPORT_GID" "$DATA_MNT/bendcnc-qt-state/imports"
    install -d -m 0755 "$ROOT_MNT/etc/ssh/sshd_config.d"
    cat > "$ROOT_MNT/etc/ssh/sshd_config.d/50-bendimport.conf" <<'EOF'
# CAD PCs upload with keys paired on the press screen (bendcnc-import-keys).
Match User bendimport
    AuthorizedKeysFile /etc/bendcnc/import_authorized_keys
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    ForceCommand /usr/local/sbin/bendcnc-import-shell
    AllowTcpForwarding no
    AllowAgentForwarding no
    X11Forwarding no
    PermitTTY no
    PermitTunnel no
EOF
    rm -f "$ROOT_MNT/etc/ssh/sshd_config.d/50-bendcnc-import.conf"
    grep -q '^Include /etc/ssh/sshd_config.d/\*.conf' "$ROOT_MNT/etc/ssh/sshd_config" \
        || sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' "$ROOT_MNT/etc/ssh/sshd_config"
    printf '%s\n' 'cnc ALL=(root) NOPASSWD: /usr/local/sbin/bendcnc-import-keys add *, /usr/local/sbin/bendcnc-import-keys list, /usr/local/sbin/bendcnc-import-keys clear' \
        > "$ROOT_MNT/etc/sudoers.d/bendcnc-import-keys"
    chmod 0440 "$ROOT_MNT/etc/sudoers.d/bendcnc-import-keys"
    install -d -m 0755 "$ROOT_MNT/etc/systemd/system/bendcnc-qt-kiosk.service.d"
    printf '%s\n' '[Service]' 'ReadWritePaths=/etc/bendcnc' \
        > "$ROOT_MNT/etc/systemd/system/bendcnc-qt-kiosk.service.d/50-cad-import-keys.conf"
    chmod go-w "$ROOT_MNT" "$ROOT_MNT/etc"
    # No developer keys on customer machines.
    rm -f "$ROOT_MNT/home/cnc/.ssh/authorized_keys" "$ROOT_MNT/root/.ssh/authorized_keys"
    # Legacy Java app is not shipped.
    rm -f "$DATA_MNT/bendcnc.jar"
    # Customer machine: only the Channel Bracket demo program (no N1 programs). The catalog
    # was generated by the real app importer (import-bcbend.sh) and is seeded at
    # the BendCNC data path the app uses (no legacy migration copies).
    CUSTOMER_CATALOG=${CUSTOMER_CATALOG:-/source/customer-catalog}
    rm -f "$DATA_MNT/bendcnc-qt-state/imports/"*.bcbend "$DATA_MNT/bendcnc-qt-state/imports/"*.bend
    find "$DATA_MNT/bendcnc-qt-state/data" -mindepth 1 -maxdepth 1 ! -name BendCNC -exec rm -rf {} + 2>/dev/null || true
    CUST_CURRENT="$DATA_MNT/bendcnc-qt-state/data/BendCNC/BendCNC/current"
    install -d -o 1000 -g 1000 "$DATA_MNT/bendcnc-qt-state/data/BendCNC" \
        "$DATA_MNT/bendcnc-qt-state/data/BendCNC/BendCNC" "$CUST_CURRENT"
    install -o 1000 -g 1000 -m 0644 "$CUSTOMER_CATALOG/programs.json" "$CUST_CURRENT/programs.json"
    install -o 1000 -g 1000 -m 0644 "$CUSTOMER_CATALOG/bends.json" "$CUST_CURRENT/bends.json"
    install -o 1000 -g 1000 -m 0644 "$CUSTOMER_CATALOG/Channel Bracket.bend" "$DATA_MNT/bendcnc-qt-state/imports/Channel Bracket.bend"
    chown -R 1000:1000 "$DATA_MNT/bendcnc-qt-state/data"
    # App is downloaded by the wizard; no stamp or license token in the image.
    rm -rf "$DATA_MNT/bendcnc-qt"
    rm -f "$DATA_MNT/bendcnc-qt-state/bendcnc-installed" \
        "$DATA_MNT/bendcnc-qt-state/config/BendCNC/License.conf" \
        "$DATA_MNT/bendcnc-qt-state/config/BendCNC/License.conf"
    # DNS via systemd-resolved (NetworkManager feeds it). Never ship the build
    # container's resolv.conf: its nameserver does not exist on the press.
    ln -sfn ../run/systemd/resolve/stub-resolv.conf "$ROOT_MNT/etc/resolv.conf"
    # Per-machine identity: no shared SSH host keys or machine-id.
    rm -f "$ROOT_MNT"/etc/ssh/ssh_host_*
    : > "$ROOT_MNT/etc/machine-id"
    # overlayroot: keep the kiosk enabled but gated on the installer's /data
    # stamp; the first-boot wizard has the inverse condition.
    install -d -m 0755 "$ROOT_MNT/etc/systemd/system/bendcnc-qt-kiosk.service.d"
    printf '[Unit]\nAfter=bendcnc-firstboot.service\nConditionPathExists=/data/bendcnc-qt-state/bendcnc-installed\n' \
        > "$ROOT_MNT/etc/systemd/system/bendcnc-qt-kiosk.service.d/10-bendcnc-installed.conf"
    ln -sf /etc/systemd/system/bendcnc-firstboot.service \
        "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/bendcnc-firstboot.service"
    mkdir -p "$ROOT_MNT/etc/systemd/system/sysinit.target.wants"
    ln -sf /etc/systemd/system/bendcnc-bootlog.service \
        "$ROOT_MNT/etc/systemd/system/sysinit.target.wants/bendcnc-bootlog.service"
    mkdir -p "$ROOT_MNT/etc/systemd/system/ssh.service.wants"
    ln -sf /etc/systemd/system/bendcnc-hostkeys.service \
        "$ROOT_MNT/etc/systemd/system/ssh.service.wants/bendcnc-hostkeys.service"
    ln -sf /etc/systemd/system/bendcnc-hostkeys.service \
        "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/bendcnc-hostkeys.service"
    ln -sf /lib/systemd/system/ssh.service \
        "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/ssh.service"
fi

# Preserve the known-good RK3566 kernel/initramfs. Only append the press-brake
# HDMI mode when not already present.
ARMBIAN_ENV="$ROOT_MNT/boot/armbianEnv.txt"
if [[ -f "$ARMBIAN_ENV" ]] && ! grep -q 'video=HDMI-A-1:1368x768@59' "$ARMBIAN_ENV"; then
    sed -i '/^extraargs=/ s/$/ video=HDMI-A-1:1368x768@59/' "$ARMBIAN_ENV"
fi
# Do NOT set rootdelay: initramfs-tools then waits only that long instead of
# its 180 s default (rootdelay=10 made every boot fail, 2026-11-14).
# panic=10: the press has no keyboard; if the SD is not detected, initramfs
# reboots after 10 s instead of dropping to an unusable (initramfs) shell.
if [[ -f "$ARMBIAN_ENV" ]] && ! grep -q 'panic=' "$ARMBIAN_ENV"; then
    sed -i '/^extraargs=/ s/$/ panic=10/' "$ARMBIAN_ENV"
fi
# Silent boot: kernel/systemd messages go to the serial console only, the HDMI
# panel shows just the BendCNC Plymouth splash until the kiosk starts.
if [[ -f "$ARMBIAN_ENV" ]]; then
    set_env() { # $1 key, $2 value
        if grep -q "^$1=" "$ARMBIAN_ENV"; then sed -i "s|^$1=.*|$1=$2|" "$ARMBIAN_ENV"
        else echo "$1=$2" >> "$ARMBIAN_ENV"; fi
    }
    set_env console serial
    set_env verbosity 0
    set_env bootlogo true
    grep -q '^extraargs=' "$ARMBIAN_ENV" || echo 'extraargs=' >> "$ARMBIAN_ENV"
    for arg in quiet splash loglevel=0 vt.global_cursor_default=0 systemd.show_status=false \
               rd.systemd.show_status=false udev.log_level=3 rd.udev.log_level=3 plymouth.ignore-serial-consoles fbcon=vc:2-6; do
        grep -qE "^extraargs=.*(^|[ =])${arg//./\\.}( |$)" "$ARMBIAN_ENV" \
            || sed -i "/^extraargs=/ s/\$/ $arg/" "$ARMBIAN_ENV"
    done
    sed -i 's/^extraargs= */extraargs=/' "$ARMBIAN_ENV"
fi
# No login prompt flashes on the panel between splash and kiosk.
ln -sf /dev/null "$ROOT_MNT/etc/systemd/system/getty@tty1.service"

# Normalize the source fstab before compaction. compact-image.sh assigns fresh
# UUIDs and writes the definitive U-Boot/fstab selectors for the new card.
ROOT_UUID=$(blkid -s UUID -o value "$P1_LOOP")
DATA_UUID=$(blkid -s UUID -o value "$P2_LOOP")
FSTAB="$ROOT_MNT/etc/fstab"
if [[ -f "$FSTAB" ]]; then
    sed -i -E "s#^/dev/(mmcblk|nvme)[^[:space:]]+[[:space:]]+/[[:space:]]+#UUID=$ROOT_UUID / #" "$FSTAB"
    sed -i -E "s#^/dev/(mmcblk|nvme)[^[:space:]]+[[:space:]]+/data[[:space:]]+#UUID=$DATA_UUID /data #" "$FSTAB"
fi

/source/prune-rootfs.sh "$ROOT_MNT"

SOURCE_IMAGE="$WORK_IMAGE" OUTPUT_IMAGE="$OUTPUT_IMAGE" \
    ROOT_MNT="$ROOT_MNT" DATA_MNT="$DATA_MNT" /source/compact-image.sh

sync
QT_HASH="none (app downloaded by first-boot wizard; setup=$(sha256sum "$ROOT_MNT/usr/lib/bendcnc/bendcnc-setup" | cut -d' ' -f1))"
BUNDLE_HASH=$(sha256sum "$QT_BUNDLE" | cut -d' ' -f1)
BASE_HASH=$(sha256sum "$BASE_IMAGE" | cut -d' ' -f1)
{
    echo "build_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "base_image=$(basename "$BASE_IMAGE")"
    echo "base_sha256=$BASE_HASH"
    echo "qt_bundle_sha256=$BUNDLE_HASH"
    echo "qt_executable_sha256=$QT_HASH"
    echo "image_profile=minimal-direct-drm"
    echo "desktop_stack=removed"
    echo "java_runtime=removed"
    echo "development_toolchain=removed"
    echo "qpa=eglfs"
    echo "eglfs_integration=eglfs_kms"
    echo "drm_device=/dev/dri/card0"
    echo "initial_program_catalog=channel-bracket-demo"
    echo "licensing=${LICENSING:-on} (license.bendcnc.com, terms set by server)"
    echo "firmware=original-v1.1"
    echo "display=HDMI-A-1 preferred (kernel forced 1368x768@59)"
    echo "touch=eGalax Inc. eGalaxTouch EXC7910-1138-48.00.00"
} > "$MANIFEST"

echo "KIOSK-IMAGE-READY image=$OUTPUT_IMAGE manifest=$MANIFEST"
