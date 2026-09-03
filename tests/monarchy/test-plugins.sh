#!/usr/bin/env bash
# shell.json placement policy. A bar widget's row belongs in bar.layout under
# the section its manifest asks for; a panel, overlay, menu or service belongs
# in plugins[]. The shell records a widget in one place only, and monarchy
# writes that file with no live shell to ask, so this is the test that catches
# the two drifting apart. No sudo, no network, no live shell.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"
# shellcheck source=../../lib/monarchy/common.sh
source "$LIB/common.sh"
# shellcheck source=../../lib/monarchy/denylist.sh
source "$LIB/denylist.sh"
# shellcheck source=../../lib/monarchy/plugins.sh
source "$LIB/plugins.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
HOME="$WORK/home"
export HOME
mkdir -p "$HOME/.config/omarchy"

SHELL_JSON="$HOME/.config/omarchy/shell.json"

# A stock-shaped bar: each section's anchor with widgets on both sides of it,
# so an insert that ignores the anchor lands somewhere the assertions notice.
write_shell_json() {
    cat >"$SHELL_JSON"
}

stock_shell_json() {
    cat <<'JSON'
{
  "version": 1,
  "bar": {
    "layout": {
      "left": [
        { "id": "omarchy.menu" },
        { "id": "omarchy.workspaces" }
      ],
      "center": [
        { "id": "omarchy.weather" },
        { "id": "omarchy.clock" }
      ],
      "right": [
        { "id": "omarchy.tray" },
        { "id": "omarchy.power" }
      ]
    }
  },
  "plugins": []
}
JSON
}

# $1 id, $2 kinds as a JSON array, $3 defaultSection or "" to omit it
make_plugin() {
    local id=$1 kinds=$2 section=${3:-}
    local dir="$WORK/plugins/$id"
    mkdir -p "$dir"
    if [ -n "$section" ]; then
        jq -n --arg id "$id" --argjson kinds "$kinds" --arg section "$section" \
            '{schemaVersion: 1, id: $id, kinds: $kinds, barWidget: {defaultSection: $section}}' \
            >"$dir/manifest.json"
    else
        jq -n --arg id "$id" --argjson kinds "$kinds" \
            '{schemaVersion: 1, id: $id, kinds: $kinds}' >"$dir/manifest.json"
    fi
    printf '%s\n' "$dir"
}

section_ids() {
    jq -r --arg s "$1" '[.bar.layout[$s][].id] | join(" ")' "$SHELL_JSON"
}

plugin_ids() {
    jq -r '[.plugins[].id] | join(" ")' "$SHELL_JSON"
}


# --- what the manifest asks for ------------------------------------------

widget=$(make_plugin acme.widget '["bar-widget"]' right)
[ "$(monarchy_plugin_bar_section "$widget")" = "right" ] \
    || fail "bar-widget with defaultSection right did not ask for right"

centred=$(make_plugin acme.centred '["bar-widget","service"]')
[ "$(monarchy_plugin_bar_section "$centred")" = "center" ] \
    || fail "a widget with no defaultSection must default to center"

odd=$(make_plugin acme.odd '["bar-widget"]' sideways)
[ "$(monarchy_plugin_bar_section "$odd")" = "center" ] \
    || fail "an unrecognised defaultSection must fall back to center"

service=$(make_plugin acme.service '["service"]')
[ -z "$(monarchy_plugin_bar_section "$service")" ] \
    || fail "a service is not a bar widget and has no section"

wholebar=$(make_plugin acme.neon-bar '["bar"]')
monarchy_plugin_is_bar "$wholebar" \
    || fail "a kinds:[bar] plugin was not recognised as a whole bar"
monarchy_plugin_is_bar "$widget" \
    && fail "a bar widget was mistaken for a whole bar"


# --- a widget lands in the bar, not in plugins[] -------------------------

stock_shell_json | write_shell_json
monarchy_enable_plugin acme.widget "$widget" >/dev/null

[ "$(section_ids right)" = "omarchy.tray acme.widget omarchy.power" ] \
    || fail "widget not placed after the right anchor: $(section_ids right)"
[ -z "$(plugin_ids)" ] \
    || fail "a bar widget must not get a plugins[] row: $(plugin_ids)"

# Twice is once. An apply runs on every update; it must not stack duplicates.
monarchy_enable_plugin acme.widget "$widget" >/dev/null
[ "$(section_ids right)" = "omarchy.tray acme.widget omarchy.power" ] \
    || fail "re-enabling duplicated the widget: $(section_ids right)"

stock_shell_json | write_shell_json
monarchy_enable_plugin acme.centred "$centred" >/dev/null
[ "$(section_ids center)" = "omarchy.weather acme.centred omarchy.clock" ] \
    || fail "sectionless widget not placed after the center anchor: $(section_ids center)"


