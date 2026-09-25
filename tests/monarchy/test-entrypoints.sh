#!/usr/bin/env bash
# The library defines what install.sh calls.
#
# A refactor deleted monarchy_ensure_log and left three callers behind. Under
# `set -e` a missing function is `command not found`, exit 127, and every
# apply and every update stopped on the first line that reached it. On a box
# that is already provisioned that is only an outage; on a fresh one it is a
# machine that cannot be brought up to a desktop at all, which is the bar in
# CODING_STANDARDS.md.
#
# The whole suite otherwise drives functions it names directly, so it
# exercised none of these: a name nothing calls in a temp prefix can vanish
# without a single test noticing.
#
# This is not a grep over install.sh. The list is the library's promised
# surface, maintained by hand; sourcing and asking bash is the behaviour.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"
# shellcheck source=../../lib/monarchy.sh
source "$REPO/lib/monarchy.sh"
# shellcheck source=../../lib/packages.sh
source "$REPO/lib/packages.sh"
# shellcheck source=../../lib/household.sh
source "$REPO/lib/household.sh"

missing=""
for fn in \
    monarchy_ensure_log monarchy_log monarchy_trace monarchy_warn monarchy_die \
    monarchy_changed monarchy_changed_many monarchy_left_alone monarchy_summary \
    monarchy_section monarchy_step monarchy_step_took \
    monarchy_load_lock monarchy_load_inventories monarchy_snapshot_first \
    monarchy_guards_check monarchy_check monarchy_apply monarchy_update \
    monarchy_real_omarchy_update monarchy_after_omarchy_update \
    monarchy_build_packages monarchy_splash_only \
    monarchy_install_if_changed monarchy_seeded monarchy_mark_seeded \
    monarchy_seed_ledger_bootstrap monarchy_shell_fingerprint \
    monarchy_overlay_shell monarchy_restart_shell \
    household_refresh household_chezmoi household_ksystemstats \
    packages_install packages_strip_omarchy_owned packages_install_omarchy_aur; do
    declare -F "$fn" >/dev/null || missing="$missing $fn"
done
[ -z "$missing" ] || fail "the library does not define:$missing"

# Every unit in the ordered list has both its verbs, which is what the apply
# loop dispatches on by name.
for u in "${MONARCHY_UNITS[@]}"; do
    declare -F "monarchy_${u}_check" >/dev/null || fail "no monarchy_${u}_check"
    declare -F "monarchy_${u}_apply" >/dev/null || fail "no monarchy_${u}_apply"
done

echo "entrypoint tests passed"
