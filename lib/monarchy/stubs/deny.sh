#!/usr/bin/env bash
# Monarchy deny stub. Overlay and /usr/local/bin copies share this body.
name=$(basename -- "$0")
msg="monarchy: blocked $name"
echo "$msg" >&2
if command -v logger >/dev/null 2>&1; then
    logger -t monarchy "blocked $name $*"
fi
# The journal above is the record that always works, whichever account ran
# this. The file is a convenience copy for the administrator, and only the
# administrator can write it: /var/log is root-owned and these stubs run as
# whoever typed the name. A writable parent only helps when the file is not
# there yet -- for an existing unwritable file the append cannot open it.
log=${MONARCHY_LOG:-/var/log/monarchy-setup.log}
if [ -w "$log" ] || { [ ! -e "$log" ] && [ -w "$(dirname "$log")" ]; }; then
    printf '%s blocked %s %s\n' "$(date -Iseconds)" "$name" "$*" >>"$log" 2>/dev/null || true
fi
exit 2
