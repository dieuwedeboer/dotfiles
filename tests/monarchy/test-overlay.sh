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

CLONE=${1:-${MONARCHY_SRC:-/tmp/quattro-on-zfs}}
[ -d "$CLONE/bin" ] || { echo "need a quattro-on-zfs checkout with bin/" >&2; exit 2; }

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
# A bare apply and --no-packages never call monarchy_check, so the guards have
# to sit in apply itself: after the clone exists, before the overlay.
apply_body=$(awk '/^monarchy_apply\(\)/,/^}$/' "$LIB/update.sh")
# Anchored so a comment naming a guard cannot outrank the call itself, and
# `|| true` so a miss returns empty instead of aborting the test under
# `set -euo pipefail` before the diagnostic below can run.
line_of() {
    printf '%s\n' "$apply_body" \
        | grep -nE "^[[:space:]]*$1[[:space:]]*$" \
        | head -1 | cut -d: -f1 || true
}

sync_at=$(line_of 'monarchy_sync_omarchy_clone')
inv_at=$(line_of 'monarchy_check_inventory_complete')
cls_at=$(line_of 'monarchy_check_clone_bin_classified')
build_at=$(line_of 'monarchy_rebuild_overlay')

[ -n "$sync_at" ] || fail "monarchy_apply does not call monarchy_sync_omarchy_clone"
[ -n "$build_at" ] || fail "monarchy_apply does not call monarchy_rebuild_overlay"
[ -n "$inv_at" ] || fail "monarchy_apply does not call monarchy_check_inventory_complete"
[ -n "$cls_at" ] || fail "monarchy_apply does not call monarchy_check_clone_bin_classified"
[ "$inv_at" -gt "$sync_at" ] || fail "inventory guard runs before the clone is synced"
[ "$cls_at" -gt "$sync_at" ] || fail "classification guard runs before the clone is synced"
[ "$inv_at" -lt "$build_at" ] || fail "inventory guard runs after the overlay is built"
[ "$cls_at" -lt "$build_at" ] || fail "classification guard runs after the overlay is built"

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
