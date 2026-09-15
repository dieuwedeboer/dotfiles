#!/usr/bin/env bash
# install.sh and --update share one household refresh. A provisioned box
# cannot skip chezmoi just because the operator typed --update.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"

install="$REPO/install.sh"
[ -f "$install" ] || fail "missing $install"

grep -q '^household_refresh()' "$install" \
    || fail "install.sh has no household_refresh"

# The old split: --update exited before chezmoi, hardware, ZFS. That is the
# bug this test exists to catch.
# shellcheck disable=SC2016  # grep pattern, not an expansion
if grep -q 'if \[ "$MODE" != full \]; then' "$install"; then
    fail "install.sh still exits early for every non-full mode, so --update skips household_refresh"
fi

# check and splash must not refresh the box.
dispatch=$(awk '/^case "\$MODE" in/,/^esac/' "$install")
printf '%s\n' "$dispatch" | grep -q 'check|splash' \
    || fail "check/splash are not dispatched before household_refresh"
# Two case "$MODE" blocks: the first must exit 0 for check/splash.
first_case=$(awk '/^case "\$MODE" in/{n++; if(n==1){p=1}} p{print} p && /^esac/{exit}' "$install")
printf '%s\n' "$first_case" | grep -q 'exit 0' \
    || fail "check/splash dispatch does not exit before household_refresh"

# update, apply, and full all reach household_refresh, then monarchy_cli.
grep -q 'household_refresh' "$install" || fail "household_refresh is never called"
call_at=$(grep -n '^[[:space:]]*household_refresh$' "$install" | head -1 | cut -d: -f1)
[ -n "$call_at" ] || fail "household_refresh is defined but never invoked"
cli_at=$(grep -n 'monarchy_cli update' "$install" | tail -1 | cut -d: -f1)
[ -n "$cli_at" ] || fail "install.sh never calls monarchy_cli update"
[ "$call_at" -lt "$cli_at" ] \
    || fail "monarchy_cli update runs before household_refresh"

# --only skips household so iterating on one unit stays cheap.
skip=$(awk '/^if \[ -z "\$\{MONARCHY_ONLY:-\}" \]; then/,/^fi/' "$install")
printf '%s\n' "$skip" | grep -q 'household_refresh' \
    || fail "--only does not skip household_refresh"

# A provisioned box: bare ./install.sh is --update.
grep -q '/etc/omarchy.conf' "$install" \
    || fail "install.sh does not promote a provisioned box from full to update"
promote=$(awk '/A provisioned box/,/^fi/' "$install")
printf '%s\n' "$promote" | grep -q 'MODE=update' \
    || fail "provisioned-box promote does not set MODE=update"

# chezmoi apply in household_refresh is gated. The Omarchy menu has no tty.
refresh_fn=$(awk '/^household_refresh\(\)/,/^}$/' "$install")
[ -n "$refresh_fn" ] || fail "could not extract household_refresh"
printf '%s\n' "$refresh_fn" | grep -q 'monarchy_can_prompt' \
    || fail "household_refresh chezmoi apply is not gated on a terminal"
gate_at=$(printf '%s\n' "$refresh_fn" | grep -n 'monarchy_can_prompt' | head -1 | cut -d: -f1)
run_at=$(printf '%s\n' "$refresh_fn" | grep -nE '^[[:space:]]*chezmoi[[:space:]]+apply' | head -1 | cut -d: -f1)
[ -n "$run_at" ] || fail "household_refresh never runs chezmoi apply"
[ "$gate_at" -lt "$run_at" ] || fail "chezmoi apply runs before the terminal check"
printf '%s\n' "$refresh_fn" | grep -q 'chezmoi apply' \
    || fail "the no-terminal path must still name chezmoi apply"

# lib/zfs.sh also ran chezmoi apply with no gate; a menu-driven --update
# that now reaches zfs.sh would hang the same way.
zfs="$REPO/lib/zfs.sh"
grep -q 'chezmoi apply' "$zfs" || fail "zfs.sh no longer applies chezmoi for the zpool sensor"
zfs_gate=$(awk '/Applying chezmoi/,/^fi$/' "$zfs")
printf '%s\n' "$zfs_gate" | grep -q -- '-t 0' \
    || fail "zfs.sh chezmoi apply is not gated on a terminal"

# Help text must not re-teach the old split.
help=$(awk '/cat <<.EOF./,/^EOF$/' "$install")
printf '%s\n' "$help" | grep -q 'Household refresh' \
    || fail "help text does not describe household refresh on the default path"
printf '%s\n' "$help" | grep -qi 'same as --update' \
    || fail "help text does not say a provisioned box is the same as --update"

echo "install-entry tests passed"
