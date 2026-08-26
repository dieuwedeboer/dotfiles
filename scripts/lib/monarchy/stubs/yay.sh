#!/usr/bin/env bash
# Overlay-only. Do not install into /usr/local/bin.
echo "monarchy: yay is denied; using paru" >&2
if ! command -v paru >/dev/null 2>&1; then
    echo "monarchy: paru is not installed" >&2
    exit 1
fi
exec paru "$@"
