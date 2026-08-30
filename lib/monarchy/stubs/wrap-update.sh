#!/usr/bin/env bash
# Overlay wrapper for omarchy-update and omarchy-update-system-pkgs.
setup=${MONARCHY_SETUP:-/usr/local/bin/setup-monarchy}
if [ ! -x "$setup" ]; then
    echo "monarchy: $setup is missing" >&2
    exit 1
fi
exec "$setup" --update "$@"
