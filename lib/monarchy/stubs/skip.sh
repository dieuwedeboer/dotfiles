#!/usr/bin/env bash
# Monarchy skip stub. Overlay and /usr/local/bin copies share this body.
#
# Unlike deny.sh this exits 0 and says nothing on stderr. It stands in for a
# name the real omarchy-update calls in its ordinary flow, which on this box
# has nothing to do -- see monarchy/bin.skip for why, per name. Refusing here
# would abort the update; complaining here would do it on every run.
name=$(basename -- "$0")
if command -v logger >/dev/null 2>&1; then
    logger -t monarchy "skipped $name $*"
fi
log=${MONARCHY_LOG:-/var/log/monarchy-setup.log}
if [ -w "$log" ] || { [ ! -e "$log" ] && [ -w "$(dirname "$log")" ]; }; then
    printf '%s skipped %s %s\n' "$(date -Iseconds)" "$name" "$*" >>"$log" 2>/dev/null || true
fi
exit 0
