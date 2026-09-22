#!/usr/bin/env bash
# A log line must never be silently dropped.
#
# monarchy_log used to be file-or-nothing, and on a real box the file lost:
# /var/log is root-owned, an apply runs as the user, so every [ -w ] test
# failed and `|| true` swallowed it. The log stopped weeks before anyone
# noticed, because a quiet log and a broken one look the same.
#
# No sudo: monarchy_sudo is stubbed to record what it would have run.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"
# shellcheck source=../../lib/monarchy/common.sh
source "$LIB/common.sh"

[ "$(id -u)" -ne 0 ] || fail "run this as a normal user; root ignores the permission bits under test"

WORK=$(mktemp -d)
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

# A logger that records instead of talking to journald, ahead of the real one.
FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/logger" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$WORK/journal"
EOF
chmod +x "$FAKE_BIN/logger"
# monarchy_log shells out to date(1) as well, so the sandbox PATH has to keep
# that reachable when logger is taken away below.
ln -s "$(command -v date)" "$FAKE_BIN/date"
PATH="$FAKE_BIN:$PATH"
export PATH
: >"$WORK/journal"

# --- a writable file takes the line, and journald is not also used ----------
MONARCHY_LOG="$WORK/ok.log"
: >"$MONARCHY_LOG"
monarchy_log "first" >/dev/null
grep -q ' first$' "$MONARCHY_LOG" || fail "a writable log file did not receive the line"
[ "$(wc -l <"$MONARCHY_LOG")" = 1 ] || fail "expected exactly one line in the log"
[ ! -s "$WORK/journal" ] || fail "fell back to journald while the file was writable"

# --- the line always reaches stdout ----------------------------------------
out=$(MONARCHY_LOG="$WORK/ok.log" monarchy_log "to stdout")
case "$out" in
    *"to stdout"*) ;;
    *) fail "monarchy_log did not echo to stdout" ;;
esac

# --- an existing unwritable file falls back rather than dropping the line ---
# This is the shape the bug had: the file exists, root owns it, we do not.
# chmod 0444 on a file we own reproduces it without needing another account.
MONARCHY_LOG="$WORK/ro.log"
: >"$MONARCHY_LOG"
chmod 0444 "$MONARCHY_LOG"
: >"$WORK/journal"
monarchy_log "unwritable" >/dev/null || fail "monarchy_log returned non-zero; set -e would abort every caller"
[ ! -s "$MONARCHY_LOG" ] || fail "wrote to a file with no write bit"
grep -q 'unwritable' "$WORK/journal" || fail "the line was dropped instead of going to journald"

# A writable parent must not be read as permission for an unwritable file.
[ -w "$(dirname "$MONARCHY_LOG")" ] || fail "test setup: the parent should be writable"

# --- an absent file in a writable directory is created ----------------------
MONARCHY_LOG="$WORK/new.log"
: >"$WORK/journal"
monarchy_log "created" >/dev/null
grep -q ' created$' "$MONARCHY_LOG" || fail "an absent log in a writable directory was not created"
[ ! -s "$WORK/journal" ] || fail "fell back to journald when the file could be created"

# --- an absent file in an unwritable directory falls back -------------------
mkdir -p "$WORK/ro.d"
chmod 0555 "$WORK/ro.d"
MONARCHY_LOG="$WORK/ro.d/new.log"
: >"$WORK/journal"
monarchy_log "nowhere" >/dev/null || fail "monarchy_log returned non-zero with nowhere to write"
grep -q 'nowhere' "$WORK/journal" || fail "the line was dropped instead of going to journald"
chmod 0755 "$WORK/ro.d"

# --- with no logger at all, monarchy_log still succeeds ---------------------
# set -e makes a non-zero return here fatal for every caller in the apply.
rm -f "$FAKE_BIN/logger"
PATH="$FAKE_BIN"          # nothing else on PATH, so logger is genuinely absent
hash -r                   # bash caches a resolved path and would still find it
if command -v logger >/dev/null 2>&1; then
    fail "test setup: logger is still reachable"
fi
MONARCHY_LOG="$WORK/ro.log"
monarchy_log "no logger" >/dev/null || fail "monarchy_log returned non-zero when logger is missing"
PATH="$FAKE_BIN:/usr/bin:/bin"
hash -r

# --- monarchy_ensure_log ----------------------------------------------------
SUDO_CALLS="$WORK/sudo-calls"
: >"$SUDO_CALLS"
monarchy_sudo() { printf '%s\n' "$*" >>"$SUDO_CALLS"; }

# Already writable: nothing to elevate for.
MONARCHY_LOG="$WORK/ok.log"
monarchy_ensure_log
[ ! -s "$SUDO_CALLS" ] || fail "monarchy_ensure_log elevated for a log it could already write"

# Not writable: take ownership, and never by truncating the history.
MONARCHY_LOG="$WORK/ro.log"
monarchy_ensure_log
grep -q "^touch $MONARCHY_LOG$" "$SUDO_CALLS" || fail "monarchy_ensure_log did not create the log"
grep -q "^chown $(id -u):$(id -g) $MONARCHY_LOG$" "$SUDO_CALLS" \
    || fail "monarchy_ensure_log did not take ownership of the log"
if grep -q 'install.*/dev/null' "$SUDO_CALLS"; then
    fail "monarchy_ensure_log truncated the log; it exists to keep that history"
fi

# A missing parent is not this function's business to create.
: >"$SUDO_CALLS"
MONARCHY_LOG="$WORK/no-such-dir/monarchy.log"
monarchy_ensure_log
[ ! -s "$SUDO_CALLS" ] || fail "monarchy_ensure_log elevated for a directory that does not exist"

echo "log tests passed"
