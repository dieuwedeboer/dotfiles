#!/usr/bin/env bash
# The overlay bin/, built into a temp prefix. No sudo, no /etc edits.
#
# This is bricking surface in the most direct way `CONTEXT.md` names it: a
# needed command replaced by a deny stub, or missing from a path that shadows
# /usr/bin. $OMARCHY_PATH/bin is an advertised path, not just a PATH element --
# packaged scripts resolve their siblings through it absolutely, so a name
# that is absent there is a name that does not run. omarchy-system-sleep-monitor
# re-execs itself and the lock helper that way, and a sparse overlay killed the
# service holding logind's delay inhibitor: the box suspended unlocked.
#
# The tree is synthetic, so this is deterministic and needs no installed
# package.
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

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

monarchy_load_inventories

# Every name we override, plus plain ones that must survive as symlinks.
PLAIN=(omarchy omarchy-install-app omarchy-pkg-add omarchy-apply-lock
    omarchy-plymouth-set-by-theme omarchy-system-sleep-monitor
    omarchy-system-sleep-lock omarchy-plugin-validate omarchy-shell)
mkdir -p "$tmp/src/bin"
for name in "${MONARCHY_BIN_DENY[@]}" "${MONARCHY_BIN_WRAP[@]}" "${PLAIN[@]}"; do
    printf '#!/bin/sh\necho %s\n' "$name" >"$tmp/src/bin/$name"
    chmod +x "$tmp/src/bin/$name"
done
# Kept to compare against afterwards: install(1) unlinks before writing, and
# the day it does not, a stub is written straight through a mirrored symlink
# into the pacman-owned tree.
cp -a "$tmp/src/bin" "$tmp/src-reference"

export MONARCHY_SRC=$tmp/src
export MONARCHY_PATH=$tmp/prefix
export MONARCHY_INSTALL_SUDO_STUBS=0
export MONARCHY_LOG=$tmp/log
mkdir -p "$MONARCHY_PATH"

monarchy_check_overrides_exist
monarchy_check_bin_hazards
monarchy_rebuild_overlay

dest=$MONARCHY_PATH/bin
kind() { stat -c %F "$1" 2>/dev/null || echo missing; }

# --- denied names: a real stub that refuses, never a link ----------------

for name in "${MONARCHY_BIN_DENY[@]}"; do
    [ "$(kind "$dest/$name")" = "regular file" ] \
        || fail "deny $name is $(kind "$dest/$name"), expected a regular file"
    cmp -s "$dest/$name" "$LIB/stubs/deny.sh" \
        || fail "deny $name is not the deny stub"
    set +e
    "$dest/$name" >/dev/null 2>&1
    st=$?
    set -e
    [ "$st" -eq 2 ] || fail "deny $name exits $st, expected 2"
done

# --- wrapped names: a real file, and the right stub behind it ------------

for name in "${MONARCHY_BIN_WRAP[@]}"; do
    [ "$(kind "$dest/$name")" = "regular file" ] \
        || fail "wrap $name is $(kind "$dest/$name"), expected a regular file"
    [ -x "$dest/$name" ] || fail "wrap $name is not executable"
    stub=$(monarchy_wrap_stub_for "$name")
    cmp -s "$dest/$name" "$stub" \
        || fail "wrap $name is not $(basename "$stub")"
done
[ -x "$dest/yay" ] || fail "yay wrapper missing"

# --- everything else: mirrored, and resolving ---------------------------

# A dangling entry is worse than no entry: it shadows /usr/bin as well as
# failing an absolute call.
for name in "${PLAIN[@]}"; do
    [ "$(kind "$dest/$name")" = "symbolic link" ] \
        || fail "$name is $(kind "$dest/$name"), expected a symlink"
    [ -x "$dest/$name" ] || fail "$name does not resolve through the overlay"
    [ "$(readlink "$dest/$name")" = "$MONARCHY_SRC/bin/$name" ] \
        || fail "$name does not point at the packaged tree"
done

# Every packaged name is reachable, override or not, and the overlay carries
# nothing beyond them but yay.
names_in() { find "$1" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort; }
missing=$(comm -23 <(names_in "$MONARCHY_SRC/bin") <(names_in "$dest"))
[ -z "$missing" ] || fail "packaged names missing from the overlay: $missing"
extra=$(comm -13 <(names_in "$MONARCHY_SRC/bin") <(names_in "$dest"))
[ "$extra" = yay ] || fail "overlay carries names the package does not ship: $extra"

# The packaged tree comes out of a rebuild byte-for-byte as it went in.
diff -r "$tmp/src-reference" "$MONARCHY_SRC/bin" >/dev/null \
    || fail "the overlay build wrote into the pacman-owned tree"

# --- the hazard scan ----------------------------------------------------

# This replaced "every name must be in an inventory". It is the only thing
# standing between a renamed brick -- an unclassified binary that drives
# limine, snapper or pacman.conf -- and the overlay.
printf '#!/bin/sh\nlimine-entry-tool --add-kernel "$@"\n' >"$tmp/src/bin/omarchy-something-new"
chmod +x "$tmp/src/bin/omarchy-something-new"
if ( monarchy_check_bin_hazards ) >/dev/null 2>&1; then
    fail "hazard scan passed an unclassified binary that calls limine-entry-tool"
fi
rm -f "$tmp/src/bin/omarchy-something-new"
monarchy_check_bin_hazards || fail "hazard scan failed on a clean tree"

# A wrap or deny for a name upstream dropped is dead weight that hides a
# rename, and a rename is how an unclassified hazard gets in.
rm -f "$tmp/src/bin/omarchy-refresh-pacman"
if ( monarchy_check_overrides_exist ) >/dev/null 2>&1; then
    fail "override check passed a denied name that is no longer in the package"
fi

echo "overlay tests passed"
