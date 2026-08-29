# shellcheck shell=bash
# SDDM as the household greeter. Stock Omarchy theme + Unlock, Monarchy Main.qml
# overlay for multi-user. Never autologin. Never leave plasma-login-manager
# installed next to sddm. The session theme does not restyle the greeter.
#
# Drop-in name is zz- so it sorts after leftover CachyOS/KDE files
# (kde_settings.conf Current=breeze). 99- loses that race: 'k' > '9'.

MONARCHY_SDDM_THEME_DIR="${MONARCHY_SDDM_THEME_DIR:-/usr/share/sddm/themes/omarchy}"
MONARCHY_SDDM_CONF="${MONARCHY_SDDM_CONF:-/etc/sddm.conf.d/zz-omarchy-sddm.conf}"
MONARCHY_SDDM_HYPR="${MONARCHY_SDDM_HYPR:-/usr/share/sddm/hyprland.lua}"
MONARCHY_SDDM_SYS_CONF_DIR="${MONARCHY_SDDM_SYS_CONF_DIR:-/usr/lib/sddm/sddm.conf.d}"
MONARCHY_SDDM_USER_CONF_DIR="${MONARCHY_SDDM_USER_CONF_DIR:-/etc/sddm.conf.d}"
MONARCHY_SDDM_LEGACY_CONF="${MONARCHY_SDDM_LEGACY_CONF:-/etc/sddm.conf}"

monarchy_sddm_qml_src() {
    printf '%s\n' "$MONARCHY_MISC/sddm/Main.qml"
}

monarchy_sddm_conf_src() {
    printf '%s\n' "$MONARCHY_MISC/sddm/zz-omarchy-sddm.conf"
}

