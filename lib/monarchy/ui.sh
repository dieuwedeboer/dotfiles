# shellcheck shell=bash
# One voice for everything a run says, and the ledger it says it from.
# Sourced first, before common.sh: monarchy_log formats its stdout copy with
# the escapes set here.
#
# Output used to come in three voices -- `=== Section ===` banners from
# install.sh, bare sentences and two-space sub-lines from the household
# refresh, and timestamped monarchy_log lines from the units -- and nothing
# ever summarised. So the line that mattered scrolled past between two
# hundred that did not. That is how a bar widget switched off by hand came
# back on three updates running without anyone noticing.
#
# The ledger is the point. Three outcomes are worth a reader's attention once
# the run is over:
#
#   changed     something on this box is different now
#   left alone  monarchy saw a local decision and did not overrule it
#   warning     something did not work and the run carried on
#
# "Already correct" is the ordinary case and is deliberately not collected.
# It is what the detail lines are for, and what -v is for. A summary that
# lists everything is the scrolling problem again with a heading on it.

# Sourced from two places -- lib/monarchy.sh for a real run, common.sh so a
# test that pulls in one lib file still has a voice. Loading twice would reset
# the ledger mid-run, so it loads once.
[ -z "${MONARCHY_UI_LOADED:-}" ] || return 0
MONARCHY_UI_LOADED=1

# Colour when a person is watching, and never otherwise: the Omarchy menu
# wraps monarchy-update with no tty, and the durable log must not collect
# escape sequences.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
    MONARCHY_UI_BOLD=$'\033[1m'
    MONARCHY_UI_DIM=$'\033[2m'
    MONARCHY_UI_YELLOW=$'\033[33m'
    MONARCHY_UI_GREEN=$'\033[32m'
    MONARCHY_UI_OFF=$'\033[0m'
else
    MONARCHY_UI_BOLD=""
    MONARCHY_UI_DIM=""
    MONARCHY_UI_YELLOW=""
    MONARCHY_UI_GREEN=""
    MONARCHY_UI_OFF=""
fi

MONARCHY_UI_CHANGED=()
MONARCHY_UI_LEFT=()
MONARCHY_UI_WARNED=()
MONARCHY_UI_STARTED=${MONARCHY_UI_STARTED:-$SECONDS}
MONARCHY_UI_STEPS=0

# A heading for a phase of the run. Blank line above, so phases separate
# without anything having to print one by hand.
monarchy_section() {
    printf '\n%s== %s%s\n' "$MONARCHY_UI_BOLD" "$*" "$MONARCHY_UI_OFF"
}

# One step within a phase. $1 name, $2 index, $3 total; the counter is
# omitted when there is no total, which is what the household refresh wants.
monarchy_step() {
    local name=$1 n=${2:-} total=${3:-}
    MONARCHY_UI_STEPS=$((MONARCHY_UI_STEPS + 1))
    if [ -n "$total" ]; then
        printf '  %s[%2d/%d]%s %s\n' \
            "$MONARCHY_UI_DIM" "$n" "$total" "$MONARCHY_UI_OFF" "$name"
    else
        printf '  %s\n' "$name"
    fi
}

# Elapsed for the step just finished, and only when it was slow enough to be
# worth wondering about. Under the threshold a run stays a clean column of
# step names rather than a column of near-zero timings.
MONARCHY_UI_SLOW_SECONDS=${MONARCHY_UI_SLOW_SECONDS:-5}

monarchy_step_took() {
    local seconds=$1
    [ "$seconds" -ge "$MONARCHY_UI_SLOW_SECONDS" ] || return 0
    printf '      %s%s%s\n' "$MONARCHY_UI_DIM" "$(monarchy_ui_duration "$seconds")" "$MONARCHY_UI_OFF"
}

monarchy_ui_duration() {
    local s=$1
    if [ "$s" -lt 60 ]; then
        printf '%ds' "$s"
    else
        printf '%dm %02ds' "$((s / 60))" "$((s % 60))"
    fi
}

# --- the ledger -----------------------------------------------------------

# Something on this box is different because of this run.
monarchy_changed() {
    MONARCHY_UI_CHANGED+=("$*")
    monarchy_log "$*"
}

