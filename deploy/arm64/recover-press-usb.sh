#!/bin/bash
set -euo pipefail

if (( EUID != 0 )); then
    echo "Run this recovery as root." >&2
    exit 77
fi

controller=fd8c0000.usb
driver=/sys/bus/platform/drivers/ohci-platform

[[ -e "/sys/bus/platform/devices/$controller" ]] || {
    echo "PRESS-USB-RECOVERY controller=$controller result=missing" >&2
    exit 66
}

# Keep the dedicated Press OHCI host and its root hub out of runtime suspend.
echo on > "/sys/bus/platform/devices/$controller/power/control"
if [[ -e /sys/bus/usb/devices/usb6/power/control ]]; then
    echo on > /sys/bus/usb/devices/usb6/power/control
fi

# Re-probe only the dedicated Press USB host. Back Gauge is on fd840000/usb4.
echo "$controller" > "$driver/unbind"
sleep 1
echo "$controller" > "$driver/bind"
udevadm settle --timeout=10

# Rebinding recreates the root hub and resets its runtime-power policy.
echo on > "/sys/bus/platform/devices/$controller/power/control"
if [[ -e /sys/bus/usb/devices/usb6/power/control ]]; then
    echo on > /sys/bus/usb/devices/usb6/power/control
fi

if lsusb -d 2341:0069 >/dev/null 2>&1 || lsusb -d 1a86:7523 >/dev/null 2>&1; then
    echo "PRESS-USB-RECOVERY controller=$controller result=enumerated"
    exit 0
fi

echo "PRESS-USB-RECOVERY controller=$controller result=still-absent" >&2
exit 1
