#!/usr/bin/env bash
# Home-level agent config. ~/.agents is a real directory (chezmoi + skills
# CLI), not a symlink into this repo. Canonical instructions are
# ~/.agents/AGENTS.md; Claude and OpenCode symlink to it via chezmoi.

agents_materialize_home() {
    local src tmp
    if [ -L "$HOME/.agents" ]; then
        monarchy_changed "replaced the ~/.agents repo symlink with a directory"
        src=$(readlink -f "$HOME/.agents")
        tmp=$(mktemp -d)
        if [ -d "$src/skills" ]; then
            cp -a "$src/skills" "$tmp/skills"
        fi
        rm "$HOME/.agents"
        mkdir -p "$HOME/.agents"
        if [ -d "$tmp/skills" ]; then
            mv "$tmp/skills" "$HOME/.agents/skills"
        fi
        rm -rf "$tmp"
    fi
    mkdir -p "$HOME/.agents/skills"
}

# Restore missing lock entries. skills experimental_install reads a project
# skills-lock.json, not ~/.agents/.skill-lock.json, so replay `skills add -g`.
agents_restore_skills() {
    local lock=$HOME/.agents/.skill-lock.json
    if [ ! -f "$lock" ]; then
        monarchy_log "no $lock; skill restore skipped"
        return 0
    fi
    if ! command -v npx >/dev/null 2>&1; then
        monarchy_warn "npx not found; skill restore skipped (install node, re-run)"
        return 0
    fi

    monarchy_log "restoring global skills from $lock"
    # The plan is captured before the loop rather than piped into it. A pipe
    # runs the loop in a subshell, where monarchy_changed appends to a copy of
    # the ledger that dies with it, and the summary loses every restore.
    local plan
    plan=$(python3 - "$lock" "$HOME/.agents/skills" <<'PY'
import json, sys
from pathlib import Path
lock = json.loads(Path(sys.argv[1]).read_text())
skills_root = Path(sys.argv[2])
by_source = {}
for name, entry in lock.get("skills", {}).items():
    if (skills_root / name / "SKILL.md").is_file():
        continue
    source = entry.get("source") or entry.get("sourceUrl")
    if not source:
        continue
    by_source.setdefault(source, []).append(name)
for source, names in sorted(by_source.items()):
    print(source + "\t" + " ".join(sorted(names)))
PY
)
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        source=${line%%$'\t'*}
        names=${line#*$'\t'}
        # shellcheck disable=SC2086
        npx --yes skills add "$source" -g -y --skill $names
        monarchy_changed "restored skills from $source: $names"
    done <<<"$plan"
}
