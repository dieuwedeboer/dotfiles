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
conf="$MISC/sddm/zz-omarchy-sddm.conf"
[ -f "$qml" ] || fail "missing $qml"
[ -f "$conf" ] || fail "missing $conf"
[ ! -f "$MISC/sddm/99-omarchy-sddm.conf" ] \
    || fail "stale 99-omarchy-sddm.conf still in the repo; it loses to kde_settings.conf"

grep -q '#1a1b26' "$qml" || fail "Main.qml missing #1a1b26 token"
grep -q '#ffffff' "$qml" || fail "Main.qml missing #ffffff token"
grep -q 'cycleUser' "$qml" || fail "Main.qml missing cycleUser"
grep -q 'cycleSession' "$qml" || fail "Main.qml missing cycleSession"
grep -q 'prefersPlasma' "$qml" || fail "Main.qml missing prefersPlasma"
grep -q 'amie' "$qml" || fail "Main.qml missing family user amie"
grep -q 'olivier' "$qml" || fail "Main.qml missing family user olivier"
grep -q 'Qt.Key_Tab' "$qml" || fail "Main.qml missing Tab user cycle"
grep -q 'Qt.Key_Down' "$qml" || fail "Main.qml missing Down session cycle"
grep -q 'background.jpg' "$qml" || fail "Main.qml missing optional background.jpg overlay"
if grep -q 'name.indexOf("uwsm")' "$qml"; then
    fail "Main.qml still auto-picks the first uwsm session"
fi

grep -q '^Current=omarchy$' "$conf" || fail "conf Current is not omarchy"
grep -q 'start-hyprland' "$conf" || fail "conf missing start-hyprland"
grep -q '^DisplayServer=wayland$' "$conf" || fail "conf missing DisplayServer=wayland"
if grep -Eq '^[[:space:]]*User=[[:space:]]*[^[:space:]]+' "$conf"; then
    fail "conf sets Autologin User"
fi
conf_name=$(basename "$conf")
[ "$conf_name" = "zz-omarchy-sddm.conf" ] || fail "conf must be zz-omarchy-sddm.conf, got $conf_name"
LC_ALL=C awk -v n="$conf_name" 'BEGIN { exit !(n > "kde_settings.conf") }' \
    || fail "$conf_name sorts before kde_settings.conf; Theme.Current=breeze would win"
LC_ALL=C awk -v n="99-omarchy-sddm.conf" 'BEGIN { exit !(n < "kde_settings.conf") }' \
    || fail "lexicographic fixture broken: 99-omarchy should lose to kde_settings.conf"

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
echo "$refresh_body" | grep -q 'monarchy_sddm_follow_unlock' \
    && fail "monarchy_refresh_sddm must stay stock overlay (Unlock default)"
echo "$refresh_body" | grep -q 'monarchy_sddm_apply_theme' \
    && fail "monarchy_refresh_sddm must stay stock overlay (Unlock default)"
if grep -q 'current/theme.name' "$SCRIPT_DIR/sddm.sh"; then
    fail "sddm.sh still restyles the greeter from the session theme"
fi
if grep -q 'current/theme.name' "$SCRIPT_DIR/splash.sh"; then
    fail "splash.sh still restyles Unlock from the session theme"
fi

maybe_body=$(awk '/^monarchy_splash_maybe_theme\(\)/,/^monarchy_splash\(\)/' "$SCRIPT_DIR/splash.sh")
echo "$maybe_body" | grep -q 'monarchy_sddm_follow_unlock' \
    || fail "splash_maybe_theme does not follow Style > Unlock"
echo "$maybe_body" | grep -q 'plymouth-set-by-theme' \
    && fail "splash_maybe_theme still applies desktop theme to plymouth"

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

merge_tmp=$(mktemp -d)
cleanup_merge() { rm -rf "$merge_tmp"; }
trap cleanup_merge EXIT
mkdir -p "$merge_tmp/sys" "$merge_tmp/etc"
printf '[Theme]\nCurrent=breeze\n' >"$merge_tmp/sys/general.conf"
printf '[Theme]\nCurrent=breeze\n' >"$merge_tmp/etc/kde_settings.conf"
printf '[Theme]\nCurrent=omarchy\n' >"$merge_tmp/etc/99-omarchy-sddm.conf"
export MONARCHY_SDDM_SYS_CONF_DIR="$merge_tmp/sys"
export MONARCHY_SDDM_USER_CONF_DIR="$merge_tmp/etc"
export MONARCHY_SDDM_LEGACY_CONF="$merge_tmp/missing-sddm.conf"
[ "$(monarchy_sddm_effective_current)" = breeze ] \
    || fail "99-omarchy-sddm.conf must lose to kde_settings.conf (the live bug)"
rm -f "$merge_tmp/etc/99-omarchy-sddm.conf"
install -m 644 "$conf" "$merge_tmp/etc/zz-omarchy-sddm.conf"
[ "$(monarchy_sddm_effective_current)" = omarchy ] \
    || fail "zz-omarchy-sddm.conf did not beat kde_settings.conf"
printf '[Theme]\nCurrent=breeze\n' >"$merge_tmp/legacy.conf"
export MONARCHY_SDDM_LEGACY_CONF="$merge_tmp/legacy.conf"
[ "$(monarchy_sddm_effective_current)" = breeze ] \
    || fail "/etc/sddm.conf must still override drop-ins"
