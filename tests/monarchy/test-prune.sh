#!/usr/bin/env bash
# /usr/local/bin must not keep clone-era symlinks.
#
# It precedes /usr/bin on PATH and in sudo's secure_path, so a leftover link
# there decides what runs. While the clone is on disk it runs the clone; once
# the clone is removed it dangles and shadows the packaged binary, and the
# name stops working altogether.
#
# The glob used to be omarchy-*, which never matched the bare router
# `omarchy` -- the one name that is deliberately not overridden, and the one
# every menu command goes through.
#
# No sudo: monarchy_sudo is stubbed to act directly on the temp prefix.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"
# shellcheck source=../../lib/monarchy/common.sh
source "$LIB/common.sh"
# shellcheck source=../../lib/monarchy/denylist.sh
source "$LIB/denylist.sh"   # monarchy_in_list, which the prune consults
# shellcheck source=../../lib/monarchy/overlay.sh
source "$LIB/overlay.sh"

declare -F monarchy_in_list >/dev/null \
    || fail "test setup: monarchy_in_list is not defined, so the deny/wrap skip would never run"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

MONARCHY_LOCAL_BIN="$WORK/bin"
export MONARCHY_LOCAL_BIN
MONARCHY_LOG="$WORK/log"
mkdir -p "$MONARCHY_LOCAL_BIN" "$WORK/clone/bin"

# Run the real command; the temp prefix needs no privileges.
monarchy_sudo() { "$@"; }

MONARCHY_BIN_DENY=(omarchy-refresh-pacman)
MONARCHY_BIN_WRAP=(omarchy-update)

: >"$WORK/clone/bin/omarchy"
: >"$WORK/clone/bin/omarchy-theme-set"

# The router, which the old glob missed.
ln -s "$WORK/clone/bin/omarchy" "$MONARCHY_LOCAL_BIN/omarchy"
# A dashed clone-era link, which it caught.
ln -s "$WORK/clone/bin/omarchy-theme-set" "$MONARCHY_LOCAL_BIN/omarchy-theme-set"
# A link that already dangles.
ln -s "$WORK/gone/omarchy-old" "$MONARCHY_LOCAL_BIN/omarchy-old"
# Real files this overlay installs: stubs for a denied and a wrapped name.
# These are not symlinks and must survive whatever the glob matches.
printf '#!/bin/sh\nexit 2\n' >"$MONARCHY_LOCAL_BIN/omarchy-refresh-pacman"
printf '#!/bin/sh\nexit 0\n' >"$MONARCHY_LOCAL_BIN/omarchy-update"
# An unrelated name must not be touched by a widened glob.
ln -s /bin/true "$MONARCHY_LOCAL_BIN/monarchy-update"
# A real file under an omarchy name that is in neither list. The glob matches
# it, the list skip does not save it, and only the symlink test does -- this
# is where "a symlink there is clone-era by definition" earns its keep.
printf '#!/bin/sh\necho hand placed\n' >"$MONARCHY_LOCAL_BIN/omarchy-hand-placed"

monarchy_prune_stale_overlay_links >/dev/null

[ ! -e "$MONARCHY_LOCAL_BIN/omarchy" ] && [ ! -L "$MONARCHY_LOCAL_BIN/omarchy" ] \
    || fail "the bare omarchy router link survived the prune; it shadows /usr/bin/omarchy"
[ ! -L "$MONARCHY_LOCAL_BIN/omarchy-theme-set" ] \
    || fail "a clone-era omarchy-* link survived the prune"
[ ! -L "$MONARCHY_LOCAL_BIN/omarchy-old" ] \
    || fail "a dangling omarchy-* link survived the prune"

[ -f "$MONARCHY_LOCAL_BIN/omarchy-refresh-pacman" ] \
    || fail "pruned the deny stub; a denied name must stay blocked in /usr/local/bin"
[ -f "$MONARCHY_LOCAL_BIN/omarchy-update" ] \
    || fail "pruned the wrap stub; the Omarchy menu calls that name"
[ -L "$MONARCHY_LOCAL_BIN/monarchy-update" ] \
    || fail "pruned monarchy-update, which is not an omarchy name at all"
[ -f "$MONARCHY_LOCAL_BIN/omarchy-hand-placed" ] \
    || fail "pruned a real file under an omarchy name; only symlinks are clone-era"

# A deny/wrap name that is still a symlink is clone-era and must go, so the
# skip has to be about the stub being a real file, not about the name.
ln -s "$WORK/clone/bin/omarchy" "$MONARCHY_LOCAL_BIN/omarchy"
monarchy_prune_stale_overlay_links >/dev/null
[ ! -L "$MONARCHY_LOCAL_BIN/omarchy" ] || fail "the prune is not idempotent"

# An empty directory is not an error: the glob matches nothing and the
# literal pattern must not be treated as a file.
rm -f "$MONARCHY_LOCAL_BIN"/*
monarchy_prune_stale_overlay_links >/dev/null || fail "prune failed on an empty directory"

echo "prune tests passed"
