#!/usr/bin/env bash
# Switch-user command and lock/menu overlay. No sudo.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"
# shellcheck source=../../lib/monarchy/common.sh
source "$LIB/common.sh"
# shellcheck source=../../lib/monarchy/clone.sh
source "$LIB/clone.sh"
# shellcheck source=../../lib/monarchy/overlay.sh
source "$LIB/overlay.sh"
# shellcheck source=../../lib/monarchy/user.sh
source "$LIB/user.sh"


cmd="$LIB/switch-user.sh"
py="$LIB/overlay-lock.py"
[ -f "$cmd" ] || fail "missing switch-user.sh"
[ -x "$cmd" ] || fail "switch-user.sh is not executable"
[ -f "$py" ] || fail "missing overlay-lock.py"
grep -q 'SUPER + CTRL + U' "$LIB/user.sh" || fail "user.sh does not seed Super+Ctrl+U"
grep -q '{ locked = true }' "$LIB/user.sh" || fail "user.sh switch-user bind is not locked=true"
grep -q 'monarchy_overlay_session_lock' "$LIB/update.sh" || fail "apply does not overlay lock"
grep -q 'monarchy_install_switch_user' "$LIB/update.sh" || fail "apply does not install monarchy-switch-user"
grep -q 'monarchy_check_session_lock_overlay' "$LIB/update.sh" || fail "check does not verify lock overlay"
grep -q 'monarchy_seed_switch_user_bind' "$LIB/user.sh" || fail "setup_user does not seed the bind"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
stub=$tmp/stub
mkdir -p "$stub"
state=$tmp/state
mkdir -p "$state"
printf 'false\n' >"$state/locked"
printf 'true\n' >"$state/canswitch"
: >"$state/busctl.log"
: >"$state/lock.log"

cat >"$stub/busctl" <<'SH'
#!/bin/bash
state_dir="${MONARCHY_TEST_STATE:?}"
printf '%s\n' "$*" >>"$state_dir/busctl.log"
if [[ $* == *CanSwitch* ]]; then
    cat "$state_dir/canswitch"
    exit 0
fi
if [[ $* == *SwitchToGreeter* ]]; then
    echo switched >>"$state_dir/busctl.log"
    exit 0
fi
exit 1
SH

cat >"$stub/omarchy-shell" <<'SH'
#!/bin/bash
state_dir="${MONARCHY_TEST_STATE:?}"
printf '%s\n' "$*" >>"$state_dir/lock.log"
locked=$(cat "$state_dir/locked")
# Production always answers `lock status` with compact JSON. isLocked is only
# a fallback when status is empty; tests must exercise the JSON path.
if [[ $1 == lock && $2 == status ]]; then
    if [[ $locked == true ]]; then
        echo '{"locked":true,"requested":true,"pending":false,"sessionLocked":true,"secure":true,"realScreens":1,"passwordPam":true,"fingerprint":false,"authenticating":false,"lastEvent":"secure=true","lastEventAt":"t"}'
    else
        echo '{"locked":false,"requested":false,"pending":false,"sessionLocked":false,"secure":false,"realScreens":1,"passwordPam":true,"fingerprint":false,"authenticating":false,"lastEvent":"unlocked","lastEventAt":"t"}'
    fi
    exit 0
fi
if [[ $1 == lock && $2 == isLocked ]]; then
    if [[ $locked == true ]]; then echo true; else echo false; fi
    exit 0
fi
if [[ $1 == lock && $2 == lock ]]; then
    echo ok
    printf 'true\n' >"$state_dir/locked"
    exit 0
fi
exit 1
SH

