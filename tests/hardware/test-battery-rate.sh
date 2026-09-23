#!/usr/bin/env bash
# ZBook battery-rate arithmetic, through its --compute entry point. No sudo,
# no real battery, no /run.
#
# The numbers are this machine's: a pack sitting at ~12Wh (1.05Ah at 11.4V)
# taking on 22.8 mAh a minute, which is 15.6W, while the EC pulses the charge
# on and off and voltage_now swings 11.34-11.64V across each pulse.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"

rate="$HARDWARE/hp-zbook/battery-rate"
[ -x "$rate" ] || fail "battery-rate is not executable"

# `t charge_uAh voltage_uV`, one line per 2s sample, charge moving by `step`
# each time. Given a second voltage, it alternates between the two the way a
# pulse does.
window() {
    local seconds=$1 start=$2 step=$3 v1=${4:-11400000} v2=${5:-} t=0 n=0 volts
    while [ "$t" -le "$seconds" ]; do
        volts=$v1
        [ -n "$v2" ] && [ $((n % 2)) -eq 1 ] && volts=$v2
        printf '%s %s %s\n' "$t" "$((start + n * step))" "$volts"
        t=$((t + 2))
        n=$((n + 1))
    done
}

compute() {
    local status=$1 ac=$2
    ZBOOK_STATUS="$status" ZBOOK_AC="$ac" "$rate" --compute
}

# --- a full window of charging ---------------------------------------------
out=$(window 60 1052631 760 | compute Charging 1)
read -r power status <<<"$out"
[ "$status" = "Charging" ] || fail "charging window: wanted Charging, got '$status'"
[ "$power" -gt 15000000 ] && [ "$power" -lt 16500000 ] \
    || fail "charging window: wanted ~15.6W, got ${power}uW"

# --- the counter jumps; the window must not be measured against the gap -----
# charge_now sits still and then jumps a few mAh every ~15s. Sampling it every
# 2s and taking first-and-last-sample measures whole jumps over a span that
# includes however much of a gap the window happened to end in. Here the last
# jump lands at 60s and sampling runs to 70s: measured sample to sample that
# is 28 mAh over 70s (16.4W), measured jump to jump it is 28 mAh over 60s.
jumpy() {
    local seconds=$1 start=$2 jump=$3 every=$4 t=0
    while [ "$t" -le "$seconds" ]; do
        printf '%s %s %s\n' "$t" "$((start + (t / every) * jump))" 11400000
        t=$((t + 2))
    done
}
out=$(jumpy 70 1052631 7000 15 | compute Charging 1)
read -r power status <<<"$out"
[ "$status" = "Charging" ] || fail "jumpy counter: wanted Charging, got '$status'"
[ "$power" -gt 18500000 ] && [ "$power" -lt 19800000 ] \
    || fail "jumpy counter: wanted ~19.1W measured jump to jump, got ${power}uW"

# --- the voltage swing is not power ----------------------------------------
# The pack is not moving, but voltage_now swings 0.3V across the pulse. Read
# as two absolute energies that is 0.36Wh of apparent charge -- 18W of pure
# artefact, and more than this pack ever actually draws. The delta is what
# gets converted, so it stays nothing.
out=$(window 60 1052631 0 11340000 11640000 | compute "Not charging" 1)
read -r power status <<<"$out"
[ "$power" = "0" ] || fail "voltage swing published as ${power}uW of power"
[ "$status" = "Not charging" ] || fail "voltage swing read as '$status'"

# The same swing over a pack that is charging must not move the answer much.
out=$(window 60 1052631 760 11340000 11640000 | compute Charging 1)
read -r power status <<<"$out"
[ "$power" -gt 15000000 ] && [ "$power" -lt 16500000 ] \
    || fail "charging under a swinging voltage: wanted ~15.6W, got ${power}uW"

# --- the pulse pause is still charging -------------------------------------
# What this whole file exists for: the kernel says Not charging because the EC
# has dropped out for a couple of seconds, but the counter has climbed all
# minute. Taking the flag at face value is what put "Holding" in the panel.
out=$(window 60 1052631 760 | compute "Not charging" 1)
read -r _ status <<<"$out"
[ "$status" = "Charging" ] || fail "pulse pause: wanted Charging, got '$status'"

# --- genuinely held --------------------------------------------------------
out=$(window 60 1052631 0 | compute "Not charging" 1)
read -r power status <<<"$out"
[ "$status" = "Not charging" ] || fail "held: wanted Not charging, got '$status'"
[ "$power" = "0" ] || fail "held: wanted 0W, got ${power}uW"

# A pack that drifts a mAh step or two (~11 mWh each, 0.7W over the window)
# is wobbling, not charging.
out=$(window 60 1052631 33 | compute "Not charging" 1)
read -r power status <<<"$out"
[ "$status" = "Not charging" ] || fail "drift read as charging: '$status'"
[ "$power" = "0" ] || fail "drift published as a rate: ${power}uW"

# A slow but real charge is still a charge: ~3.6W over the window.
out=$(window 60 1052631 175 | compute "Not charging" 1)
read -r _ status <<<"$out"
[ "$status" = "Charging" ] || fail "slow charge read as idle: '$status'"

# --- full stays full -------------------------------------------------------
out=$(window 60 4166000 0 | compute Full 1)
read -r _ status <<<"$out"
[ "$status" = "Full" ] || fail "full: wanted Full, got '$status'"

# --- discharging: the one flag this EC never gets wrong ---------------------
out=$(window 60 1052631 -760 | compute Discharging 0)
read -r power status <<<"$out"
[ "$status" = "Discharging" ] || fail "discharging: wanted Discharging, got '$status'"
[ "$power" -gt 15000000 ] && [ "$power" -lt 16500000 ] \
    || fail "discharging: rate is a magnitude, got ${power}uW"

# --- an energy-reporting pack needs no voltage -----------------------------
# Two fields instead of three. Nothing here is ZBook-shaped.
{ echo "0 12000000"; echo "60 12260000"; } >"${TMPDIR:-/tmp}/energy.$$"
out=$(compute Charging 1 <"${TMPDIR:-/tmp}/energy.$$")
rm -f "${TMPDIR:-/tmp}/energy.$$"
read -r power status <<<"$out"
[ "$status" = "Charging" ] || fail "energy pack: wanted Charging, got '$status'"
[ "$power" -gt 15000000 ] && [ "$power" -lt 16000000 ] \
    || fail "energy pack: wanted ~15.6W, got ${power}uW"

# --- too short a window is not an answer -----------------------------------
# Under two pulse cycles the window can sit inside one ramp or one drop-out.
if window 20 1052631 760 | compute Charging 1 >/dev/null; then
    fail "a 20s window was treated as an answer"
fi
out=$(window 20 1052631 760 | compute Charging 1)
[ "${out% *}" = "-" ] || fail "short window should publish no rate: '$out'"
[ "${out#* }" = "Charging" ] || fail "short window should fall back to the kernel flag: '$out'"

echo "zbook battery rate tests passed"
