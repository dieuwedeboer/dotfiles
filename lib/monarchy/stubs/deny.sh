#!/usr/bin/env bash
# Monarchy deny stub. Overlay and /usr/local/bin copies share this body.
name=$(basename -- "$0")
msg="monarchy: blocked $name"
echo "$msg" >&2
if command -v logger >/dev/null 2>&1; then
    logger -t monarchy "blocked $name $*"
fi
log=${MONARCHY_LOG:-/var/log/monarchy-setup.log}
if [ -w "$log" ] || [ -w "$(dirname "$log")" ] 2>/dev/null; then
    printf '%s blocked %s %s\n' "$(date -Iseconds)" "$name" "$*" >>"$log" 2>/dev/null || true
fi
exit 2
