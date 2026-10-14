#!/usr/bin/env bash
# omarchy-base rows install unless one sits on a brick path nobody has read.
# A display manager or kernel slipping in unread can leave a box without a
# greeter or without a bootable root pool. ADR 0010.
#
# No sudo, no network. A temp package tree.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"
# shellcheck source=../../lib/monarchy.sh
source "$REPO/lib/monarchy.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
MONARCHY_SRC="$tmp/src"
mkdir -p "$MONARCHY_SRC/install"
export MONARCHY_LOG="$tmp/log"
# Read by monarchy_check_packages_deny.
# shellcheck disable=SC2034
MONARCHY_PKG_DENY=(plasma-login-manager tldr snapper limine limine-mkinitcpio-hook
    limine-snapper-sync omarchy-dev omarchy-settings omarchy-settings-dev ufw-docker)
# shellcheck disable=SC2034
MONARCHY_PKG_ALLOW=(sddm)

base() { printf '%s\n' "$@" >"$MONARCHY_SRC/install/omarchy-base.packages"; }

# Rows nobody has listed anywhere are installed, not held.
base btop disktree-bin linux-firmware sddm limine ufw-docker
( monarchy_check_packages_deny ) >/dev/null 2>&1 \
    || fail "held an ordinary new row, or a row already in packages.deny or packages.allow"

for row in linux-omarchy greetd grub zfs-utils omarchy tlp snap-pac; do
    base btop "$row"
    if ( monarchy_check_packages_deny ) >/dev/null 2>&1; then
        fail "installed $row unread; it sits on a brick path"
    fi
done

echo "base package tests passed"
