#!/usr/bin/env bash
# Greeter overlay and SDDM policy. No sudo, no systemctl enable.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MISC="$SCRIPT_DIR/../../../misc/monarchy"

fail() {
    echo "test-sddm: $*" >&2
    exit 1
}

qml="$MISC/sddm/Main.qml"
conf="$MISC/sddm/99-omarchy-sddm.conf"
[ -f "$qml" ] || fail "missing $qml"
[ -f "$conf" ] || fail "missing $conf"

grep -q '#1a1b26' "$qml" || fail "Main.qml missing #1a1b26 token"
grep -q '#ffffff' "$qml" || fail "Main.qml missing #ffffff token"
grep -q 'cycleUser' "$qml" || fail "Main.qml missing cycleUser"
grep -q 'cycleSession' "$qml" || fail "Main.qml missing cycleSession"
grep -q 'prefersPlasma' "$qml" || fail "Main.qml missing prefersPlasma"
grep -q 'amie' "$qml" || fail "Main.qml missing family user amie"
grep -q 'olivier' "$qml" || fail "Main.qml missing family user olivier"
grep -q 'Qt.Key_Tab' "$qml" || fail "Main.qml missing Tab user cycle"
grep -q 'Qt.Key_Down' "$qml" || fail "Main.qml missing Down session cycle"
if grep -q 'name.indexOf("uwsm")' "$qml"; then
    fail "Main.qml still auto-picks the first uwsm session"
fi

grep -q '^Current=omarchy$' "$conf" || fail "conf Current is not omarchy"
grep -q 'start-hyprland' "$conf" || fail "conf missing start-hyprland"
grep -q '^DisplayServer=wayland$' "$conf" || fail "conf missing DisplayServer=wayland"
if grep -Eq '^[[:space:]]*User=[[:space:]]*[^[:space:]]+' "$conf"; then
    fail "conf sets Autologin User"
fi

grep -qx 'sddm' "$MISC/packages.deny" && fail "sddm is still in packages.deny"
grep -qx 'plasma-login-manager' "$MISC/packages.deny" \
    || fail "plasma-login-manager missing from packages.deny"
grep -qx 'omarchy-refresh-sddm' "$MISC/bin.wrap" \
    || fail "omarchy-refresh-sddm missing from bin.wrap"
if grep -qx 'omarchy-refresh-sddm' "$MISC/bin.deny"; then
    fail "omarchy-refresh-sddm is still denied"
fi

apply_body=$(awk '/^monarchy_apply\(\)/,/^monarchy_update\(\)/' "$SCRIPT_DIR/update.sh")
echo "$apply_body" | grep -q 'monarchy_keep_sddm' \
    || fail "monarchy_apply does not call monarchy_keep_sddm"
echo "$apply_body" | grep -q 'monarchy_keep_plasmalogin' \
    && fail "monarchy_apply still calls monarchy_keep_plasmalogin"

check_body=$(awk '/^monarchy_check\(\)/,/^monarchy_apply_lock\(\)/' "$SCRIPT_DIR/update.sh")
echo "$check_body" | grep -q 'monarchy_assert_sddm_runtime' \
    || fail "monarchy_check does not call monarchy_assert_sddm_runtime"
echo "$check_body" | grep -q 'monarchy_keep_plasmalogin' \
    && fail "monarchy_check still calls monarchy_keep_plasmalogin"

grep -q 'monarchy_sddm_sync_assets' "$SCRIPT_DIR/splash.sh" \
    || fail "plymouth-set does not sync SDDM"
grep -q 'skipped SDDM' "$SCRIPT_DIR/splash.sh" \
    && fail "splash.sh still skips SDDM"
grep -q 'monarchy_refresh_sddm' "$SCRIPT_DIR/splash.sh" \
    || fail "plymouth-reset / splash does not refresh SDDM"

[ -f "$SCRIPT_DIR/stubs/wrap-sddm.sh" ] || fail "missing wrap-sddm.sh"
grep -q 'omarchy-refresh-sddm' "$SCRIPT_DIR/overlay.sh" \
    || fail "overlay wrap_stub_for missing omarchy-refresh-sddm"

echo "sddm tests passed"
