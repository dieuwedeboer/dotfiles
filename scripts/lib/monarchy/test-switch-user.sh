#!/usr/bin/env bash
# Switch-user command and lock/menu overlay. No sudo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
# shellcheck source=clone.sh
source "$SCRIPT_DIR/clone.sh"
# shellcheck source=overlay.sh
source "$SCRIPT_DIR/overlay.sh"
# shellcheck source=user.sh
source "$SCRIPT_DIR/user.sh"

fail() {
    echo "test-switch-user: $*" >&2
    exit 1
}

cmd="$SCRIPT_DIR/switch-user.sh"
py="$SCRIPT_DIR/overlay-lock.py"
[ -f "$cmd" ] || fail "missing switch-user.sh"
[ -x "$cmd" ] || fail "switch-user.sh is not executable"
[ -f "$py" ] || fail "missing overlay-lock.py"
grep -q 'SUPER + CTRL + U' "$SCRIPT_DIR/user.sh" || fail "user.sh does not seed Super+Ctrl+U"
grep -q 'monarchy_overlay_session_lock' "$SCRIPT_DIR/update.sh" || fail "apply does not overlay lock"
grep -q 'monarchy_install_switch_user' "$SCRIPT_DIR/update.sh" || fail "apply does not install monarchy-switch-user"
grep -q 'monarchy_check_session_lock_overlay' "$SCRIPT_DIR/update.sh" || fail "check does not verify lock overlay"
grep -q 'monarchy_seed_switch_user_bind' "$SCRIPT_DIR/user.sh" || fail "setup_user does not seed the bind"

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
if [[ $1 == lock && $2 == isLocked ]]; then
    cat "$state_dir/locked"
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
    grep -q '"system.switch-user"' "$menu" || fail "menu missing system.switch-user"
    awk '/system.lock/{lock=NR} /system.switch-user/{sw=NR} END{if(!(lock&&sw&&sw==lock+1)) exit 1}' "$menu" \
        || fail "system.switch-user is not the row after system.lock"
    [ -L "$MONARCHY_PATH/shell/plugins/menu" ] || fail "unrelated shell plugin should stay a symlink"
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
monarchy_seed_switch_user_bind
n=$(grep -c 'monarchy-switch-user' "$bind")
[ "$n" -eq 1 ] || fail "bind seed is not idempotent ($n)"

echo "switch-user tests passed"