# --- the anchor is a preference, not a requirement -----------------------

jq 'del(.bar.layout.right[] | select(.id == "omarchy.tray"))' <(stock_shell_json) \
    | write_shell_json
monarchy_enable_plugin acme.widget "$widget" >/dev/null
[ "$(section_ids right)" = "omarchy.power acme.widget" ] \
    || fail "with no anchor the widget must go to the end: $(section_ids right)"


# --- a hand placement survives an apply ----------------------------------

# Settings and position are the operator's, set through the live UI. Apply
# must leave both alone, which is why the insert is skipped rather than
# rewritten when the widget is already somewhere in the bar.
jq '.bar.layout.left += [{"id": "acme.widget", "samplingSpeed": "Efficient"}]' \
    <(stock_shell_json) | write_shell_json
monarchy_enable_plugin acme.widget "$widget" >/dev/null
[ "$(section_ids left)" = "omarchy.menu omarchy.workspaces acme.widget" ] \
    || fail "apply moved a hand-placed widget: $(section_ids left)"
[ "$(section_ids right)" = "omarchy.tray omarchy.power" ] \
    || fail "apply also placed the widget in its default section"
[ "$(jq -r '.bar.layout.left[] | select(.id == "acme.widget") | .samplingSpeed' \
    "$SHELL_JSON")" = "Efficient" ] \
    || fail "apply dropped a hand-set widget setting"


# --- migrating a shell.json an older monarchy wrote ----------------------

# The bogus plugins[] row is not merely useless: while it is there the shell
# reads the widget as already recorded, so `omarchy plugin enable` and
# `omarchy bar put` both decline to place it. Removing it is the migration.
jq '.plugins += [{"id": "acme.widget"}]' <(stock_shell_json) | write_shell_json
monarchy_enable_plugin acme.widget "$widget" >/dev/null
[ -z "$(plugin_ids)" ] \
    || fail "the stale plugins[] row was not dropped: $(plugin_ids)"
[ "$(section_ids right)" = "omarchy.tray acme.widget omarchy.power" ] \
    || fail "migration did not place the widget: $(section_ids right)"

# A widget already correctly in the bar, with the stale row alongside it.
jq '.bar.layout.right += [{"id": "acme.widget"}] | .plugins += [{"id": "acme.widget"}]' \
    <(stock_shell_json) | write_shell_json
monarchy_enable_plugin acme.widget "$widget" >/dev/null
[ -z "$(plugin_ids)" ] \
    || fail "stale row kept when the widget was already placed: $(plugin_ids)"
[ "$(section_ids right)" = "omarchy.tray omarchy.power acme.widget" ] \
    || fail "a placed widget was moved or duplicated: $(section_ids right)"


# --- everything else still goes to plugins[] -----------------------------

stock_shell_json | write_shell_json
monarchy_enable_plugin acme.service "$service" >/dev/null
[ "$(plugin_ids)" = "acme.service" ] \
    || fail "a service did not get a plugins[] row: $(plugin_ids)"
[ "$(section_ids right)" = "omarchy.tray omarchy.power" ] \
    || fail "a service was placed in the bar: $(section_ids right)"
monarchy_enable_plugin acme.service "$service" >/dev/null
[ "$(plugin_ids)" = "acme.service" ] \
    || fail "re-enabling a service duplicated its row: $(plugin_ids)"

# An existing version is the config's, not ours to reset on every apply.
jq '.version = 2' <(stock_shell_json) | write_shell_json
monarchy_enable_plugin acme.service "$service" >/dev/null
[ "$(jq -r '.version' "$SHELL_JSON")" = "2" ] \
    || fail "apply overwrote the shell.json version"


# --- a whole bar is refused rather than written wrongly ------------------

stock_shell_json | write_shell_json
if (monarchy_enable_plugin acme.neon-bar "$wholebar") >/dev/null 2>&1; then
    fail "a kinds:[bar] plugin must not be enabled offline"
fi
[ "$(plugin_ids)" = "" ] && [ "$(section_ids right)" = "omarchy.tray omarchy.power" ] \
    || fail "the refused bar still changed shell.json"

if (monarchy_enable_plugin acme.widget "") >/dev/null 2>&1; then
    fail "enable without a plugin directory must fail, not guess the kind"
fi


# --- the shipped list stays enable-able ----------------------------------

# Every row in monarchy/plugins must pass the flag check, and no row may name
# a plugin twice under two URLs.
monarchy_check_plugins || fail "monarchy/plugins does not pass its own check"
dupes=$(monarchy_load_list "$MISC/plugins" | awk '{print $1}' | sort | uniq -d)
[ -z "$dupes" ] || fail "monarchy/plugins lists a URL twice: $dupes"

echo "plugin placement tests passed"
