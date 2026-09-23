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
    for required in plasma-login-manager tldr snapper limine \
        limine-mkinitcpio-hook limine-snapper-sync omarchy-dev \
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
            || monarchy_die "applications.drop $name missing from the omarchy package applications/"
    done
    return 0
}

# One ordered list of units, each with a check verb and an apply verb.
# check and apply were two hand-maintained linear lists, free to drift, and
# they had: apply never ran the two inventory guards. Now they cannot, because
# both walk this array. The order is the constraint that used to live only in
# prose, so it is the one thing to read carefully before editing.
#
# The order changed when the clone went away. It now has to be:
#   pacman     [omarchy] has to exist before anything can be downloaded
#   packaging  builds the two local packages, then installs `omarchy`
#   prefix     links the working prefix out of the tree `omarchy` just landed
#   overlay    stubs and wraps, which need that prefix
#   leaves     reads install/omarchy-base.packages, which only exists after
#              `omarchy` is installed
# Everything from settings onward is unchanged.
#
# --only=<unit> runs a single unit. There is no canary box here and
# zfs-snapshot-pre-update keeps three snapshots, so a full apply is an
# expensive way to iterate on one subsystem.
MONARCHY_UNITS=(guards pacman packaging prefix overlay leaves settings sddm session logind portals user splash)

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

# ---- pacman: CachyOS first, [omarchy] after ------------------------------

monarchy_pacman_check() {
    monarchy_preserve_pacman_conf
    monarchy_refuse_archzfs
    monarchy_refuse_omarchy_zfs_repo
}

monarchy_pacman_apply() {
    monarchy_add_omarchy_repo
}

# ---- packaging: the two local packages, then the real omarchy ------------

monarchy_packaging_check() {
    monarchy_check_pkgbuilds
}

monarchy_packaging_apply() {
    monarchy_build_packages
}

# ---- prefix: the working prefix out of the package tree ------------------

# Everything that must hold about the package tree once it is on disk.
monarchy_prefix_assert() {
    monarchy_assert_source_tree
    monarchy_check_overrides_exist
    monarchy_check_bin_hazards
    monarchy_check_migrations
}

# Apply runs every unit's check before its apply, and on a first install the
# omarchy package is not there yet at this point. monarchy_prefix_apply
# asserts again once it is, so skipping here loses nothing.
monarchy_prefix_check() {
    [ -d "$MONARCHY_SRC/bin" ] || return 0
    monarchy_prefix_assert
}

monarchy_prefix_apply() {
    monarchy_prefix_assert
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
    monarchy_check_power_panel_overlay
    monarchy_check_launcher_unhides
}

monarchy_overlay_apply() {
    monarchy_rebuild_overlay
    monarchy_overlay_session_lock
    monarchy_overlay_power_panel
    monarchy_overlay_launcher_hides
    monarchy_install_switch_user
    monarchy_install_user_setup
}

# ---- leaves: the filtered omarchy-base.packages set ----------------------

# The partial-upgrade guard lives here, on the only unit that installs from a
# repo, and not on `pacman` where it used to sit. `pacman` runs before
# `packaging`, and once an [omarchy] package hard-depends on `omarchy` --
# flea 0.3.1 does -- the pending upgrade a converting box cannot clear is the
# very one `packaging` makes resolvable, by installing omarchy-settings-monarchy
# in place of the upstream omarchy-settings that collides with 64 files.
# The guard then refused every route to its own precondition and the only way
# through was --only=packaging, which is an escape hatch, not a workflow.
#
# Nothing is lost by moving it: this check returns early until `omarchy` has
# landed install/omarchy-base.packages, there are no leaves to install before
# that, and monarchy_install_packages calls the guard again at the point of use.
monarchy_leaves_check() {
    [ -f "$MONARCHY_SRC/install/omarchy-base.packages" ] || return 0
    monarchy_refuse_partial_upgrade
    monarchy_check_packages_deny
    monarchy_filtered_packages | grep -qx sddm \
        || monarchy_die "sddm missing from filtered package list"
    if monarchy_filtered_packages | grep -qx plasma-login-manager; then
        monarchy_die "plasma-login-manager leaked into filtered package list"
    fi
}

monarchy_leaves_apply() {
    monarchy_install_packages
}

