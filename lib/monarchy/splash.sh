# shellcheck shell=bash
# Omarchy Plymouth theme. Never plymouth-zfs. Never limine-mkinitcpio.
# plymouth sits before zfs when the host keyfile is in FILES, otherwise after.
# SDDM greeter sync is in sddm.sh (plymouth-set / follow Unlock write overlay QML).

# shellcheck source=sddm.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sddm.sh"

MONARCHY_PLYMOUTH_THEME_DIR="${MONARCHY_PLYMOUTH_THEME_DIR:-/usr/share/plymouth/themes/omarchy}"
MONARCHY_PLYMOUTH_RETAIN="${MONARCHY_PLYMOUTH_RETAIN:-/etc/systemd/system/plymouth-quit.service.d/20-monarchy-retain.conf}"

# $1 is before or after (relative to zfs). Remaining args are HOOKS.
monarchy_hooks_insert_plymouth() {
    local side=$1
    shift
    local -a hooks=("$@")
    local h has_zfs=0
    local -a new=()
    [ "$side" = before ] || [ "$side" = after ] || return 1
    [ "${#hooks[@]}" -gt 0 ] || return 1
    for h in "${hooks[@]}"; do
        [ "$h" = zfs ] && has_zfs=1
    done
    if [ "$has_zfs" -ne 1 ]; then
        echo "zfs hook missing" >&2
        return 1
    fi
    for h in "${hooks[@]}"; do
        [ "$h" = plymouth ] && continue
        if [ "$h" = zfs ] && [ "$side" = before ]; then
            new+=(plymouth zfs)
        elif [ "$h" = zfs ] && [ "$side" = after ]; then
            new+=(zfs plymouth)
        else
            new+=("$h")
        fi
    done
    printf '%s\n' "${new[*]}"
}

monarchy_plymouth_side() {
    if monarchy_zfs_keyfile_in_initramfs; then
        printf '%s\n' before
    else
        printf '%s\n' after
    fi
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
    local side
    side=$(monarchy_plymouth_side)
    rebuilt=$(monarchy_hooks_insert_plymouth "$side" "${hooks[@]}") \
        || monarchy_die "cannot place plymouth $side zfs in HOOKS"
    newline="HOOKS=($rebuilt)"
    if [ "$newline" = "$line" ]; then
        monarchy_log "plymouth already $side zfs in $conf"
        return 0
    fi
    monarchy_log "place plymouth $side zfs in $conf"
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

monarchy_splash_retain() {
    local src="$MONARCHY_MISC/plymouth-quit-retain.conf"
    local dest=$MONARCHY_PLYMOUTH_RETAIN
    [ -f "$src" ] || monarchy_die "missing $src"
    if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
        return 0
    fi
    monarchy_log "install $dest (plymouth quit --retain-splash)"
    monarchy_sudo mkdir -p "$(dirname "$dest")"
    monarchy_sudo install -m 644 "$src" "$dest"
    if command -v systemctl >/dev/null 2>&1; then
        monarchy_sudo systemctl daemon-reload
    fi
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
        magick "$staging_dir/$asset" -channel RGB +level-colors "#$text_hex,#$text_hex" "$staging_dir/$asset"
    done
    monarchy_sudo mkdir -p "$dest"
    monarchy_sudo cp -a --no-preserve=mode,ownership "$staging_dir/." "$dest/"
    monarchy_sudo plymouth-set-default-theme omarchy
    monarchy_splash_rebuild
    local fail_asset
    for fail_asset in entry lock; do
        magick "$staging_dir/${fail_asset}.png" -channel RGB +level-colors "#f7768e,#f7768e" \
            "$staging_dir/${fail_asset}-failed.png"
    done
    monarchy_sddm_sync_assets "$staging_dir" "$bg_hex" "$text_hex"
    monarchy_log "plymouth theme colors set; SDDM greeter synced"
}

monarchy_plymouth_reset() {
    monarchy_refresh_plymouth
    monarchy_refresh_sddm
    monarchy_log "plymouth reset; SDDM greeter refreshed"
}

monarchy_splash_maybe_theme() {
    # Stock Omarchy: Unlock (plymouth + SDDM) is Style > Unlock, not the
    # session theme. Apply installs Unlock default. Re-apply recopies the
    # stock greeter, then this restores a previously chosen Unlock.
    monarchy_sddm_follow_unlock
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
    monarchy_splash_retain
    if [ "${MONARCHY_SPLASH_REBUILD:-0}" = 1 ]; then
        monarchy_splash_rebuild
    fi
    if [ -d "$(monarchy_sddm_clone_theme)" ]; then
        monarchy_refresh_sddm
    fi
    monarchy_skip_plymouth_zfs
    monarchy_log "splash ready (plymouth $(monarchy_plymouth_side) zfs, theme omarchy, retain-splash, sddm greeter synced)"
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
    monarchy_overlay_session_lock
    export OMARCHY_PATH
    monarchy_pkg_installed plymouth || monarchy_die "plymouth is not installed"
    monarchy_splash
    monarchy_splash_maybe_theme
    monarchy_log "splash-only complete"
}
