#!/bin/bash
set -euo pipefail

ROOT=${1:?rootfs mount path is required}

# Remove application stacks that are not part of the direct-DRM appliance.
# Package removal is performed inside the ARM64 rootfs so dpkg keeps its
# dependency database coherent. Essential boot, kernel, firmware, systemd,
# NetworkManager, OpenSSH, udev, Mesa/DRM and input packages are retained.
mount --bind /dev "$ROOT/dev"
mount --bind /dev/pts "$ROOT/dev/pts"
mount -t proc proc "$ROOT/proc"
mount -t sysfs sysfs "$ROOT/sys"
mount --bind /run "$ROOT/run"
cleanup_chroot() {
    set +e
    umount "$ROOT/run" 2>/dev/null
    umount "$ROOT/sys" 2>/dev/null
    umount "$ROOT/proc" 2>/dev/null
    umount "$ROOT/dev/pts" 2>/dev/null
    umount "$ROOT/dev" 2>/dev/null
}
trap cleanup_chroot EXIT

cp -L /etc/resolv.conf "$ROOT/etc/resolv.conf.kiosk-build"
if [[ -L "$ROOT/etc/resolv.conf" ]]; then
    readlink "$ROOT/etc/resolv.conf" > "$ROOT/etc/resolv.conf.pre-kiosk-link"
    rm -f "$ROOT/etc/resolv.conf"
elif [[ -f "$ROOT/etc/resolv.conf" ]]; then
    mv "$ROOT/etc/resolv.conf" "$ROOT/etc/resolv.conf.pre-kiosk"
fi
cp "$ROOT/etc/resolv.conf.kiosk-build" "$ROOT/etc/resolv.conf"

cat > "$ROOT/tmp/prune-kiosk-rootfs.sh" <<'CHROOT_SCRIPT'
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

candidates=(
    gdm3 gnome-shell gnome-shell-common gnome-session gnome-session-bin
    gnome-session-common ubuntu-session ubuntu-desktop ubuntu-desktop-minimal
    mutter mutter-common libmutter-10-0 xwayland
    evolution-data-server evolution-data-server-common
    gnome-keyring gnome-keyring-pkcs11 libpam-gnome-keyring
    ubuntu-wallpapers ubuntu-wallpapers-jammy humanity-icon-theme ubuntu-mono
    libwebkit2gtk-4.0-37 libjavascriptcoregtk-4.0-18
    pipewire pipewire-bin pipewire-pulse wireplumber pulseaudio
    gstreamer1.0-plugins-base gstreamer1.0-plugins-good
    cups cups-daemon cups-browsed
    bluez modemmanager packagekit packagekit-tools fwupd snapd
    libreoffice-common chromium-browser firefox
    build-essential gcc g++ cpp cpp-11 make cmake ninja-build
    libc6-dev linux-libc-dev libicu-dev libglib2.0-dev libgtk2.0-dev
    libx11-dev libcairo2-dev libdrm-dev libegl-dev libgl-dev
    man-db manpages groff-base
)
installed=()
for package in "${candidates[@]}"; do
    if dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null | grep -q '^installed$'; then
        installed+=("$package")
    fi
done
if ((${#installed[@]})); then
    apt-get purge -y "${installed[@]}"
fi
# Keep the hardware/runtime authorities explicitly installed. Do not run an
# unrestricted autoremove against the vendor image: Armbian's board support is
# partly metapackage-driven and must not be inferred as disposable.
apt-mark manual systemd udev network-manager wpasupplicant openssh-server \
    sudo libgl1-mesa-dri libegl1 libgbm1 libdrm2 libinput10 >/dev/null
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*
rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/*
rm -rf /var/log/journal/* /var/log/*.gz /var/log/*.[0-9]
rm -rf /tmp/* /var/tmp/*
CHROOT_SCRIPT
chmod 0755 "$ROOT/tmp/prune-kiosk-rootfs.sh"
chroot "$ROOT" /bin/bash /tmp/prune-kiosk-rootfs.sh
rm -f "$ROOT/tmp/prune-kiosk-rootfs.sh"

if [[ -f "$ROOT/etc/resolv.conf.pre-kiosk" ]]; then
    mv -f "$ROOT/etc/resolv.conf.pre-kiosk" "$ROOT/etc/resolv.conf"
elif [[ -f "$ROOT/etc/resolv.conf.pre-kiosk-link" ]]; then
    target=$(cat "$ROOT/etc/resolv.conf.pre-kiosk-link")
    rm -f "$ROOT/etc/resolv.conf"
    ln -s "$target" "$ROOT/etc/resolv.conf"
    rm -f "$ROOT/etc/resolv.conf.pre-kiosk-link"
fi
rm -f "$ROOT/etc/resolv.conf.kiosk-build"

# SDKMAN/OpenJDK/OpenJFX and Arduino caches are user-local and therefore not
# represented in dpkg. Firmware flashing is intentionally outside this first
# direct-DRM runtime image.
rm -rf "$ROOT/home/cnc/.sdkman" "$ROOT/home/cnc/.openjfx" "$ROOT/home/cnc/.arduino15"
rm -rf "$ROOT/home/cnc/.cache"/* "$ROOT/home/cnc/.local/share/Trash"
rm -f "$ROOT/home/cnc/.config/autostart/bendcnc.desktop"

cleanup_chroot
trap - EXIT
