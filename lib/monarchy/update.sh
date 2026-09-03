# shellcheck shell=bash
# Sourced into one shell by lib/monarchy.sh; common.sh state is in scope.
# shellcheck disable=SC2154,SC2153

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
    local required
    for required in plasma-login-manager tldr snapper limine omarchy omarchy-dev \
        omarchy-settings omarchy-settings-dev ufw-docker; do
        monarchy_in_list "$required" "${MONARCHY_PKG_DENY[@]}" \
            || monarchy_die "$required missing from packages.deny"
    done

    local installed_file="$MONARCHY_MISC/packages.installed"
    local -a installed=()
    if [ -f "$installed_file" ]; then
        mapfile -t installed < <(monarchy_load_list "$installed_file")
    fi

    local pkg new=0
    while read -r pkg; do
        [ -n "$pkg" ] || continue
        case "$pkg" in
            \#*) continue ;;
        esac
        if monarchy_in_list "$pkg" "${MONARCHY_PKG_DENY[@]}"; then
            continue
        fi
        if [ "${#installed[@]}" -gt 0 ] && ! monarchy_in_list "$pkg" "${installed[@]}"; then
            echo "package not in packages.deny or packages.installed: $pkg" >&2
            new=1
        fi
    done <"$list"
    [ "$new" = 0 ] || monarchy_die "classify new omarchy-base.packages rows into packages.deny or packages.installed"
    return 0
}

monarchy_check_applications_drop() {
    local name
    [ -f "$MONARCHY_MISC/applications.drop" ] || monarchy_die "missing applications.drop"
    for name in "${MONARCHY_APP_DROP[@]}"; do
        [ -f "$MONARCHY_SRC/applications/${name}.desktop" ] \
            || monarchy_die "applications.drop $name missing from clone applications/"
    done
    return 0
}

# One ordered list of units, each with a check verb and an apply verb.
# check and apply were two hand-maintained linear lists, free to drift, and
# they had: apply never ran the two inventory guards. Now they cannot, because
# both walk this array. The order is the constraint that used to live only in
# prose, so it is the one thing to read carefully before editing.
#
# --only=<unit> runs a single unit. There is no canary box here and
# zfs-snapshot-pre-update keeps three snapshots, so a full apply is an
# expensive way to iterate on one subsystem.
MONARCHY_UNITS=(guards clone overlay pacman settings sddm session logind portals user splash)

monarchy_unit_exists() {
    local u
    for u in "${MONARCHY_UNITS[@]}"; do
        [ "$u" = "$1" ] && return 0
    done
    return 1
}

# ---- guards: refuse a host this overlay was never meant to touch ----------

monarchy_guards_check() {
    monarchy_assert_zfs_layout
    monarchy_assert_os_release
    monarchy_refuse_bootloader
    monarchy_refuse_snapper
    monarchy_refuse_kernel_swap
    monarchy_skip_os_release_clobber
    monarchy_skip_autologin
    monarchy_skip_plymouth_zfs
    monarchy_refuse_dataset_rename
    monarchy_disable_omarchy_update_guard
}

monarchy_guards_apply() { :; }

# ---- clone: the pinned tree and the working prefix -----------------------

# Everything that must hold about the pinned tree once it is on disk.
monarchy_clone_assert() {
    monarchy_check_inventory_complete
    monarchy_check_clone_bin_classified
    monarchy_check_migrations
}

# Apply runs every unit's check before its apply, and on a first install the
# clone does not exist yet at this point. monarchy_clone_apply asserts again
# once it does, so skipping here loses nothing. monarchy_check calls
# monarchy_ensure_clone_for_check before the loop, so in check mode there is
# always a tree and this never silently passes.
monarchy_clone_check() {
    [ -d "$MONARCHY_SRC/bin" ] || return 0
    monarchy_clone_assert
}

monarchy_clone_apply() {
    monarchy_sync_omarchy_clone
    # After the clone exists, before anything is built from it.
    monarchy_clone_assert
    monarchy_link_working_prefix
    monarchy_write_omarchy_conf
    export OMARCHY_PATH
}

# ---- overlay: bin/, the lock plugin, the monarchy commands ---------------

monarchy_overlay_check() {
    [ -f "$monarchy_lib_dir/switch-user.sh" ] || monarchy_die "missing switch-user.sh"
    [ -f "$monarchy_lib_dir/user-setup.sh" ] || monarchy_die "missing user-setup.sh"
    [ -f "$monarchy_lib_dir/stubs/wrap-update.sh" ] || monarchy_die "missing wrap-update.sh"
    monarchy_check_session_lock_overlay
}

monarchy_overlay_apply() {
    monarchy_rebuild_overlay
    monarchy_overlay_session_lock
    monarchy_install_switch_user
    monarchy_install_user_setup
}

# ---- pacman: CachyOS first, [omarchy] after, filtered leaves -------------

monarchy_pacman_check() {
    monarchy_preserve_pacman_conf
    monarchy_refuse_archzfs
    monarchy_refuse_omarchy_zfs_repo
    monarchy_refuse_partial_upgrade
    monarchy_check_packages_deny
    monarchy_filtered_packages | grep -qx sddm \
        || monarchy_die "sddm missing from filtered package list"
    if monarchy_filtered_packages | grep -qx plasma-login-manager; then
        monarchy_die "plasma-login-manager leaked into filtered package list"
    fi
}

