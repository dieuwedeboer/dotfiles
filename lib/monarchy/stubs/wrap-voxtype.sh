#!/usr/bin/env bash
# Overlay wrapper for omarchy-voxtype-config.
#
# The bar's Dictate indicator always calls this, whether or not voxtype is
# installed. Stock then opens `voxtype configure` in a floating terminal and
# restarts the shell. With no voxtype binary that is "command not found" plus
# a shell restart that drops the menu until Quickshell finishes coming back.
#
# Monarchy also skips the first-run voxtype invitation (apply marks first-run
# done without running install-voxtype.hook), so this host hits that path on
# a fresh session. Send the same click to the install flow instead; that
# already confirms, installs, and restarts the shell on success.
#
# 4.5 renamed the install flow to omarchy-install-dictation-voxtype and
# dropped omarchy-voxtype-install. The lists serve every channel (ADR 0009),
# so take whichever name the installed package ships.
set -euo pipefail

packaged="${MONARCHY_SRC:-/usr/share/omarchy}/bin/omarchy-voxtype-config"

if ! command -v voxtype >/dev/null 2>&1; then
    installer=omarchy-install-dictation-voxtype
    command -v "$installer" >/dev/null 2>&1 || installer=omarchy-voxtype-install
    exec omarchy-launch-floating-terminal-with-presentation "$installer"
fi

if [ ! -x "$packaged" ]; then
    echo "monarchy: missing $packaged" >&2
    exit 1
fi
exec "$packaged" "$@"
