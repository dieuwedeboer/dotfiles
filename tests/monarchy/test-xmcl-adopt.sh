#!/usr/bin/env bash
# Moving each player's own XMCL data into /games/xmcl is the one step here that
# could lose a world for good: two players with a world or instance of the same
# name must both keep theirs, and a moved instance must still point at its own
# files and Java afterwards.
#
# No sudo, no network. monarchy_sudo runs the command as the caller; chattr,
# chown and lsattr, which need root, keep their state in a file.
# shellcheck disable=SC2329  # the stubs are called from xmcl.sh
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/games"
LOCKED=$T/locked
: >"$LOCKED"

monarchy_changed() { :; }
monarchy_left_alone() { echo "left alone: $*" >&2; }
monarchy_warn() { echo "warning: $*" >&2; }
getent() { printf '%s:x:1000:1000::%s/home/%s:/bin/sh\n' "$2" "$T" "$2"; }
pgrep() { return 1; }
monarchy_sudo() {
    case "$1" in
        runuser) shift 4; "$@" ;;
        chown) ;;
        chattr)
            if [ "$2" = +i ]; then echo "$3" >>"$LOCKED"; else grep -vxF "$3" "$LOCKED" >"$LOCKED.new" || true; mv "$LOCKED.new" "$LOCKED"; fi
            ;;
        lsattr) if grep -qxF "$3" "$LOCKED"; then echo "----i----- $3"; else echo "---------- $3"; fi ;;
        stat) echo 0 ;;
        *) "$@" ;;
    esac
}

GAMES_ROOT=$T/games
# shellcheck source=../../lib/xmcl.sh
source "$REPO/lib/xmcl.sh"

# A player's data root as XMCL leaves it: an instance linked back to the root,
# its own worlds, and shared worlds.
make_root() {
    local user=$1 world=$2 root=$T/home/$1/.minecraftx inst
    inst=$root/instances/Minecraft
    mkdir -p "$inst/saves/Own $world" "$root/saves/$world" "$root/libraries/lib" "$root/jre/bin" "$T/home/$user/.config/xmcl"
    echo "$user" >"$root/saves/$world/level.dat"
    echo "$user" >"$inst/saves/Own $world/level.dat"
    echo "$user" >"$root/libraries/lib/$user.jar"
    ln -s "$root/libraries" "$inst/libraries"
    printf '{"path":"%s","java":"%s/jre/bin/java","name":"Minecraft"}\n' "$inst" "$root" >"$inst/instance.json"
    printf '%s' "$root" >"$T/home/$user/.config/xmcl/root"
}

make_root king Survival
make_root kid Survival

xmcl_ensure_player king
xmcl_ensure_player kid

X=$GAMES_ROOT/xmcl
[ "$(cat "$X/saves/Survival/level.dat")" = king ] || fail "the first player's world was not kept under its own name"
[ "$(cat "$X/saves/Survival (kid)/level.dat")" = kid ] || fail "the second player's world of the same name was not kept beside it"
[ "$(cat "$X/instances/Minecraft/saves/Own Survival/level.dat")" = king ] || fail "the first player's instance world was not moved"
[ "$(cat "$X/instances/Minecraft (kid)/saves/Own Survival/level.dat")" = kid ] || fail "the second player's instance of the same name was not kept beside it"
[ -f "$X/libraries/lib/king.jar" ] && [ -f "$X/libraries/lib/kid.jar" ] || fail "libraries were not merged from both players"

inst="$X/instances/Minecraft (kid)"
[ "$(readlink "$inst/libraries")" = "$X/libraries" ] || fail "the instance's libraries link still points at $(readlink "$inst/libraries")"
[ "$(jq -r .path "$inst/instance.json")" = "$inst" ] || fail "instance.json path is $(jq -r .path "$inst/instance.json")"
[ "$(jq -r .java "$inst/instance.json")" = "$X/jre/bin/java" ] || fail "instance.json java is $(jq -r .java "$inst/instance.json")"

for user in king kid; do
    [ "$(cat "$T/home/$user/.config/xmcl/root")" = "$X" ] || fail "$user's data location is not $X"
    grep -qxF "$T/home/$user/.config/xmcl/root" "$LOCKED" || fail "$user's data location was not made immutable"
    [ -d "$T/home/$user/.minecraftx.before-monarchy" ] || fail "$user's old root was not kept aside"
done

# A second apply finds nothing to move and leaves every world where it is.
xmcl_ensure_player kid
[ "$(cat "$X/saves/Survival (kid)/level.dat")" = kid ] || fail "a second apply moved a world"
worlds=$(find "$X/saves" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort | paste -sd '|')
[ "$worlds" = "Survival|Survival (kid)" ] || fail "after a second apply the shared worlds are $worlds"

echo "xmcl adopt tests passed"
