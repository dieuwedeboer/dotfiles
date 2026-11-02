#!/usr/bin/env bash
# Run the packaged omarchy-keyboard-toprow unchanged. Its boot-image rebuild is
# `sudo limine-mkinitcpio`, which the bin.alias stub in /usr/local/bin turns
# into `mkinitcpio -P`; checked by hand against r7555.
original="${MONARCHY_SRC:-/usr/share/omarchy}/bin/omarchy-keyboard-toprow"
if [ ! -x "$original" ]; then
    echo "monarchy: missing $original" >&2
    exit 1
fi
exec "$original" "$@"
