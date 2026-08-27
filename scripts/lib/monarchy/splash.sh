# shellcheck shell=bash
# Post-unlock Plymouth using the Omarchy theme. Never plymouth-zfs.
# Never plymouth-before-zfs. Never SDDM. Never limine-mkinitcpio.

MONARCHY_PLYMOUTH_THEME_DIR="${MONARCHY_PLYMOUTH_THEME_DIR:-/usr/share/plymouth/themes/omarchy}"
MONARCHY_MKINITCPIO_CONF="${MONARCHY_MKINITCPIO_CONF:-/etc/mkinitcpio.conf}"

monarchy_hooks_insert_plymouth() {
    local -a hooks=("$@")
    local i zfs_i=-1 plymouth_i=-1
    [ "${#hooks[@]}" -gt 0 ] || return 1
    for i in "${!hooks[@]}"; do
        case "${hooks[$i]}" in
            zfs) zfs_i=$i ;;
            plymouth) plymouth_i=$i ;;
        esac
    done
    if [ "$zfs_i" -lt 0 ]; then
        echo "zfs hook missing" >&2
        return 1
    fi
    if [ "$plymouth_i" -ge 0 ]; then
        if [ "$plymouth_i" -le "$zfs_i" ]; then
            echo "plymouth appears before zfs" >&2
            return 1
        fi
        printf '%s\n' "${hooks[*]}"
        return 0
    fi
    local -a new=()
    for i in "${!hooks[@]}"; do
        new+=("${hooks[$i]}")
        if [ "$i" -eq "$zfs_i" ]; then
            new+=(plymouth)
        fi
    done
    printf '%s\n' "${new[*]}"
}

monarchy_splash_refuse_omarchy_hooks_dropin() {
    local dropin=/etc/mkinitcpio.conf.d/omarchy_hooks.conf
    [ -e "$dropin" ] && monarchy_die "$dropin exists; refusing Omarchy plymouth-before-zfs drop-in"
    return 0
}

monarchy_splash_hooks() {
    local conf=$MONARCHY_MKINITCPIO_CONF
    local line inner newline rebuilt
    [ -f "$conf" ] || monarchy_die "missing $conf"
    monarchy_splash_refuse_omarchy_hooks_dropin
    line=$(grep -E '^HOOKS=' "$conf" | tail -n 1)
    [ -n "$line" ] || monarchy_die "no HOOKS= in $conf"
    inner=${line#HOOKS=(}
    inner=${inner%)}
    local -a hooks
    # shellcheck disable=SC2206
    hooks=($inner)
    rebuilt=$(monarchy_hooks_insert_plymouth "${hooks[@]}") \
        || monarchy_die "cannot place plymouth after zfs in HOOKS"
    newline="HOOKS=($rebuilt)"
    if [ "$newline" = "$line" ]; then
        monarchy_log "plymouth already after zfs in $conf"
        return 0
    fi
    monarchy_log "insert plymouth after zfs in $conf"
    if [ ! -f "${conf}.monarchy.bak" ]; then
        monarchy_sudo cp -a "$conf" "${conf}.monarchy.bak"
    fi
    local tmp
    tmp=$(mktemp)
    awk -v n="$newline" '/^HOOKS=/ { print n; next } { print }' "$conf" >"$tmp"
    monarchy_sudo cp "$tmp" "$conf"
    rm -f "$tmp"
    MONARCHY_SPLASH_REBUILD=1
}

monarchy_splash_install_theme() {
    local src="${OMARCHY_PATH:-/usr/local/share/omarchy}/default/plymouth"
    local dest=$MONARCHY_PLYMOUTH_THEME_DIR
    [ -f "$src/omarchy.plymouth" ] || monarchy_die "missing $src/omarchy.plymouth"
    if [ ! -f "$dest/omarchy.plymouth" ]; then
        monarchy_log "install Omarchy plymouth theme to $dest"
        monarchy_sudo mkdir -p "$dest"
        monarchy_sudo cp -a "$src/." "$dest/"
        MONARCHY_SPLASH_REBUILD=1
    fi
    local current
    current=$(plymouth-set-default-theme 2>/dev/null || true)
    if [ "$current" != "omarchy" ]; then
        monarchy_log "plymouth-set-default-theme omarchy (was '$current')"
        monarchy_sudo plymouth-set-default-theme omarchy
        MONARCHY_SPLASH_REBUILD=1
    fi
}

monarchy_splash_rebuild() {
    if monarchy_pkg_installed limine-mkinitcpio-hook || command -v limine-mkinitcpio >/dev/null 2>&1; then
        monarchy_die "limine-mkinitcpio is present; refusing to rebuild initramfs via Limine"
    fi
    monarchy_log "mkinitcpio -P"
    monarchy_sudo mkinitcpio -P
}

monarchy_refresh_plymouth() {
    local src="${OMARCHY_PATH:-/usr/local/share/omarchy}/default/plymouth"
    local dest=$MONARCHY_PLYMOUTH_THEME_DIR
    [ -f "$src/omarchy.plymouth" ] || monarchy_die "missing $src/omarchy.plymouth"
    monarchy_skip_plymouth_zfs
    monarchy_splash_refuse_omarchy_hooks_dropin
    monarchy_log "refresh Omarchy plymouth theme"
    monarchy_sudo mkdir -p "$dest"
    monarchy_sudo cp -a "$src/." "$dest/"
    monarchy_sudo plymouth-set-default-theme omarchy
    monarchy_splash_rebuild
}

