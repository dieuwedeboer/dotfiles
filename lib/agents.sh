#!/usr/bin/env bash
# Home-level agent config. ~/.agents is a real directory (chezmoi + skills
# CLI), not a symlink into this repo. Canonical instructions are
# ~/.agents/AGENTS.md; Claude and OpenCode symlink to it via chezmoi.

agents_materialize_home() {
    local src tmp
    if [ -L "$HOME/.agents" ]; then
        echo "Replacing ~/.agents repo symlink with a directory"
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
        echo "  no $lock, skipping skill restore"
        return 0
    fi
    if ! command -v npx >/dev/null 2>&1; then
        echo "  npx not found, skip skill restore (install node, re-run)"
        return 0
    fi

    echo "Restoring global skills from lock..."
    python3 - "$lock" "$HOME/.agents/skills" <<'PY' | while IFS= read -r line; do
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
        [ -n "$line" ] || continue
        source=${line%%$'\t'*}
        names=${line#*$'\t'}
        echo "  npx skills add $source -g -y --skill $names"
        # shellcheck disable=SC2086
        npx --yes skills add "$source" -g -y --skill $names
    done
}
