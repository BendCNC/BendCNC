#!/bin/bash
set -euo pipefail

if (( EUID != 0 )); then
    echo "Run this one-time bootstrap as root." >&2
    exit 77
fi

SOURCE_SCRIPT=${1:-/tmp/deploy-kiosk-bundle.sh}
INSTALL_SCRIPT=/usr/local/sbin/bendcnc-deploy-kiosk
SUDOERS_FILE=/etc/sudoers.d/bendcnc-deploy

[[ -f "$SOURCE_SCRIPT" ]] || {
    echo "Missing deployment script: $SOURCE_SCRIPT" >&2
    exit 66
}

install -o root -g root -m 0755 "$SOURCE_SCRIPT" "$INSTALL_SCRIPT"

temporary_sudoers=$(mktemp)
trap 'rm -f "$temporary_sudoers"' EXIT
cat >"$temporary_sudoers" <<'EOF'
cnc ALL=(root) NOPASSWD: /usr/local/sbin/bendcnc-deploy-kiosk /tmp/bendcnc-qt-arm64.tar
EOF
chmod 0440 "$temporary_sudoers"
visudo -cf "$temporary_sudoers"
install -o root -g root -m 0440 "$temporary_sudoers" "$SUDOERS_FILE"
visudo -cf "$SUDOERS_FILE"

echo "PASSWORDLESS-DEPLOY-INSTALLED command=sudo -n $INSTALL_SCRIPT /tmp/bendcnc-qt-arm64.tar"