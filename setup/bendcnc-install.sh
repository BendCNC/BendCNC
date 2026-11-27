#!/bin/bash
# BendCNC app installer, run by bendcnc-setup via sudo -n.
#   bendcnc-install.sh <download_url> <signed_release_token>
#   bendcnc-install.sh --finish     (disable first-boot setup, start kiosk)
# The release token is "<b64url(json)>.<b64url(ed25519 sig)>" signed by the
# license server; json = {"object","sha256","version"}.
set -euo pipefail

APP_DIR=/data/bendcnc-qt
PUBKEY_B64="${BENDCNC_TEST_PUBKEY_B64:-8wWHEiwJ2wtykgiP9RNIfiZAu5y8CKNA+EmFO3i4Qjc=}"  # override only reachable in tests (sudo resets env)
APP_DIR="${BENDCNC_TEST_APP_DIR:-$APP_DIR}"
STAMP=/data/bendcnc-qt-state/bendcnc-installed

if [ "${1:-}" = "--finish" ]; then
    touch "$STAMP"; sync
    # /etc is tmpfs (overlayroot): the image keeps the kiosk enabled, gated on
    # $STAMP. --no-block: stopping the wizard kills its cgroup, which includes
    # this script; the kiosk is ordered After= the wizard so it gets DRM.
    # Run the handoff in its own transient unit: stopping the wizard kills this
    # script's cgroup, so a second systemctl here never executed (2026-11-14).
    systemd-run --no-block --unit=bendcnc-handoff --collect /bin/sh -c \
        'systemctl stop bendcnc-firstboot.service; systemctl start bendcnc-qt-kiosk.service'
    exit 0
fi

URL="$1"; TOKEN="$2"
WORK=$(mktemp -d "$(dirname "$APP_DIR")/bendcnc-install.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

b64u_dec() { local s="${1//-/+}"; s="${s//_//}"; while [ $(( ${#s} % 4 )) -ne 0 ]; do s="$s="; done; printf '%s' "$s" | base64 -d; }

echo "STATUS Verifying release signature..."
PAYLOAD="${TOKEN%%.*}"; SIG="${TOKEN#*.}"
{ printf '\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00'; printf '%s' "$PUBKEY_B64" | base64 -d; } > "$WORK/pub.der"
printf '%s' "$PAYLOAD" > "$WORK/payload"
b64u_dec "$SIG" > "$WORK/sig"
openssl pkeyutl -verify -pubin -keyform DER -inkey "$WORK/pub.der" -rawin \
    -in "$WORK/payload" -sigfile "$WORK/sig" >/dev/null || { echo "STATUS Release signature invalid"; exit 10; }
META=$(b64u_dec "$PAYLOAD")
SHA=$(printf '%s' "$META" | sed -n 's/.*"sha256":"\([0-9a-f]\{64\}\)".*/\1/p')
[ -n "$SHA" ] || { echo "STATUS Release has no checksum"; exit 11; }

echo "STATUS Downloading BendCNC..."
curl -fsSL --retry 3 --connect-timeout 15 -o "$WORK/app.tar" "$URL" &
CURL_PID=$!
while kill -0 "$CURL_PID" 2>/dev/null; do
    sleep 1
    MB=$(( $(stat -c %s "$WORK/app.tar" 2>/dev/null || echo 0) / 1048576 ))
    echo "STATUS Downloading BendCNC... $MB MB"
done
wait "$CURL_PID" || exit 12

echo "STATUS Checking download..."
echo "$SHA  $WORK/app.tar" | sha256sum -c --status || { echo "STATUS Download corrupted"; exit 13; }

echo "STATUS Installing..."
rm -rf "$APP_DIR.new"; mkdir -p "$APP_DIR.new"
if [ "$(head -c4 "$WORK/app.tar" | od -An -tx1 | tr -d ' ')" = "28b52ffd" ]; then
    zstd -q -d -c "$WORK/app.tar" | tar -x -C "$APP_DIR.new" || { echo "STATUS Package incomplete"; exit 14; }
else
    tar -xf "$WORK/app.tar" -C "$APP_DIR.new"
fi
[ -x "$APP_DIR.new/prototype" ] || { echo "STATUS Package incomplete"; exit 14; }
chown -R cnc:cnc "$APP_DIR.new"
rm -rf "$APP_DIR.old"; [ -d "$APP_DIR" ] && mv "$APP_DIR" "$APP_DIR.old"
mv "$APP_DIR.new" "$APP_DIR"
rm -rf "$APP_DIR.old"
sync
echo "STATUS Done"