# Last non-empty Theme.Current in SDDM merge order (sys drop-ins, then
# /etc/sddm.conf.d, then /etc/sddm.conf). Same order as man 5 sddm.conf.
monarchy_sddm_effective_current() {
    local dir f got current=""
    for dir in "$MONARCHY_SDDM_SYS_CONF_DIR" "$MONARCHY_SDDM_USER_CONF_DIR"; do
        [ -d "$dir" ] || continue
        while IFS= read -r f; do
            [ -f "$f" ] || continue
            got=$(awk '
                /^\[Theme\]/ { in_theme=1; next }
                /^\[/ { in_theme=0; next }
                in_theme && /^Current=/ {
                    sub(/^Current=/, "")
                    gsub(/^[ \t]+|[ \t]+$/, "")
                    if (length) print
                }
            ' "$f" | tail -1)
            [ -n "$got" ] && current=$got
        done < <(LC_ALL=C find "$dir" -maxdepth 1 -name '*.conf' -print | LC_ALL=C sort)
    done
    if [ -f "$MONARCHY_SDDM_LEGACY_CONF" ]; then
        got=$(awk '
            /^\[Theme\]/ { in_theme=1; next }
            /^\[/ { in_theme=0; next }
            in_theme && /^Current=/ {
                sub(/^Current=/, "")
                gsub(/^[ \t]+|[ \t]+$/, "")
                if (length) print
            }
        ' "$MONARCHY_SDDM_LEGACY_CONF" | tail -1)
        [ -n "$got" ] && current=$got
    fi
    printf '%s\n' "$current"
}

monarchy_sddm_assert_theme_wins() {
    local current
    current=$(monarchy_sddm_effective_current)
    [ "$current" = omarchy ] || monarchy_die \
        "effective SDDM Theme.Current is '${current:-<unset>}', expected omarchy (drop-in must sort after kde_settings.conf)"
}

monarchy_sddm_clone_theme() {
    local src="${OMARCHY_PATH:-$MONARCHY_PATH}/default/sddm/omarchy"
    [ -d "$src" ] || src="$MONARCHY_SRC/default/sddm/omarchy"
    printf '%s\n' "$src"
}

monarchy_sddm_clone_hypr() {
    local src="${OMARCHY_PATH:-$MONARCHY_PATH}/default/sddm/hyprland.lua"
    [ -f "$src" ] || src="$MONARCHY_SRC/default/sddm/hyprland.lua"
    printf '%s\n' "$src"
}

monarchy_assert_sddm_assets() {
    local qml conf
    qml=$(monarchy_sddm_qml_src)
    conf=$(monarchy_sddm_conf_src)
    [ -f "$qml" ] || monarchy_die "missing $qml"
    [ -f "$conf" ] || monarchy_die "missing $conf"
    grep -q '#1a1b26' "$qml" || monarchy_die "$qml missing plymouth color token #1a1b26"
    grep -q '#ffffff' "$qml" || monarchy_die "$qml missing plymouth color token #ffffff"
    grep -q 'cycleUser' "$qml" || monarchy_die "$qml is not the multi-user overlay"
    grep -q '^Current=omarchy$' "$conf" || monarchy_die "$conf must set Current=omarchy"
    grep -q 'start-hyprland' "$conf" || monarchy_die "$conf must use start-hyprland"
    if grep -q '^SessionCommand=' "$conf"; then
        monarchy_die "$conf must not set SessionCommand (re-login starts a second compositor)"
    fi
    [ -f "$monarchy_lib_dir/sddm-resume.sh" ] || monarchy_die "missing sddm-resume.sh"
    [ -f "$MONARCHY_MISC/sddm/monarchy-sddm-resume.service" ] \
        || monarchy_die "missing monarchy-sddm-resume.service"
    grep -q '127.0.0.1:17621/resume' "$qml" || monarchy_die "$qml missing resume URL"
    if ! LC_ALL=C awk -v n="$(basename "$conf")" 'BEGIN { exit !(n > "kde_settings.conf") }'; then
        monarchy_die "$conf must sort after kde_settings.conf (use zz-, not 99-)"
    fi
    if grep -Eq '^[[:space:]]*User=[[:space:]]*[^[:space:]]+' "$conf"; then
        monarchy_die "$conf must not set Autologin User"
    fi
    monarchy_in_list sddm "${MONARCHY_PKG_DENY[@]}" \
        && monarchy_die "sddm must not be in packages.deny"
    monarchy_in_list plasma-login-manager "${MONARCHY_PKG_DENY[@]}" \
        || monarchy_die "plasma-login-manager must be in packages.deny"
    return 0
}

monarchy_assert_sddm_runtime() {
    if ! monarchy_pkg_installed sddm; then
        monarchy_log "sddm not installed yet; apply will switch from plasmalogin"
        return 0
    fi
    if monarchy_pkg_installed plasma-login-manager; then
        monarchy_die "plasma-login-manager is still installed; two display managers"
    fi
    if command -v systemctl >/dev/null 2>&1; then
        systemctl is-enabled sddm >/dev/null 2>&1 \
            || monarchy_die "sddm is installed but not enabled"
        if [ -L /etc/systemd/system/display-manager.service ]; then
            local target
            target=$(readlink -f /etc/systemd/system/display-manager.service)
            case "$target" in
                */sddm.service) ;;
                *) monarchy_die "display-manager.service is $target, expected sddm.service" ;;
            esac
        fi
    fi
    return 0
}

monarchy_sddm_write_qml() {
    local qml dest tmp bg_hex=${1:-} text_hex=${2:-}
    qml=$(monarchy_sddm_qml_src)
    dest="$MONARCHY_SDDM_THEME_DIR/Main.qml"
    [ -f "$qml" ] || monarchy_die "missing $qml"
    monarchy_sudo mkdir -p "$MONARCHY_SDDM_THEME_DIR"
    tmp=$(mktemp)
    if [ -n "$bg_hex" ] && [ -n "$text_hex" ]; then
        sed -e "s/#1a1b26/#$bg_hex/g" -e "s/#ffffff/#$text_hex/g" "$qml" >"$tmp"
    else
        cat "$qml" >"$tmp"
    fi
    monarchy_sudo install -m 644 "$tmp" "$dest"
    rm -f "$tmp"
}

monarchy_sddm_install_overlay_assets() {
    local src dest f base
    src="$MONARCHY_MISC/sddm"
    dest=$MONARCHY_SDDM_THEME_DIR
    [ -d "$src" ] || return 0
    monarchy_sudo mkdir -p "$dest"
    for f in "$src"/*; do
        [ -f "$f" ] || continue
        base=$(basename "$f")
        case "$base" in
            *.conf|*.service|Main.qml) continue ;;
        esac
        monarchy_sudo install -m 644 "$f" "$dest/$base"
    done
}

monarchy_sddm_install_conf() {
    local src stale
    src=$(monarchy_sddm_conf_src)
    [ -f "$src" ] || monarchy_die "missing $src"
    monarchy_sudo mkdir -p "$MONARCHY_SDDM_USER_CONF_DIR"
    monarchy_sudo install -m 644 "$src" "$MONARCHY_SDDM_CONF"
    stale="$MONARCHY_SDDM_USER_CONF_DIR/99-omarchy-sddm.conf"
    if [ -e "$stale" ] && [ "$stale" != "$MONARCHY_SDDM_CONF" ]; then
        monarchy_sudo rm -f "$stale"
        monarchy_log "removed stale $stale"
    fi
    monarchy_sddm_assert_theme_wins
    monarchy_log "installed $MONARCHY_SDDM_CONF"
}

monarchy_sddm_install_hyprland_lua() {
    local src
    src=$(monarchy_sddm_clone_hypr)
    [ -f "$src" ] || monarchy_die "missing greeter hyprland.lua at $src"
    monarchy_sudo mkdir -p /usr/share/sddm
    monarchy_sudo install -m 644 "$src" "$MONARCHY_SDDM_HYPR"
}

monarchy_sddm_sync_assets() {
    local staging_dir=$1
    local bg_hex=${2:-}
    local text_hex=${3:-}
    local dest=$MONARCHY_SDDM_THEME_DIR
    local asset
    [ -d "$staging_dir" ] || monarchy_die "sddm staging dir missing"
    if [ ! -d "$dest" ]; then
        monarchy_refresh_sddm
    fi
    monarchy_sudo mkdir -p "$dest"
    monarchy_sudo cp "$staging_dir/logo.png" "$dest/logo.png"
    for asset in bullet.png entry.png lock.png; do
        [ -f "$staging_dir/$asset" ] || continue
        monarchy_sudo cp "$staging_dir/$asset" "$dest/$asset"
    done
    for asset in entry-failed.png lock-failed.png; do
        [ -f "$staging_dir/$asset" ] || continue
        monarchy_sudo cp "$staging_dir/$asset" "$dest/$asset"
    done
    monarchy_sudo rm -f "$dest/logo.svg"
    monarchy_sddm_write_qml "$bg_hex" "$text_hex"
    monarchy_sddm_install_overlay_assets
}

# Same TOML colour scrape as clone bin/omarchy-plymouth-set-by-theme.
monarchy_theme_toml_color() {
    local file=$1 key=$2 fallback=${3:-}
    [ -f "$file" ] || return 1
    awk -F= -v key="$key" -v fallback="$fallback" '
        function clean(raw) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", raw)
            if (raw ~ /^"/) {
                sub(/^"/, "", raw)
                sub(/".*$/, "", raw)
            }
            return raw
        }
        {
            field = $1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", field)
            if (field == key) {
                print clean($2)
                found = 1
                exit
            }
            if (field == fallback) fallback_value = clean($2)
        }
        END {
            if (!found && fallback_value != "") print fallback_value
        }
    ' "$file"
}

monarchy_current_theme_dir() {
    local theme=$1
    local theme_dir="${OMARCHY_PATH:-$MONARCHY_PATH}/themes/$theme"
    [ -d "$HOME/.config/omarchy/themes/$theme" ] && theme_dir="$HOME/.config/omarchy/themes/$theme"
    printf '%s\n' "$theme_dir"
}

# Which Style > Unlock theme is installed in plymouth, or "default".
# Does not consult the session theme. Stock Omarchy keeps those independent.
monarchy_unlock_theme_name() {
    local ply_logo=$MONARCHY_PLYMOUTH_THEME_DIR/logo.png
    local default_logo="${OMARCHY_PATH:-$MONARCHY_PATH}/default/plymouth/logo.png"
    local dir
    [ -f "$default_logo" ] || default_logo="$MONARCHY_SRC/default/plymouth/logo.png"
    if [ ! -f "$ply_logo" ]; then
        printf '%s\n' default
        return 0
    fi
    if [ -f "$default_logo" ] && cmp -s "$ply_logo" "$default_logo"; then
        printf '%s\n' default
        return 0
    fi
    for dir in "$HOME/.config/omarchy/themes"/* "${OMARCHY_PATH:-$MONARCHY_PATH}/themes"/*; do
        [ -f "$dir/unlock.png" ] || continue
        [ ! -L "$dir/unlock.png" ] || continue
        if cmp -s "$ply_logo" "$dir/unlock.png"; then
            basename "$dir"
            return 0
        fi
    done
    printf '%s\n' default
}

# Restyle the greeter from a named theme's unlock.png + colors.toml.
# Does not rebuild initramfs. No-op when the theme cannot restyle.
monarchy_sddm_apply_theme() {
    local theme=$1
    local theme_dir colors bg_hex text_hex src_ply staging_dir asset dest
    [ -n "$theme" ] && [ "$theme" != "default" ] || return 0
    theme_dir=$(monarchy_current_theme_dir "$theme")
    [ -f "$theme_dir/unlock.png" ] || return 0
    [ ! -L "$theme_dir/unlock.png" ] || return 0
    colors="$theme_dir/colors.toml"
    [ -f "$colors" ] || return 0
    bg_hex=$(monarchy_theme_toml_color "$colors" background)
    text_hex=$(monarchy_theme_toml_color "$colors" foreground)
    bg_hex=${bg_hex#\#}
    text_hex=${text_hex#\#}
    [[ $bg_hex =~ ^[0-9a-fA-F]{6}$ ]] || return 0
    [[ $text_hex =~ ^[0-9a-fA-F]{6}$ ]] || return 0

    dest=$MONARCHY_SDDM_THEME_DIR
    if [ ! -d "$dest" ]; then
        monarchy_refresh_sddm
    fi
    monarchy_sudo mkdir -p "$dest"

    src_ply="${OMARCHY_PATH:-$MONARCHY_PATH}/default/plymouth"
    [ -f "$src_ply/bullet.png" ] || src_ply="$MONARCHY_SRC/default/plymouth"
    staging_dir=$(mktemp -d)
    cp "$theme_dir/unlock.png" "$staging_dir/logo.png"
    if command -v magick >/dev/null 2>&1 && [ -f "$src_ply/bullet.png" ]; then
        for asset in bullet.png entry.png lock.png; do
            [ -f "$src_ply/$asset" ] || continue
            magick "$src_ply/$asset" -channel RGB +level-colors "#$text_hex","#$text_hex" \
                "$staging_dir/$asset"
        done
        for asset in entry lock; do
            [ -f "$staging_dir/${asset}.png" ] || continue
            magick "$staging_dir/${asset}.png" -channel RGB +level-colors "#f7768e","#f7768e" \
                "$staging_dir/${asset}-failed.png"
        done
    fi
    monarchy_sddm_sync_assets "$staging_dir" "$bg_hex" "$text_hex"
    rm -rf "$staging_dir"
    monarchy_log "SDDM greeter synced to Unlock $theme"
}

# After a stock greeter copy, match Style > Unlock. Leave default Unlock alone.
monarchy_sddm_follow_unlock() {
    local theme
    theme=$(monarchy_unlock_theme_name)
    [ "$theme" != "default" ] || return 0
    monarchy_sddm_apply_theme "$theme"
}

monarchy_refresh_sddm() {
    local src dest
    src=$(monarchy_sddm_clone_theme)
    dest=$MONARCHY_SDDM_THEME_DIR
    [ -d "$src" ] || monarchy_die "missing Omarchy sddm theme at $src"
    monarchy_log "refresh SDDM theme from $src"
    monarchy_sudo rm -rf "$dest"
    monarchy_sudo mkdir -p "$(dirname "$dest")"
    monarchy_sudo cp -a "$src" "$dest"
    monarchy_sddm_install_hyprland_lua
    monarchy_sddm_write_qml
    monarchy_sddm_install_overlay_assets
}

monarchy_install_sddm_resume() {
    local src="$monarchy_lib_dir/sddm-resume.sh"
    local unit="$MONARCHY_MISC/sddm/monarchy-sddm-resume.service"
    [ -f "$src" ] || monarchy_die "missing $src"
    [ -f "$unit" ] || monarchy_die "missing $unit"
    monarchy_sudo install -m 755 "$src" /usr/local/bin/monarchy-sddm-resume
    monarchy_sudo rm -f /usr/local/bin/monarchy-wayland-session
    monarchy_sudo install -m 644 "$unit" /etc/systemd/system/monarchy-sddm-resume.service
    if command -v systemctl >/dev/null 2>&1; then
        monarchy_sudo systemctl enable --now monarchy-sddm-resume.service
    fi
    monarchy_log "installed monarchy-sddm-resume"
}

monarchy_keep_sddm() {
    monarchy_assert_sddm_assets
    monarchy_install_sddm_resume
    if ! monarchy_pkg_installed sddm; then
        if [ "${MONARCHY_NO_PACKAGES:-0}" = 1 ]; then
            monarchy_die "sddm is not installed; run without --no-packages"
        fi
        monarchy_log "install sddm"
        monarchy_sudo pacman -S --needed --noconfirm sddm
    fi
    monarchy_sddm_install_conf
    monarchy_refresh_sddm
    if command -v systemctl >/dev/null 2>&1; then
        monarchy_log "enable sddm; disable plasmalogin"
        monarchy_sudo systemctl enable --force sddm.service
        if systemctl list-unit-files plasmalogin.service >/dev/null 2>&1; then
            monarchy_sudo systemctl disable plasmalogin.service >/dev/null 2>&1 || true
        fi
    fi
    if monarchy_pkg_installed plasma-login-manager; then
        monarchy_log "remove plasma-login-manager"
        monarchy_sudo pacman -R --noconfirm plasma-login-manager
    fi
    monarchy_skip_autologin
    monarchy_assert_sddm_runtime
    monarchy_log "sddm is the display manager (Omarchy theme, multi-user overlay)"
}
