# shellcheck shell=bash

monarchy_migration_denied() {
    local file=$1
    local base
    base=$(basename "$file")
    monarchy_in_list "$base" "${MONARCHY_MIGRATE_DENY[@]}" && return 0
    if grep -Eq 'limine-mkinitcpio|omarchy-refresh-pacman|use_omarchy_pacman_config|/etc/os-release|nvidia-dkms' "$file" 2>/dev/null; then
        if grep -Eq 'systemctl enable sddm|sddm\.conf' "$file" 2>/dev/null; then
            return 0
        fi
        if grep -Eq 'limine-mkinitcpio|omarchy-refresh-pacman|use_omarchy_pacman_config' "$file" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

monarchy_check_migrations() {
    local dir="$MONARCHY_SRC/migrations"
    [ -d "$dir" ] || return 0
    local f base
    for f in "$dir"/*.sh; do
        [ -f "$f" ] || continue
        base=$(basename "$f")
        if monarchy_in_list "$base" "${MONARCHY_MIGRATE_DENY[@]}"; then
            continue
        fi
        if grep -Eq 'limine-mkinitcpio|omarchy-refresh-pacman|use_omarchy_pacman_config' "$f"; then
            echo "migration not in migrations.deny but touches limine/pacman: $base" >&2
            monarchy_die "classify $base into migrations.deny"
        fi
    done
    return 0
}

monarchy_check_packages_deny() {
    local list="$MONARCHY_SRC/install/omarchy-base.packages"
    [ -f "$list" ] || return 0
    local pkg
    while read -r pkg; do
        [ -n "$pkg" ] || continue
        case "$pkg" in
            \#*) continue ;;
        esac
        if monarchy_in_list "$pkg" "${MONARCHY_PKG_DENY[@]}"; then
            continue
        fi
    done <"$list"
    return 0
}

monarchy_check() {
    monarchy_load_lock
    monarchy_load_inventories
    monarchy_ensure_clone_for_check
    monarchy_assert_zfs_layout
    monarchy_assert_os_release
    monarchy_assert_sddm_assets
    monarchy_assert_sddm_runtime
    monarchy_refuse_bootloader
    monarchy_refuse_snapper
    monarchy_refuse_kernel_swap
    monarchy_skip_os_release_clobber
    monarchy_skip_autologin
    monarchy_skip_plymouth_zfs
    monarchy_refuse_dataset_rename
    monarchy_disable_omarchy_update_guard
    monarchy_preserve_pacman_conf
    monarchy_refuse_archzfs
    monarchy_refuse_omarchy_zfs_repo
    monarchy_check_inventory_complete
    monarchy_check_clone_bin_classified
    monarchy_check_migrations
    monarchy_check_packages_deny
    [ -f "$MONARCHY_MISC/omarchy.desktop" ] || monarchy_die "missing omarchy.desktop"
    grep -q '^DesktopNames=Hyprland$' "$MONARCHY_MISC/omarchy.desktop" \
        || monarchy_die "omarchy.desktop missing DesktopNames=Hyprland"
    [ -f "$MONARCHY_MISC/10-monarchy" ] || monarchy_die "missing 10-monarchy"
    [ -f "$MONARCHY_MISC/hyprland-portals.conf" ] || monarchy_die "missing hyprland-portals.conf"
    [ -f "$MONARCHY_MISC/sddm/Main.qml" ] || monarchy_die "missing sddm/Main.qml"
    [ -f "$MONARCHY_MISC/sddm/zz-omarchy-sddm.conf" ] || monarchy_die "missing zz-omarchy-sddm.conf"
    monarchy_filtered_packages | grep -qx sddm \
        || monarchy_die "sddm missing from filtered package list"
    if monarchy_filtered_packages | grep -qx plasma-login-manager; then
        monarchy_die "plasma-login-manager leaked into filtered package list"
    fi
    [ -f "$monarchy_lib_dir/switch-user.sh" ] || monarchy_die "missing switch-user.sh"
    [ -f "$monarchy_lib_dir/sddm-resume.sh" ] || monarchy_die "missing sddm-resume.sh"
    monarchy_check_session_lock_overlay
    monarchy_check_logind
    monarchy_check_hidden_hyprland_sessions
    monarchy_assert_settings_assets
    grep -q 'mise activate' "$MONARCHY_MISC/10-monarchy" \
        || monarchy_die "10-monarchy missing mise activate"
    monarchy_log "check passed"
}

# Quickshell lock refuses without /etc/pam.d/omarchy-lock-password.
# Omarchy install/config/lockscreen-pam.sh is this one command.
monarchy_apply_lock() {
    local bin="$MONARCHY_PATH/bin/omarchy-apply-lock"
    [ -x "$bin" ] || monarchy_die "missing $bin"
    export OMARCHY_PATH
    export PATH="$MONARCHY_PATH/bin:${PATH:-/usr/bin}"
    monarchy_log "omarchy-apply-lock"
    "$bin"
    [ -f /etc/pam.d/omarchy-lock-password ] \
        || monarchy_die "omarchy-apply-lock did not write /etc/pam.d/omarchy-lock-password"
}

monarchy_apply() {
    monarchy_load_lock
    monarchy_load_inventories
    monarchy_snapshot_first
    monarchy_assert_zfs_layout
    monarchy_assert_os_release
    monarchy_assert_sddm_assets
    monarchy_refuse_bootloader
    monarchy_refuse_snapper
    monarchy_refuse_kernel_swap
    monarchy_skip_os_release_clobber
    monarchy_skip_plymouth_zfs
    monarchy_refuse_dataset_rename
    monarchy_disable_omarchy_update_guard
    monarchy_sync_omarchy_clone
    monarchy_link_working_prefix
    monarchy_rebuild_overlay
    monarchy_overlay_session_lock
    monarchy_install_switch_user
    monarchy_write_omarchy_conf
    export OMARCHY_PATH
    monarchy_add_omarchy_repo
    monarchy_install_packages
    monarchy_install_settings
    monarchy_run_omarchy_config
    monarchy_keep_sddm
    monarchy_apply_lock
    monarchy_install_omarchy_session
    monarchy_apply_logind
    monarchy_install_uwsm_env
    monarchy_install_hyprland_portals
    monarchy_setup_user
    monarchy_skip_autologin
    monarchy_keep_family_mime
    monarchy_splash
    monarchy_splash_maybe_theme
    monarchy_log "apply complete"
}

monarchy_update() {
    monarchy_load_lock
    monarchy_load_inventories
    monarchy_snapshot_first
    monarchy_ensure_clone_for_check
    if [ -d "$MONARCHY_SRC/.git" ]; then
        git -C "$MONARCHY_SRC" fetch --quiet origin "$MONARCHY_LOCK_BRANCH" || \
            monarchy_sudo git -C "$MONARCHY_SRC" fetch --quiet origin "$MONARCHY_LOCK_BRANCH"
    fi
    monarchy_check
    monarchy_apply
}