monarchy_pacman_apply() {
    monarchy_add_omarchy_repo
    monarchy_install_packages
}

# ---- settings: omarchy-settings files minus settings.skip ----------------

monarchy_settings_check() { monarchy_assert_settings_assets; }

monarchy_settings_apply() {
    monarchy_install_settings
    monarchy_run_omarchy_config
}

# ---- sddm: the greeter and the lock PAM ---------------------------------

monarchy_sddm_check() {
    monarchy_assert_sddm_assets
    monarchy_assert_sddm_runtime
    [ -f "$MONARCHY_MISC/sddm/Main.qml" ] || monarchy_die "missing sddm/Main.qml"
    [ -f "$MONARCHY_MISC/sddm/zz-omarchy-sddm.conf" ] || monarchy_die "missing zz-omarchy-sddm.conf"
    [ -f "$monarchy_lib_dir/sddm-resume.sh" ] || monarchy_die "missing sddm-resume.sh"
}

monarchy_sddm_apply() {
    monarchy_keep_sddm
    monarchy_apply_lock
}

# ---- session: the wayland-sessions desktop file --------------------------

monarchy_session_check() {
    [ -f "$MONARCHY_MISC/omarchy.desktop" ] || monarchy_die "missing omarchy.desktop"
    grep -q '^DesktopNames=Hyprland$' "$MONARCHY_MISC/omarchy.desktop" \
        || monarchy_die "omarchy.desktop missing DesktopNames=Hyprland"
    monarchy_check_hidden_hyprland_sessions
}

monarchy_session_apply() { monarchy_install_omarchy_session; }

# ---- logind: power key and lid ------------------------------------------

monarchy_logind_check() { monarchy_check_logind; }
monarchy_logind_apply() { monarchy_apply_logind; }

# ---- portals: uwsm env and the portal preference -------------------------

monarchy_portals_check() {
    [ -f "$MONARCHY_MISC/10-monarchy" ] || monarchy_die "missing 10-monarchy"
    [ -f "$MONARCHY_MISC/hyprland-portals.conf" ] || monarchy_die "missing hyprland-portals.conf"
    grep -q 'mise activate' "$MONARCHY_MISC/10-monarchy" \
        || monarchy_die "10-monarchy missing mise activate"
}

monarchy_portals_apply() {
    monarchy_install_uwsm_env
    monarchy_install_hyprland_portals
}

# ---- user: the king's account ------------------------------------------

monarchy_user_check() {
    monarchy_check_plugins
    monarchy_check_applications_drop
}

monarchy_user_apply() {
    monarchy_setup_user
    monarchy_skip_autologin
    monarchy_keep_family_mime
}

# ---- splash: plymouth ---------------------------------------------------

monarchy_splash_check() { :; }

monarchy_splash_apply() {
    monarchy_splash
    monarchy_splash_maybe_theme
}

monarchy_assert_only_valid() {
    [ -n "${MONARCHY_ONLY:-}" ] || return 0
    monarchy_unit_exists "$MONARCHY_ONLY" \
        || monarchy_die "--only=$MONARCHY_ONLY is not a unit. Units: ${MONARCHY_UNITS[*]}"
}

monarchy_check() {
    local u
    monarchy_assert_only_valid
    monarchy_load_lock
    monarchy_load_inventories
    # Check-mode only. On a box with no clone this repoints MONARCHY_SRC at a
    # user cache so a dry run has something to read. Doing that during apply
    # would make apply build from the cache instead of /usr/local/src.
    monarchy_ensure_clone_for_check
    for u in "${MONARCHY_UNITS[@]}"; do
        [ -z "${MONARCHY_ONLY:-}" ] || [ "$u" = "$MONARCHY_ONLY" ] || continue
        "monarchy_${u}_check"
    done
    monarchy_log "check passed${MONARCHY_ONLY:+ (only $MONARCHY_ONLY)}"
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
    local u
    monarchy_assert_only_valid
    monarchy_load_lock
    monarchy_load_inventories
    monarchy_snapshot_first
    # Apply first, then verify. A unit's check is a postcondition: it asserts
    # what that unit's apply is supposed to have produced. Checking first
    # aborted every fresh box, because monarchy_check_hidden_hyprland_sessions
    # requires the NoDisplay that monarchy_install_omarchy_session writes, and
    # every converting box, because monarchy_assert_sddm_runtime refuses the
    # plasma-login-manager that monarchy_keep_sddm removes.
    #
    # Host preconditions live in the guards unit, whose apply is a no-op, so
    # they still run before anything is touched.
    for u in "${MONARCHY_UNITS[@]}"; do
        [ -z "${MONARCHY_ONLY:-}" ] || [ "$u" = "$MONARCHY_ONLY" ] || continue
        "monarchy_${u}_apply"
        "monarchy_${u}_check"
    done
    monarchy_log "apply complete${MONARCHY_ONLY:+ (only $MONARCHY_ONLY)}"
}

monarchy_update() {
    monarchy_load_lock
    monarchy_load_inventories
    monarchy_snapshot_first
    # Root-owned clone. Fetch+checkout the lock commit as root before
    # check so a lock bump is classified against the new tree, not the
    # previous checkout. User git hits "dubious ownership" on this dest.
    monarchy_sync_omarchy_clone
    monarchy_check
    monarchy_apply
}
