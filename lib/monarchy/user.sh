# shellcheck shell=bash
# Sourced into one shell by lib/monarchy.sh; common.sh state is in scope.
# shellcheck disable=SC2153

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
    monarchy_seed_hypr_boot_color
    monarchy_log "seeded $dest (existing files left in place)"
}

# First Hyprland frame matches Unlock #1a1b26 instead of the default grey.
monarchy_seed_hypr_boot_color() {
    local src="$MONARCHY_MISC/hypr/boot-color.lua"
    local dest="$HOME/.config/hypr/boot-color.lua"
    local hypr="$HOME/.config/hypr/hyprland.lua"
    [ -f "$src" ] || monarchy_die "missing $src"
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
    [ -f "$hypr" ] || return 0
    monarchy_seed_block "$hypr" boot-color 'hypr[.]boot-color' <<'EOF'
require("hypr.boot-color")
EOF
    monarchy_log "required hypr.boot-color from $hypr"
}

# Append a replaceable, marked block to a Lua config the user also edits.
# Same shape as the [omarchy] block in pacman.sh: drop whatever sits between
# the markers, then append the current text. Idempotent by construction, so
# changing the body no longer needs a hand-written migration the way the
# switch-user bind did when it gained locked = true.
#
# A block is also removable: step 5 hands these files to chezmoi, and a marked
# block can be deleted from a box that an earlier apply wrote to.
#
#   monarchy_seed_block <file> <id> [legacy_regex] <<'EOF'
#
# legacy_regex, when given, drops matching unmarked lines left by an older
# apply, so converting a box does not leave the line twice.
monarchy_new_bindings_file() {
    local dest=$1
    mkdir -p "$(dirname "$dest")"
    [ -f "$dest" ] \
        || printf -- '-- Keep only your personal keybinding overrides here.\n' >"$dest"
}

