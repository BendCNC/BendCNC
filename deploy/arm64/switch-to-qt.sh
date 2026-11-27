#!/bin/bash
set -euo pipefail

APP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
JAVA_PID="$(pgrep -o -x java || true)"
SESSION_ENV="$APP_DIR/validation-home/session.env"
JAVA_STOPPED=0

restart_java() {
    local qt_status=$?
    trap - EXIT INT TERM
    if (( JAVA_STOPPED == 1 )) && ! pgrep -x java >/dev/null 2>&1; then
        nohup /home/cnc/start.sh >"$APP_DIR/validation-home/java-restart.log" 2>&1 &
        for _ in {1..100}; do
            pgrep -x java >/dev/null 2>&1 && break
            sleep 0.1
        done
        if ! pgrep -x java >/dev/null 2>&1; then
            echo "ERROR: Java did not restart after Qt exited." >&2
            exit 23
        fi
    fi
    exit "$qt_status"
}

mkdir -p "$APP_DIR/validation-home"
trap restart_java EXIT INT TERM

if [[ -n "$JAVA_PID" ]]; then
    : >"$SESSION_ENV"
    while IFS= read -r entry; do
        case "$entry" in
            DISPLAY=*|WAYLAND_DISPLAY=*|XAUTHORITY=*|XDG_RUNTIME_DIR=*|XDG_SESSION_TYPE=*|DBUS_SESSION_BUS_ADDRESS=*|DESKTOP_SESSION=*|XDG_CURRENT_DESKTOP=*|XDG_SESSION_DESKTOP=*)
                printf 'export %q\n' "$entry" >>"$SESSION_ENV"
                ;;
        esac
    done < <(tr '\0' '\n' <"/proc/$JAVA_PID/environ")
    chmod 600 "$SESSION_ENV"
    # shellcheck disable=SC1090
    source "$SESSION_ENV"
    JAVA_STOPPED=1
    kill -TERM "$JAVA_PID"
    for _ in {1..50}; do
        if ! kill -0 "$JAVA_PID" 2>/dev/null; then
            break
        fi
        sleep 0.1
    done
    if kill -0 "$JAVA_PID" 2>/dev/null; then
        echo "Java did not stop cleanly; refusing to force it closed." >&2
        exit 22
    fi
fi

"$APP_DIR/launch-offline.sh" "$@"
