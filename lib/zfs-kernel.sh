#!/usr/bin/env bash
# Which kernels can boot the root pool. ADR 0008.
#
# Any kernel may be installed, Omarchy's included, as long as one kernel stays
# whose ZFS module comes from a package rather than from DKMS. That is the
# fallback: when zfs-dkms cannot build for a new kernel, the fallback still
# boots, and ZFSBootMenu offers it. Today the fallback is linux-cachyos with
# linux-cachyos-zfs, which CachyOS builds in lockstep with the kernel.
#
# Installed to /usr/local/lib/monarchy/zfs-kernel by lib/zfs.sh and run by
# three pacman hooks in etc/pacman.d/hooks, as root, with nothing from this
# repo in scope. Monarchy's guards source it for zk_fallback_kvers. So it is
# self-contained: no monarchy_* calls.
#
#   check-install    PreTransaction, aborts. Every incoming kernel has a
#                    packaged ZFS module, or a zfs-dkms whose Linux-Maximum
#                    covers its series.
#   check-remove     PreTransaction, aborts. The removal leaves a fallback.
#   check-initramfs  PostTransaction, warns. Every kernel's initramfs holds
#                    zfs.ko. Catches a DKMS build that failed within a series
#                    OpenZFS claims to support.
#
# Targets arrive on stdin, one per line: paths relative to / for the Path
# hooks, package names for the Package hook.

ZK_MODULES=${ZK_MODULES:-/usr/lib/modules}
ZK_SRC=${ZK_SRC:-/usr/src}
ZK_BOOT=${ZK_BOOT:-/boot}

# Stubbed by the tests.
zk_owner() { pacman -Qqo "$1" 2>/dev/null; }
zk_cache_dirs() { pacman-conf CacheDir 2>/dev/null; }
zk_initramfs_list() { lsinitcpio "$1" 2>/dev/null; }

zk_say() { printf 'zfs-kernel: %s\n' "$*" >&2; }

# 7.2.5-3-omarchy -> 7.2
zk_series() {
    printf '%s\n' "${1%%-*}" | awk -F. '{ print $1 "." $2 }'
}

# True when series $1 is no newer than series $2.
zk_series_le() {
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$2" ]
}

zk_meta_max() {
    awk -F': *' '$1 == "Linux-Maximum" { print $2; exit }'
}

# The newest zfs-dkms source tree already on disk.
zk_installed_meta() {
    local meta
    meta=$(find "$ZK_SRC" -mindepth 2 -maxdepth 2 -path '*/zfs-*/META' 2>/dev/null | sort -V | tail -1)
    [ -n "$meta" ] && cat "$meta"
}

# META from the zfs-dkms package pacman has downloaded for this transaction.
# Pre-transaction hooks run after the download, so it is in the cache.
zk_cached_meta() {
    local ver=$1 dir pkg
    while read -r dir; do
        [ -n "$dir" ] || continue
        pkg=$(find "$dir" -maxdepth 1 -name "zfs-dkms-${ver}-*.pkg.tar.*" ! -name '*.sig' 2>/dev/null | sort -V | tail -1)
        if [ -n "$pkg" ]; then
            bsdtar -xOf "$pkg" "usr/src/zfs-$ver/META" 2>/dev/null && return 0
        fi
    done < <(zk_cache_dirs)
    return 1
}

