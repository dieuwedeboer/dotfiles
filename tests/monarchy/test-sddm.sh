#!/usr/bin/env bash
# Greeter overlay and SDDM policy. No sudo, no systemctl enable.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"



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
grep -q 'isStockHyprlandSession' "$qml" || fail "Main.qml missing isStockHyprlandSession"
grep -q 'hyprland-uwsm.desktop' "$qml" || fail "Main.qml does not skip hyprland-uwsm.desktop"
if grep -q 'blob.indexOf("hyprland")' "$qml"; then
    fail "Main.qml must not hide Omarchy by matching the word hyprland"
fi
grep -q 'prefersPlasma' "$qml" || fail "Main.qml missing prefersPlasma"
# Do not name anyone here: read both lists out of the code and require they
# agree. The greeter's picker default and the AccountsService Session= writer
# have to describe the same people, or a user sees one default and gets another.
# Step 6 moves both to /etc/monarchy/users.conf and this reads that instead.
qml_plasma=$(sed -n '/function prefersPlasma/,/^  }/p' "$qml" \
    | grep -oE 'user === "[^"]+"' | sed 's/.*"\(.*\)"/\1/' | sort)
svc_plasma=$(grep -oE '^[[:space:]]*monarchy_accountsservice_session [^ ]+ plasma\.desktop' \
    "$LIB/sessions.sh" | awk '{print $2}' | sort)
[ -n "$qml_plasma" ] || fail "Main.qml prefersPlasma names nobody"
[ -n "$svc_plasma" ] || fail "sessions.sh defaults nobody to plasma.desktop"
[ "$qml_plasma" = "$svc_plasma" ] \
    || fail "greeter and AccountsService disagree on who defaults to Plasma"
grep -q 'Qt.Key_Tab' "$qml" || fail "Main.qml missing Tab user cycle"
grep -q 'Qt.Key_Down' "$qml" || fail "Main.qml missing Down session cycle"
grep -q 'background.jpg' "$qml" || fail "Main.qml missing optional background.jpg overlay"
if grep -q 'name.indexOf("uwsm")' "$qml"; then
    fail "Main.qml still auto-picks the first uwsm session"
fi

grep -q '^Current=omarchy$' "$conf" || fail "conf Current is not omarchy"
grep -q 'start-hyprland' "$conf" || fail "conf missing start-hyprland"
hypr="$MISC/sddm/hyprland.lua"
[ -f "$hypr" ] || fail "missing $hypr"
grep -q 'background_color' "$hypr" || fail "greeter hyprland.lua missing background_color"
grep -q 'rgb(26, 27, 38)' "$hypr" || fail "greeter hyprland.lua missing Unlock rgb"
boot_color="$MISC/hypr/boot-color.lua"
[ -f "$boot_color" ] || fail "missing $boot_color"
grep -q 'rgb(26, 27, 38)' "$boot_color" || fail "boot-color.lua missing Unlock rgb"
if grep -q '^SessionCommand=' "$conf"; then
    fail "conf must not set SessionCommand"
fi
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

apply_body=$(awk '/^monarchy_apply\(\)/,/^monarchy_update\(\)/' "$LIB/update.sh")
echo "$apply_body" | grep -q 'monarchy_keep_sddm' \
    || fail "monarchy_apply does not call monarchy_keep_sddm"
install_body=$(awk '/^monarchy_install_omarchy_session\(\)/,/^}$/' "$LIB/sessions.sh")
echo "$install_body" | grep -q 'monarchy_hide_stock_hyprland_sessions' \
    || fail "omarchy session install does not hide stock Hyprland sessions"
grep -q 'print "NoDisplay=true"' "$LIB/sessions.sh" \
    || fail "hide stock Hyprland sessions must write NoDisplay=true"
if grep -q 'print "Hidden=true"' "$LIB/sessions.sh"; then
    fail "must not set Hidden=true; uwsm start … hyprland.desktop would refuse it"
