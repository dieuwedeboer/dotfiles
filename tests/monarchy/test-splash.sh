#!/usr/bin/env bash
# Where plymouth sits in the initramfs HOOKS line, and when that is allowed.
#
# This is a boot-or-not question, not a cosmetic one. Plymouth before zfs on a
# box whose pool key is not in the initramfs means nothing is left to prompt
# for the passphrase, and the machine stops at a splash screen that cannot be
# typed into. Everything else about the splash -- which theme, which logo --
# is cosmetic and uncovered. See CODING_STANDARDS.md.
#
# Pure string arithmetic plus one fixture mkinitcpio.conf. No sudo, no
# mkinitcpio.
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

echo "splash hook tests passed"
