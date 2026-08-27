#!/usr/bin/env python3
"""Build bin.allow / bin.wrap / bin.deny from a quattro-on-zfs checkout.

The three files must partition every name in clone/bin at the lock commit.
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
    "omarchy-reinstall",
    "omarchy-reinstall-pkgs",
    "omarchy-reinstall-configs",
    "omarchy-channel-set",
    "omarchy-sudo-passwordless",
    "omarchy-sudo-docker",
    "omarchy-provision-first-run",
    "omarchy-provision-user",
    "omarchy-provision-owner",
    "omarchy-apply-system",
    "omarchy-apply-hardware",
    "omarchy-dev-link",
    "omarchy-dev-unlink",
    "omarchy-mise-install",
    "omarchy-update-mise",
    "omarchy-update-pacman-guard",
    "omarchy-update-aur-pkgs",
    "omarchy-update-keyring",
    "omarchy-update-dev",
    "omarchy-setup-security-sudoless-docker",
    "omarchy-remove-security-sudoless-docker",
    "omarchy-hook-install",
    "omarchy-voxtype-install",
    "omarchy-toggle-hybrid-gpu",
}

ALLOW_EXACT = {
    "omarchy",
    "omarchy-launch-shell",
    "omarchy-powerprofiles-init",
    "omarchy-hyprland-monitor-watch",
    "omarchy-hook",
    "omarchy-bar",
    "omarchy-hw-nvidia",
    "omarchy-hw-nvidia-gsp",
    "omarchy-hw-nvidia-without-gsp",
    "omarchy-menu",
    "omarchy-launch-nautilus",
    "omarchy-launch-terminal",
    "omarchy-launch-browser",
    "omarchy-launch-editor",
    "omarchy-launch-screensaver",
    "omarchy-refresh-hyprland",
    "omarchy-refresh-shell",
    "omarchy-refresh-config",
    "omarchy-refresh-applications",
    "omarchy-migrate",
    "omarchy-snapshot",
    "omarchy-default-terminal",
    "omarchy-default-browser",
    "omarchy-default-editor",
    "omarchy-version",
    "omarchy-cmd-present",
    "omarchy-cmd-missing",
    "omarchy-state",
    "omarchy-plymouth-current",
    "omarchy-plymouth-list",
    "omarchy-plymouth-preview",
    "omarchy-plymouth-switcher",
    "omarchy-plymouth-set-by-theme",
}

ALLOW_PREFIXES = (
    "omarchy-launch-",
    "omarchy-menu-",
    "omarchy-theme-",
    "omarchy-font-",
    "omarchy-notification-",
    "omarchy-hyprland-",
    "omarchy-restart-",
    "omarchy-toggle-",
    "omarchy-audio-",
    "omarchy-brightness-",
    "omarchy-battery-",
    "omarchy-bluetooth-",
    "omarchy-capture-",
    "omarchy-clipboard-",
    "omarchy-weather-",
    "omarchy-bar-",
    "omarchy-branding-",
    "omarchy-powerprofiles-",
    "omarchy-cmd-",
    "omarchy-version-",
    "omarchy-default-",
    "omarchy-hw-",
    "omarchy-agent",
    "omarchy-plugin-",
    "omarchy-refresh-herdr",
    "omarchy-refresh-hyprsunset",
    "omarchy-refresh-tmux",
    "omarchy-refresh-chromium",
    "omarchy-osd",
    "omarchy-screensaver",
    "omarchy-reminder",
    "omarchy-shell",
    "omarchy-show-",
    "omarchy-ascii",
    "omarchy-done",
    "omarchy-apply-lock",
    "omarchy-system-lock",
    "omarchy-system-logout",
    "omarchy-system-reboot",
    "omarchy-system-shutdown",
    "omarchy-system-sleep",
    "omarchy-system-wake",
    "omarchy-system-lid",
    "omarchy-system-stats",
    "omarchy-power-present",
    "omarchy-debug",
    "omarchy-crash-watch",
    "omarchy-monitor-state",
    "omarchy-network-",
    "omarchy-file-select",
    "omarchy-drive-",
    "omarchy-display-text-size",
    "omarchy-dns",
    "omarchy-voxtype-",
    "omarchy-webapp-",
    "omarchy-transcode",
    "omarchy-upload-log",
    "omarchy-windows-key",
    "omarchy-channel-current",
    "omarchy-hibernation-available",
    "omarchy-migrate",
)

DENY_PREFIXES = (
    "omarchy-pkg-",
    "omarchy-install-",
    "omarchy-installed-",
    "omarchy-remove-",
    "omarchy-update-",
    "omarchy-reinstall",
    "omarchy-dev-",
    "omarchy-plymouth-",
    "omarchy-tui-install",
    "omarchy-tui-remove",
    "omarchy-setup-",
    "omarchy-provision-",
    "omarchy-upgrade-",
    "omarchy-refresh-limine",
    "omarchy-refresh-pacman",
    "omarchy-refresh-plymouth",
    "omarchy-apply-system",
    "omarchy-apply-hardware",
    "omarchy-sudo-",
    "omarchy-system-factory-",
    "omarchy-hibernation-setup",
    "omarchy-hibernation-remove",
    "omarchy-channel-set",
    "omarchy-mise-",
    "omarchy-windows-vm",
    "omarchy-games-",
    "omarchy-hook-install",
    "omarchy-voxtype-install",
    "omarchy-toggle-hybrid-gpu",
)


def classify(name: str) -> str:
    if name in WRAP:
        return "wrap"
    if name in HARD_DENY:
        return "deny"
    if any(name.startswith(p) or name == p.rstrip("-") for p in DENY_PREFIXES):
        if name in ALLOW_EXACT:
            return "allow"
        return "deny"
    if name in ALLOW_EXACT:
        return "allow"
    if any(name.startswith(p) or name == p for p in ALLOW_PREFIXES):
        return "allow"
    return "deny"


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
    missing = sorted(ALLOW_EXACT - set(names))
    if missing:
        print(f"required allow names missing from clone: {missing}", file=sys.stderr)
        return 1
    for req in sorted(HARD_DENY):
        if req in names and classify(req) != "deny":
            print(f"hard-deny not denied: {req}", file=sys.stderr)
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
