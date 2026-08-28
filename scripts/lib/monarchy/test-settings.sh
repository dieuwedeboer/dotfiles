#!/usr/bin/env bash
# Settings skip list and file install. No live /etc writes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MISC="$SCRIPT_DIR/../../../misc/monarchy"

fail() {
    echo "test-settings: $*" >&2
    exit 1
}

skip="$MISC/settings.skip"
[ -f "$skip" ] || fail "missing $skip"
grep -qx 'etc/mkinitcpio.conf.d/omarchy_hooks.conf' "$skip" \
    || fail "skip list missing plymouth-before-zfs hooks"
grep -qx 'etc/limine-entry-tool.d/omarchy-defaults.conf' "$skip" \
    || fail "skip list missing Limine"
grep -qx 'default/applications/mimeapps.list' "$skip" \
    || fail "skip list missing mimeapps"
grep -qx 'etc/sddm.conf.d/10-theme.conf' "$skip" \
    || fail "skip list missing stock sddm 10-theme.conf"

# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
# shellcheck source=denylist.sh
source "$SCRIPT_DIR/denylist.sh"
# shellcheck source=settings.sh
source "$SCRIPT_DIR/settings.sh"

monarchy_load_inventories
monarchy_assert_settings_assets

monarchy_in_list omarchy-install-app "${MONARCHY_BIN_ALLOW[@]}" \
    || fail "omarchy-install-app not allowed"
monarchy_in_list omarchy-pkg-add "${MONARCHY_BIN_ALLOW[@]}" \
    || fail "omarchy-pkg-add not allowed"
monarchy_in_list omarchy-provision-user "${MONARCHY_BIN_ALLOW[@]}" \
    || fail "omarchy-provision-user not allowed"
monarchy_in_list omarchy-refresh-pacman "${MONARCHY_BIN_DENY[@]}" \
    || fail "omarchy-refresh-pacman not denied"
monarchy_in_list omarchy-apply-system "${MONARCHY_BIN_DENY[@]}" \
    || fail "omarchy-apply-system not denied"
monarchy_in_list omarchy-refresh-limine "${MONARCHY_BIN_DENY[@]}" \
    || fail "omarchy-refresh-limine not denied"

apply_body=$(awk '/^monarchy_apply\(\)/,/^monarchy_update\(\)/' "$SCRIPT_DIR/update.sh")
echo "$apply_body" | grep -q 'monarchy_install_settings' \
    || fail "monarchy_apply does not install settings files"
echo "$apply_body" | grep -q 'monarchy_run_omarchy_config' \
    || fail "monarchy_apply does not run omarchy config scripts"
grep -q 'mise activate' "$MISC/10-monarchy" \
    || fail "10-monarchy missing mise activate"
grep -q '/usr/local/share/omarchy/default/bash/env-bootstrap' "$MISC/10-monarchy" \
    || fail "10-monarchy lost the working-prefix bootstrap"

CLONE="${MONARCHY_SRC:-/usr/local/src/monarchy/omarchy}"
if [ -d "$CLONE/etc/sudoers.d" ]; then
    tmp=$(mktemp -d)
    cleanup_tmp() { rm -rf "$tmp"; }
    trap cleanup_tmp EXIT
    monarchy_sudo() { "$@"; }
    export MONARCHY_SRC="$CLONE"
    export MONARCHY_ROOT="$tmp/root"
    export MONARCHY_MISC="$MISC"
    mkdir -p "$MONARCHY_ROOT"
    monarchy_install_settings
    [ -f "$MONARCHY_ROOT/etc/sudoers.d/omarchy-tzupdate" ] \
        || fail "did not install sudoers drop-in"
    [ ! -e "$MONARCHY_ROOT/etc/mkinitcpio.conf.d/omarchy_hooks.conf" ] \
        || fail "installed plymouth-before-zfs hooks"
    [ ! -e "$MONARCHY_ROOT/etc/limine-entry-tool.d/omarchy-defaults.conf" ] \
        || fail "installed Limine drop-in"
    [ ! -e "$MONARCHY_ROOT/etc/sddm.conf.d/10-theme.conf" ] \
        || fail "installed stock sddm 10-theme.conf"
    grep -q '/usr/local/share/omarchy/default/bash/env-bootstrap' \
        "$MONARCHY_ROOT/etc/profile.d/omarchy.sh" \
        || fail "profile.d still hardcodes /usr/share/omarchy"
    grep -q '/usr/share/omarchy/default/bash/env-bootstrap' \
        "$MONARCHY_ROOT/etc/profile.d/omarchy.sh" \
        && fail "profile.d still sources /usr/share/omarchy"
    unit="$MONARCHY_ROOT/usr/lib/systemd/user/omarchy-sleep-lock.service"
    [ -f "$unit" ] || fail "did not install sleep-lock unit"
    grep -q '/usr/local/bin/omarchy-system-sleep-monitor' "$unit" \
        || fail "sleep-lock unit still points at /usr/bin"
    [ -f "$MONARCHY_ROOT/usr/share/fontconfig/conf.avail/50-omarchy.conf" ] \
        || fail "did not install fontconfig"
    [ -L "$MONARCHY_ROOT/etc/fonts/conf.d/50-omarchy.conf" ] \
        || fail "fontconfig conf.d symlink missing"
else
    echo "test-settings: skip live copy (no $CLONE/etc)" >&2
fi

echo "settings tests passed"
