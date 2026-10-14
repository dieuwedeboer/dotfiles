#!/usr/bin/env bash
# The kernel hooks: a kernel the root pool cannot be imported by is refused,
# and the last kernel with a packaged ZFS module is kept. ADR 0008.
# Fixture module trees; pacman, pacman-conf and lsinitcpio are stubbed.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"
# shellcheck source=../../lib/zfs-kernel.sh
source "$REPO/lib/zfs-kernel.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ZK_MODULES="$tmp/modules"
ZK_SRC="$tmp/src"
ZK_BOOT="$tmp/boot"
CACHE="$tmp/cache"
OWNERS="$tmp/owners"
mkdir -p "$ZK_MODULES" "$ZK_SRC" "$ZK_BOOT" "$CACHE"
: >"$OWNERS"

# "path package" per line; a path not listed has no owner, as DKMS output.
zk_owner() { awk -v p="$1" '$1 == p { print $2; found = 1 } END { exit !found }' "$OWNERS"; }
zk_cache_dirs() { printf '%s\n' "$CACHE"; }
# The fixture "initramfs" is a text file listing its contents.
zk_initramfs_list() { cat "$1"; }

# kernel <kver> <pkg> [zfs-pkg|dkms]
kernel() {
    local kver=$1 pkg=$2 zfs=${3:-}
    mkdir -p "$ZK_MODULES/$kver/extramodules" "$ZK_MODULES/$kver/updates/dkms"
    : >"$ZK_MODULES/$kver/vmlinuz"
    printf '%s\n' "$pkg" >"$ZK_MODULES/$kver/pkgbase"
    printf '%s %s\n' "$ZK_MODULES/$kver/vmlinuz" "$pkg" >>"$OWNERS"
    case "$zfs" in
        "") ;;
        dkms) : >"$ZK_MODULES/$kver/updates/dkms/zfs.ko.zst" ;;
        *)
            : >"$ZK_MODULES/$kver/extramodules/zfs.ko.zst"
            printf '%s %s\n' "$ZK_MODULES/$kver/extramodules/zfs.ko.zst" "$zfs" >>"$OWNERS"
            ;;
    esac
}

dkms_installed() {
    mkdir -p "$ZK_SRC/zfs-$1"
    printf 'Name: zfs\nLinux-Maximum: %s\nLinux-Minimum: 4.18\n' "$2" >"$ZK_SRC/zfs-$1/META"
}

dkms_cached() {
    local stage="$tmp/stage-$1"
    mkdir -p "$stage/usr/src/zfs-$1"
    printf 'Name: zfs\nLinux-Maximum: %s\n' "$2" >"$stage/usr/src/zfs-$1/META"
    bsdtar -c --zstd -f "$CACHE/zfs-dkms-$1-1-x86_64.pkg.tar.zst" -C "$stage" "usr/src/zfs-$1/META"
}

kernel 7.2.6-1-cachyos linux-cachyos linux-cachyos-zfs
kernel 7.2.5-3-omarchy linux-omarchy dkms
dkms_installed 2.4.4 7.2

# ---- check-install ------------------------------------------------------

printf 'usr/lib/modules/7.2.8-1-omarchy/vmlinuz\n' | zk_check_install 2>/dev/null \
    || fail "refused a kernel inside zfs-dkms's Linux-Maximum"

if printf 'usr/lib/modules/7.3.1-1-omarchy/vmlinuz\n' | zk_check_install 2>/dev/null; then
    fail "allowed a 7.3 kernel against zfs-dkms Linux-Maximum 7.2"
fi

printf 'usr/lib/modules/7.3.1-1-cachyos/vmlinuz\nusr/lib/modules/7.3.1-1-cachyos/extramodules/zfs.ko.zst\n' \
    | zk_check_install 2>/dev/null \
    || fail "refused a new series that brings its own packaged ZFS module"

dkms_cached 2.5.0 7.3
printf 'usr/lib/modules/7.3.1-1-omarchy/vmlinuz\nusr/src/zfs-2.5.0/META\n' | zk_check_install 2>/dev/null \
    || fail "refused 7.3 alongside an incoming zfs-dkms that supports it"

rm -rf "$ZK_SRC/zfs-2.4.4"
if printf 'usr/lib/modules/7.2.8-1-omarchy/vmlinuz\n' | zk_check_install 2>/dev/null; then
    fail "allowed a kernel with no packaged ZFS module and no zfs-dkms"
fi
dkms_installed 2.4.4 7.2

# ---- check-remove -------------------------------------------------------

printf 'linux-omarchy\nlinux-omarchy-headers\n' | zk_check_remove 2>/dev/null \
    || fail "refused removing a DKMS kernel while the fallback stays"

if printf 'linux-cachyos-zfs\n' | zk_check_remove 2>/dev/null; then
    fail "allowed removing the only packaged ZFS module"
fi
if printf 'linux-cachyos\n' | zk_check_remove 2>/dev/null; then
    fail "allowed removing the only kernel with a packaged ZFS module"
fi

kernel 6.18.52-1-cachyos-lts linux-cachyos-lts linux-cachyos-lts-zfs
printf 'linux-cachyos\nlinux-cachyos-zfs\n' | zk_check_remove 2>/dev/null \
    || fail "refused removing one fallback while another stays"

got=$(zk_fallback_kvers | awk '{ print $2 }' | paste -sd' ')
[ "$got" = "linux-cachyos-lts linux-cachyos" ] || fail "fallbacks got '$got'"

# ---- check-initramfs ----------------------------------------------------

printf 'usr/lib/modules/7.2.6-1-cachyos/extramodules/zfs.ko.zst\n' >"$ZK_BOOT/initramfs-linux-cachyos.img"
printf 'usr/lib/modules/6.18.52-1-cachyos-lts/extramodules/zfs.ko.zst\n' >"$ZK_BOOT/initramfs-linux-cachyos-lts.img"
printf 'usr/lib/modules/7.2.5-3-omarchy/kernel/fs/ext4/ext4.ko.zst\n' >"$ZK_BOOT/initramfs-linux-omarchy.img"
got=$(zk_check_initramfs 2>&1 | grep WARNING || true)
[ "$got" = "zfs-kernel: WARNING: $ZK_BOOT/initramfs-linux-omarchy.img has no zfs module; linux-omarchy (7.2.5-3-omarchy) cannot import the root pool" ] \
    || fail "initramfs warnings got '$got'"

echo "zfs kernel tests passed"
