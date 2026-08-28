#!/usr/bin/env bash
# Rebuild the overlay into a temp prefix. No sudo. No /etc edits.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
# shellcheck source=denylist.sh
source "$SCRIPT_DIR/denylist.sh"
# shellcheck source=overlay.sh
source "$SCRIPT_DIR/overlay.sh"

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
grep -q 'setup-monarchy' "$dest/omarchy-update" || { echo "update wrap is not wrap-update" >&2; exit 1; }
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

echo "overlay test passed ($allow_n allow, $wrap_n wrap, $deny_n deny)"
