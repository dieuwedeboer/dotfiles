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
#     upstream's to word. The one word this does change is "left" on a pack
#     the tree says is charging: stock picks that wording from UPower's state,
#     and gives it to anything that is not "charging" -- including the
#     pending-charge an EC that pulses the charge spends most of its time in.
#     A time to full under a "left" label is worse than no time at all.
#     The substitutions below are anchored on stock spacing, so if upstream
#     re-spaces that line the fill-in stops firing and the field reads as it
#     does today. Quiet no-op, not a mangled line.
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

# The direction the tree says the pack is going. On a ZBook that is the
# helper's smoothed status; anywhere else it is the kernel's own.
battery_state() {
    local bat
    bat=$(find_battery) || return 0
    read_attr "$bat/status" || return 0
}

# Microwatt-hours between here and the end of the current direction: down to
# empty, or up to full. Empty output for a pack that is going neither way.
battery_remaining_uwh() {
    local bat=$1 state now full

    state=$(read_attr "$bat/status") || return 0
    now=$(battery_energy_uwh "$bat" now) || return 0

    case "$state" in
        Discharging)
            printf '%s\n' "$now"
            ;;
        Charging)
            full=$(battery_energy_uwh "$bat" full) || return 0
            printf '%s\n' "$((full - now))"
            ;;
        # Full / Not charging / Unknown: the panel shows a dash for these
        # anyway, and a hold at a charge threshold has no end to predict.
        *) return 0 ;;
    esac
}

# The whole point of the wrapper. Empty output means "say nothing", which
# leaves the packaged em dash in place.
estimate_time() {
    local bat rate remaining

    bat=$(find_battery) || return 0
    rate=$(battery_rate_uw "$bat") || return 0
    remaining=$(battery_remaining_uwh "$bat") || return 0
    [ -n "$remaining" ] || return 0

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

# True when the time the packaged script printed cannot be squared with the
# rate printed beside it.
#
# The two come from different places. The rate is sysfs power_now, which the
# packaged script prefers over UPower precisely because UPower's lags. The
# time is energy divided by UPower's energy-rate and nothing else. Where that
# rate is merely stale the two still agree within a little; where sysfs is a
# corrected tree standing in for an EC that cannot be believed, they do not
# agree at all -- 14.5W beside "8h 5m to full" for 14Wh of headroom, which is
# an hour's charging, because UPower divided by a 1.8W sample of a pulse.
#
# A panel that prints both is claiming both. The factor of two is deliberately
# far wider than any lag: it fires on contradiction, not on disagreement.
time_contradicts_rate() {
    local text=$1 bat rate remaining hours minutes seconds

    [ -n "$text" ] || return 1
    bat=$(find_battery) || return 1
    rate=$(battery_rate_uw "$bat") || return 1
    remaining=$(battery_remaining_uwh "$bat") || return 1
    [ -n "$remaining" ] || return 1

    hours=0
    minutes=0
    [[ $text =~ ([0-9]+)h ]] && hours=${BASH_REMATCH[1]}
    [[ $text =~ ([0-9]+)m ]] && minutes=${BASH_REMATCH[1]}
    seconds=$((hours * 3600 + minutes * 60))
    [ "$seconds" -gt 0 ] || return 1

    awk -v uwh="$remaining" -v uw="$rate" -v s="$seconds" 'BEGIN {
        if (uw <= 0 || uwh <= 0) exit 1
        implied = uwh / (s / 3600.0)
        ratio = implied > uw ? implied / uw : uw / implied
        exit ratio > 2 ? 0 : 1
    }'
}

if [ "${1:-}" = "--shell" ]; then
    # An empty time field is ours to fill. A filled one is ours only when it
    # contradicts the rate on the line above it. No line at all means no
    # battery, and stays that way.
    packaged_time=$(awk -F'\t' '$1 == "time" { print $2 }' <<<"$out")
    if awk -F'\t' '$1 == "time" { found = 1 } END { exit !found }' <<<"$out" \
        && { [ -z "$packaged_time" ] || time_contradicts_rate "$packaged_time"; }; then
        human=$(estimate_time)
        if [ -n "$human" ]; then
            out=$(awk -F'\t' -v v="$human" 'BEGIN { OFS = "\t" }
                $1 == "time" { print $1, v; next }
                { print }' <<<"$out")
        fi
    fi
    printf '%s\n' "$out"
    exit 0
fi

# Human form. Stock renders "·  <time> left  ·" and "·  <time> to full  ·";
# with the time empty those collapse to the three-space shapes matched here.
# A filled figure is replaced only when it contradicts the rate beside it.
packaged_time=$(sed -n 's/.*·  \(.*\) \(left\|to full\)  ·.*/\1/p' <<<"$out")
if [ -z "$packaged_time" ] || time_contradicts_rate "$packaged_time"; then
    human=$(estimate_time)
    if [ -n "$human" ]; then
        # With $packaged_time empty these are stock's own collapsed shapes,
        # so the same two patterns cover a missing figure and a wrong one.
        word=left
        [ "$(battery_state)" = "Charging" ] && word="to full"
        case "$out" in
            *"·  $packaged_time left  ·"*)
                out=${out/"·  $packaged_time left  ·"/"·  $human $word  ·"}
                ;;
            *"·  $packaged_time to full  ·"*)
                out=${out/"·  $packaged_time to full  ·"/"·  $human to full  ·"}
                ;;
        esac
    fi
fi
printf '%s\n' "$out"
