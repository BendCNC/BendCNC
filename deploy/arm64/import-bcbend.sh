#!/bin/bash
set -euo pipefail

APP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
QT_ROOT="$APP_DIR/runtime/usr"
QT_LIB="$QT_ROOT/lib/aarch64-linux-gnu"
RUNTIME_LIB="$APP_DIR/runtime/lib/aarch64-linux-gnu"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
APP_HOME="${BENDCNC_QT_HOME:-$APP_DIR/validation-home}"
LOG_DIR="$APP_HOME/state"
LOG_FILE="$LOG_DIR/cad-import.log"

if (( $# != 2 )); then
    echo "Usage: $0 PROGRAM_NAME BCBEND_PATH" >&2
    exit 64
fi
if pgrep -x prototype >/dev/null 2>&1; then
    echo "REFUSED: BendCNC Qt must be stopped for an unattended import." >&2
    exit 20
fi

PROGRAM_NAME="$1"
BCBEND_PATH="$2"
if [[ ! -f "$BCBEND_PATH" ]]; then
    echo "Missing .bcbend file: $BCBEND_PATH" >&2
    exit 66
fi

mkdir -p "$APP_HOME/data" "$APP_HOME/config" "$LOG_DIR"
export XDG_RUNTIME_DIR="$RUNTIME_DIR"
export XDG_DATA_HOME="$APP_HOME/data"
export XDG_CONFIG_HOME="$APP_HOME/config"
export XDG_STATE_HOME="$APP_HOME/state"
export QT_QPA_PLATFORM=offscreen
export LD_LIBRARY_PATH="$QT_LIB:$RUNTIME_LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QT_PLUGIN_PATH="$QT_LIB/qt6/plugins"
export QML2_IMPORT_PATH="$QT_LIB/qt6/qml"
export QML_XHR_ALLOW_FILE_READ=1
export QML_XHR_ALLOW_FILE_WRITE=1

cd "$APP_DIR"
printf '\n=== %s Import %s ===\n' "$(date --iso-8601=seconds)" "$PROGRAM_NAME" >>"$LOG_FILE"
"$APP_DIR/prototype" --offline-validation \
    "--cad-import=$BCBEND_PATH" \
    "--cad-program-name=$PROGRAM_NAME" \
    --cad-generate --cad-exit-after-generate 2>&1 | tee -a "$LOG_FILE"