#!/usr/bin/env bash
# Logind drop-ins exist and ignore the power key. No sudo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MISC="$SCRIPT_DIR/../../../misc/monarchy"

fail() {
    echo "test-logind: $*" >&2
    exit 1
}

grep -q '^HandlePowerKey=ignore' "$MISC/logind/10-ignore-power-button.conf" \
    || fail "misc logind drop-in does not ignore the power key"
grep -q '^InhibitDelayMaxSec=15' "$MISC/logind/20-inhibit-delay.conf" \
    || fail "misc logind drop-in missing InhibitDelayMaxSec=15"
grep -q 'monarchy_apply_logind' "$SCRIPT_DIR/update.sh" \
    || fail "apply does not call monarchy_apply_logind"
grep -q 'monarchy_check_logind' "$SCRIPT_DIR/update.sh" \
    || fail "check does not call monarchy_check_logind"
grep -q 'systemctl reload systemd-logind' "$SCRIPT_DIR/sessions.sh" \
    || fail "apply restarts logind instead of reloading, or never reloads"

echo "logind tests passed"
