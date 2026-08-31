#!/usr/bin/env bash
# Overlay wrapper for plymouth write-path binaries. Skips Limine.
# plymouth-set restyles the Monarchy Main.qml overlay (Style > Unlock).
set -e
name=$(basename -- "$0")
setup=${MONARCHY_SETUP:-/usr/local/bin/monarchy-update}
if [ ! -x "$setup" ]; then
    echo "monarchy: $setup is missing" >&2
    exit 1
fi
real=$(readlink -f "$setup")
lib="$(cd "$(dirname "$real")/lib/monarchy" && pwd)"
# shellcheck source=../common.sh
source "$lib/common.sh"
# shellcheck source=../splash.sh
source "$lib/splash.sh"
export OMARCHY_PATH="${OMARCHY_PATH:-/usr/local/share/omarchy}"
case "$name" in
    omarchy-plymouth-set) monarchy_plymouth_set "$@" ;;
    omarchy-plymouth-reset) monarchy_plymouth_reset "$@" ;;
    omarchy-refresh-plymouth) monarchy_refresh_plymouth "$@" ;;
    *)
        echo "monarchy: wrap-plymouth does not handle $name" >&2
        exit 2
        ;;
esac
