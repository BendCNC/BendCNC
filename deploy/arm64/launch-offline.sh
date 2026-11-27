#!/bin/bash
set -euo pipefail

APP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
QT_ROOT="$APP_DIR/runtime/usr"
QT_LIB="$QT_ROOT/lib/aarch64-linux-gnu"
RUNTIME_LIB="$APP_DIR/runtime/lib/aarch64-linux-gnu"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
VALIDATION_HOME="${BENDCNC_QT_VALIDATION_HOME:-$APP_DIR/validation-home}"
LOG_DIR="$VALIDATION_HOME/state"
LOG_FILE="$LOG_DIR/runtime.log"

if pgrep -x java >/dev/null 2>&1; then
    echo "REFUSED: the Java production application is still running." >&2
    exit 20
fi
if pgrep -x prototype >/dev/null 2>&1; then
    echo "REFUSED: BendCNC Qt is already running." >&2
    exit 21
fi

mkdir -p "$VALIDATION_HOME/data" "$VALIDATION_HOME/config" "$LOG_DIR"
export XDG_RUNTIME_DIR="$RUNTIME_DIR"
export XDG_DATA_HOME="$VALIDATION_HOME/data"
export XDG_CONFIG_HOME="$VALIDATION_HOME/config"
export XDG_STATE_HOME="$VALIDATION_HOME/state"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
export LD_LIBRARY_PATH="$QT_LIB:$RUNTIME_LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QT_PLUGIN_PATH="$QT_LIB/qt6/plugins"
export QML2_IMPORT_PATH="$QT_LIB/qt6/qml"
export QSG_INFO="${QSG_INFO:-1}"
export QML_XHR_ALLOW_FILE_READ=1
export QML_XHR_ALLOW_FILE_WRITE=1

cd "$APP_DIR"
printf '\n=== %s BendCNC Qt offline validation ===\n' "$(date --iso-8601=seconds)" >>"$LOG_FILE"
"$APP_DIR/prototype" --offline-validation --fullscreen \
    "--run-debug-log=$LOG_DIR/run-preview-debug.log" "$@" 2>&1 | tee -a "$LOG_FILE"
