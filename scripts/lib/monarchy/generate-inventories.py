#!/usr/bin/env python3
"""Build bin.allow / bin.wrap / bin.deny from a quattro-on-zfs checkout.

Omarchy-first: every clone bin name is allowed unless it is a wrap or a
brick. Bricks are the commands that replace pacman.conf, Limine, the
dataset contract, or the ISO provisioner.

Re-run after bumping misc/monarchy/omarchy.lock:

    python3 scripts/lib/monarchy/generate-inventories.py /usr/local/src/monarchy/omarchy
"""

from __future__ import annotations

import sys
from pathlib import Path

WRAP = {
    "omarchy-update",
    "omarchy-update-system-pkgs",
    "omarchy-plymouth-set",
    "omarchy-plymouth-reset",
    "omarchy-refresh-plymouth",
    "omarchy-refresh-sddm",
    "omarchy-screensaver",
}

# Same job as omarchy-on-cachyos deleting installer steps: only the commands
# that brick CachyOS+ZFS+KDE. Everything else is a real binary.
HARD_DENY = {
    "omarchy-refresh-pacman",
    "omarchy-refresh-limine",
    "omarchy-upgrade-to-quattro",
    "omarchy-upgrade-to-quattro-zfs-check",
    "omarchy-setup-direct-boot",
    "omarchy-hibernation-setup",
    "omarchy-hibernation-remove",
    "omarchy-system-factory-reset",
    "omarchy-system-factory-reset-finish",
    "omarchy-channel-set",
    "omarchy-sudo-passwordless",
    "omarchy-provision-owner",
    "omarchy-apply-system",
    "omarchy-apply-hardware",
    "omarchy-update-pacman-guard",
    "omarchy-update-dev",
    "omarchy-reinstall",
    "omarchy-reinstall-pkgs",
    "omarchy-dev-link",
    "omarchy-dev-unlink",
}


def classify(name: str) -> str:
    if name in WRAP:
        return "wrap"
    if name in HARD_DENY:
        return "deny"
    return "allow"


def write_list(path: Path, items: list[str]) -> None:
    path.write_text("".join(f"{n}\n" for n in items))


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: generate-inventories.py <omarchy-clone>", file=sys.stderr)
        return 2
    clone = Path(sys.argv[1])
    bin_dir = clone / "bin"
    if not bin_dir.is_dir():
        print(f"no bin/ under {clone}", file=sys.stderr)
        return 2

    repo = Path(__file__).resolve().parents[3]
    dest = repo / "misc" / "monarchy"
    dest.mkdir(parents=True, exist_ok=True)

    names = sorted(p.name for p in bin_dir.iterdir() if p.is_file())
    buckets = {"allow": [], "wrap": [], "deny": []}
    for n in names:
        buckets[classify(n)].append(n)

    if len(buckets["allow"]) + len(buckets["wrap"]) + len(buckets["deny"]) != len(names):
        print("inventory does not partition clone bin/", file=sys.stderr)
        return 1
    for req in sorted(WRAP | HARD_DENY):
        if req not in names:
            print(f"classified name missing from clone bin/: {req}", file=sys.stderr)
            return 1
        if req in WRAP and classify(req) != "wrap":
            print(f"wrap not wrapped: {req}", file=sys.stderr)
            return 1
        if req in HARD_DENY and classify(req) != "deny":
            print(f"hard-deny not denied: {req}", file=sys.stderr)
            return 1
    for req in ("omarchy", "omarchy-install-app", "omarchy-pkg-add", "omarchy-provision-user"):
        if req in names and classify(req) != "allow":
            print(f"omarchy-first name not allowed: {req}", file=sys.stderr)
            return 1

    write_list(dest / "bin.allow", buckets["allow"])
    write_list(dest / "bin.wrap", buckets["wrap"])
    write_list(dest / "bin.deny", buckets["deny"])
    print(
        f"wrote {len(buckets['allow'])} allow, "
        f"{len(buckets['wrap'])} wrap, "
        f"{len(buckets['deny'])} deny "
        f"(total {len(names)})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
