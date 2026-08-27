# shellcheck shell=bash

monarchy_copy_if_missing() {
    local src=$1
    local dest=$2
    if [ -e "$dest" ]; then
        return 0
    fi
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
}

monarchy_seed_hyprland_config() {
    local src="$MONARCHY_SRC/config/hypr"
    local dest="$HOME/.config/hypr"
    local f
    [ -d "$src" ] || monarchy_die "missing $src"
    mkdir -p "$dest"
    for f in "$src"/*; do
        [ -e "$f" ] || continue
        monarchy_copy_if_missing "$f" "$dest/$(basename "$f")"
    done
    monarchy_log "seeded $dest (existing files left in place)"
}

monarchy_seed_branding() {
    local dest="$HOME/.config/omarchy/branding"
    [ -f "$MONARCHY_SRC/logo.txt" ] || monarchy_die "missing $MONARCHY_SRC/logo.txt"
    [ -f "$MONARCHY_SRC/icon.txt" ] || monarchy_die "missing $MONARCHY_SRC/icon.txt"
    mkdir -p "$dest"
    monarchy_copy_if_missing "$MONARCHY_SRC/logo.txt" "$dest/logo.txt"
    monarchy_copy_if_missing "$MONARCHY_SRC/icon.txt" "$dest/icon.txt"
    [ -f "$MONARCHY_SRC/icon.png" ] && monarchy_copy_if_missing "$MONARCHY_SRC/icon.png" "$dest/icon.png"
    # Omarchy skel names. ttfx reads screensaver.txt; missing it crash-loops the
    # fullscreen terminal so a key cannot dismiss it.
    monarchy_copy_if_missing "$MONARCHY_SRC/logo.txt" "$dest/screensaver.txt"
    monarchy_copy_if_missing "$MONARCHY_SRC/icon.txt" "$dest/about.txt"
}

monarchy_seed_uwsm_user_env() {
    local dest="$HOME/.config/uwsm/env.d/20-monarchy-terminal"
    mkdir -p "$(dirname "$dest")"
    if [ -f "$dest" ]; then
        return 0
    fi
    printf 'export TERMINAL=ghostty\n' >"$dest"
    monarchy_log "wrote $dest"
}

monarchy_mark_first_run_done() {
    local dir="$HOME/.local/state/omarchy/done"
    mkdir -p "$dir" "$HOME/.local/state/omarchy"
    : >"$dir/first-run-user"
    : >"$HOME/.local/state/omarchy/first-run-user"
    monarchy_log "marked first-run complete for $USER"
}

monarchy_user_xcompose() {
    local dest="$HOME/.XCompose"
    local include="$MONARCHY_PATH/default/xcompose"
    [ -f "$dest" ] && return 0
    [ -f "$include" ] || return 0
    cat >"$dest" <<EOF
# Run omarchy-restart-xcompose to apply changes
include "$include"
EOF
}

monarchy_user_theme() {
    export PATH="$MONARCHY_PATH/bin:$PATH"
    export OMARCHY_PATH
    export OMARCHY_SETUP_CONTEXT=monarchy-setup
    export OMARCHY_THEME_HEADLESS=1
    if [ ! -s "$HOME/.local/state/omarchy/current/theme.name" ]; then
        if ! omarchy-theme-set "Tokyo Night"; then
            monarchy_log "warning: omarchy-theme-set Tokyo Night failed; set a theme from the Omarchy menu after login"
            return 0
        fi
    fi
    # Pi theme is optional; tokyo-night only has pi.json after templates run.
    omarchy-theme-set-pi --activate >/dev/null 2>&1 || true
    monarchy_log "theme $(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null)"
}

monarchy_seed_switch_user_bind() {
    local dest="$HOME/.config/hypr/bindings.lua"
    mkdir -p "$(dirname "$dest")"
    [ -f "$dest" ] || printf -- '-- Keep only your personal keybinding overrides here.\n' >"$dest"
    grep -q 'monarchy-switch-user' "$dest" 2>/dev/null && return 0
    cat >>"$dest" <<'EOF'

-- Switch user: lock, then SDDM greeter. Same chord on the lock screen.
o.bind("SUPER + CTRL + U", "Switch user", "monarchy-switch-user")
EOF
    monarchy_log "seeded Super+Ctrl+U switch-user bind in $dest"
}

monarchy_seed_kwallet_autostart() {
    local dest="$HOME/.config/hypr/autostart.lua"
    mkdir -p "$(dirname "$dest")"
    [ -f "$dest" ] || printf -- '-- Extra autostart processes.\n' >"$dest"
    grep -q pam_kwallet_init "$dest" 2>/dev/null && return 0
    cat >>"$dest" <<'EOF'

-- Unlock KWallet so NetworkManager can use Wi-Fi secrets saved under Plasma.
o.launch_on_start("/usr/lib/pam_kwallet_init")
EOF
    monarchy_log "seeded pam_kwallet_init in $dest"
}

monarchy_user_git() {
    local gitsh="$MONARCHY_SRC/install/user/git.sh"
    [ -f "$gitsh" ] || return 0
    bash "$gitsh" || true
}

monarchy_setup_user() {
    [ "$USER" != "root" ] || monarchy_die "user setup must not run as root"
    monarchy_seed_hyprland_config
    monarchy_seed_switch_user_bind
    monarchy_seed_kwallet_autostart
    monarchy_seed_branding
    monarchy_seed_uwsm_user_env
    monarchy_user_xcompose
    monarchy_user_git
    monarchy_user_theme
    monarchy_mark_first_run_done
    monarchy_keep_family_mime
    if [ -f "$HOME/.config/mimeapps.list" ] && grep -qi omarchy "$HOME/.config/mimeapps.list"; then
        monarchy_die "Omarchy mimeapps landed in $HOME/.config/mimeapps.list"
    fi
    monarchy_log "user config seeded for $USER"
    return 0
}
