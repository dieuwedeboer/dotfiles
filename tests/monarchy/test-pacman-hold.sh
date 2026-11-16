#!/usr/bin/env bash
# The hyprland hold is the one thing monarchy writes into [options] of
# pacman.conf. A wrong edit there reaches every transaction, so the block has
# to land under [options], leave every other line alone, and come out again
# byte for byte.
#
# No sudo, no network. pacman is answered by stubbed functions.
# shellcheck disable=SC2329  # the stubs are called from pacman.sh
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"
# shellcheck source=../../lib/monarchy/common.sh
source "$LIB/common.sh"
# shellcheck source=../../lib/monarchy/pacman.sh
source "$LIB/pacman.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

conf=$WORK/pacman.conf
cat >"$conf" <<'EOF'
[options]
HoldPkg     = pacman glibc
#IgnorePkg   =
Architecture = auto

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist

[core]
Include = /etc/pacman.d/mirrorlist
EOF

held=$WORK/held.conf
monarchy_pacman_conf_with_hold "$conf" "aquamarine hyprland" >"$held"
expected=$(printf '[options]\n# BEGIN monarchy-hold\nIgnorePkg = aquamarine hyprland\n# END monarchy-hold\n')
[ "$(head -4 "$held")" = "$expected" ] || fail "hold block is not straight under [options]"
[ "$(sed '2,4d' "$held")" = "$(cat "$conf")" ] || fail "holding changed a line outside the block"

monarchy_pacman_conf_with_hold "$held" "aquamarine hyprland" | cmp -s - "$held" || fail "holding twice added a second block"
monarchy_pacman_conf_with_hold "$held" "" | cmp -s - "$conf" || fail "releasing did not restore the file byte for byte"

# Held exactly when [omarchy]'s plugin pins a version the repo no longer has.
monarchy_pkg_installed() { [ "$1" = omarchy-hyprland-titlebars ]; }
monarchy_titlebars_hyprland_pin() { echo 0.56.2; }
monarchy_repo_pkg_version() { echo "$REPO"; }

REPO=0.57.2-1.1
monarchy_hyprland_hold_wanted || fail "no hold with the plugin on 0.56.2 and the repo on 0.57.2"
REPO=0.56.2-4.1
if monarchy_hyprland_hold_wanted; then fail "held although the repo has the pinned version"; fi

# Without the plugin there is nothing to keep in step.
REPO=0.57.2-1.1
monarchy_pkg_installed() { return 1; }
if monarchy_hyprland_hold_wanted; then fail "held hyprland with no titlebars plugin installed"; fi

# What goes with hyprland, from the stack as it stood on 16 November 2026:
# aquamarine and hyprgraphics bump their sonames, hyprtoolkit's new build needs
# the bumped ones, and hyprcursor and hyprland-guiutils take nothing away.
# The second aquamarine is a lower-priority repo; pacman installs the first.
cat >"$WORK/installed" <<'PKGS'
Name            : hyprland
Depends On      : libaquamarine.so=14-64  libhyprgraphics.so=4-64  libhyprcursor.so=0-64

Name            : aquamarine
Provides        : libaquamarine.so=14-64

Name            : hyprgraphics
Provides        : libhyprgraphics.so=4-64

Name            : hyprcursor
Provides        : libhyprcursor.so=0-64

Name            : hyprtoolkit
Provides        : libhyprtoolkit.so=6-64
Depends On      : libaquamarine.so=14-64  libhyprgraphics.so=4-64

Name            : hyprland-guiutils
Depends On      : libhyprtoolkit.so=6-64
PKGS
cat >"$WORK/repo" <<'PKGS'
Name            : hyprland
Depends On      : libaquamarine.so=15-64  libhyprgraphics.so=5-64  libhyprcursor.so=0-64

Name            : aquamarine
Provides        : libaquamarine.so=15-64

Name            : hyprgraphics
Provides        : libhyprgraphics.so=5-64

Name            : hyprcursor
Provides        : libhyprcursor.so=0-64

Name            : hyprtoolkit
Provides        : libhyprtoolkit.so=6-64
Depends On      : libaquamarine.so=15-64  libhyprgraphics.so=5-64

Name            : hyprland-guiutils
Depends On      : libhyprtoolkit.so=6-64

Name            : aquamarine
Provides        : libaquamarine.so=14-64
PKGS
printf '%s\n' hyprland aquamarine hyprgraphics hyprcursor hyprtoolkit hyprland-guiutils >"$WORK/pending"
held_set=$(python3 -I "$LIB/hold.py" --installed "$WORK/installed" --repo "$WORK/repo" \
    --pending "$WORK/pending" hyprland | paste -sd' ' -)
[ "$held_set" = "aquamarine hyprgraphics hyprland hyprtoolkit" ] \
    || fail "held with hyprland: $held_set"

# What the hold leaves behind is not a partial upgrade, or every run stops on it.
pacman() {
    printf 'hyprland 0.56.2-4.1 -> 0.57.2-1.1 [ignored]\n'
    [ "${UNHELD:-0}" = 0 ] || printf 'ffmpeg 2:8.0-1 -> 2:9.0-1\n'
}
(monarchy_refuse_partial_upgrade) || fail "the partial-upgrade guard stopped on a held package"
if (UNHELD=1 monarchy_refuse_partial_upgrade) >/dev/null 2>&1; then
    fail "the partial-upgrade guard let a real pending upgrade through"
fi

echo "pacman hold tests passed"