monarchy_seed_block() {
    local file=$1
    local id=$2
    local legacy=${3:-}
    local begin="-- BEGIN monarchy: $id"
    local end="-- END monarchy: $id"
    local body tmp kept

    body=$(cat)
    mkdir -p "$(dirname "$file")"
    [ -f "$file" ] || printf -- '-- Keep only your personal overrides here.\n' >"$file"

    tmp=$(mktemp)
    # Removing a block from the middle of the file leaves the blank line that
    # preceded it, and the replacement is appended at the end. Without
    # squeezing, every apply would add one blank line per block.
    kept=$(awk -v b="$begin" -v e="$end" -v legacy="$legacy" '
        $0 == b { skip = 1; next }
        $0 == e { skip = 0; next }
        skip { next }
        legacy != "" && $0 ~ legacy { next }
        /^[[:space:]]*$/ { blank++; next }
        { if (blank && NR > blank) print ""; blank = 0; print }
    ' "$file")
    # $(...) drops trailing newlines, so the block cannot accrue blank lines
    # ahead of it on every apply.
    printf '%s\n\n%s\n%s\n%s\n' "$kept" "$begin" "$body" "$end" >"$tmp"
    mv "$tmp" "$file"
}

# True when the file carries a monarchy block with this id.
monarchy_has_block() {
    local file=$1
    local id=$2
    [ -f "$file" ] || return 1
    grep -Fqx -- "-- BEGIN monarchy: $id" "$file"
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

monarchy_clear_terminal_override() {
    local dest="$HOME/.config/uwsm/env.d/20-monarchy-terminal"
    if [ -f "$dest" ]; then
        rm -f "$dest"
        monarchy_log "removed $dest (Omarchy owns the default terminal)"
    fi
}

# ~/.emacs.d shadows ~/.config/emacs. Chezmoi owns init.el under XDG;
# move a leftover ~/.emacs.d aside so Emacs reads the XDG layout.
monarchy_prefer_xdg_emacs() {
    local src="$HOME/.emacs.d"
    local dest
    [ -e "$src" ] || [ -L "$src" ] || return 0
    dest="${src}.bak"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        dest="${src}.bak.$(date +%Y%m%d%H%M%S)"
    fi
    mv "$src" "$dest"
    monarchy_log "moved $src -> $dest (Emacs uses ~/.config/emacs)"
}

MONARCHY_EMACS_THEME_URL="${MONARCHY_EMACS_THEME_URL:-https://github.com/berenddeboer/omarchy-emacs-theme.git}"
MONARCHY_EMACS_THEME_DIR="${MONARCHY_EMACS_THEME_DIR:-$HOME/.local/share/omarchy-emacs-theme}"

# omarchy-emacs (scottjones) is Omarchy 3: it restarts Emacs and does not
# use Quattro's themed/ + theme-set.d templates. Drop its assets/package.
monarchy_drop_omarchy_emacs_package() {
    rm -f "$HOME/.config/emacs/omarchy.el"
    rm -f "$HOME/.config/emacs/themes/omarchy-theme.el"
    rm -f "$HOME/.config/omarchy/themed/omarchy-colors.el.tpl"
    rm -f "$HOME/.config/omarchy/hooks/theme-set.d/omarchy-emacs"
    rm -f "$HOME/.config/omarchy/hooks/font-set.d/omarchy-emacs"
    if monarchy_pkg_exactly omarchy-emacs; then
        monarchy_log "removing omarchy-emacs (Quattro uses omarchy-emacs-theme)"
        monarchy_sudo pacman -R --noconfirm omarchy-emacs \
            || monarchy_log "warning: could not remove omarchy-emacs"
    fi
}

monarchy_sync_emacs_theme_repo() {
    local dest=$MONARCHY_EMACS_THEME_DIR
    export GIT_TERMINAL_PROMPT=0
    mkdir -p "$(dirname "$dest")"
    if [ -d "$dest/.git" ]; then
        if ! { git -C "$dest" fetch --quiet origin \
            && git -C "$dest" pull --ff-only --quiet; }; then
            monarchy_log "warning: could not update $dest"
        fi
        return 0
    fi
    if [ -e "$dest" ]; then
        monarchy_die "$dest exists and is not a git clone"
    fi
    git clone --depth 1 -- "$MONARCHY_EMACS_THEME_URL" "$dest" \
        || monarchy_die "failed to clone $MONARCHY_EMACS_THEME_URL"
}

monarchy_install_emacs_theme() {
    local setup="$MONARCHY_EMACS_THEME_DIR/bin/omarchy-emacs-theme-setup"
    monarchy_sync_emacs_theme_repo
    [ -x "$setup" ] || monarchy_die "missing $setup"
    if ! "$setup"; then
        monarchy_log "warning: omarchy-emacs-theme-setup failed"
        return 0
    fi
    monarchy_log "omarchy-emacs-theme hooked (themed/ + theme-set.d)"
}

monarchy_omarchy_pkg_add() {
    local pkg=$1
    if monarchy_pkg_installed "$pkg"; then
        return 0
    fi
    if ! command -v omarchy-pkg-add >/dev/null 2>&1; then
        monarchy_log "warning: omarchy-pkg-add missing; skipped $pkg"
        return 0
    fi
    monarchy_log "omarchy-pkg-add $pkg"
    omarchy-pkg-add "$pkg" || monarchy_log "warning: omarchy-pkg-add $pkg failed"
}

monarchy_user_emacs() {
    export OMARCHY_PATH
    export PATH="$MONARCHY_PATH/bin:${PATH:-/usr/bin}"
    if monarchy_pkg_exactly emacs; then
        monarchy_sudo pacman -R --noconfirm emacs \
            || monarchy_log "warning: could not remove emacs (conflicts with emacs-wayland)"
    fi
    # Keep emacs-wayland as explicit so dropping omarchy-emacs does not
    # leave it as an unused dependency.
    monarchy_sudo pacman -S --needed --noconfirm --asexplicit emacs-wayland \
        || monarchy_log "warning: could not install emacs-wayland"
    monarchy_drop_omarchy_emacs_package
    monarchy_prefer_xdg_emacs
    monarchy_install_emacs_theme
    systemctl --user enable --now emacs.service 2>/dev/null \
        || monarchy_log "warning: could not enable emacs.service"
}

# Webapp launchers, mise agent stubs, and the tools that used to be competing
# copies in lib/packages.sh (Spotify/Discord flatpaks, pacman bun/signal,
# AUR chrome/cursor-bin, curl grok/opencode/cursor-agent).
monarchy_user_omarchy_defaults() {
    export OMARCHY_PATH
    export PATH="$MONARCHY_PATH/bin:${PATH:-/usr/bin}"
    if [ -x "$MONARCHY_PATH/bin/omarchy-refresh-applications" ]; then
        omarchy-refresh-applications
    elif [ -f "$MONARCHY_SRC/install/user/mise.sh" ]; then
        bash "$MONARCHY_SRC/install/user/mise.sh"
    fi
    monarchy_drop_webapps
    monarchy_omarchy_pkg_add spotify
    monarchy_omarchy_pkg_add signal-desktop
    monarchy_omarchy_pkg_add cursor-bin
    monarchy_omarchy_pkg_add cursor-cli
    monarchy_omarchy_pkg_add omakade
    if ! monarchy_pkg_installed google-chrome; then
        if command -v omarchy-install-browser >/dev/null 2>&1; then
            monarchy_log "omarchy-install-browser chrome"
            omarchy-install-browser chrome \
                || monarchy_log "warning: omarchy-install-browser chrome failed"
        fi
    fi
    if command -v mise >/dev/null 2>&1 && ! mise which bun >/dev/null 2>&1; then
        monarchy_log "mise use -g bun@latest"
        mise use -g bun@latest >/dev/null || monarchy_log "warning: mise bun failed"
    fi
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
    monarchy_new_bindings_file "$dest"
    # The legacy pattern also catches a pre-block seed that lacked
    # locked = true, so the bind is replaced rather than duplicated.
    monarchy_seed_block "$dest" switch-user \
        'monarchy-switch-user|^-- Switch user: lock, then SDDM' <<'EOF'
-- Lock, then the SDDM greeter. locked = true so the chord also works while
-- ext-session-lock is held; Hyprland drops unlocked binds on the lock screen.
o.bind("SUPER + CTRL + U", "Switch user", "monarchy-switch-user", { locked = true })
EOF
    monarchy_log "seeded Super+Ctrl+U switch-user bind in $dest"
}

monarchy_drop_webapps() {
    local name desktop icon_slug
    local app_dir="$HOME/.local/share/applications"
    local icon_dir="$HOME/.local/share/icons/hicolor/256x256/apps"
    local old_icon_dir="$HOME/.local/share/applications/icons"
    [ "${#MONARCHY_APP_DROP[@]}" -gt 0 ] || return 0
    for name in "${MONARCHY_APP_DROP[@]}"; do
        desktop="$app_dir/${name}.desktop"
        [ -f "$desktop" ] || continue
        icon_slug=$(printf '%s\n' "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^[:alnum:]]\+/-/g; s/^-//; s/-$//')
        rm -f "$desktop"
        rm -f "$icon_dir/${icon_slug}.png" "$icon_dir/${name}.png" "$old_icon_dir/${name}.png"
        monarchy_log "dropped webapp $name"
    done
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$app_dir" >/dev/null 2>&1 || true
    fi
}

monarchy_seed_hypr_unbind() {
    local dest="$HOME/.config/hypr/bindings.lua"
    local chord=$1
    local slug chord_re
    slug=$(printf '%s' "$chord" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\+/-/g; s/^-//; s/-$//')
    # A chord is full of + signs, which are quantifiers in an ERE.
    chord_re=${chord//+/[+]}
    monarchy_new_bindings_file "$dest"
    monarchy_seed_block "$dest" "unbind-$slug" "^hl[.]unbind[(]\"$chord_re\"[)]\$" <<EOF
hl.unbind("$chord")
EOF
    monarchy_log "unbound $chord in $dest"
}

monarchy_seed_emacs_bind() {
    local dest="$HOME/.config/hypr/bindings.lua"
    monarchy_new_bindings_file "$dest"
    monarchy_seed_block "$dest" emacs-bind \
        'SUPER [+] SHIFT [+] E"|^-- Omarchy default is HEY email' <<'EOF'
-- Omarchy binds this chord to HEY email. This box uses emacsclient.
hl.unbind("SUPER + SHIFT + E")
o.bind("SUPER + SHIFT + E", "Emacs", "emacsclient -c --no-wait")
EOF
    monarchy_log "seeded Super+Shift+E emacsclient bind in $dest"
}

monarchy_seed_kwallet_autostart() {
    local dest="$HOME/.config/hypr/autostart.lua"
    mkdir -p "$(dirname "$dest")"
    [ -f "$dest" ] || printf -- '-- Extra autostart processes.\n' >"$dest"
    monarchy_seed_block "$dest" kwallet \
        'pam_kwallet_init|^-- Unlock KWallet' <<'EOF'
-- Unlock KWallet so NetworkManager can use Wi-Fi secrets saved under Plasma.
o.launch_on_start("/usr/lib/pam_kwallet_init")
EOF
    monarchy_log "seeded pam_kwallet_init in $dest"
}

# Omarchy's default input.lua sets compose:caps (Caps Lock becomes Compose).
# User kb_options replaces that. caps:capslock is the stock Caps Lock behavior.
monarchy_seed_capslock() {
    local dest="$HOME/.config/hypr/input.lua"
    mkdir -p "$(dirname "$dest")"
    [ -f "$dest" ] || printf -- '-- Keep only your personal input overrides here.\n' >"$dest"

    if grep -Eq '^[[:space:]]*kb_options' "$dest"; then
        if grep -Eq '^[[:space:]]*kb_options[[:space:]]*=[[:space:]]*"caps:capslock"' "$dest"; then
            return 0
        fi
        if ! grep -Eq '^[[:space:]]*kb_options.*compose:caps' "$dest"; then
            return 0
        fi
    fi

    monarchy_seed_block "$dest" capslock <<'EOF'
-- Caps Lock is Caps Lock. Omarchy's default (compose:caps) remaps it to Compose.
hl.config({
  input = {
    kb_options = "caps:capslock",
  },
})
EOF
    monarchy_log "restored Caps Lock in $dest"
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
    monarchy_seed_emacs_bind
    monarchy_seed_hypr_unbind "SUPER + SHIFT + C"
    monarchy_seed_hypr_unbind "SUPER + SHIFT + ALT + E"
    monarchy_seed_kwallet_autostart
    monarchy_seed_capslock
    monarchy_seed_branding
    monarchy_clear_terminal_override
    monarchy_user_omarchy_defaults
    monarchy_install_plugins
    monarchy_user_xcompose
    monarchy_user_git
    monarchy_user_theme
    # After theme-set so omarchy-emacs-theme-setup's `omarchy theme refresh`
    # can render the palette file before the daemon starts.
    monarchy_user_emacs
    monarchy_run_install_script "$MONARCHY_SRC/install/user/chromium.sh"
    monarchy_run_install_script "$MONARCHY_SRC/install/user/default-keyring.sh"
    monarchy_run_install_script "$MONARCHY_SRC/install/user/first-run/gnome-theme.sh"
    monarchy_run_install_script "$MONARCHY_SRC/install/user/first-run/gtk-primary-paste.sh"
    monarchy_enable_user_units
    monarchy_mark_first_run_done
    monarchy_keep_family_mime
    if [ -f "$HOME/.config/mimeapps.list" ] && grep -qi omarchy "$HOME/.config/mimeapps.list"; then
        monarchy_die "Omarchy mimeapps landed in $HOME/.config/mimeapps.list"
    fi
    monarchy_log "user config seeded for $USER"
    return 0
}
