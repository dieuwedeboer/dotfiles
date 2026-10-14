#!/usr/bin/env bash
# Overlay wrapper for omarchy-sudo-passwordless. Granting passwordless sudo
# stays denied; this only answers the shell bar's PasswordlessSudo indicator,
# which asks `--active` every five seconds. Through deny.sh each of those polls
# was a journal line. Exit 3 is the packaged script's own "inactive".
if [ "${1:-}" = --active ] && [ $# -eq 1 ]; then
    exit 3
fi

name=$(basename -- "$0")
echo "monarchy: blocked $name" >&2
if command -v logger >/dev/null 2>&1; then
    logger -t monarchy "blocked $name $*"
fi
log=${MONARCHY_LOG:-/var/log/monarchy-setup.log}
if [ -w "$log" ] || { [ ! -e "$log" ] && [ -w "$(dirname "$log")" ]; }; then
    printf '%s blocked %s %s\n' "$(date -Iseconds)" "$name" "$*" >>"$log" 2>/dev/null || true
fi
exit 2
