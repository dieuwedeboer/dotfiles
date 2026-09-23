#!/usr/bin/env bash
# The launcher.hides overlay is subtractive, and the unhide list cannot rot.
#
# The subtractive shape is the whole point: omarchy adds rows to
# launcher.hides between releases, and a Monarchy-owned copy would silently
# stop inheriting them. So the test that matters is not "base is unhidden",
# it is "everything we did not name is still hidden".
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"
# shellcheck source=../../lib/monarchy/common.sh
source "$LIB/common.sh"
# shellcheck source=../../lib/monarchy/denylist.sh
source "$LIB/denylist.sh"
# shellcheck source=../../lib/monarchy/prefix.sh
source "$LIB/prefix.sh"
# shellcheck source=../../lib/monarchy/overlay.sh
source "$LIB/overlay.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

monarchy_load_inventories

[ "${#MONARCHY_LAUNCHER_UNHIDE[@]}" -gt 0 ] || fail "launcher.unhides is empty"

# A stand-in for the packaged default/omarchy/. UPSTREAM_ONLY stands for a row
# added by a later omarchy release that nobody has classified: it must survive.
UPSTREAM_ONLY=(btop foot-server some-new-app-omarchy-will-add)
mkdir -p "$tmp/src/default/omarchy"
printf '%s\n' "${MONARCHY_LAUNCHER_UNHIDE[@]}" "${UPSTREAM_ONLY[@]}" \
    >"$tmp/src/default/omarchy/launcher.hides"
: >"$tmp/src/default/omarchy/omarchy-menu.jsonc"

export MONARCHY_SRC=$tmp/src
export MONARCHY_PATH=$tmp/prefix
export MONARCHY_LOG=$tmp/log
mkdir -p "$MONARCHY_PATH"
ln -sfn "$MONARCHY_SRC/default" "$MONARCHY_PATH/default"

monarchy_check_launcher_unhides
monarchy_overlay_launcher_hides

dest=$MONARCHY_PATH/default/omarchy/launcher.hides
[ -f "$dest" ] || fail "no launcher.hides in the prefix"
[ ! -L "$dest" ] || fail "launcher.hides is still a symlink into the package tree"

# The package file must not have been edited. pacman owns it, and the next
# -Syu would revert a write here anyway.
grep -qx libreoffice-base "$MONARCHY_SRC/default/omarchy/launcher.hides" \
    || fail "the overlay wrote through to the pacman-owned launcher.hides"

for name in "${MONARCHY_LAUNCHER_UNHIDE[@]}"; do
    grep -qx -- "$name" "$dest" && fail "$name is still hidden"
done

for name in "${UPSTREAM_ONLY[@]}"; do
    grep -qx -- "$name" "$dest" || fail "$name was dropped; the overlay is not subtractive"
done

# The sibling file the lock overlay owns must survive exploding default/.
[ -e "$MONARCHY_PATH/default/omarchy/omarchy-menu.jsonc" ] \
    || fail "exploding default/omarchy lost omarchy-menu.jsonc"

# Applying twice must be a no-op, not an accumulation: an apply runs on every
# update and the second one starts from the package file again.
before=$(cat "$dest")
monarchy_overlay_launcher_hides
[ "$before" = "$(cat "$dest")" ] || fail "a second apply changed the result"

# A row upstream stops hiding is a no-op, and a no-op row is indistinguishable
# from one that works. The guard has to catch it.
grep -vx libreoffice-base "$MONARCHY_SRC/default/omarchy/launcher.hides" >"$tmp/trimmed"
mv "$tmp/trimmed" "$MONARCHY_SRC/default/omarchy/launcher.hides"
if ( monarchy_check_launcher_unhides ) 2>/dev/null; then
    fail "the guard passed a launcher.unhides row that omarchy no longer hides"
fi

echo "$TEST_NAME: passed"
