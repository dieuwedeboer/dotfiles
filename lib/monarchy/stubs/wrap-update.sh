#!/usr/bin/env bash
# Overlay wrapper for omarchy-update. The public command is monarchy-update,
# which brackets the real omarchy-update rather than replacing it: guards and
# a ZFS snapshot and the household refresh before, the packaged
# omarchy-update in full, then classify and apply over the top. See
# docs/adr/0003-omarchy-owns-the-system-update.md.
#
# omarchy-update-system-pkgs is no longer wrapped onto this, because the real
# omarchy-update calls it and that would recurse.
# Reached from inside the bracketed update means the update root holds this
# wrap instead of the real omarchy-update. Each pass took a ZFS snapshot and
# re-entered; 16 November 2026 went 71 deep.
if [ "${MONARCHY_IN_OMARCHY_UPDATE:-0}" = 1 ]; then
    echo "omarchy-update: reached the monarchy wrap from inside monarchy-update; refusing to recurse" >&2
    exit 1
fi
cmd=${MONARCHY_UPDATE:-/usr/local/bin/monarchy-update}
if [ ! -x "$cmd" ]; then
    echo "monarchy-update: $cmd is missing" >&2
    exit 1
fi
exec "$cmd" "$@"