cat >"$stub/omarchy-system-lock" <<'SH'
#!/bin/bash
state_dir="${MONARCHY_TEST_STATE:?}"
echo system-lock >>"$state_dir/lock.log"
printf 'true\n' >"$state_dir/locked"
exit 0
SH
chmod +x "$stub"/*

export PATH="$stub:$PATH"
export MONARCHY_TEST_STATE=$state
export MONARCHY_SWITCH_USER_LOCK_TRIES=5
export MONARCHY_SWITCH_USER_LOCK_SLEEP=0

printf 'true\n' >"$state/locked"
: >"$state/busctl.log"
"$cmd" || fail "already-locked switch-user failed"
grep -q SwitchToGreeter "$state/busctl.log" || fail "already-locked did not call SwitchToGreeter"
if grep -q system-lock "$state/lock.log"; then
    fail "already-locked still called omarchy-system-lock"
fi

printf 'false\n' >"$state/locked"
: >"$state/busctl.log"
: >"$state/lock.log"
"$cmd" || fail "unlocked switch-user failed"
grep -q SwitchToGreeter "$state/busctl.log" || fail "unlocked did not call SwitchToGreeter"
grep -q 'lock lock' "$state/lock.log" || fail "unlocked did not take the session lock"

printf 'false\n' >"$state/locked"
: >"$state/busctl.log"
: >"$state/lock.log"
"$cmd" --already-locked || fail "--already-locked switch-user failed"
grep -q SwitchToGreeter "$state/busctl.log" || fail "--already-locked did not call SwitchToGreeter"
if grep -q 'lock lock' "$state/lock.log"; then
    fail "--already-locked still tried to take the session lock"
fi

printf 'false\n' >"$state/canswitch"
printf 'true\n' >"$state/locked"
: >"$state/busctl.log"
if "$cmd" >/dev/null 2>&1; then
    fail "CanSwitch false should fail"
fi
if grep -q SwitchToGreeter "$state/busctl.log"; then
    fail "CanSwitch false still called SwitchToGreeter"
fi
printf 'true\n' >"$state/canswitch"

printf 'false\n' >"$state/locked"
cat >"$stub/omarchy-shell" <<'SH'
#!/bin/bash
state_dir="${MONARCHY_TEST_STATE:?}"
if [[ $1 == lock && $2 == isLocked ]]; then
    echo false
    exit 0
fi
if [[ $1 == lock && $2 == lock ]]; then
    echo missing-pam
    exit 0
fi
exit 1
SH
chmod +x "$stub/omarchy-shell"
: >"$state/busctl.log"
if "$cmd" >/dev/null 2>&1; then
    fail "missing-pam should not switch"
fi
if grep -q SwitchToGreeter "$state/busctl.log"; then
    fail "missing-pam still called SwitchToGreeter"
fi

clone="${1:-${MONARCHY_SRC:-/usr/local/src/monarchy/omarchy}}"
if [ -f "$clone/shell/plugins/lock/LockView.qml" ]; then
    python3 "$py" check lock "$clone/shell/plugins/lock" || fail "lock overlay check failed against clone"
    python3 "$py" check menu "$clone/default/omarchy/omarchy-menu.jsonc" || fail "menu overlay check failed against clone"

    export MONARCHY_SRC=$clone
    export MONARCHY_PATH=$tmp/prefix
    export MONARCHY_LOG=$tmp/log
    export MONARCHY_INSTALL_SUDO_STUBS=0
    mkdir -p "$MONARCHY_PATH"
    monarchy_link_working_prefix
    monarchy_overlay_session_lock

    view="$MONARCHY_PATH/shell/plugins/lock/LockView.qml"
    service="$MONARCHY_PATH/shell/plugins/lock/Service.qml"
    menu="$MONARCHY_PATH/default/omarchy/omarchy-menu.jsonc"
    [ -f "$view" ] && [ ! -L "$view" ] || fail "overlaid LockView.qml should be a real file"
    grep -q 'signal switchUserRequested' "$view" || fail "LockView missing switchUserRequested"
    grep -q 'switchUserHint' "$view" || fail "LockView missing switch-user caption"
    grep -q 'Super+Ctrl+U to switch user' "$view" || fail "LockView caption text drifted"
    grep -q 'ctrl && meta && event.key === Qt.Key_U' "$view" || fail "LockView missing Super+Ctrl+U"
    grep -q 'ctrl && !meta && event.key === Qt.Key_U' "$view" || fail "LockView Ctrl+U clear no longer ignores Super"
    grep -q 'function runSwitchUser' "$service" || fail "Service.qml missing runSwitchUser"
    grep -q '/usr/local/bin/monarchy-switch-user' "$service" || fail "Service.qml does not call monarchy-switch-user"
    grep -q -- '--already-locked' "$service" || fail "Service.qml lock-screen path must pass --already-locked"
    grep -q '"system.switch-user"' "$menu" || fail "menu missing system.switch-user"
    awk '/system.lock/{lock=NR} /system.switch-user/{sw=NR} END{if(!(lock&&sw&&sw==lock+1)) exit 1}' "$menu" \
        || fail "system.switch-user is not the row after system.lock"
    # PluginRegistry scans with `find -type f` and does not follow directory
    # symlinks. Child-dir-symlinks hide wallpaper and the menu: black desktop.
    menu_manifest="$MONARCHY_PATH/shell/plugins/menu/manifest.json"
    bg_manifest="$MONARCHY_PATH/shell/plugins/background/manifest.json"
    [ -f "$menu_manifest" ] && [ ! -L "$menu_manifest" ] \
        || fail "menu manifest must be a real file (find -type f)"
    [ -f "$bg_manifest" ] && [ ! -L "$bg_manifest" ] \
        || fail "background manifest must be a real file (find -type f)"
    overlay_scan=$(find "$MONARCHY_PATH/shell/plugins" -mindepth 2 -maxdepth 3 \
        -type f \( -name manifest.json -o -name '*.manifest.json' \) | wc -l)
    clone_scan=$(find "$clone/shell/plugins" -mindepth 2 -maxdepth 3 \
        -type f \( -name manifest.json -o -name '*.manifest.json' \) | wc -l)
    [ "$overlay_scan" -eq "$clone_scan" ] \
        || fail "overlay plugin scan finds $overlay_scan manifests, clone has $clone_scan"
    grep -q 'signal switchUserRequested' "$clone/shell/plugins/lock/LockView.qml" \
        && fail "clone LockView.qml was patched"
    [ -L "$MONARCHY_PATH/logo.txt" ] || fail "prefix logo.txt should stay a symlink"
else
    echo "test-switch-user: skip live clone overlay (no $clone/shell/plugins/lock)" >&2
fi

bind=$tmp/home/.config/hypr/bindings.lua
export HOME=$tmp/home
mkdir -p "$(dirname "$bind")"
printf -- '-- Keep only your personal keybinding overrides here.\n' >"$bind"
monarchy_seed_switch_user_bind
grep -q 'SUPER + CTRL + U' "$bind" || fail "bind seed missing Super+Ctrl+U"
grep -q 'monarchy-switch-user' "$bind" || fail "bind seed missing monarchy-switch-user"
grep -q '{ locked = true }' "$bind" || fail "bind seed missing locked=true"
monarchy_seed_switch_user_bind
n=$(grep -c 'monarchy-switch-user' "$bind")
[ "$n" -eq 1 ] || fail "bind seed is not idempotent ($n)"

printf -- '-- Keep only your personal keybinding overrides here.\n\no.bind("SUPER + CTRL + U", "Switch user", "monarchy-switch-user")\n' >"$bind"
monarchy_seed_switch_user_bind
grep -q '{ locked = true }' "$bind" || fail "seed did not upgrade an unlocked switch-user bind"
n=$(grep -c 'monarchy-switch-user' "$bind")
[ "$n" -eq 1 ] || fail "bind upgrade is not idempotent ($n)"

echo "switch-user tests passed"
