#!/bin/bash
set -euo pipefail

APP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
QT_ROOT="$APP_DIR/runtime/usr"
QT_LIB="$QT_ROOT/lib/aarch64-linux-gnu"
RUNTIME_LIB="$APP_DIR/runtime/lib/aarch64-linux-gnu"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
APP_HOME="${BENDCNC_QT_HOME:-$APP_DIR/validation-home}"
LOG_DIR="$APP_HOME/state"
LOG_FILE="$LOG_DIR/normal-runtime.log"

if pgrep -x java >/dev/null 2>&1; then
    echo "REFUSED: the Java production application is still running." >&2
    exit 20
fi
if pgrep -x prototype >/dev/null 2>&1; then
    echo "REFUSED: BendCNC Qt is already running." >&2
    exit 21
fi

mkdir -p "$APP_HOME/data" "$APP_HOME/config" "$LOG_DIR"
export XDG_RUNTIME_DIR="$RUNTIME_DIR"
export XDG_DATA_HOME="$APP_HOME/data"
export XDG_CONFIG_HOME="$APP_HOME/config"
export XDG_STATE_HOME="$APP_HOME/state"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
export LD_LIBRARY_PATH="$QT_LIB:$RUNTIME_LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QT_PLUGIN_PATH="$QT_LIB/qt6/plugins"
export QML2_IMPORT_PATH="$QT_LIB/qt6/qml"
export QSG_INFO="${QSG_INFO:-1}"
export QML_XHR_ALLOW_FILE_READ=1
export QML_XHR_ALLOW_FILE_WRITE=1

cd "$APP_DIR"
printf '\n=== %s BendCNC Qt normal launch ===\n' "$(date --iso-8601=seconds)" >>"$LOG_FILE"
APP_EXEC=("$APP_DIR/prototype")
# Board-bound build: prototype.sealed only decrypts on this CPU serial.
if [[ -f "$APP_DIR/prototype.sealed" ]]; then
    APP_EXEC=(bash "$APP_DIR/bendcnc-device-bind.sh" run "$APP_DIR/prototype.sealed")
fi
"${APP_EXEC[@]}" --fullscreen --run-debug-logs-off --run-canvas-immediate \
    --serial-debug-logs-on "$@" 2>&1 | tee -a "$LOG_FILE"