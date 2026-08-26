#!/usr/bin/env bash
# PR 3 greeter Exec. Logs a successful pick without launching Hyprland.
# Replaced by uwsm start … hyprland.desktop once that desktop file exists.
set -e
state="${XDG_STATE_HOME:-$HOME/.local/state}/monarchy"
mkdir -p "$state"
{
    echo "$(date -Iseconds) session probe"
    echo "user=$USER display=${XDG_SESSION_TYPE:-} desktop=${XDG_CURRENT_DESKTOP:-}"
} >>"$state/session-probe.log"
echo "Monarchy: Omarchy session is registered. Hyprland is not installed yet, or this probe is still the Exec=." >&2
exit 0
