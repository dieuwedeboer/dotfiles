#!/usr/bin/env bash
set -e
[ "${VERBOSE:-0}" = 1 ] && set -x

# =========================================================================
# HP ZBook (DMI vendor HP + product_name/family contains ZBook).
# First machine: HP ZBook 14u G6 (Whiskey Lake i7-8665U, board 8549,
# KBC 52.70.00) + AMD Radeon Pro WX 3200.
# =========================================================================
# Scope of THIS script:
#   - DMI-gated. Skip on anything that is not an HP ZBook.
#   - Publish a synthetic BAT0/power_now so Omarchy can show watts, and a
#     synthetic BAT0/status so a consumer knows which way to count, beside
#     symlinks to the kernel's charge/energy and voltage attributes.
#   - Relax RAPL energy_uj so wheel can read package/psys counters.
# What this script deliberately does NOT do:
#   - Install TLP / tlp-pd (conflicts with power-profiles-daemon).
#   - Touch power-profiles-daemon, platform_profile, or CPU governors.
#   - Bind-mount over kernel BAT0 (that would feed UPower a fake rate).
#   - Guess EC current registers (ztop's 0x9d/0xa5 are a later ZBook).
#   - Do the time-remaining arithmetic. That belongs to the consumer, and
#     lib/monarchy/stubs/wrap-battery-status.sh does it for Omarchy off this
#     tree. Nothing about it is ZBook-shaped once power_now exists.
#   - Enable thermald / intel-lpmd (lpmd is Alder Lake+; thermald is
#     unrelated to the 0W reading).
# =========================================================================
# Why the power panel shows 0W
#   ACPI _BST Present Rate is 0xFFFFFFFF (Unknown). Kernel still creates
#   current_now because the battery reports mAh units; reads return
#   ENODEV. omarchy-battery-status prefers that file over UPower's
#   energy-rate and prints 0W.
#
#   UPower does not have the number either, and an earlier version of this
#   comment said it did. /var/lib/upower/history-rate-* settles it: every
#   charging sample carries a rate, every discharging sample is 0.000. The
#   rate the kernel withholds is withheld from everyone.
#
#   That is also why there is no time left. UPower divides energy by
#   energy-rate; 0 leaves it nothing to divide, history-time-empty has only
#   ever held 0, and the panel shows a real "Time to full" on AC against an
#   em dash on battery.
#
#   That is the discharging half. Charging, current_now reads and is a
#   sawtooth: the EC pulse-charges, ramping 0 -> ~2.9A over ~12s, dropping
#   out, and repeating, with BAT0/status alternating Charging / Not charging
#   across the cycle. The mean is honest -- measured over 98s, current_now x
#   voltage_now averaged 15.8W against the charge counter's own 15.8W -- but
#   a single sample lands anywhere in 0-44.6W and the panel samples every 5s.
#   UPower turns the "Not charging" half into state: pending-charge, which
#   the power panel reads as a hold at a charge limit. This machine has no
#   charge_control_* at all, so that row rendered "Charge limit -" and
#   "Battery state: Holding" while the pack was filling at 27%. The panel
#   half of that is lib/monarchy/overlay-power.py; the helper half is a rate
#   and a status averaged over a window that spans several pulses.
# =========================================================================
# Lessons learned (dead ends) — DO NOT REDO.
# (A) TLP. tlp-stat does not create current_now either. tlp-pd Provides
#     power-profiles-daemon; monarchy aborts if TLP is installed.
# (B) RAPL as the battery rate. psys/package are SoC counters, not wall
#     power. Idle RAPL is a few watts below what the pack actually
#     delivers (panel, EC, USB). Fine as extra telemetry, wrong as the
#     Omarchy "rate" field.
# (C) Bind-mount over sysfs current_now. UPower would stop estimating
#     and echo the synthetic value back. Private OMARCHY_POWER_SUPPLY_PATH
#     tree avoids that.
# (D) ztop EC offsets. George Hotz's ztop reads 0x9d/0xa5 on a ZBook
#     Ultra G1a (Strix Halo). This G6 is a different KBC. Dump the EC
#     read-only (modprobe ec_sys, no write_support) and correlate 16-bit
#     fields with UPower's energy-rate before ever writing those regs.
# (E) Trusting BAT0/status, or current_now, while the charger is attached.
#     Both flip with the pulse. The charge counter over a minute is the only
#     thing on this EC that does not. Discharging is the one status this
#     firmware never gets wrong -- it is not reported on AC -- so that one is
#     taken at its word.
# (F) Deriving the rate from two absolute energy readings (charge x voltage).
#     voltage_now swings ~0.3V across a pulse, and 0.3V against a 1.2Ah pack
#     is 0.36Wh of apparent energy -- larger than the 0.26Wh a minute the
#     pack is actually taking on. It read 68W. Convert the delta, not the
#     readings, and measure it between counter steps: charge_now jumps a few
#     mAh every ~15s, and a window that does not line up with those jumps is
#     +-25% on the rate.
# =========================================================================

