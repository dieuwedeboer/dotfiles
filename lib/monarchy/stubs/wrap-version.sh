#!/usr/bin/env bash
# Overlay wrapper for omarchy-version, omarchy-version-branch, and
# omarchy-version-channel. Fastfetch About uses these three commands.
set -euo pipefail

omarchy_path=${OMARCHY_PATH:-/usr/local/share/omarchy}
omarchy_path=${omarchy_path%/}
pin=${MONARCHY_PIN:-/etc/omarchy.lock}
pacman_conf=${PACMAN_CONF:-/etc/pacman.conf}
name=$(basename -- "$0")

case "$name" in
    omarchy-version)
        # No longer a git checkout, so no -git suffix: this is the version
        # file out of the omarchy package.
        [ -f "$omarchy_path/version" ] || exit 1
        version=$(tr -d '[:space:]' <"$omarchy_path/version")
        [ -n "$version" ] || exit 1
        printf '%s\n' "$version"
        ;;
    omarchy-version-branch)
        # Was "branch @ commit" of the pinned fork. Monarchy tracks a package
        # now, so the honest answer is the package and its installed version.
        [ -f "$pin" ] || exit 1
        package=$(awk -F= '$1=="package"{print substr($0,index($0,"=")+1)}' "$pin")
        [ -n "$package" ] || exit 1
        installed=$(pacman -Q "$package" 2>/dev/null | awk '{print $2}')
        [ -n "$installed" ] || installed=not-installed
        printf '%s %s\n' "$package" "$installed"
        ;;
    omarchy-version-channel)
        if grep -q 'https://pkgs.omarchy.org/stable/' "$pacman_conf" 2>/dev/null; then
            echo stable
        elif grep -q 'https://pkgs.omarchy.org/edge/' "$pacman_conf" 2>/dev/null; then
            echo edge
        else
            echo unknown
        fi
        ;;
    *)
        echo "monarchy: wrap-version does not handle $name" >&2
        exit 2
        ;;
esac
