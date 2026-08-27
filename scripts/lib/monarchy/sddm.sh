# shellcheck shell=bash
# SDDM as the household greeter. Omarchy theme, Monarchy Main.qml overlay.
# Never autologin. Never leave plasma-login-manager installed next to sddm.

MONARCHY_SDDM_THEME_DIR="${MONARCHY_SDDM_THEME_DIR:-/usr/share/sddm/themes/omarchy}"
MONARCHY_SDDM_CONF="${MONARCHY_SDDM_CONF:-/etc/sddm.conf.d/99-omarchy-sddm.conf}"
MONARCHY_SDDM_HYPR="${MONARCHY_SDDM_HYPR:-/usr/share/sddm/hyprland.lua}"

monarchy_sddm_qml_src() {
    printf '%s\n' "$MONARCHY_MISC/sddm/Main.qml"
}

monarchy_sddm_conf_src() {
    printf '%s\n' "$MONARCHY_MISC/sddm/99-omarchy-sddm.conf"
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

monarchy_sddm_install_conf() {
    local src
    src=$(monarchy_sddm_conf_src)
    [ -f "$src" ] || monarchy_die "missing $src"
    monarchy_sudo mkdir -p /etc/sddm.conf.d
    monarchy_sudo install -m 644 "$src" "$MONARCHY_SDDM_CONF"
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
}

monarchy_keep_sddm() {
    monarchy_assert_sddm_assets
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
