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
monarchy_pacman_conf_with_hold "$conf" 1 >"$held"
expected=$(printf '[options]\n# BEGIN monarchy-hold\nIgnorePkg = hyprland\n# END monarchy-hold\n')
[ "$(head -4 "$held")" = "$expected" ] || fail "hold block is not straight under [options]"
[ "$(sed '2,4d' "$held")" = "$(cat "$conf")" ] || fail "holding changed a line outside the block"

monarchy_pacman_conf_with_hold "$held" 1 | cmp -s - "$held" || fail "holding twice added a second block"
monarchy_pacman_conf_with_hold "$held" 0 | cmp -s - "$conf" || fail "releasing did not restore the file byte for byte"

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

echo "pacman hold tests passed"
