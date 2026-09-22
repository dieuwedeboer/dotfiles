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
    cat >"$bin/upower" <<UPOWER
#!/usr/bin/env bash
case "\$1" in
    -e) echo /org/freedesktop/UPower/devices/battery_BAT0 ;;
    -i)
        cat <<'INFO'
  native-path:          BAT0
  battery
    present:             yes
    state:               discharging
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
printf 'Discharging\n' >"$tree/BAT0/status"

# --- UPower answering wins; the wrapper must not touch it ------------------
write_upower "    time to empty:       3.2 hours"
out=$(run --shell)
[ "$(field time "$out")" = "3h 12m" ] \
    || fail "UPower's own answer was overwritten: '$(field time "$out")'"
stock=$(MONARCHY_SRC="$SRC" OMARCHY_POWER_SUPPLY_PATH="$tree" PATH="$bin:$PATH" \
    "$SRC/bin/omarchy-battery-status" --shell)
[ "$out" = "$stock" ] || fail "wrapper is not byte-identical to stock when UPower answers"
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
