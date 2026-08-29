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
        [ -f "$omarchy_path/version" ] || exit 1
        version=$(tr -d '[:space:]' <"$omarchy_path/version")
        [ -n "$version" ] || exit 1
        printf '%s-git\n' "$version"
        ;;
    omarchy-version-branch)
        [ -f "$pin" ] || exit 1
        branch=$(awk -F= '$1=="branch"{print substr($0,index($0,"=")+1)}' "$pin")
        commit=$(awk -F= '$1=="commit"{print substr($0,index($0,"=")+1)}' "$pin")
        [ -n "$branch" ] || exit 1
        [ -n "$commit" ] || exit 1
        short=$commit
        if [ ${#commit} -gt 7 ]; then
            short=${commit:0:7}
        fi
        printf '%s @ %s\n' "$branch" "$short"
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
