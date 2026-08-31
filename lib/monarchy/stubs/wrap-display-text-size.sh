#!/usr/bin/env bash
# Run clone omarchy-display-text-size, then the user display-text-size hook.
# Query and help skip the hook so they report what is already on disk.
set -euo pipefail

original="${MONARCHY_SRC:-/usr/local/src/monarchy/omarchy}/bin/omarchy-display-text-size"
omarchy_path="${OMARCHY_PATH:-/usr/local/share/omarchy}"
hook="${omarchy_path%/}/bin/omarchy-hook"

if [ ! -x "$original" ]; then
    echo "monarchy: missing $original" >&2
    exit 1
fi

case "${1:-}" in
    ""|-h|--help)
        exec "$original" "$@"
        ;;
esac

"$original" "$@"
status=$?
if [ "$status" -eq 0 ] && [ -x "$hook" ]; then
    "$hook" display-text-size "$@" || true
fi
exit "$status"