# ---- settings: the profile.d repoint; the package owns the rest ----------

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
    monarchy_assert_denied_migrations_marked
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
    # There is no clone to fall back on any more: MONARCHY_SRC is a
    # pacman-owned path, so a dry run either has the omarchy package or the
    # units that need it return early.
    # Guards refuse a host this overlay must never touch, so --only cannot
    # skip them. It exists to shrink blast radius, not to remove the floor.
    monarchy_guards_check
    for u in "${MONARCHY_UNITS[@]}"; do
        [ "$u" = guards ] && continue
        [ -z "${MONARCHY_ONLY:-}" ] || [ "$u" = "$MONARCHY_ONLY" ] || continue
        "monarchy_${u}_check"
    done
    monarchy_log "check passed${MONARCHY_ONLY:+ (only $MONARCHY_ONLY)}"
}

# Quickshell lock refuses without /etc/pam.d/omarchy-lock-password.
# Omarchy install/config/lockscreen-pam.sh is this one command.
monarchy_apply_lock() {
    # Not overridden, so it is not in the overlay: it comes from /usr/bin with
    # the rest of the package.
    local bin="$MONARCHY_SRC/bin/omarchy-apply-lock"
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
    monarchy_ensure_log
    monarchy_assert_only_valid
    monarchy_load_lock
    monarchy_load_inventories
    monarchy_snapshot_first
    monarchy_ensure_users_conf
    # Apply first, then verify. A unit's check is a postcondition: it asserts
    # what that unit's apply is supposed to have produced. Checking first
    # aborted every fresh box, because monarchy_check_hidden_hyprland_sessions
    # requires the NoDisplay that monarchy_install_omarchy_session writes, and
    # every converting box, because monarchy_assert_sddm_runtime refuses the
    # plasma-login-manager that monarchy_keep_sddm removes.
    #
    # Host preconditions live in the guards unit, whose apply is a no-op, so
    # they still run before anything is touched.
    # Same floor for apply: the guards run whatever --only says.
    monarchy_guards_check
    for u in "${MONARCHY_UNITS[@]}"; do
        [ "$u" = guards ] && continue
        [ -z "${MONARCHY_ONLY:-}" ] || [ "$u" = "$MONARCHY_ONLY" ] || continue
        "monarchy_${u}_apply"
        "monarchy_${u}_check"
    done
    # After every unit, not inside the overlay one: the shell is restarted
    # once, against a tree that has finished settling, rather than mid-apply.
    monarchy_restart_shell
    monarchy_log "apply complete${MONARCHY_ONLY:+ (only $MONARCHY_ONLY)}"
}

# What a new upstream release can bring that a human has to classify before
# anything is applied: a migration or a binary that touches Limine, snapper or
# pacman.conf, a new omarchy-base.packages row, an applications.drop name that
# upstream stopped shipping, a wrap or deny for a name upstream renamed.
#
# These are the only preconditions an update has. Every other unit check is a
# postcondition -- it asserts what that unit's apply is supposed to have just
# produced -- which is why monarchy_apply runs apply before check.
#
# monarchy_update used to run the whole check sweep first and so re-broke
# exactly what that ordering fixed. Every `hyprland` upgrade replaces
# /usr/share/wayland-sessions/hyprland.desktop and drops the NoDisplay=true
# that monarchy_install_omarchy_session writes, so monarchy_session_check
# failed and the update refused to run the apply that would put it back. The
# same shape waits in monarchy_assert_sddm_runtime. A postcondition reset by a
# package upgrade is the ordinary case for an updater, not an error.
#
# --only is "run one unit only", so the sweep is not part of it; that unit's
# own check still runs inside monarchy_apply.
monarchy_classify_check() {
    [ -z "${MONARCHY_ONLY:-}" ] || return 0
    [ -d "$MONARCHY_SRC/bin" ] || return 0
    monarchy_check_overrides_exist
    monarchy_check_bin_hazards
    monarchy_check_migrations
    monarchy_check_packages_deny
    monarchy_check_applications_drop
    monarchy_check_launcher_unhides
    monarchy_log "classification guards passed"
}

monarchy_update() {
    monarchy_ensure_log
    monarchy_load_lock
    monarchy_load_inventories
    monarchy_snapshot_first
    # Build and install the packages before classifying, so a new upstream
    # version is classified against the tree that is about to be applied
    # rather than the one already on disk.
    monarchy_build_packages
    monarchy_classify_check
    monarchy_apply
}