# The first few of a list, then a count. A summary bullet is a glance: eight
# package names tell a reader what happened, thirty-one tell them to scroll.
# The log line that goes with the change has every name.
MONARCHY_UI_SUMMARY_NAMES=${MONARCHY_UI_SUMMARY_NAMES:-6}

monarchy_ui_some() {
    local extra=0 out
    if [ "$#" -gt "$MONARCHY_UI_SUMMARY_NAMES" ]; then
        extra=$(($# - MONARCHY_UI_SUMMARY_NAMES))
        set -- "${@:1:MONARCHY_UI_SUMMARY_NAMES}"
    fi
    out=$(printf '%s, ' "$@")
    out=${out%, }
    if [ "$extra" -gt 0 ]; then
        printf '%s and %d more' "$out" "$extra"
    else
        printf '%s' "$out"
    fi
}

# One change covering many names: `monarchy_changed_many installed \
# "pacman packages" ripgrep fd ...` reads as
# "installed 12 pacman packages: ripgrep, fd, … and 6 more".
monarchy_changed_many() {
    local verb=$1 noun=$2
    shift 2
    [ "$#" -gt 0 ] || return 0
    MONARCHY_UI_CHANGED+=("$verb $# $noun: $(monarchy_ui_some "$@")")
    monarchy_log "$verb $# $noun: $*"
}

# Monarchy found a local decision and let it stand. This is the entry that
# exists because of the plugin bug: a thing monarchy deliberately did not do
# is an outcome, and silence made it indistinguishable from not looking.
monarchy_left_alone() {
    MONARCHY_UI_LEFT+=("$*")
    monarchy_log "left alone: $*"
}

# Warnings are collected by monarchy_log itself, from the `warning:` prefix
# nineteen call sites already used, so no caller has to remember two calls.
monarchy_warn() {
    monarchy_log "warning: $*"
}

monarchy_ui_note_warning() {
    MONARCHY_UI_WARNED+=("${1#warning: }")
}

monarchy_ui_list() {
    local colour=$1 heading=$2
    shift 2
    [ "$#" -gt 0 ] || return 0
    printf '\n  %s%s (%d)%s\n' "$colour" "$heading" "$#" "$MONARCHY_UI_OFF"
    local line
    for line in "$@"; do
        printf '    %s·%s %s\n' "$MONARCHY_UI_DIM" "$MONARCHY_UI_OFF" "$line"
    done
}

# Printed once, from an EXIT trap, so a run that dies partway still reports
# what it managed to change before it stopped. Guarded against running twice.
monarchy_summary() {
    [ "${MONARCHY_UI_SUMMARISED:-0}" = 0 ] || return 0
    MONARCHY_UI_SUMMARISED=1
    local elapsed=$((SECONDS - MONARCHY_UI_STARTED))

    monarchy_section "Summary"
    if [ "${#MONARCHY_UI_CHANGED[@]}" -eq 0 ] \
        && [ "${#MONARCHY_UI_LEFT[@]}" -eq 0 ] \
        && [ "${#MONARCHY_UI_WARNED[@]}" -eq 0 ]; then
        printf '\n  Nothing changed.\n'
    fi
    monarchy_ui_list "$MONARCHY_UI_GREEN" Changed "${MONARCHY_UI_CHANGED[@]}"
    monarchy_ui_list "$MONARCHY_UI_BOLD" "Left alone" "${MONARCHY_UI_LEFT[@]}"
    monarchy_ui_list "$MONARCHY_UI_YELLOW" Warnings "${MONARCHY_UI_WARNED[@]}"

    if [ "${#MONARCHY_UI_LEFT[@]}" -gt 0 ]; then
        printf '\n  %sLeft alone is not a failure: monarchy seeds, it does not\n' "$MONARCHY_UI_DIM"
        printf '  switch anything back on that was switched off here.%s\n' "$MONARCHY_UI_OFF"
    fi

    printf '\n  %s%d steps · %s%s\n' \
        "$MONARCHY_UI_DIM" "$MONARCHY_UI_STEPS" \
        "$(monarchy_ui_duration "$elapsed")" "$MONARCHY_UI_OFF"
}
