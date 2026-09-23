#!/usr/bin/env bash
# Power panel overlay: the "Holding" gate. No sudo.
#
# Drives the real patcher against the real packaged panel, then runs the
# patched Model.js under node to assert what the panel will actually decide.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"

SRC=$(require_omarchy_tree "${1:-}") || exit 1
py="$LIB/overlay-power.py"

[ -f "$py" ] || fail "missing overlay-power.py"
grep -q 'monarchy_overlay_power_panel' "$LIB/update.sh" || fail "apply does not overlay the power panel"
grep -q 'monarchy_check_power_panel_overlay' "$LIB/update.sh" || fail "check does not verify the power panel overlay"
# splash-only recopies shell/plugins from the package tree, which throws the
# patch away unless it is re-applied in the same pass.
grep -q 'monarchy_overlay_power_panel' "$LIB/splash.sh" || fail "splash-only path drops the power panel overlay"

src_dir="$SRC/shell/plugins/panels/power"
[ -f "$src_dir/Model.js" ] || fail "package tree has no power panel Model.js"

# --- the drift guard -------------------------------------------------------
python3 "$py" check "$src_dir" || fail "power panel overlay check failed against the package tree"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -a "$src_dir/Model.js" "$src_dir/Panel.qml" "$tmp/"
python3 "$py" apply "$tmp" || fail "power panel overlay apply failed"

grep -q 'hasChargeLimit === false' "$tmp/Model.js" || fail "Model.js missing the charge-limit gate"
grep -q 'readonly property var hasChargeLimit' "$tmp/Panel.qml" || fail "Panel.qml missing hasChargeLimit"
grep -q 'upowerStates(), root.hasChargeLimit' "$tmp/Panel.qml" || fail "Panel.qml does not pass the gate to Model"
[ "$(grep -c 'upowerStates(), root.hasChargeLimit' "$tmp/Panel.qml")" -eq 3 ] \
    || fail "all three Model call sites must pass the gate"
grep -q 'batteryInfo.threshold' "$tmp/Panel.qml" || fail "the gate must read the threshold field"

# The gate is only as good as batteryInfo, and stock fills batteryInfo only
# while the panel is open. Without the seed the bar icon never leaves stock
# behaviour on a machine nobody has clicked the battery on.
grep -q 'root.batteryPresent && root.hasChargeLimit === undefined' "$tmp/Panel.qml" \
    || fail "Panel.qml does not seed the status read the gate needs"
grep -q 'triggeredOnStart: true' "$tmp/Panel.qml" || fail "the seed timer does not fire at startup"
# Self-limiting: the seed must stop once batteryInfo lands, not poll forever.
grep -q 'running: root.opened; repeat: true' "$tmp/Panel.qml" \
    || fail "the stock open-only refresh timer is gone; the seed may now be redundant"

# The overlay is dead on disk until the running shell is restarted.
grep -q 'monarchy_restart_shell' "$LIB/overlay.sh" || fail "no shell restart helper"
grep -q 'MONARCHY_SHELL_DIRTY=1' "$LIB/overlay.sh" || fail "the power panel overlay does not mark the shell stale"
grep -q 'monarchy_restart_shell' "$LIB/update.sh" || fail "apply never restarts the shell"
grep -q 'monarchy_restart_shell' "$LIB/splash.sh" || fail "splash-only never restarts the shell"

# Applying to already-patched files must fail rather than double-patch.
if python3 "$py" apply "$tmp" 2>/dev/null; then
    fail "overlay applied twice without complaining"
fi

# The package tree is not ours to write.
grep -q 'hasChargeLimit' "$src_dir/Model.js" && fail "package Model.js was patched"

# --- what the panel decides ------------------------------------------------
# Skipped rather than faked when node is absent, the same way run.sh skips
# shellcheck. The greps above still hold the shape.
if command -v node >/dev/null 2>&1; then
    node - "$tmp/Model.js" <<'JS' || fail "patched Model.js does not behave"
const Model = require(process.argv[2])
const states = { Charging: 1, Discharging: 2, FullyCharged: 3, PendingCharge: 4 }
const fail = (m) => { console.error("power panel: " + m); process.exit(1) }

// An HP ZBook 14u G6 at 27%, plugged in, mid pulse-pause: UPower says
// pending-charge and the machine has no charge_control_* at all.
const pulsing = { isPresent: true, state: states.PendingCharge, percentage: 0.27, changeRate: 0 }
if (Model.chargeThresholdActive(pulsing, false, states, false) !== false)
  fail("pending-charge with no limit is still read as a hold")
if (Model.modeLabel(pulsing, false, states, false) === "Threshold")
  fail("mode label still says Threshold with no limit")
if (Model.modeLabel(pulsing, false, states, false) !== "Charging")
  fail("mode label should say Charging: " + Model.modeLabel(pulsing, false, states, false))

// A machine that does have one is untouched: same answer as before the patch.
if (Model.chargeThresholdActive(pulsing, false, states, true) !== true)
  fail("a real charge limit no longer registers as a hold")
if (Model.modeLabel(pulsing, false, states, true) !== "Threshold")
  fail("a real charge limit lost its Threshold label")

// Before the first status read the panel knows nothing, and stock behaviour
// is what the bar icon keeps.
if (Model.chargeThresholdActive(pulsing, false, states, undefined) !== true)
  fail("unknown limit should keep the stock answer")

// The gate is not a licence to call a discharging pack held.
const onBattery = { isPresent: true, state: states.Discharging, percentage: 0.27, changeRate: 12 }
if (Model.chargeThresholdActive(onBattery, true, states, true) !== false)
  fail("discharging read as a hold")

// A pack genuinely held at its limit, with the limit reported.
const held = { isPresent: true, state: states.FullyCharged, percentage: 0.8, changeRate: 0 }
if (Model.chargeThresholdActive(held, false, states, true) !== true)
  fail("a pack held below full is not reported as holding")
if (Model.chargeThresholdActive(held, false, states, false) !== false)
  fail("held-below-full with no limit to hold at is still a hold")
JS
else
    echo "power panel: node absent, skipping the behavioural arm"
fi

echo "power panel overlay tests passed"
