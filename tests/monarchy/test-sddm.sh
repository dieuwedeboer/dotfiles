#!/usr/bin/env bash
# The two ways the greeter strands someone. No sudo, no systemctl.
#
# 1. A stock Hyprland session marked Hidden=true instead of NoDisplay=true.
#    `uwsm start … hyprland.desktop` refuses a Hidden entry, so the session
#    the greeter launches exits immediately and there is no way forward.
# 2. A username that reaches the generated QML unquotable. The SDDM theme
#    reads no files at runtime, so the Plasma list is written into Main.qml
#    at apply time; a name carrying a quote is a syntax error in the theme,
#    and a greeter whose theme will not parse cannot be logged in on.
#
# Everything else about the greeter -- which drop-in wins, what colour the
# background is, whose logo is on it -- is cosmetic. A breeze greeter is ugly
# and still lets you in. See CODING_STANDARDS.md.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"
# shellcheck source=../../lib/monarchy/common.sh
source "$LIB/common.sh"
# shellcheck source=../../lib/monarchy/users.sh
source "$LIB/users.sh"
# shellcheck source=../../lib/monarchy/sessions.sh
source "$LIB/sessions.sh"
# shellcheck source=../../lib/monarchy/sddm.sh
source "$LIB/sddm.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MONARCHY_LOG=$tmp/log

# --- hiding the stock Hyprland sessions ----------------------------------

sess=$tmp/wayland-sessions
mkdir -p "$sess"
write_session() {
    cat >"$sess/$1.desktop" <<EOF
[Desktop Entry]
Name=$1
Exec=$2
DesktopNames=Hyprland
EOF
}
write_session hyprland /usr/bin/start-hyprland
write_session hyprland-uwsm 'uwsm start -e -D Hyprland hyprland.desktop'
write_session omarchy 'uwsm start -g -1 -e -D Hyprland hyprland.desktop'
write_session plasma /usr/bin/startplasma-wayland
export MONARCHY_WAYLAND_SESSIONS_DIR=$sess

# The whole visibility state of the directory, as one value. Asserting on
# this rather than on "Hidden is not present" means a third key with the same
# effect would show up here too, and a rename of the function under test
# cannot leave the assertion passing for nothing.
visibility() {
    local f
    for f in "$sess"/*.desktop; do
        printf '%s:%s\n' "$(basename "$f" .desktop)" \
            "$(grep -E '^(NoDisplay|Hidden)=' "$f" | paste -sd, - || true)"
    done | LC_ALL=C sort
}

before_omarchy=$(cat "$sess/omarchy.desktop")
before_plasma=$(cat "$sess/plasma.desktop")

monarchy_hide_stock_hyprland_sessions
want='hyprland-uwsm:NoDisplay=true
hyprland:NoDisplay=true
omarchy:
plasma:'
[ "$(visibility)" = "$want" ] || fail "visibility after hiding is:
$(visibility)"

# The two sessions a person actually picks must come out byte-identical.
[ "$(cat "$sess/omarchy.desktop")" = "$before_omarchy" ] \
    || fail "hiding rewrote omarchy.desktop"
[ "$(cat "$sess/plasma.desktop")" = "$before_plasma" ] \
    || fail "hiding rewrote plasma.desktop"

# An apply runs on every update, so twice has to equal once.
monarchy_hide_stock_hyprland_sessions
[ "$(visibility)" = "$want" ] || fail "hiding is not idempotent:
$(visibility)"
monarchy_check_hidden_hyprland_sessions

# Hidden=true is the brick: uwsm refuses the entry the greeter would launch.
# Refusing to proceed is the only safe answer, so the function must exit
# non-zero rather than carry on.
printf '\nHidden=true\n' >>"$sess/hyprland.desktop"
if ( monarchy_hide_stock_hyprland_sessions ) 2>/dev/null; then
    fail "hiding accepted a Hidden=true hyprland.desktop"
fi
unset MONARCHY_WAYLAND_SESSIONS_DIR

# --- the generated Plasma list -------------------------------------------

gen=$tmp/gen
mkdir -p "$gen"
cp "$MISC/sddm/Main.qml" "$gen/Main.qml"
default_line=$(grep -E '^[[:space:]]*property var plasmaUsers:' "$gen/Main.qml")
[ "$default_line" = '  property var plasmaUsers: []' ] \
    || fail "the repo copy of Main.qml must ship an empty list, has: $default_line"

cat >"$gen/users.conf" <<'CONF'
# comment
someking   king
somequeen  queen
somekid    kid
nosuchuser kid
CONF
(
    # shellcheck disable=SC2034  # read by monarchy_users
    MONARCHY_USERS_CONF="$gen/users.conf"
    # Only accounts that exist on the box may reach the list. someking exists
    # too, so the result tests the role filter and not just this stub.
    # shellcheck disable=SC2329
    getent() { case "$2" in someking|somequeen|somekid) return 0 ;; *) return 1 ;; esac; }
    # shellcheck disable=SC2329
    monarchy_sudo() { "$@"; }
    monarchy_sddm_write_plasma_users "$gen/Main.qml" >/dev/null
)
line=$(grep -E '^[[:space:]]*property var plasmaUsers:' "$gen/Main.qml")
[ "$line" = '  property var plasmaUsers: ["somekid", "somequeen"]' ] \
    || fail "generated plasma list is: $line"

# users.conf is hand-edited and unvalidated. A name carrying a quote would
# close the QML string and break the theme, so the file must come back
# untouched rather than half-written.
printf '%s queen\n' 'bad"name' >"$gen/hostile.conf"
cp "$MISC/sddm/Main.qml" "$gen/Hostile.qml"
(
    # shellcheck disable=SC2034
    MONARCHY_USERS_CONF="$gen/hostile.conf"
    # shellcheck disable=SC2329
    getent() { return 0; }
    # shellcheck disable=SC2329
    monarchy_sudo() { "$@"; }
    monarchy_sddm_write_plasma_users "$gen/Hostile.qml" >/dev/null 2>&1 || true
)
cmp -s "$gen/Hostile.qml" "$MISC/sddm/Main.qml" \
    || fail "a username containing a quote changed the generated QML:
$(grep -E '^[[:space:]]*property var plasmaUsers:' "$gen/Hostile.qml")"

echo "sddm tests passed"
