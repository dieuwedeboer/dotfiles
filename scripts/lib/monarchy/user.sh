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
    mkdir -p "$dest"
    [ -f "$MONARCHY_SRC/logo.txt" ] && monarchy_copy_if_missing "$MONARCHY_SRC/logo.txt" "$dest/logo.txt"
    [ -f "$MONARCHY_SRC/icon.txt" ] && monarchy_copy_if_missing "$MONARCHY_SRC/icon.txt" "$dest/icon.txt"
    [ -f "$MONARCHY_SRC/icon.png" ] && monarchy_copy_if_missing "$MONARCHY_SRC/icon.png" "$dest/icon.png"
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
    local theme="$MONARCHY_SRC/install/user/theme.sh"
    [ -f "$theme" ] || return 0
    export PATH="$MONARCHY_PATH/bin:$PATH"
    export OMARCHY_PATH
    export OMARCHY_SETUP_CONTEXT=monarchy-setup
    export OMARCHY_THEME_HEADLESS=1
    if ! bash "$theme"; then
        monarchy_log "warning: theme.sh failed; set a theme from the Omarchy menu after login"
    fi
    return 0
}

monarchy_user_git() {
    local gitsh="$MONARCHY_SRC/install/user/git.sh"
    [ -f "$gitsh" ] || return 0
    bash "$gitsh" || true
}

monarchy_setup_user() {
    [ "$USER" != "root" ] || monarchy_die "user setup must not run as root"
    monarchy_seed_hyprland_config
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
