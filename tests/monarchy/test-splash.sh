#!/usr/bin/env bash
# Pure HOOKS rewrite tests. No sudo, no mkinitcpio.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"
# shellcheck source=../../lib/monarchy/common.sh
source "$LIB/common.sh"
# shellcheck source=../../lib/monarchy/splash.sh
source "$LIB/splash.sh"


got=$(monarchy_hooks_insert_plymouth after base udev autodetect zfs filesystems) \
    || fail "insert after failed"
[ "$got" = "base udev autodetect zfs plymouth filesystems" ] \
    || fail "insert after got '$got'"

got=$(monarchy_hooks_insert_plymouth after base zfs plymouth filesystems) \
    || fail "idempotent after failed"
[ "$got" = "base zfs plymouth filesystems" ] \
    || fail "idempotent after got '$got'"

got=$(monarchy_hooks_insert_plymouth before base udev zfs filesystems) \
    || fail "insert before failed"
[ "$got" = "base udev plymouth zfs filesystems" ] \
    || fail "insert before got '$got'"

got=$(monarchy_hooks_insert_plymouth before base zfs plymouth filesystems) \
    || fail "reorder to before failed"
[ "$got" = "base plymouth zfs filesystems" ] \
    || fail "reorder to before got '$got'"

got=$(monarchy_hooks_insert_plymouth after base plymouth zfs filesystems) \
    || fail "reorder to after failed"
[ "$got" = "base zfs plymouth filesystems" ] \
    || fail "reorder to after got '$got'"

if monarchy_hooks_insert_plymouth after base udev filesystems >/dev/null 2>&1; then
    fail "missing zfs should fail"
fi

if monarchy_hooks_insert_plymouth sideways base zfs filesystems >/dev/null 2>&1; then
    fail "bad side should fail"
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
key=$tmp/zroot.key
conf=$tmp/mkinitcpio.conf
printf 'secret' >"$key"
printf 'FILES=()\nHOOKS=(base zfs filesystems)\n' >"$conf"
if MONARCHY_ZFS_KEYFILE=$key monarchy_zfs_keyfile_in_initramfs "$conf"; then
    fail "empty FILES should not count as keyfile"
fi
printf 'FILES=(/not/the/key)\nHOOKS=(base zfs filesystems)\n' >"$conf"
if MONARCHY_ZFS_KEYFILE=$key monarchy_zfs_keyfile_in_initramfs "$conf"; then
    fail "unrelated FILES entry should not count as keyfile"
fi
printf 'FILES=(%s)\nHOOKS=(base zfs filesystems)\n' "$key" >"$conf"
MONARCHY_ZFS_KEYFILE=$key monarchy_zfs_keyfile_in_initramfs "$conf" \
    || fail "keyfile in FILES should count"

retain="$MISC/plymouth-quit-retain.conf"
[ -f "$retain" ] || fail "missing $retain"
grep -q 'quit --retain-splash' "$retain" || fail "retain drop-in missing --retain-splash"
grep -q '^ExecStart=$' "$retain" || fail "retain drop-in must clear ExecStart first"

grep -q 'monarchy_splash_retain' "$LIB/splash.sh" \
    || fail "splash.sh does not install retain-splash"
grep -q 'monarchy_plymouth_side' "$LIB/splash.sh" \
    || fail "splash.sh does not choose plymouth side from keyfile"

echo "splash hook tests passed"
