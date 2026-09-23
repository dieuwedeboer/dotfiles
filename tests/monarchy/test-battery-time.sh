#!/usr/bin/env bash
# wrap-battery-status against fixture power_supply trees and a fake upower.
#
# Drives the real packaged omarchy-battery-status so the test covers the
# output it actually emits, not a restatement of it. No sudo, no real battery.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"

SRC=$(require_omarchy_tree) || exit 1
WRAP="$LIB/stubs/wrap-battery-status.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

bin="$work/bin"
mkdir -p "$bin"

# 42 Wh in the pack (3.5 Ah at 12 V), 48 Wh when full, drawing 12 W.
# Discharging that is 3.5 hours; the 6 Wh back to full is 30 minutes.
tree="$work/power_supply"
mkdir -p "$tree/BAT0" "$tree/AC"
printf 'Mains\n' >"$tree/AC/type"
printf '0\n' >"$tree/AC/online"
printf '3500000\n' >"$tree/BAT0/charge_now"
printf '4000000\n' >"$tree/BAT0/charge_full"
printf '12000000\n' >"$tree/BAT0/voltage_now"
printf '12000000\n' >"$tree/BAT0/power_now"
printf '136\n' >"$tree/BAT0/cycle_count"
printf 'Discharging\n' >"$tree/BAT0/status"

# UPower as this EC leaves it on battery: a rate of zero and no time at all.
# The extra line is spliced in for the case where UPower does answer.
write_upower() {
    local extra=${1:-}
    local state=${2:-discharging}
    cat >"$bin/upower" <<UPOWER
#!/usr/bin/env bash
case "\$1" in
    -e) echo /org/freedesktop/UPower/devices/battery_BAT0 ;;
    -i)
        cat <<'INFO'
  native-path:          BAT0
  battery
    present:             yes
    state:               $state
    energy:              42.0 Wh
    energy-full:         48.0 Wh
    energy-rate:         0 W
    voltage:             12.0 V
    percentage:          87%
$extra
INFO
        ;;
esac
UPOWER
    chmod 755 "$bin/upower"
}

run() {
    MONARCHY_SRC="$SRC" \
    OMARCHY_POWER_SUPPLY_PATH="$tree" \
    PATH="$bin:$PATH" \
        bash "$WRAP" "$@"
}

field() {
    awk -F'\t' -v k="$1" '$1 == k { print $2 }' <<<"$2"
}

write_upower

# --- discharging, UPower silent: the wrapper supplies the estimate ----------
out=$(run --shell)
[ "$(field time "$out")" = "3h 30m" ] \
    || fail "discharging estimate: wanted '3h 30m', got '$(field time "$out")'"
[ "$(field rate "$out")" = "12W" ] \
    || fail "wrapper disturbed the rate field: '$(field rate "$out")'"
[ "$(field cycles "$out")" = "136" ] \
    || fail "wrapper disturbed the cycles field: '$(field cycles "$out")'"

# The human one-liner carries it too, in stock's wording.
line=$(run)
case "$line" in
    *"·  3h 30m left  ·"*) ;;
    *) fail "human form not filled in: $line" ;;
esac

# --- charging counts up to full, not down to empty -------------------------
printf 'Charging\n' >"$tree/BAT0/status"
out=$(run --shell)
[ "$(field time "$out")" = "30m" ] \
    || fail "charging estimate: wanted '30m', got '$(field time "$out")'"

# --- charging, but UPower calls it pending-charge --------------------------
# An EC that pulses the charge spends most of a charge in pending-charge, and
# stock words anything that is not "charging" as "left". A time to full under
# that label is worse than the em dash it replaces, so the wrapper takes the
# wording from the same tree the estimate came from.
write_upower "" "pending-charge"
line=$(run)
case "$line" in
    *"·  30m to full  ·"*) ;;
    *"left"*) fail "pending-charge while charging still reads 'left': $line" ;;
    *) fail "pending-charge line not filled in: $line" ;;
esac

# The tree, not the UPower state, is what decides that. A pack the tree says
# is discharging keeps stock's wording whatever UPower calls it.
printf 'Discharging\n' >"$tree/BAT0/status"
line=$(run)
case "$line" in
    *"·  3h 30m left  ·"*) ;;
    *) fail "discharging wording changed: $line" ;;
esac
write_upower

# --- UPower answering wins; the wrapper must not touch it ------------------
write_upower "    time to empty:       3.2 hours"
out=$(run --shell)
[ "$(field time "$out")" = "3h 12m" ] \
    || fail "UPower's own answer was overwritten: '$(field time "$out")'"
stock=$(MONARCHY_SRC="$SRC" OMARCHY_POWER_SUPPLY_PATH="$tree" PATH="$bin:$PATH" \
    "$SRC/bin/omarchy-battery-status" --shell)
[ "$out" = "$stock" ] || fail "wrapper is not byte-identical to stock when UPower answers"
write_upower

# --- a UPower time that contradicts the rate beside it ---------------------
# UPower divides by its own energy-rate; the panel prints sysfs power_now.
# Where the two disagree by a factor, the row and the watts next to it cannot
# both be true. 42Wh at 12W is 3.5 hours, so "8h 5m" is UPower dividing by
# 1.5W -- a sample of a pulse, not a rate. Ours replaces it.
write_upower "    time to empty:       8.1 hours"
out=$(run --shell)
[ "$(field time "$out")" = "3h 30m" ] \
    || fail "contradictory UPower time survived: '$(field time "$out")'"
line=$(run)
case "$line" in
    *"·  3h 30m left  ·"*) ;;
    *) fail "contradictory time not replaced in the human form: $line" ;;
esac

# Merely stale is not contradictory. UPower lagging the instantaneous rate is
# what upstream's own comment describes, and it is not ours to overrule: 42Wh
# over 3.2h implies 13.1W against 12W showing.
write_upower "    time to empty:       3.2 hours"
out=$(run --shell)
[ "$(field time "$out")" = "3h 12m" ] \
    || fail "a merely stale UPower time was overwritten: '$(field time "$out")'"
write_upower

# --- no rate to divide by: say nothing rather than guess -------------------
mv "$tree/BAT0/power_now" "$work/power_now.bak"
out=$(run --shell)
[ -z "$(field time "$out")" ] \
    || fail "estimated a time with no rate: '$(field time "$out")'"
mv "$work/power_now.bak" "$tree/BAT0/power_now"

# --- a rate small enough to be sampling noise is not an answer -------------
# 0.1W against 42Wh is 420 hours. The helper's 60s window over a pack that
# steps in whole mAh can produce exactly that, so it is capped, not printed.
printf '100000\n' >"$tree/BAT0/power_now"
out=$(run --shell)
[ -z "$(field time "$out")" ] \
    || fail "printed an implausible estimate: '$(field time "$out")'"
printf '12000000\n' >"$tree/BAT0/power_now"

# --- a pack reporting energy units directly needs no voltage ---------------
rm "$tree/BAT0/charge_now" "$tree/BAT0/charge_full" "$tree/BAT0/voltage_now"
printf '42000000\n' >"$tree/BAT0/energy_now"
printf '48000000\n' >"$tree/BAT0/energy_full"
out=$(run --shell)
[ "$(field time "$out")" = "3h 30m" ] \
    || fail "energy-unit pack: wanted '3h 30m', got '$(field time "$out")'"

echo "battery time wrap tests passed"
