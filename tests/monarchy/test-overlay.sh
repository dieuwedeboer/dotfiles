#!/usr/bin/env bash
# Rebuild the overlay into a temp prefix. No sudo. No /etc edits.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"
# shellcheck source=../../lib/monarchy/common.sh
source "$LIB/common.sh"
# shellcheck source=../../lib/monarchy/denylist.sh
source "$LIB/denylist.sh"
# shellcheck source=../../lib/monarchy/overlay.sh
source "$LIB/overlay.sh"

CLONE=$(require_clone "${1:-}")
[ -d "$CLONE/bin" ] || fail "clone at $CLONE has no bin/"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export MONARCHY_SRC=$CLONE
export MONARCHY_PATH=$tmp/prefix
export MONARCHY_INSTALL_SUDO_STUBS=0
export MONARCHY_LOG=$tmp/log
mkdir -p "$MONARCHY_PATH"

monarchy_load_inventories
monarchy_check_inventory_complete
monarchy_check_clone_bin_classified
monarchy_rebuild_overlay

dest=$MONARCHY_PATH/bin
[ -L "$dest/omarchy" ] || { echo "omarchy is not a symlink" >&2; exit 1; }
[ "$(readlink "$dest/omarchy")" = "$CLONE/bin/omarchy" ] || {
    echo "omarchy symlink target wrong" >&2
    exit 1
}
[ -x "$dest/omarchy-refresh-pacman" ] || { echo "deny stub missing" >&2; exit 1; }
[ ! -L "$dest/omarchy-refresh-pacman" ] || { echo "deny name is a symlink" >&2; exit 1; }
set +e
"$dest/omarchy-refresh-pacman" >/dev/null 2>&1
st=$?
set -e
[ "$st" -eq 2 ] || { echo "deny stub exit is $st, expected 2" >&2; exit 1; }
[ -x "$dest/omarchy-update" ] || { echo "wrap missing" >&2; exit 1; }
grep -q 'monarchy-update' "$dest/omarchy-update" || { echo "update wrap is not wrap-update" >&2; exit 1; }
[ -x "$dest/omarchy-refresh-plymouth" ] || { echo "plymouth wrap missing" >&2; exit 1; }
grep -q 'wrap-plymouth does not handle' "$dest/omarchy-refresh-plymouth" || {
    echo "refresh-plymouth is not wrap-plymouth" >&2
    exit 1
}
[ -x "$dest/omarchy-refresh-sddm" ] || { echo "sddm wrap missing" >&2; exit 1; }
[ ! -L "$dest/omarchy-refresh-sddm" ] || { echo "refresh-sddm wrap is a symlink" >&2; exit 1; }
grep -q 'monarchy_refresh_sddm' "$dest/omarchy-refresh-sddm" || {
    echo "refresh-sddm is not wrap-sddm" >&2
    exit 1
}
[ -L "$dest/omarchy-plymouth-set-by-theme" ] || { echo "set-by-theme should be allowlisted" >&2; exit 1; }
[ -L "$dest/omarchy-install-app" ] || { echo "omarchy-install-app should be allowlisted" >&2; exit 1; }
[ -L "$dest/omarchy-pkg-add" ] || { echo "omarchy-pkg-add should be allowlisted" >&2; exit 1; }
[ ! -L "$dest/omarchy-apply-system" ] || { echo "omarchy-apply-system must stay a deny stub" >&2; exit 1; }
[ -x "$dest/omarchy-screensaver" ] || { echo "screensaver wrap missing" >&2; exit 1; }
[ ! -L "$dest/omarchy-screensaver" ] || { echo "screensaver wrap is a symlink" >&2; exit 1; }
grep -q 'monarchy_seed_branding' "$dest/omarchy-screensaver" || {
    echo "screensaver wrap does not seed branding" >&2
    exit 1
}
[ -x "$dest/omarchy-version" ] || { echo "version wrap missing" >&2; exit 1; }
[ ! -L "$dest/omarchy-version" ] || { echo "omarchy-version wrap is a symlink" >&2; exit 1; }
[ ! -L "$dest/omarchy-version-branch" ] || { echo "omarchy-version-branch wrap is a symlink" >&2; exit 1; }
[ ! -L "$dest/omarchy-version-channel" ] || { echo "omarchy-version-channel wrap is a symlink" >&2; exit 1; }
grep -q 'wrap-version does not handle' "$dest/omarchy-version" || {
    echo "omarchy-version is not wrap-version" >&2
    exit 1
}
[ -x "$dest/yay" ] || { echo "yay wrapper missing" >&2; exit 1; }

