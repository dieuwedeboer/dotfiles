#!/usr/bin/env python3
"""The packages that have to be held with a seed package.

Reads `pacman -Qi` (installed) and `pacman -Si` (repo) output and the names
`pacman -Qu` reports, and prints one name per line. A held package keeps the
sonames its installed version needs, so a pending upgrade that would stop
providing one is held too; and a pending upgrade that needs a soname only the
new version of a held package provides cannot go in either. ADR 0012.
"""

import argparse
import sys
from pathlib import Path


def parse(text: str) -> dict[str, dict[str, set[str]]]:
    pkgs: dict[str, dict[str, set[str]]] = {}
    for block in text.split("\n\n"):
        fields: dict[str, str] = {}
        for line in block.splitlines():
            key, sep, value = line.partition(":")
            if sep:
                fields[key.strip()] = value.strip()
        name = fields.get("Name")
        # pacman -Si lists every repo that carries a name; the first is the
        # one pacman would install.
        if not name or name in pkgs:
            continue

        def sonames(field: str) -> set[str]:
            return {w for w in fields.get(field, "").split() if ".so=" in w}

        pkgs[name] = {"provides": sonames("Provides"), "depends": sonames("Depends On")}
    return pkgs


def closure(seed: str, installed, repo, pending: set[str]) -> set[str]:
    held = {seed}
    changed = True
    while changed:
        changed = False
        needed = set().union(*(installed.get(h, {}).get("depends", set()) for h in held))
        new_only = set()
        for h in held:
            if h in repo and h in installed:
                new_only |= repo[h]["provides"] - installed[h]["provides"]
        for name in sorted(pending - held):
            if name not in installed or name not in repo:
                continue
            drops = installed[name]["provides"] - repo[name]["provides"]
            if drops & needed or repo[name]["depends"] & new_only:
                held.add(name)
                changed = True
    return held


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--installed", required=True)
    p.add_argument("--repo", required=True)
    p.add_argument("--pending", required=True)
    p.add_argument("seed")
    args = p.parse_args()
    installed = parse(Path(args.installed).read_text())
    repo = parse(Path(args.repo).read_text())
    pending = {line.split()[0] for line in Path(args.pending).read_text().splitlines() if line.strip()}
    for name in sorted(closure(args.seed, installed, repo, pending)):
        print(name)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception as e:
        print(f"hold: {e}", file=sys.stderr)
        raise SystemExit(1)
