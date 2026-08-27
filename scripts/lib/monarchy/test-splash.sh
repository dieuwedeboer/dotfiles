#!/usr/bin/env bash
# Pure HOOKS rewrite tests. No sudo, no mkinitcpio.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
# shellcheck source=splash.sh
source "$SCRIPT_DIR/splash.sh"

fail() {
    echo "test-splash: $*" >&2
    exit 1
}

got=$(monarchy_hooks_insert_plymouth base udev autodetect zfs filesystems) \
    || fail "insert failed"
[ "$got" = "base udev autodetect zfs plymouth filesystems" ] \
    || fail "insert got '$got'"

got=$(monarchy_hooks_insert_plymouth base zfs plymouth filesystems) \
    || fail "idempotent failed"
[ "$got" = "base zfs plymouth filesystems" ] \
    || fail "idempotent got '$got'"

if monarchy_hooks_insert_plymouth base plymouth zfs filesystems >/dev/null 2>&1; then
    fail "plymouth-before-zfs should fail"
fi

if monarchy_hooks_insert_plymouth base udev filesystems >/dev/null 2>&1; then
    fail "missing zfs should fail"
fi

echo "splash hook tests passed"
