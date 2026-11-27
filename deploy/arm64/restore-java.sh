#!/bin/bash
set -euo pipefail

APP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
QT_PID="$(pgrep -o -x prototype || true)"

if [[ -n "$QT_PID" ]]; then
    kill -TERM "$QT_PID"
    for _ in {1..150}; do
        if ! kill -0 "$QT_PID" 2>/dev/null; then
            break
        fi
        sleep 0.1
    done
    if kill -0 "$QT_PID" 2>/dev/null; then
        echo "Qt did not stop cleanly; refusing to force it closed." >&2
        exit 24
    fi
fi

for _ in {1..150}; do
    pgrep -x java >/dev/null 2>&1 && exit 0
    sleep 0.1
done

if [[ -f "$APP_DIR/validation-home/session.env" ]]; then
    # shellcheck disable=SC1090
    source "$APP_DIR/validation-home/session.env"
fi
nohup /home/cnc/start.sh >"$APP_DIR/validation-home/java-restart.log" 2>&1 &
for _ in {1..150}; do
    pgrep -x java >/dev/null 2>&1 && exit 0
    sleep 0.1
done

echo "ERROR: Java did not start." >&2
exit 23