HW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=detect.sh
source "$HW_DIR/detect.sh"

LIB="$HW_DIR"
DEST_LIB=/usr/local/lib/zbook
UDEV_RULE=/etc/udev/rules.d/99-zbook-rapl.rules
SERVICE=/etc/systemd/system/zbook-battery-rate.service
UWSM_ENV=/usr/share/uwsm/env.d/20-zbook-battery

zbook_print_probe() {
    local bat current rapl
    echo "DMI vendor:  $(zbook_dmi_field sys_vendor)"
    echo "DMI product: $(zbook_dmi_field product_name)"
    echo "DMI family:  $(zbook_dmi_field product_family)"
    if zbook_detected; then
        echo "detect:      HP ZBook"
    else
        echo "detect:      not a ZBook"
    fi

    bat=/sys/class/power_supply/BAT0
    if [ -e "$bat/current_now" ]; then
        if current=$(cat "$bat/current_now" 2>/dev/null) && [ -n "$current" ]; then
            echo "current_now: $current uA"
        else
            echo "current_now: ENODEV (ACPI present rate unknown)"
        fi
    else
        echo "current_now: missing"
    fi

    if command -v upower >/dev/null 2>&1; then
        upower -i /org/freedesktop/UPower/devices/battery_BAT0 2>/dev/null \
            | awk '/energy-rate/ { printf "UPower rate: %s %s\n", $2, $3 }'
    fi

    rapl=/sys/class/powercap/intel-rapl:0/energy_uj
    if [ -e "$rapl" ]; then
        if [ -r "$rapl" ]; then
            echo "RAPL pkg:    readable"
        else
            echo "RAPL pkg:    root-only"
        fi
    else
        echo "RAPL pkg:    missing"
    fi

    if [ -r /run/zbook-battery/watts ]; then
        echo "helper:      $(tr -d '\n' </run/zbook-battery/watts)W ($(tr -d '\n' </run/zbook-battery/mode 2>/dev/null))"
    elif [ -x "$DEST_LIB/battery-rate" ]; then
        echo "helper:      installed, no /run/zbook-battery/watts yet"
    else
        echo "helper:      not installed"
    fi
}

install_file() {
    local src=$1 dest=$2 mode=$3
    if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
        echo "  $dest already current"
        return
    fi
    sudo install -m "$mode" "$src" "$dest"
    echo "  wrote $dest"
}

if [ "${1:-}" = "--check" ]; then
    echo "=== ZBook power probe (read-only) ==="
    zbook_print_probe
    exit 0
fi

echo "=== ZBook-specific setup ==="
zbook_print_probe

if ! zbook_detected; then
    echo "  not an HP ZBook (DMI), skipping"
    exit 0
fi

echo "Installing helper into $DEST_LIB..."
sudo mkdir -p "$DEST_LIB"
install_file "$LIB/battery-rate" "$DEST_LIB/battery-rate" 755
install_file "$LIB/rapl-perms.sh" "$DEST_LIB/rapl-perms.sh" 755
install_file "$LIB/detect.sh" "$DEST_LIB/detect.sh" 644

echo "Installing systemd unit..."
install_file "$HW_DIR/zbook-battery-rate.service" "$SERVICE" 644
sudo systemctl daemon-reload
if ! systemctl is-enabled zbook-battery-rate.service >/dev/null 2>&1; then
    sudo systemctl enable zbook-battery-rate.service
    echo "  enabled zbook-battery-rate.service"
else
    echo "  zbook-battery-rate.service already enabled"
fi
sudo systemctl restart zbook-battery-rate.service

echo "Installing RAPL udev rule..."
install_file "$HW_DIR/99-zbook-rapl.rules" "$UDEV_RULE" 644
sudo udevadm control --reload
sudo "$DEST_LIB/rapl-perms.sh" || true

echo "Installing UWSM env for Omarchy battery path..."
sudo mkdir -p "$(dirname "$UWSM_ENV")"
install_file "$HW_DIR/20-zbook-battery" "$UWSM_ENV" 644

echo "=== ZBook setup complete ==="
echo "Log out of Omarchy and back in so UWSM picks up OMARCHY_POWER_SUPPLY_PATH."
echo "omarchy-restart-shell is not enough on the first apply."
echo "Immediate check: OMARCHY_POWER_SUPPLY_PATH=/run/zbook-battery/power_supply omarchy-battery-status"
