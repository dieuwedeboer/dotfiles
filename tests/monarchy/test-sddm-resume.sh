#!/usr/bin/env bash
# Resuming an open Wayland session from the greeter. Two failures here are
# critical and the rest of this path is not:
#
#   * resuming somebody else's session, which hands whoever is standing at
#     the greeter a live logged-in desktop and cannot be undone afterwards;
#   * a username taken from the query string reaching a shell.
#
# Going through sddm.login() instead would start a second compositor on top
# of the running one, which is the greeter launching a session nobody can
# use. That is why the helper exists; what it must never do is resume the
# wrong one.
#
# No sudo, no real logind: loginctl is a stub over fixture session files.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"

cmd="$LIB/sddm-resume.sh"
[ -x "$cmd" ] || fail "sddm-resume.sh is not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
stub=$tmp/stub
mkdir -p "$stub"
state=$tmp/state
mkdir -p "$state"

cat >"$stub/loginctl" <<'SH'
#!/bin/bash
state_dir="${MONARCHY_TEST_STATE:?}"
printf '%s\n' "$*" >>"$state_dir/loginctl.log"
if [[ $1 == list-sessions ]]; then
    cat "$state_dir/list"
    exit 0
fi
if [[ $1 == show-session ]]; then
    sid=$2
    f="$state_dir/session-$sid"
    [ -f "$f" ] || exit 1
    cat "$f"
    exit 0
fi
if [[ $1 == activate ]]; then
    echo "$2" >"$state_dir/activated"
    exit 0
fi
exit 1
SH
chmod +x "$stub/loginctl"

write_session() {
    local sid=$1
    cat >"$state/session-$sid"
}

# What the helper actually handed over, as a value rather than as the absence
# of a file. "none" is the answer that matters for every case below except
# the two where a resume is correct.
activated() { cat "$state/activated" 2>/dev/null || echo none; }

run_resume() {
    local user=$1
    : >"$state/loginctl.log"
    rm -f "$state/activated"
    env -i \
        PATH="$stub:/usr/bin:/bin" \
        HOME="$tmp/home" \
        MONARCHY_TEST_STATE="$state" \
        MONARCHY_LOGINCTL="$stub/loginctl" \
        "$cmd" "$user"
}

printf '2 1000 king seat0 1152 user tty2 no -\n' >"$state/list"
write_session 2 <<'EOF'
Id=2
Name=king
Class=user
Type=wayland
Seat=seat0
State=online
TimestampMonotonic=100
VTNr=2
EOF
run_resume king || fail "did not resume king's open session"
[ "$(activated)" = 2 ] || fail "activated $(activated), expected session 2"

printf '5 1000 king seat0 43623 user tty3 no -\n' >"$state/list"
write_session 5 <<'EOF'
Id=5
Name=king
Class=user
Type=wayland
Seat=seat0
State=active
TimestampMonotonic=900
VTNr=3
EOF
if run_resume queen >/dev/null 2>&1; then
    fail "queen with no session still resumed"
fi
[ "$(activated)" = none ] || fail "queen with no session activated $(activated)"

printf '2 1000 king seat0 1152 user tty2 no -\n' >"$state/list"
write_session 2 <<'EOF'
Id=2
Name=king
Class=user
Type=wayland
Seat=seat0
State=closing
TimestampMonotonic=100
VTNr=2
EOF
if run_resume king >/dev/null 2>&1; then
    fail "closing session was resumed"
fi
[ "$(activated)" = none ] || fail "a closing session was activated: $(activated)"

printf '2 1001 queen seat0 2000 user tty2 no -\n' >"$state/list"
write_session 2 <<'EOF'
Id=2
Name=queen
Class=user
Type=wayland
Seat=seat0
State=online
TimestampMonotonic=100
VTNr=2
EOF
if run_resume king >/dev/null 2>&1; then
    fail "resumed another user's session"
fi
[ "$(activated)" = none ] \
    || fail "the greeter handed over another account's session: $(activated)"

if run_resume 'king;rm -rf /' >/dev/null 2>&1; then
    fail "accepted a junk username"
fi
[ "$(activated)" = none ] || fail "a junk username activated $(activated)"

# Oldest Wayland session wins when several exist.
printf '2 1000 king seat0 1152 user tty2 no -\n8 1000 king seat0 9000 user tty4 no -\n' >"$state/list"
write_session 2 <<'EOF'
Id=2
Name=king
Class=user
Type=wayland
Seat=seat0
State=online
TimestampMonotonic=100
VTNr=2
EOF
write_session 8 <<'EOF'
Id=8
Name=king
Class=user
Type=wayland
Seat=seat0
State=online
TimestampMonotonic=900
VTNr=4
EOF
run_resume king || fail "did not resume when two sessions exist"
[ "$(activated)" = 2 ] || fail "activated $(activated), expected the oldest session 2"

if command -v python3 >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
    cat >"$stub/monarchy-sddm-resume" <<'SH'
#!/bin/bash
state_dir="${MONARCHY_TEST_STATE:?}"
if [ "$1" = king ]; then
    echo ok >"$state_dir/http-activated"
    exit 0
fi
exit 1
SH
    chmod +x "$stub/monarchy-sddm-resume"
    port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
    env -i \
        PATH="/usr/bin:/bin" \
        MONARCHY_SDDM_RESUME_PORT="$port" \
        MONARCHY_SDDM_RESUME_BIN="$stub/monarchy-sddm-resume" \
        MONARCHY_TEST_STATE="$state" \
        "$cmd" --httpd &
    http_pid=$!
    trap 'kill $http_pid 2>/dev/null || true; rm -rf "$tmp"' EXIT
    ok=0
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if curl -sS -o /dev/null --max-time 0.2 "http://127.0.0.1:$port/resume?user=king"; then
            ok=1
            break
        fi
        sleep 0.05
    done
    [ "$ok" = 1 ] || fail "httpd did not come up on $port"
    code=$(curl -sS -o "$tmp/resume.png" -w '%{http_code}' "http://127.0.0.1:$port/resume?user=king")
    [ "$code" = 200 ] || fail "resume httpd returned $code for king"
    file "$tmp/resume.png" | grep -qi png || fail "resume httpd did not return a png"
    [ -f "$state/http-activated" ] || fail "resume httpd did not call the helper"
    code=$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/resume?user=queen")
    [ "$code" = 404 ] || fail "resume httpd returned $code for a user with no session"
    kill $http_pid 2>/dev/null || true
    wait $http_pid 2>/dev/null || true
    trap 'rm -rf "$tmp"' EXIT
fi

echo "sddm-resume tests passed"
