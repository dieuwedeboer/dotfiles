#!/usr/bin/env bash
# Overlay wrapper for omarchy-version, omarchy-version-branch, and
# omarchy-version-channel. Fastfetch About uses these three commands.
set -euo pipefail

omarchy_path=${OMARCHY_PATH:-/usr/local/share/omarchy}
omarchy_path=${omarchy_path%/}
pacman_conf=${PACMAN_CONF:-/etc/pacman.conf}
name=$(basename -- "$0")

case "$name" in
    omarchy-version)
        # Stock reads the pacman version, but only when OMARCHY_PATH is
        # /usr/share/omarchy; against a working prefix it decides it is a
        # dev-link and prints "dev". Monarchy always runs from a prefix, so do
        # the package lookup here. $OMARCHY_PATH/version is not the answer: the
        # 4.0.2 package still ships a version file reading 4.0.0.alpha.
        version=$(pacman -Q omarchy 2>/dev/null | awk '{print $2}')
        if [ -z "$version" ]; then
            [ -f "$omarchy_path/version" ] || exit 1
            version=$(tr -d '[:space:]' <"$omarchy_path/version")
        fi
        [ -n "$version" ] || exit 1
        printf '%s\n' "$version"
        ;;
    omarchy-version-branch)
        # Was "branch @ commit" of the pinned fork. There is no branch now:
        # Monarchy tracks a package, and the version is already
        # omarchy-version. Stock exits 1 when there is no dev-link git branch
        # and Fastfetch simply omits the line; do the same rather than invent
        # a value.
        exit 1
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