# kver of an installed module tree whose zfs.ko is owned by a package, one
# per line. DKMS-built modules have no owner.
zk_packaged_kvers() {
    local ko kver
    for ko in "$ZK_MODULES"/*/extramodules/zfs.ko* "$ZK_MODULES"/*/kernel/*/zfs.ko* \
        "$ZK_MODULES"/*/updates/zfs.ko*; do
        [ -e "$ko" ] || continue
        zk_owner "$ko" >/dev/null || continue
        kver=${ko#"$ZK_MODULES"/}
        printf '%s\n' "${kver%%/*}"
    done | sort -u
}

# Fallbacks: a packaged ZFS module for an installed kernel, both owned by
# packages not in $1 (newline-separated names being removed). Prints
# "kver kernel-pkg zfs-pkg".
zk_fallback_kvers() {
    local removing=${1:-} kver ko kpkg zpkg
    while read -r kver; do
        [ -n "$kver" ] || continue
        [ -e "$ZK_MODULES/$kver/vmlinuz" ] || continue
        kpkg=$(zk_owner "$ZK_MODULES/$kver/vmlinuz") || continue
        zpkg=""
        for ko in "$ZK_MODULES/$kver"/extramodules/zfs.ko* "$ZK_MODULES/$kver"/kernel/*/zfs.ko* \
            "$ZK_MODULES/$kver"/updates/zfs.ko*; do
            [ -e "$ko" ] || continue
            zpkg=$(zk_owner "$ko") && break
        done
        [ -n "$zpkg" ] || continue
        if printf '%s\n' "$removing" | grep -qxF -e "$kpkg" -e "$zpkg"; then
            continue
        fi
        printf '%s %s %s\n' "$kver" "$kpkg" "$zpkg"
    done < <(zk_packaged_kvers)
}

zk_check_install() {
    local line rel kver ver new_kvers="" packaged_in="" meta_ver="" meta="" max fail=0
    while read -r line; do
        rel=${line#/}
        case "$rel" in
            usr/lib/modules/*/vmlinuz)
                kver=${rel#usr/lib/modules/}
                new_kvers+="${kver%%/*}"$'\n'
                ;;
            usr/lib/modules/*/zfs.ko*)
                kver=${rel#usr/lib/modules/}
                packaged_in+="${kver%%/*}"$'\n'
                ;;
            usr/src/zfs-*/META)
                ver=${rel#usr/src/zfs-}
                meta_ver=${ver%%/*}
                ;;
        esac
    done

    if [ -n "$meta_ver" ]; then
        meta=$(zk_cached_meta "$meta_ver") \
            || zk_say "could not read zfs-dkms $meta_ver from the package cache; judging by the installed one"
    fi
    [ -n "$meta" ] || meta=$(zk_installed_meta) || meta=""
    max=$(printf '%s\n' "$meta" | zk_meta_max)

    while read -r kver; do
        [ -n "$kver" ] || continue
        if printf '%s' "$packaged_in" | grep -qxF "$kver" \
            || zk_packaged_kvers | grep -qxF "$kver"; then
            continue
        fi
        if [ -z "$max" ]; then
            zk_say "kernel $kver has no packaged ZFS module and zfs-dkms is not installed: it could not import the root pool"
            fail=1
        elif ! zk_series_le "$(zk_series "$kver")" "$max"; then
            zk_say "kernel $kver is newer than zfs-dkms supports (Linux-Maximum $max): it could not import the root pool"
            zk_say "wait for a zfs-dkms that supports $(zk_series "$kver"), or hold the kernel with IgnorePkg"
            fail=1
        fi
    done < <(printf '%s' "$new_kvers" | sort -u)
    return "$fail"
}

zk_check_remove() {
    local removing fallback
    removing=$(cat)
    fallback=$(zk_fallback_kvers "$removing")
    if [ -z "$fallback" ]; then
        if [ -z "$(zk_fallback_kvers)" ]; then
            # Nothing to protect: the box has no fallback already. Monarchy's
            # guards say so; blocking every removal here would not help.
            return 0
        fi
        zk_say "this removes the last kernel whose ZFS module does not need DKMS"
        zk_say "keep linux-cachyos and linux-cachyos-zfs (ADR 0008)"
        return 1
    fi
    return 0
}

zk_check_initramfs() {
    local dir kver base img missing=0
    for dir in "$ZK_MODULES"/*/; do
        dir=${dir%/}
        kver=${dir##*/}
        [ -e "$dir/vmlinuz" ] && [ -r "$dir/pkgbase" ] || continue
        # A tree a removed kernel left behind (DKMS output keeps it) still
        # has a pkgbase, and would be reported against the live kernel's image.
        zk_owner "$dir/vmlinuz" >/dev/null || continue
        base=$(cat "$dir/pkgbase")
        img="$ZK_BOOT/initramfs-$base.img"
        [ -e "$img" ] || continue
        if ! zk_initramfs_list "$img" | grep -qE '(^|/)zfs\.ko'; then
            zk_say "WARNING: $img has no zfs module; $base ($kver) cannot import the root pool"
            missing=1
        fi
    done
    if [ "$missing" = 1 ]; then
        if [ -n "$(zk_fallback_kvers)" ]; then
            zk_say "choose another kernel in ZFSBootMenu until this is fixed"
        else
            zk_say "WARNING: there is no fallback kernel with a packaged ZFS module"
        fi
    fi
    return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -uo pipefail
    case "${1:-}" in
        check-install) zk_check_install ;;
        check-remove) zk_check_remove ;;
        check-initramfs) zk_check_initramfs ;;
        *)
            echo "usage: zfs-kernel check-install|check-remove|check-initramfs" >&2
            exit 2
            ;;
    esac
fi
