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
echo "$apply_body" | grep -q 'monarchy_splash_maybe_theme' \
    || fail "monarchy_apply does not call monarchy_splash_maybe_theme"
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

refresh_body=$(awk '/^monarchy_refresh_sddm\(\)/,/^monarchy_keep_sddm\(\)/' "$SCRIPT_DIR/sddm.sh")
echo "$refresh_body" | grep -q 'monarchy_sddm_apply_current_theme' \
    && fail "monarchy_refresh_sddm must stay stock overlay (Unlock default)"

maybe_body=$(awk '/^monarchy_splash_maybe_theme\(\)/,/^monarchy_splash\(\)/' "$SCRIPT_DIR/splash.sh")
echo "$maybe_body" | grep -q 'monarchy_sddm_apply_current_theme' \
    || fail "splash_maybe_theme does not restyle SDDM when plymouth already matches"
echo "$maybe_body" | grep -q 'cmp -s' \
    || fail "splash_maybe_theme no longer detects a matching plymouth logo"

[ -f "$SCRIPT_DIR/stubs/wrap-sddm.sh" ] || fail "missing wrap-sddm.sh"
grep -q 'omarchy-refresh-sddm' "$SCRIPT_DIR/overlay.sh" \
    || fail "overlay wrap_stub_for missing omarchy-refresh-sddm"

# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
# shellcheck source=sddm.sh
source "$SCRIPT_DIR/sddm.sh"
# shellcheck source=splash.sh
source "$SCRIPT_DIR/splash.sh"

monarchy_sudo() { "$@"; }

CLONE="${MONARCHY_SRC:-/usr/local/src/monarchy/omarchy}"
if [ -d "$CLONE/default/sddm/omarchy" ] && [ -f "$CLONE/themes/osaka-jade/unlock.png" ]; then
    tmp=$(mktemp -d)
    cleanup_tmp() { rm -rf "$tmp"; }
    trap cleanup_tmp EXIT

    export HOME="$tmp/home"
    export OMARCHY_PATH="$CLONE"
    export MONARCHY_SRC="$CLONE"
    export MONARCHY_SDDM_THEME_DIR="$tmp/sddm"
    export MONARCHY_SDDM_HYPR="$tmp/hyprland.lua"
    export MONARCHY_PLYMOUTH_THEME_DIR="$tmp/plymouth"
    export MONARCHY_LOG="$tmp/log"

    mkdir -p "$HOME/.local/state/omarchy/current" \
        "$HOME/.config/omarchy/themes/jade-test" \
        "$MONARCHY_PLYMOUTH_THEME_DIR"
    printf 'jade-test\n' >"$HOME/.local/state/omarchy/current/theme.name"
    cat >"$HOME/.config/omarchy/themes/jade-test/colors.toml" <<'EOF'
background = "#111c18"
foreground = "#C1C497"
EOF
    cp "$CLONE/themes/osaka-jade/unlock.png" \
        "$HOME/.config/omarchy/themes/jade-test/unlock.png"

    monarchy_refresh_sddm
    grep -q '#1a1b26' "$MONARCHY_SDDM_THEME_DIR/Main.qml" \
        || fail "refresh_sddm should keep stock overlay tokens"
    grep -q 'cycleUser' "$MONARCHY_SDDM_THEME_DIR/Main.qml" \
        || fail "refresh_sddm did not overlay multi-user Main.qml"
    cmp -s "$MONARCHY_SDDM_THEME_DIR/logo.png" \
        "$CLONE/default/sddm/omarchy/logo.png" \
        || fail "refresh_sddm should keep the stock clone logo"

    # Apply copies stock SDDM after plymouth is already this theme. The
    # maybe_theme early-return used to skip the greeter in that case.
    rm -rf "$MONARCHY_SDDM_THEME_DIR"
    mkdir -p "$MONARCHY_SDDM_THEME_DIR"
    cp -a "$CLONE/default/sddm/omarchy/." "$MONARCHY_SDDM_THEME_DIR/"
    install -m 644 "$MISC/sddm/Main.qml" "$MONARCHY_SDDM_THEME_DIR/Main.qml"
    : >"$MONARCHY_PLYMOUTH_THEME_DIR/omarchy.plymouth"
    cp "$HOME/.config/omarchy/themes/jade-test/unlock.png" \
        "$MONARCHY_PLYMOUTH_THEME_DIR/logo.png"
    cmp -s "$HOME/.config/omarchy/themes/jade-test/unlock.png" \
        "$MONARCHY_PLYMOUTH_THEME_DIR/logo.png" \
        || fail "setup: plymouth logo should already match the theme"
    grep -q '#1a1b26' "$MONARCHY_SDDM_THEME_DIR/Main.qml" \
        || fail "setup: stock overlay QML missing #1a1b26"

    monarchy_splash_maybe_theme
    grep -q '#111c18' "$MONARCHY_SDDM_THEME_DIR/Main.qml" \
        || fail "maybe_theme skipped SDDM because plymouth already matched"
    grep -q '#1a1b26' "$MONARCHY_SDDM_THEME_DIR/Main.qml" \
        && fail "maybe_theme left stock #1a1b26 on a matching plymouth"
    cmp -s "$MONARCHY_SDDM_THEME_DIR/logo.png" \
        "$HOME/.config/omarchy/themes/jade-test/unlock.png" \
        || fail "maybe_theme did not copy the theme unlock logo"

    export HOME="$tmp/home-empty"
    mkdir -p "$HOME"
    rm -rf "$MONARCHY_SDDM_THEME_DIR"
    monarchy_refresh_sddm
    monarchy_sddm_apply_current_theme
    grep -q '#1a1b26' "$MONARCHY_SDDM_THEME_DIR/Main.qml" \
        || fail "apply_current_theme without theme.name should leave stock tokens"
    grep -q '#111c18' "$MONARCHY_SDDM_THEME_DIR/Main.qml" \
        && fail "apply_current_theme without theme.name restyled the greeter"
else
    echo "test-sddm: skip live theme restyle (no $CLONE/default/sddm/omarchy)" >&2
fi

echo "sddm tests passed"
