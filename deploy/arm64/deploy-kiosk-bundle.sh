#!/bin/bash
set -euo pipefail

if (( $# != 1 )); then
    echo "Usage: $0 BENDCNC_ARM64_TAR" >&2
    exit 64
fi

BUNDLE=$1
APP_DIR=/data/bendcnc-qt
NEW_DIR=/data/bendcnc-qt.new
PREVIOUS_DIR=/data/bendcnc-qt.previous
PRIVATE_STAGE=""
VERIFIED_BUNDLE=""
DEPLOY_STATE=preflight
HAD_APP=0
SERVICE_WAS_ACTIVE=0

if (( EUID != 0 )); then
    echo "REFUSED: run through the approved passwordless deploy command (sudo -n)." >&2
    exit 77
fi

start_and_verify_kiosk() {
    local expected_pid=""
    local stable_checks=0

    systemctl start bendcnc-qt-kiosk.service || return 1
    for _ in {1..15}; do
        local active_state
        local main_pid
        active_state=$(systemctl show bendcnc-qt-kiosk.service --property=ActiveState --value)
        main_pid=$(systemctl show bendcnc-qt-kiosk.service --property=MainPID --value)
        if [[ "$active_state" == "active" && "$main_pid" =~ ^[1-9][0-9]*$ ]] \
                && kill -0 "$main_pid" 2>/dev/null; then
            if [[ "$main_pid" == "$expected_pid" ]]; then
                ((stable_checks += 1))
            else
                expected_pid=$main_pid
                stable_checks=1
            fi
            (( stable_checks >= 5 )) && return 0
        else
            expected_pid=""
            stable_checks=0
        fi
        sleep 1
    done
    return 1
}

rollback_deployment() {
    local original_status=${1:-1}
    trap - ERR INT TERM
    set +e

    systemctl stop bendcnc-qt-kiosk.service
    if [[ "$DEPLOY_STATE" == "activated" ]]; then
        rm -rf "$APP_DIR"
    fi
    if [[ ! -d "$APP_DIR" && -d "$PREVIOUS_DIR" ]]; then
        mv "$PREVIOUS_DIR" "$APP_DIR"
    fi
    rm -rf "$NEW_DIR"
    [[ -z "$PRIVATE_STAGE" ]] || rm -rf "$PRIVATE_STAGE"
    if (( HAD_APP == 0 )); then
        rm -rf "$APP_DIR" "$PREVIOUS_DIR"
        echo "Deployment failed; original absent-package state restored." >&2
    elif (( SERVICE_WAS_ACTIVE == 0 )); then
        echo "Deployment failed; previous package restored and left stopped." >&2
    elif [[ -x "$APP_DIR/prototype" ]] && start_and_verify_kiosk; then
        echo "Deployment failed; previous package restored and restarted." >&2
    else
        echo "Deployment failed and the previous package could not be restarted." >&2
        original_status=2
    fi
    exit "$original_status"
}

[[ -f "$BUNDLE" ]] || { echo "Missing ARM64 bundle: $BUNDLE" >&2; exit 66; }
[[ -x /usr/local/sbin/bendcnc-kiosk-launch ]] || {
    echo "REFUSED: trusted kiosk launcher is not installed." >&2
    exit 78
}

[[ -d "$APP_DIR" ]] && HAD_APP=1
[[ "$(systemctl is-active bendcnc-qt-kiosk.service 2>/dev/null || true)" == "active" ]] \
    && SERVICE_WAS_ACTIVE=1

# Freeze the caller-owned upload into a root-only staging directory before it
# is parsed or extracted. This closes the validate/open race on /tmp.
PRIVATE_STAGE=$(mktemp -d /tmp/bendcnc-deploy.XXXXXXXX)
chmod 0700 "$PRIVATE_STAGE"
VERIFIED_BUNDLE="$PRIVATE_STAGE/bundle.tar"
cp -- "$BUNDLE" "$VERIFIED_BUNDLE"
chmod 0400 "$VERIFIED_BUNDLE"
trap 'rm -rf "$PRIVATE_STAGE"' EXIT

# Accept only normalized relative regular files and directories. Links and
# special files are unnecessary in the application archive and are rejected.
archive_stats=$(python3 - "$VERIFIED_BUNDLE" <<'PY'
import pathlib
import sys
import tarfile

archive = sys.argv[1]
total = 0
entries = 0
with tarfile.open(archive, "r:") as bundle:
    for member in bundle:
        name = member.name
        path = pathlib.PurePosixPath(name)
        normalized = path.as_posix()
        canonical_names = {normalized, normalized + "/"} if member.isdir() else {normalized}
        if (not name or "\n" in name or "\r" in name or path.is_absolute()
                or any(part in ("", ".", "..") for part in path.parts)
            or name not in canonical_names
                or not (member.isfile() or member.isdir())):
            raise SystemExit(f"unsafe archive member: {name!r}")
        total += member.size
        entries += 1
print(total, entries)
PY
) || { echo "Invalid ARM64 bundle: unsafe archive member." >&2; exit 65; }
read -r archive_bytes archive_entries <<<"$archive_stats"
available_kib=$(df --output=avail -k /data | tail -n 1 | tr -d ' ')
available_inodes=$(df --output=iavail /data | tail -n 1 | tr -d ' ')
previous_kib=0
previous_inodes=0
if [[ -d "$PREVIOUS_DIR" ]]; then
    previous_kib=$(du -sk "$PREVIOUS_DIR" | awk '{ print $1 }')
    previous_inodes=$(find "$PREVIOUS_DIR" -xdev | wc -l)
fi
# df already excludes the active rollback source. The uploaded archive lives
# on /tmp, so the new extraction plus reserve must fit after reclaiming only an
# older .previous copy.
required_kib=$(( (archive_bytes + 1023) / 1024 + 32768 ))
required_inodes=$(( archive_entries + 1024 ))
if (( available_kib + previous_kib < required_kib )); then
    echo "REFUSED: insufficient /data space for transactional deployment (need=${required_kib}KiB available_after_cleanup=$((available_kib + previous_kib))KiB)." >&2
    exit 28
fi
if (( available_inodes + previous_inodes < required_inodes )); then
    echo "REFUSED: insufficient /data inodes for transactional deployment (need=$required_inodes available_after_cleanup=$((available_inodes + previous_inodes)))." >&2
    exit 28
fi

# Cover a stop that changes service state but still returns a failure.
trap 'rollback_deployment $?' ERR INT TERM
systemctl stop bendcnc-qt-kiosk.service
DEPLOY_STATE=stopped
if pgrep -x prototype >/dev/null 2>&1; then
    echo "REFUSED: prototype is still running." >&2
    rollback_deployment 20
fi

# Reclaim only the older fallback now that the active application is known to
# be stopped and remains available as the immediate rollback source.
rm -rf "$PREVIOUS_DIR" "$NEW_DIR"
mkdir -p "$NEW_DIR"
tar --no-same-owner --no-same-permissions -xf "$VERIFIED_BUNDLE" -C "$NEW_DIR"
# Profile packages are assembled in private staging directories. Normalize the
# deployed root independently of archive metadata so the cnc service can CHDIR.
chmod 0755 "$NEW_DIR"
[[ -x "$NEW_DIR/prototype" ]] || { echo "Invalid ARM64 bundle." >&2; rollback_deployment 65; }

# EGLFS must load libgbm and Panfrost DRI from the same board Mesa build.
# Portable libgbm is useful on generic validation hosts but must never enter
# the live RK3566 launch directory.
rm -f "$NEW_DIR/runtime/usr/lib/aarch64-linux-gnu/libgbm.so.1" \
    "$NEW_DIR/runtime/usr/lib/aarch64-linux-gnu/libgbm.so.1.0.0"

# The Press is connected to the dedicated fd8c0000 OHCI host (usb6). If that
# host is runtime-suspended after an electrical disconnect, the Arduino R4 can
# remain absent even though the cable is still attached. Recover only that host
# before launching Qt; Back Gauge remains untouched on fd840000/usb4.
if [[ -x "$NEW_DIR/recover-press-usb.sh" ]] \
        && ! lsusb -d 2341:0069 >/dev/null 2>&1 \
        && ! lsusb -d 1a86:7523 >/dev/null 2>&1; then
    "$NEW_DIR/recover-press-usb.sh" || true
fi

if [[ -d "$APP_DIR" ]]; then
    mv "$APP_DIR" "$PREVIOUS_DIR"
    DEPLOY_STATE=previous-moved
fi
mv "$NEW_DIR" "$APP_DIR"
DEPLOY_STATE=activated

if ! start_and_verify_kiosk; then
    rollback_deployment 1
fi

trap - ERR INT TERM
rm -rf "$PRIVATE_STAGE"
PRIVATE_STAGE=""

echo "KIOSK-BUNDLE-DEPLOYED executable=$(sha256sum "$APP_DIR/prototype" | cut -d' ' -f1)"