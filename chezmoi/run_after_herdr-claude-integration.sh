#!/bin/bash
# herdr ships its Claude Code hook itself: `herdr integration install claude`
# writes ~/.claude/hooks/herdr-agent-state.sh and merges the SessionStart hook
# into ~/.claude/settings.json. Neither is tracked here; this only asks herdr
# to put them back when they are missing or out of date.
command -v herdr >/dev/null || exit 0
herdr integration status 2>/dev/null | grep -q '^claude: current' && exit 0
herdr integration install claude
