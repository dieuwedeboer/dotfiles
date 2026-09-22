#!/usr/bin/env bash
# Overlay wrapper for omarchy-battery-status: fill in a missing time estimate.
#
# The packaged script takes "time to empty" / "time to full" from `upower -i`
# and from nowhere else. UPower divides energy by energy-rate, and energy-rate
# is whatever sysfs power_now (or current_now x voltage_now) reports. On an HP
# ZBook 14u G6 the EC writes 0xFFFFFFFF into ACPI _BST Present Rate while
# discharging, so current_now reads ENODEV, energy-rate is 0.000, and there is
# no rate to divide by. UPower's own history shows the asymmetry plainly:
# every charging sample carries a rate, every discharging sample is 0.000, and
# history-time-empty has never held anything but 0. The panel's "Time left"
# row is an em dash on battery and a real figure on AC.
#
# hardware/hp-zbook already publishes a synthetic power_now derived from
# charge_now deltas and points OMARCHY_POWER_SUPPLY_PATH at that private tree,
# which is what puts watts back in the panel. The time is still UPower's to
# give, and UPower still has no rate, so do the division here instead -- from
# the same tree the packaged script is already reading.
#
# Generic by construction rather than DMI-gated: it only fires when the
# packaged script left the field empty, and every input comes from
# $OMARCHY_POWER_SUPPLY_PATH. On a machine where UPower answers, the output is
# byte-identical to stock.
#
# Deliberately NOT done here:
#   - Feeding the synthetic rate back to UPower. That needs a bind-mount over
#     the kernel's current_now, which hardware/hp-zbook/apply.sh rejects as
#     dead end (C): UPower would stop estimating and echo our own number back.
#   - Re-rendering the human one-line form from scratch. Reusing the packaged
#     output keeps the three branches (holding / charging / discharging)
#     upstream's to word. The substitution below is anchored on stock spacing,
#     so if upstream re-spaces that line the fill-in stops firing and the field
#     reads as it does today. Quiet no-op, not a mangled line.
set -uo pipefail

packaged="${MONARCHY_SRC:-/usr/share/omarchy}/bin/omarchy-battery-status"
power_supply_path="${OMARCHY_POWER_SUPPLY_PATH:-/sys/class/power_supply}"

if [ ! -x "$packaged" ]; then
    echo "monarchy: missing $packaged" >&2
    exit 1
fi

out=$("$packaged" "$@")
status=$?
if [ "$status" -ne 0 ]; then
    [ -n "$out" ] && printf '%s\n' "$out"
    exit "$status"
fi

# Usage, --help, anything that is not a status read: pass straight through.
case "${1:-}" in
    "" | --shell) ;;
    *)
        printf '%s\n' "$out"
        exit 0
        ;;
esac

read_attr() {
    local file=$1 value
    # A sysfs attribute can exist and still fail to read -- current_now on this
    # EC is exactly that -- so -f alone is not enough to trust it.
    [ -f "$file" ] || return 1
    value=$(cat "$file" 2>/dev/null) || return 1
    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    [ -n "$value" ] || return 1
    printf '%s\n' "$value"
}

# The first BAT* in the tree carrying a charge or energy reading. The packaged
# script asks UPower for the native path; globbing instead keeps this from
# caring whether the tree is the kernel's or the ZBook helper's synthetic one.
find_battery() {
    local dir
    for dir in "$power_supply_path"/BAT*; do
        [ -d "$dir" ] || continue
        if read_attr "$dir/charge_now" >/dev/null || read_attr "$dir/energy_now" >/dev/null; then
            printf '%s\n' "$dir"
            return 0
        fi
    done
    return 1
}

# Microwatts, in the precedence the packaged script uses for its rate field.
battery_rate_uw() {
    local bat=$1 power current volts
    if power=$(read_attr "$bat/power_now"); then
        printf '%s\n' "$power"
        return 0
    fi
    current=$(read_attr "$bat/current_now") || return 1
    volts=$(read_attr "$bat/voltage_now") || return 1
    awk -v a="$current" -v v="$volts" 'BEGIN { printf "%d", a * v / 1000000 }'
}

# Microwatt-hours. Charge-reporting packs (this one) need the voltage to get
# there; energy-reporting packs hand it over directly.
battery_energy_uwh() {
    local bat=$1 which=$2 charge volts energy
    if energy=$(read_attr "$bat/energy_$which"); then
        printf '%s\n' "$energy"
        return 0
    fi
    charge=$(read_attr "$bat/charge_$which") || return 1
    volts=$(read_attr "$bat/voltage_now") || return 1
    awk -v c="$charge" -v v="$volts" 'BEGIN { printf "%d", c * v / 1000000 }'
}

# The whole point of the wrapper. Empty output means "say nothing", which
# leaves the packaged em dash in place.
estimate_time() {
    local bat state rate now full remaining

    bat=$(find_battery) || return 0
    state=$(read_attr "$bat/status") || return 0
    rate=$(battery_rate_uw "$bat") || return 0
    now=$(battery_energy_uwh "$bat" now) || return 0

    case "$state" in
        Discharging)
            remaining=$now
            ;;
        Charging)
            full=$(battery_energy_uwh "$bat" full) || return 0
            remaining=$((full - now))
            ;;
        # Full / Not charging / Unknown: the panel shows a dash for these
        # anyway, and a hold at a charge threshold has no end to predict.
        *) return 0 ;;
    esac

    awk -v uwh="$remaining" -v uw="$rate" 'BEGIN {
        if (uw <= 0 || uwh <= 0) exit 0
        seconds = uwh / uw * 3600
        # A 60s sampling window over a pack that steps in whole mAh can put the
        # rate near zero and the answer in the tens of hours. Better the em
        # dash than a confident lie.
        if (seconds > 24 * 3600) exit 0
        hours = int(seconds / 3600)
        minutes = int((seconds - hours * 3600) / 60)
        if (hours == 0) printf "%dm", minutes
        else if (minutes > 0) printf "%dh %dm", hours, minutes
        else printf "%dh", hours
    }'
}

if [ "${1:-}" = "--shell" ]; then
    # Only a present-but-empty time field is ours. No line at all means no
    # battery; a filled one means UPower answered.
    if awk -F'\t' '$1 == "time" && $2 == "" { found = 1 } END { exit !found }' <<<"$out"; then
        human=$(estimate_time)
        if [ -n "$human" ]; then
            out=$(awk -F'\t' -v v="$human" 'BEGIN { OFS = "\t" }
                $1 == "time" && $2 == "" { print $1, v; next }
                { print }' <<<"$out")
        fi
    fi
    printf '%s\n' "$out"
    exit 0
fi

# Human form. Stock renders "·  <time> left  ·" and "·  <time> to full  ·";
# with the time empty those collapse to the three-space shapes matched here.
case "$out" in
    *"·   left  ·"* | *"·   to full  ·"*)
        human=$(estimate_time)
        if [ -n "$human" ]; then
            out=${out/"·   left  ·"/"·  $human left  ·"}
            out=${out/"·   to full  ·"/"·  $human to full  ·"}
        fi
        ;;
esac
printf '%s\n' "$out"
