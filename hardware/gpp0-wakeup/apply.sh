#!/usr/bin/env bash
# Disable GPP0 as an ACPI wakeup source when the firmware exposes it.
set -e
[ "${VERBOSE:-0}" = 1 ] && set -x

HW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=detect.sh
source "$HW_DIR/detect.sh"

if ! gpp0_wakeup_detected; then
    echo "  GPP0 not in /proc/acpi/wakeup, skipping"
    exit 0
fi

SERVICE_FILE=/etc/systemd/system/disable-gpp0-wakeup.service
SRC="$HW_DIR/disable-gpp0-wakeup.service"

if [ -f "$SERVICE_FILE" ] && cmp -s "$SRC" "$SERVICE_FILE"; then
    echo "  disable-gpp0-wakeup.service already current"
    exit 0
fi

echo "  installing disable-gpp0-wakeup.service"
sudo cp "$SRC" "$SERVICE_FILE"
sudo systemctl daemon-reload
sudo systemctl enable --now disable-gpp0-wakeup.service
