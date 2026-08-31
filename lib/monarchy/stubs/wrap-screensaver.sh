#!/usr/bin/env bash
# Seed screensaver.txt if missing, then run the clone screensaver.
# ttfx exits immediately without that file and omarchy-screensaver respawns it
# in a tight loop, so a key never dismisses the fullscreen window.
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
# shellcheck source=../user.sh
source "$lib/user.sh"
export OMARCHY_PATH="${OMARCHY_PATH:-/usr/local/share/omarchy}"
monarchy_seed_branding
exec "$MONARCHY_SRC/bin/omarchy-screensaver" "$@"