allow_n=${#MONARCHY_BIN_ALLOW[@]}
wrap_n=${#MONARCHY_BIN_WRAP[@]}
deny_n=${#MONARCHY_BIN_DENY[@]}
overlay_n=$(find "$dest" -maxdepth 1 \( -type f -o -type l \) | wc -l)
# overlay also has yay
expected=$((allow_n + wrap_n + deny_n + 1))
[ "$overlay_n" -eq "$expected" ] || {
    echo "overlay has $overlay_n entries, expected $expected" >&2
    exit 1
}

# monarchy_apply must classify the clone before it builds anything from it.
# That property now lives in two places: the clone unit runs before the overlay
# unit, and inside monarchy_clone_apply the sync happens before the assert.
monarchy_reaches apply | grep -qx 'monarchy_check_inventory_complete' \
    || fail "apply does not reach monarchy_check_inventory_complete"
monarchy_reaches apply | grep -qx 'monarchy_check_clone_bin_classified' \
    || fail "apply does not reach monarchy_check_clone_bin_classified"

units=$(sed -n 's/^MONARCHY_UNITS=(\(.*\))$/\1/p' "$LIB/update.sh")
[ -n "$units" ] || fail "MONARCHY_UNITS not found"
idx_of() { printf '%s\n' "$units" | tr ' ' '\n' | grep -nx "$1" | cut -d: -f1; }
clone_i=$(idx_of clone); overlay_i=$(idx_of overlay); pacman_i=$(idx_of pacman)
[ -n "$clone_i" ] && [ -n "$overlay_i" ] && [ -n "$pacman_i" ] \
    || fail "clone, overlay and pacman must all be units"
[ "$clone_i" -lt "$overlay_i" ] || fail "overlay unit runs before the clone unit"
[ "$overlay_i" -lt "$pacman_i" ] || fail "pacman unit runs before the overlay unit"

clone_apply=$(awk '/^monarchy_clone_apply\(\)/,/^}$/' "$LIB/update.sh")
line_of() {
    printf '%s\n' "$clone_apply" \
        | grep -nE "^[[:space:]]*$1[[:space:]]*$" \
        | head -1 | cut -d: -f1 || true
}
sync_at=$(line_of 'monarchy_sync_omarchy_clone')
assert_at=$(line_of 'monarchy_clone_assert')
link_at=$(line_of 'monarchy_link_working_prefix')
[ -n "$sync_at" ] || fail "monarchy_clone_apply does not sync the clone"
[ -n "$assert_at" ] || fail "monarchy_clone_apply does not assert the clone"
[ -n "$link_at" ] || fail "monarchy_clone_apply does not link the working prefix"
[ "$assert_at" -gt "$sync_at" ] || fail "clone asserted before it is synced"
[ "$assert_at" -lt "$link_at" ] || fail "working prefix linked before the clone is asserted"

# The cache bootstrap repoints MONARCHY_SRC and must never run during apply.
monarchy_reaches apply | grep -qx 'monarchy_ensure_clone_for_check' \
    && fail "apply reaches monarchy_ensure_clone_for_check; it repoints MONARCHY_SRC at a cache"
monarchy_reaches check | grep -qx 'monarchy_ensure_clone_for_check' \
    || fail "check does not bootstrap a clone for a dry run"

# monarchy_write_to is the whole difference between building the overlay as
# the user on a temp prefix and as root on a real box. The temp-prefix run
# above only exercises the writable path, so drive the dispatch directly with
# monarchy_sudo stubbed out. Skipped as root, where -w is always true.
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    wt=$(mktemp -d)
    calls=$wt/calls
    : >"$calls"
    # Called indirectly, by monarchy_write_to.
    # shellcheck disable=SC2329
    monarchy_sudo() { printf 'sudo %s\n' "$*" >>"$calls"; }

    mkdir -p "$wt/open"
    monarchy_write_to "$wt/open" touch "$wt/open/f"
    [ -f "$wt/open/f" ] || fail "write_to did not run the command on a writable dir"
    [ ! -s "$calls" ] || fail "write_to elevated for a writable dir"

    mkdir -p "$wt/closed"
    chmod 500 "$wt/closed"
    monarchy_write_to "$wt/closed" touch "$wt/closed/f"
    grep -q '^sudo touch ' "$calls" || fail "write_to did not elevate for an unwritable dir"
    [ ! -e "$wt/closed/f" ] || fail "write_to ran unelevated against an unwritable dir"

    chmod 700 "$wt/closed"
    rm -rf "$wt"
    unset -f monarchy_sudo
fi

echo "overlay test passed ($allow_n allow, $wrap_n wrap, $deny_n deny)"
