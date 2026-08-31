#!/usr/bin/env bash
# Overlay wrapper for omarchy-update and omarchy-update-system-pkgs.
# The public command is monarchy-update.
cmd=${MONARCHY_UPDATE:-/usr/local/bin/monarchy-update}
if [ ! -x "$cmd" ]; then
    echo "monarchy-update: $cmd is missing" >&2
    exit 1
fi
exec "$cmd" "$@"
