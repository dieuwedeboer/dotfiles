#!/usr/bin/env bash
# Overlay wrapper for omarchy-refresh-sddm. Copies the clone theme, then the
# multi-user Main.qml overlay. Never leaves stock last-user/uwsm-only QML.
set -e
setup=${MONARCHY_SETUP:-/usr/local/bin/monarchy-update}
if [ ! -x "$setup" ]; then
    echo "monarchy: $setup is missing" >&2
    exit 1
fi
real=$(readlink -f "$setup")
lib="$(cd "$(dirname "$real")/lib/monarchy" && pwd)"
# shellcheck source=../common.sh
source "$lib/common.sh"
# shellcheck source=../sddm.sh
source "$lib/sddm.sh"
export OMARCHY_PATH="${OMARCHY_PATH:-/usr/local/share/omarchy}"
monarchy_refresh_sddm
