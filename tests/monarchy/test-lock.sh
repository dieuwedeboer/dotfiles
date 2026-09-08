#!/usr/bin/env bash
# Apply must install Quickshell lock PAM. No sudo.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"



# The bug: monarchy_apply never ran install/config/lockscreen-pam.sh
# (one line: omarchy-apply-lock). Service.qml then logs lock-denied: missing-pam.
monarchy_reaches apply | grep -qx 'monarchy_apply_lock' \
    || fail "apply does not reach monarchy_apply_lock"

# There is no allow list any more: not overriding a name is what allows it.
# It must be neither denied nor wrapped, so it resolves from /usr/bin.
if grep -qx 'omarchy-apply-lock' "$MISC/bin.deny"; then
    fail "omarchy-apply-lock is denied"
fi
if grep -qx 'omarchy-apply-lock' "$MISC/bin.wrap"; then
    fail "omarchy-apply-lock is wrapped; it should come straight from the package"
fi

clone=$(require_omarchy_tree)
[ -f "$clone/bin/omarchy-apply-lock" ] || fail "omarchy package has no bin/omarchy-apply-lock"
grep -q '/etc/pam.d/omarchy-lock-password' "$clone/bin/omarchy-apply-lock" \
    || fail "omarchy-apply-lock does not write omarchy-lock-password"

service="$clone/shell/plugins/lock/Service.qml"
[ -f "$service" ] || fail "omarchy package has no lock plugin Service.qml"
grep -q 'config: "omarchy-lock-password"' "$service" \
    || fail "lock plugin PAM config name drifted"
grep -q 'path: "/etc/pam.d/omarchy-lock-password"' "$service" \
    || fail "lock plugin PAM path drifted"

echo "lock tests passed"
