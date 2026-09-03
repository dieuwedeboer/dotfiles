#!/usr/bin/env bash
# The unit list is the ordering constraint that used to live in prose.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"
# shellcheck source=../../lib/monarchy.sh
source "$REPO/lib/monarchy.sh"

[ "${#MONARCHY_UNITS[@]}" -gt 0 ] || fail "MONARCHY_UNITS is empty"

# check and apply cannot drift apart any more, because both walk this array.
for u in "${MONARCHY_UNITS[@]}"; do
    declare -F "monarchy_${u}_check" >/dev/null || fail "no monarchy_${u}_check"
    declare -F "monarchy_${u}_apply" >/dev/null || fail "no monarchy_${u}_apply"
done

# Every guard the old linear check ran must still be reached.
for fn in monarchy_assert_zfs_layout monarchy_assert_os_release \
    monarchy_refuse_bootloader monarchy_refuse_snapper monarchy_refuse_kernel_swap \
    monarchy_skip_os_release_clobber monarchy_skip_autologin monarchy_skip_plymouth_zfs \
    monarchy_refuse_dataset_rename monarchy_disable_omarchy_update_guard \
    monarchy_preserve_pacman_conf monarchy_refuse_archzfs monarchy_refuse_omarchy_zfs_repo \
    monarchy_refuse_partial_upgrade monarchy_check_inventory_complete \
    monarchy_check_clone_bin_classified monarchy_check_migrations \
    monarchy_check_packages_deny monarchy_check_applications_drop monarchy_check_plugins \
    monarchy_check_session_lock_overlay monarchy_check_logind \
    monarchy_check_hidden_hyprland_sessions monarchy_assert_settings_assets \
    monarchy_assert_sddm_assets monarchy_assert_sddm_runtime; do
    monarchy_reaches check | grep -qx "$fn" || fail "check no longer reaches $fn"
done

# Every action the old linear apply performed must still be reached.
for fn in monarchy_sync_omarchy_clone monarchy_link_working_prefix monarchy_rebuild_overlay \
    monarchy_overlay_session_lock monarchy_install_switch_user monarchy_install_user_setup \
    monarchy_write_omarchy_conf monarchy_add_omarchy_repo monarchy_install_packages \
    monarchy_install_settings monarchy_run_omarchy_config monarchy_keep_sddm \
    monarchy_apply_lock monarchy_install_omarchy_session monarchy_apply_logind \
    monarchy_install_uwsm_env monarchy_install_hyprland_portals monarchy_setup_user \
    monarchy_keep_family_mime monarchy_splash monarchy_splash_maybe_theme; do
    monarchy_reaches apply | grep -qx "$fn" || fail "apply no longer reaches $fn"
done

# Apply runs each unit's check before its apply, so a guard cannot be skipped
# by using a bare apply instead of an update. One deliberate exception:
# monarchy_ensure_clone_for_check repoints MONARCHY_SRC at a user cache when no
# clone exists, so that a dry run has something to read. During apply it would
# make apply build from the cache instead of /usr/local/src.
check_only='monarchy_ensure_clone_for_check'
apply_reaches=$(monarchy_reaches apply)
for fn in $(monarchy_reaches check); do
    [ "$fn" = "$check_only" ] && continue
    printf '%s\n' "$apply_reaches" | grep -qx "$fn" \
        || fail "apply does not run $fn, which check does"
done
printf '%s\n' "$apply_reaches" | grep -qx "$check_only" \
    && fail "$check_only must not run during apply"

# --only must reject a name that is not a unit rather than doing nothing.
if ( trap - EXIT; MONARCHY_ONLY=nosuchunit monarchy_assert_only_valid ) >/dev/null 2>&1; then
    fail "--only accepted a name that is not a unit"
fi
MONARCHY_ONLY=sddm monarchy_assert_only_valid || fail "--only=sddm was rejected"
grep -q -- '--only=' "$REPO/install.sh" || fail "install.sh does not accept --only"

echo "unit tests passed"