fi
grep -q 'is Hidden=true' "$LIB/sessions.sh" \
    || fail "hide must refuse a Hidden=true hyprland.desktop"
echo "$apply_body" | grep -q 'monarchy_splash_maybe_theme' \
    || fail "monarchy_apply does not call monarchy_splash_maybe_theme"
echo "$apply_body" | grep -q 'monarchy_keep_plasmalogin' \
    && fail "monarchy_apply still calls monarchy_keep_plasmalogin"

check_body=$(awk '/^monarchy_check\(\)/,/^monarchy_apply_lock\(\)/' "$LIB/update.sh")
echo "$check_body" | grep -q 'monarchy_assert_sddm_runtime' \
    || fail "monarchy_check does not call monarchy_assert_sddm_runtime"
echo "$check_body" | grep -q 'monarchy_check_hidden_hyprland_sessions' \
    || fail "monarchy_check does not assert stock Hyprland sessions are hidden"
echo "$check_body" | grep -q 'monarchy_keep_plasmalogin' \
    && fail "monarchy_check still calls monarchy_keep_plasmalogin"

grep -q 'monarchy_sddm_sync_assets' "$LIB/splash.sh" \
    || fail "plymouth-set does not sync SDDM"
grep -q 'skipped SDDM' "$LIB/splash.sh" \
    && fail "splash.sh still skips SDDM"
grep -q 'monarchy_refresh_sddm' "$LIB/splash.sh" \
    || fail "plymouth-reset / splash does not refresh SDDM"

refresh_body=$(awk '/^monarchy_refresh_sddm\(\)/,/^monarchy_keep_sddm\(\)/' "$LIB/sddm.sh")
echo "$refresh_body" | grep -q 'monarchy_sddm_follow_unlock' \
    && fail "monarchy_refresh_sddm must stay stock overlay (Unlock default)"
echo "$refresh_body" | grep -q 'monarchy_sddm_apply_theme' \
    && fail "monarchy_refresh_sddm must stay stock overlay (Unlock default)"
if grep -q 'current/theme.name' "$LIB/sddm.sh"; then
    fail "sddm.sh still restyles the greeter from the session theme"
fi
if grep -q 'current/theme.name' "$LIB/splash.sh"; then
    fail "splash.sh still restyles Unlock from the session theme"
fi

maybe_body=$(awk '/^monarchy_splash_maybe_theme\(\)/,/^monarchy_splash\(\)/' "$LIB/splash.sh")
echo "$maybe_body" | grep -q 'monarchy_sddm_follow_unlock' \
    || fail "splash_maybe_theme does not follow Style > Unlock"
echo "$maybe_body" | grep -q 'plymouth-set-by-theme' \
    && fail "splash_maybe_theme still applies desktop theme to plymouth"

[ -f "$LIB/stubs/wrap-sddm.sh" ] || fail "missing wrap-sddm.sh"
grep -q 'omarchy-refresh-sddm' "$LIB/overlay.sh" \
    || fail "overlay wrap_stub_for missing omarchy-refresh-sddm"

# shellcheck source=../../lib/monarchy/common.sh
source "$LIB/common.sh"
# shellcheck source=../../lib/monarchy/sessions.sh
source "$LIB/sessions.sh"
# shellcheck source=../../lib/monarchy/sddm.sh
source "$LIB/sddm.sh"
# shellcheck source=../../lib/monarchy/splash.sh
source "$LIB/splash.sh"

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
printf '[Unit]\nDescription=x\n' >"$overlay_misc/sddm/monarchy-sddm-resume.service"
export MONARCHY_MISC="$overlay_misc"
export MONARCHY_SDDM_THEME_DIR="$merge_tmp/theme"
monarchy_sddm_install_overlay_assets
[ -f "$merge_tmp/theme/background.jpg" ] \
    || fail "overlay did not copy background.jpg"
