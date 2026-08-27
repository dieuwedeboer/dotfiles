#!/usr/bin/env bash
# Apply must install Quickshell lock PAM. No sudo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MISC="$SCRIPT_DIR/../../../misc/monarchy"

fail() {
    echo "test-lock: $*" >&2
    exit 1
}

# The bug: monarchy_apply never ran install/config/lockscreen-pam.sh
# (one line: omarchy-apply-lock). Service.qml then logs lock-denied: missing-pam.
apply_body=$(awk '/^monarchy_apply\(\)/,/^monarchy_update\(\)/' "$SCRIPT_DIR/update.sh")
echo "$apply_body" | grep -q 'monarchy_apply_lock' \
    || fail "monarchy_apply does not call monarchy_apply_lock"

grep -qx 'omarchy-apply-lock' "$MISC/bin.allow" \
    || fail "omarchy-apply-lock missing from bin.allow"
if grep -qx 'omarchy-apply-lock' "$MISC/bin.deny"; then
    fail "omarchy-apply-lock is denied"
fi

clone="${MONARCHY_SRC:-/usr/local/src/monarchy/omarchy}"
if [ -f "$clone/bin/omarchy-apply-lock" ]; then
    grep -q '/etc/pam.d/omarchy-lock-password' "$clone/bin/omarchy-apply-lock" \
        || fail "omarchy-apply-lock does not write omarchy-lock-password"
fi
if [ -f "$clone/shell/plugins/lock/Service.qml" ]; then
    grep -q 'config: "omarchy-lock-password"' "$clone/shell/plugins/lock/Service.qml" \
        || fail "lock plugin PAM config name drifted"
    grep -q 'path: "/etc/pam.d/omarchy-lock-password"' "$clone/shell/plugins/lock/Service.qml" \
        || fail "lock plugin PAM path drifted"
fi

echo "lock tests passed"
