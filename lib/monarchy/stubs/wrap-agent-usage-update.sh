#!/usr/bin/env bash
# Overlay wrapper for omarchy-agent-usage-update. The shell's agents panel runs
# it every fifteen minutes and it starts every collector at once. The claude
# collector parses all of ~/.claude/projects in Python: 3.3 GiB peak for a
# 1.1 GiB transcript tree, and it grows with the transcripts. On a box already
# short of memory that burst stalled the whole session for close to a minute.
#
# Run it in its own scope under MemoryHigh, a sixteenth of RAM with a 512 MiB
# floor. Over that the kernel reclaims from the collectors alone, so they slow
# down instead of the desktop. MemoryHigh throttles, it never kills, so the
# panel still gets its records. Without a user manager it runs as stock does.
packaged="${MONARCHY_SRC:-/usr/share/omarchy}/bin/omarchy-agent-usage-update"

mem_bytes=$(awk '/^MemTotal:/ {print $2 * 1024}' /proc/meminfo 2>/dev/null)
high=$(( ${mem_bytes:-0} / 16 ))
[ "$high" -lt 536870912 ] && high=536870912

if systemctl --user show-environment >/dev/null 2>&1; then
    exec systemd-run --user --scope --quiet --collect \
        -p MemoryHigh="$high" -p CPUWeight=idle -p IOWeight=10 \
        "$packaged" "$@"
fi
exec "$packaged" "$@"
