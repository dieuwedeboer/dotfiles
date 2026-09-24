#!/usr/bin/env bash
# migrations.deny has to be enforced, not just recorded.
#
# The list used to be read in one place -- monarchy_check_migrations, which
# halts an apply until a newly arrived hazardous migration is classified. Once
# classified, nothing stopped omarchy-migrate offering and running it, so a
# denied migration sat pending for ever, one menu click from executing. Omarchy
# tracks completion as a per-user marker, so marking a denied migration
# complete is what takes it out of --pending.
#
# No sudo, no network. Temp HOME and a temp package tree.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"
# shellcheck source=../../lib/monarchy/common.sh
source "$LIB/common.sh"
# shellcheck source=../../lib/monarchy/user.sh
source "$LIB/user.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

HOME="$WORK/home"
export HOME
MONARCHY_SRC="$WORK/src"
export MONARCHY_SRC
mkdir -p "$MONARCHY_SRC/migrations" "$HOME"

STATE="$HOME/.local/state/omarchy/migrations"

# Three shipped migrations: two denied, one not. Plus a deny row for a name
# this tree does not ship, which is what a migration upstream dropped looks
# like -- it must not leave a marker behind.
for m in 1000000001.sh 1000000002.sh 1000000003.sh; do
    printf 'echo %s\n' "$m" >"$MONARCHY_SRC/migrations/$m"
done
# shellcheck disable=SC2034  # read by monarchy_mark_denied_migrations
MONARCHY_MIGRATE_DENY=(1000000001.sh 1000000003.sh 1999999999.sh)

monarchy_mark_denied_migrations >/dev/null

# The whole marker set as one value. 1000000002.sh is shipped and not denied,
# so marking it would skip a migration nobody classified; 1999999999.sh is
# denied and not shipped, and marking that would hide a stale deny row from
# monarchy_check_migrations. Both show up here as the set being wrong.
markers=$(cd "$STATE" && printf '%s\n' * | LC_ALL=C sort | paste -sd' ' -)
[ "$markers" = "1000000001.sh 1000000003.sh" ] \
    || fail "marked migrations are: $markers"

# The postcondition passes once the apply has run...
monarchy_assert_denied_migrations_marked || fail "assert failed on a correctly marked tree"

# ...and catches the state the bug left behind: denied, shipped, unmarked.
rm -f "$STATE/1000000003.sh"
if ( trap - EXIT; monarchy_assert_denied_migrations_marked ) >/dev/null 2>&1; then
    fail "assert passed with a denied migration unmarked; omarchy-migrate would still run it"
fi
: >"$STATE/1000000003.sh"

# Marking is idempotent and must not disturb a marker already there. Omarchy
# writes these as empty files; a re-run that truncated a real one would be
# harmless, but a re-run that removed it would put the migration back.
before=$(find "$STATE" -maxdepth 1 -type f | sort)
monarchy_mark_denied_migrations >/dev/null
after=$(find "$STATE" -maxdepth 1 -type f | sort)
[ "$before" = "$after" ] || fail "a second run changed the marker set"

# No package tree yet (a box before the omarchy package lands) is not a
# failure: there is nothing to mark and nothing to assert.
rm -rf "$MONARCHY_SRC/migrations"
monarchy_mark_denied_migrations >/dev/null || fail "marking failed with no package tree"
monarchy_assert_denied_migrations_marked || fail "assert failed with no package tree"

echo "migration deny tests passed"
