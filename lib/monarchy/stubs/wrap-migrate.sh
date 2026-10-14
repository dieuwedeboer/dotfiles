#!/usr/bin/env bash
# Overlay wrapper for omarchy-migrate. Every migration runs, after
# monarchy-migrate has checked the pending ones for a brick path. ADR 0005.
#
# The real omarchy-update calls this directly after the upgrade that ships a
# migration, before monarchy has classified it, so inside that run it does
# nothing; monarchy_after_omarchy_update calls it again afterwards.
if [ "${MONARCHY_IN_OMARCHY_UPDATE:-0}" = 1 ]; then
    exit 0
fi
cmd=${MONARCHY_MIGRATE:-/usr/local/bin/monarchy-migrate}
if [ ! -x "$cmd" ]; then
    echo "omarchy-migrate: $cmd is missing; run monarchy-update" >&2
    exit 1
fi
exec "$cmd" "$@"