[ ! -e "$merge_tmp/theme/Main.qml" ] \
    || fail "overlay copied Main.qml (write_qml owns that)"
[ ! -e "$merge_tmp/theme/zz-omarchy-sddm.conf" ] \
    || fail "overlay copied the drop-in conf into the theme dir"
[ ! -e "$merge_tmp/theme/monarchy-sddm-resume.service" ] \
    || fail "overlay copied the resume unit into the theme dir"
export MONARCHY_MISC="$MISC"
rm -rf "$overlay_misc"
unset MONARCHY_SDDM_SYS_CONF_DIR MONARCHY_SDDM_USER_CONF_DIR \
    MONARCHY_SDDM_LEGACY_CONF MONARCHY_SDDM_CONF MONARCHY_SDDM_THEME_DIR
trap - EXIT
cleanup_merge
cleanup_merge() { :; }

sess=$merge_tmp/wayland-sessions
mkdir -p "$sess"
cat >"$sess/hyprland.desktop" <<'EOF'
[Desktop Entry]
Name=Hyprland
Exec=/usr/bin/start-hyprland
DesktopNames=Hyprland
EOF
cat >"$sess/hyprland-uwsm.desktop" <<'EOF'
[Desktop Entry]
Name=Hyprland (uwsm-managed)
Exec=uwsm start -e -D Hyprland hyprland.desktop
TryExec=uwsm
DesktopNames=Hyprland
EOF
cat >"$sess/omarchy.desktop" <<'EOF'
[Desktop Entry]
Name=Omarchy (Hyprland uwsm)
Exec=uwsm start -g -1 -e -D Hyprland hyprland.desktop
TryExec=uwsm
DesktopNames=Hyprland
EOF
cat >"$sess/plasma.desktop" <<'EOF'
[Desktop Entry]
Name=Plasma (Wayland)
Exec=/usr/bin/startplasma-wayland
DesktopNames=KDE
EOF
export MONARCHY_WAYLAND_SESSIONS_DIR=$sess
export MONARCHY_LOG=$merge_tmp/log
monarchy_hide_stock_hyprland_sessions
grep -q '^NoDisplay=true' "$sess/hyprland.desktop" \
    || fail "did not set NoDisplay on hyprland.desktop"
grep -q '^NoDisplay=true' "$sess/hyprland-uwsm.desktop" \
    || fail "did not set NoDisplay on hyprland-uwsm.desktop"
if grep -q '^Hidden=' "$sess/hyprland.desktop"; then
    fail "set Hidden on hyprland.desktop (uwsm would refuse it)"
fi
if grep -q '^NoDisplay=' "$sess/omarchy.desktop"; then
    fail "hid omarchy.desktop"
fi
if grep -q '^NoDisplay=' "$sess/plasma.desktop"; then
    fail "hid plasma.desktop"
fi
monarchy_hide_stock_hyprland_sessions
n=$(grep -c '^NoDisplay=true' "$sess/hyprland.desktop")
[ "$n" -eq 1 ] || fail "NoDisplay seed is not idempotent ($n)"
monarchy_check_hidden_hyprland_sessions

printf '\nHidden=true\n' >>"$sess/hyprland.desktop"
if ( monarchy_hide_stock_hyprland_sessions ) 2>/dev/null; then
    fail "hide did not refuse Hidden=true on hyprland.desktop"
fi
unset MONARCHY_WAYLAND_SESSIONS_DIR
rm -rf "$merge_tmp"

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
    grep -q 'background_color' "$MONARCHY_SDDM_HYPR" \
        || fail "refresh_sddm did not install greeter hyprland.lua overlay"
    grep -q 'rgb(26, 27, 38)' "$MONARCHY_SDDM_HYPR" \
        || fail "refresh_sddm greeter hyprland.lua missing Unlock background"
    [ ! -f "$MONARCHY_SDDM_THEME_DIR/hyprland.lua" ] \
        || fail "hyprland.lua overlay leaked into the QML theme dir"
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