rm -f "$merge_tmp/legacy.conf"
export MONARCHY_SDDM_LEGACY_CONF="$merge_tmp/missing-sddm.conf"
export MONARCHY_SDDM_CONF="$merge_tmp/etc/zz-omarchy-sddm.conf"
printf '[Theme]\nCurrent=omarchy\n' >"$merge_tmp/etc/99-omarchy-sddm.conf"
monarchy_sddm_install_conf
[ ! -e "$merge_tmp/etc/99-omarchy-sddm.conf" ] \
    || fail "install_conf left stale 99-omarchy-sddm.conf"
[ "$(monarchy_sddm_effective_current)" = omarchy ] \
    || fail "install_conf did not leave effective Current=omarchy"

overlay_misc=$(mktemp -d)
mkdir -p "$overlay_misc/sddm" "$merge_tmp/theme"
printf 'asset\n' >"$overlay_misc/sddm/background.jpg"
printf 'keep\n' >"$overlay_misc/sddm/Main.qml"
printf '[Theme]\nCurrent=omarchy\n' >"$overlay_misc/sddm/zz-omarchy-sddm.conf"
export MONARCHY_MISC="$overlay_misc"
export MONARCHY_SDDM_THEME_DIR="$merge_tmp/theme"
monarchy_sddm_install_overlay_assets
[ -f "$merge_tmp/theme/background.jpg" ] \
    || fail "overlay did not copy background.jpg"
[ ! -e "$merge_tmp/theme/Main.qml" ] \
    || fail "overlay copied Main.qml (write_qml owns that)"
[ ! -e "$merge_tmp/theme/zz-omarchy-sddm.conf" ] \
    || fail "overlay copied the drop-in conf into the theme dir"
export MONARCHY_MISC="$MISC"
rm -rf "$overlay_misc"
unset MONARCHY_SDDM_SYS_CONF_DIR MONARCHY_SDDM_USER_CONF_DIR \
    MONARCHY_SDDM_LEGACY_CONF MONARCHY_SDDM_CONF MONARCHY_SDDM_THEME_DIR
trap - EXIT
cleanup_merge
cleanup_merge() { :; }

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

    # Desktop theme.name is osaka-jade/jade-test, Unlock is still default.
    # Stock Omarchy does not restyle the greeter from the session theme.
    : >"$MONARCHY_PLYMOUTH_THEME_DIR/omarchy.plymouth"
    cp "$CLONE/default/plymouth/logo.png" "$MONARCHY_PLYMOUTH_THEME_DIR/logo.png"
    monarchy_splash_maybe_theme
    grep -q '#1a1b26' "$MONARCHY_SDDM_THEME_DIR/Main.qml" \
        || fail "maybe_theme restyled stock Unlock from desktop theme.name"
    grep -q '#111c18' "$MONARCHY_SDDM_THEME_DIR/Main.qml" \
        && fail "maybe_theme applied jade colours while Unlock is default"
    cmp -s "$MONARCHY_SDDM_THEME_DIR/logo.png" \
        "$CLONE/default/sddm/omarchy/logo.png" \
        || fail "maybe_theme replaced the stock greeter logo while Unlock is default"

    # Re-apply recopies stock SDDM after Style > Unlock already set plymouth.
    rm -rf "$MONARCHY_SDDM_THEME_DIR"
    mkdir -p "$MONARCHY_SDDM_THEME_DIR"
    cp -a "$CLONE/default/sddm/omarchy/." "$MONARCHY_SDDM_THEME_DIR/"
    install -m 644 "$MISC/sddm/Main.qml" "$MONARCHY_SDDM_THEME_DIR/Main.qml"
    cp "$HOME/.config/omarchy/themes/jade-test/unlock.png" \
        "$MONARCHY_PLYMOUTH_THEME_DIR/logo.png"
    cmp -s "$HOME/.config/omarchy/themes/jade-test/unlock.png" \
        "$MONARCHY_PLYMOUTH_THEME_DIR/logo.png" \
        || fail "setup: plymouth logo should already match Unlock"
    grep -q '#1a1b26' "$MONARCHY_SDDM_THEME_DIR/Main.qml" \
        || fail "setup: stock overlay QML missing #1a1b26"

    monarchy_splash_maybe_theme
    grep -q '#111c18' "$MONARCHY_SDDM_THEME_DIR/Main.qml" \
        || fail "maybe_theme did not follow Unlock after a stock greeter copy"
    grep -q '#1a1b26' "$MONARCHY_SDDM_THEME_DIR/Main.qml" \
        && fail "maybe_theme left stock #1a1b26 on a themed Unlock"
    cmp -s "$MONARCHY_SDDM_THEME_DIR/logo.png" \
        "$HOME/.config/omarchy/themes/jade-test/unlock.png" \
        || fail "maybe_theme did not copy the Unlock logo"

    export HOME="$tmp/home-empty"
    mkdir -p "$HOME"
    rm -rf "$MONARCHY_SDDM_THEME_DIR"
    cp "$CLONE/default/plymouth/logo.png" "$MONARCHY_PLYMOUTH_THEME_DIR/logo.png"
    monarchy_refresh_sddm
    monarchy_sddm_follow_unlock
    grep -q '#1a1b26' "$MONARCHY_SDDM_THEME_DIR/Main.qml" \
        || fail "follow_unlock on default plymouth should leave stock tokens"
    grep -q '#111c18' "$MONARCHY_SDDM_THEME_DIR/Main.qml" \
        && fail "follow_unlock on default plymouth restyled the greeter"
else
    echo "test-sddm: skip live theme restyle (no $CLONE/default/sddm/omarchy)" >&2
fi

echo "sddm tests passed"