monarchy_plymouth_set() {
    if [ "$#" -ne 3 ]; then
        echo "Usage: omarchy-plymouth-set <background-hex> <text-hex> <path-to-logo.png>" >&2
        exit 1
    fi
    command -v magick >/dev/null 2>&1 || monarchy_die "imagemagick (magick) is required for plymouth-set"

    local bg_hex=${1#\#}
    local text_hex=${2#\#}
    local logo_path=$3
    if ! [[ $bg_hex =~ ^[0-9a-fA-F]{6}$ ]]; then
        monarchy_die "invalid background color: $1"
    fi
    if ! [[ $text_hex =~ ^[0-9a-fA-F]{6}$ ]]; then
        monarchy_die "invalid text color: $2"
    fi
    [ -f "$logo_path" ] || monarchy_die "logo file not found: $logo_path"
    [ -L "$logo_path" ] && monarchy_die "logo file is a symlink, which is not accepted: $logo_path"

    monarchy_skip_plymouth_zfs
    monarchy_splash_refuse_omarchy_hooks_dropin

    local bg_r bg_g bg_b
    bg_r=$(awk -v n=$((16#${bg_hex:0:2})) 'BEGIN{printf "%.3f", n/255}')
    bg_g=$(awk -v n=$((16#${bg_hex:2:2})) 'BEGIN{printf "%.3f", n/255}')
    bg_b=$(awk -v n=$((16#${bg_hex:4:2})) 'BEGIN{printf "%.3f", n/255}')

    local src="${OMARCHY_PATH:-/usr/local/share/omarchy}/default/plymouth"
    local dest=$MONARCHY_PLYMOUTH_THEME_DIR
    [ -f "$src/omarchy.script" ] || monarchy_die "missing $src/omarchy.script"

    local staging_dir
    staging_dir=$(mktemp -d)
    trap 'rm -rf "$staging_dir"' RETURN
    find "$src" -maxdepth 1 -type f -exec cp -t "$staging_dir/" {} +
    cp "$logo_path" "$staging_dir/logo.png"
    sed -i \
        -e "s/^Window.SetBackgroundTopColor.*/Window.SetBackgroundTopColor($bg_r, $bg_g, $bg_b);/" \
        -e "s/^Window.SetBackgroundBottomColor.*/Window.SetBackgroundBottomColor($bg_r, $bg_g, $bg_b);/" \
        "$staging_dir/omarchy.script"
    local asset
    for asset in bullet.png entry.png lock.png progress_bar.png; do
        magick "$staging_dir/$asset" -channel RGB +level-colors "#$text_hex","#$text_hex" "$staging_dir/$asset"
    done
    monarchy_sudo mkdir -p "$dest"
    monarchy_sudo cp -a --no-preserve=mode,ownership "$staging_dir/." "$dest/"
    monarchy_sudo plymouth-set-default-theme omarchy
    monarchy_splash_rebuild
    monarchy_log "plymouth theme colors set; skipped SDDM"
}

monarchy_plymouth_reset() {
    monarchy_refresh_plymouth
    monarchy_log "plymouth reset; skipped omarchy-refresh-sddm"
}

monarchy_splash_maybe_theme() {
    local name_file="$HOME/.local/state/omarchy/current/theme.name"
    local theme theme_dir
    [ -s "$name_file" ] || return 0
    [ -f "$MONARCHY_PLYMOUTH_THEME_DIR/omarchy.plymouth" ] || return 0
    theme=$(cat "$name_file")
    [ -n "$theme" ] || return 0
    theme_dir="${OMARCHY_PATH:-/usr/local/share/omarchy}/themes/$theme"
    [ -d "$HOME/.config/omarchy/themes/$theme" ] && theme_dir="$HOME/.config/omarchy/themes/$theme"
    [ -f "$theme_dir/unlock.png" ] || return 0
    if cmp -s "$theme_dir/unlock.png" "$MONARCHY_PLYMOUTH_THEME_DIR/logo.png" 2>/dev/null; then
        return 0
    fi
    monarchy_log "apply plymouth unlock from theme $theme"
    local set_by="${MONARCHY_PATH:-/usr/local/share/omarchy}/bin/omarchy-plymouth-set-by-theme"
    export PATH="${MONARCHY_PATH:-/usr/local/share/omarchy}/bin:$PATH"
    if [ -x "$set_by" ]; then
        "$set_by" "$theme"
    fi
}

monarchy_splash() {
    monarchy_skip_plymouth_zfs
    if ! monarchy_pkg_installed plymouth; then
        monarchy_log "plymouth not installed; skip splash"
        return 0
    fi
    export OMARCHY_PATH="${OMARCHY_PATH:-/usr/local/share/omarchy}"
    MONARCHY_SPLASH_REBUILD=0
    monarchy_splash_install_theme
    monarchy_splash_hooks
    if [ "${MONARCHY_SPLASH_REBUILD:-0}" = 1 ]; then
        monarchy_splash_rebuild
    fi
    monarchy_skip_plymouth_zfs
    monarchy_log "splash ready (plymouth after zfs, theme omarchy)"
}

monarchy_splash_only() {
    monarchy_load_lock
    monarchy_load_inventories
    monarchy_snapshot_first
    monarchy_assert_zfs_layout
    monarchy_assert_os_release
    monarchy_refuse_bootloader
    monarchy_skip_plymouth_zfs
    monarchy_sync_omarchy_clone
    monarchy_link_working_prefix
    monarchy_rebuild_overlay
    export OMARCHY_PATH
    monarchy_pkg_installed plymouth || monarchy_die "plymouth is not installed"
    monarchy_splash
    monarchy_splash_maybe_theme
    monarchy_log "splash-only complete"
}
