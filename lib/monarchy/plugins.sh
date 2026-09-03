# shellcheck shell=bash
# Sourced into one shell by lib/monarchy.sh; common.sh state is in scope.
# shellcheck disable=SC2153

monarchy_plugin_user_dir() {
    printf '%s\n' "$HOME/.config/omarchy/plugins"
}

monarchy_plugin_shell_json() {
    printf '%s\n' "$HOME/.config/omarchy/shell.json"
}

monarchy_plugin_default_shell_json() {
    if [ -f "$MONARCHY_PATH/config/omarchy/shell.json" ]; then
        printf '%s\n' "$MONARCHY_PATH/config/omarchy/shell.json"
        return 0
    fi
    if [ -f "$MONARCHY_SRC/config/omarchy/shell.json" ]; then
        printf '%s\n' "$MONARCHY_SRC/config/omarchy/shell.json"
        return 0
    fi
    monarchy_die "missing default shell.json under $MONARCHY_PATH or $MONARCHY_SRC"
}

monarchy_check_plugins() {
    local file="$MONARCHY_MISC/plugins"
    local line url rest flag
    [ -f "$file" ] || monarchy_die "missing $file"
    while IFS= read -r line; do
        read -r url rest <<<"$line"
        [ -n "$url" ] || continue
        case "$url" in
            --*) monarchy_die "plugin line missing git URL: $line" ;;
        esac
        # shellcheck disable=SC2086
        for flag in $rest; do
            case "$flag" in
                --enable) ;;
                *) monarchy_die "unknown plugin flag '$flag' for $url" ;;
            esac
        done
    done < <(monarchy_load_list "$file")
}

monarchy_plugin_id_from_dir() {
    local dir=$1
    [ -f "$dir/manifest.json" ] || monarchy_die "missing $dir/manifest.json"
    local id
    id=$(jq -r '.id // empty' "$dir/manifest.json")
    [ -n "$id" ] || monarchy_die "empty plugin id in $dir/manifest.json"
    printf '%s\n' "$id"
}

monarchy_validate_plugin_dir() {
    local dir=$1
    local validate="$MONARCHY_PATH/bin/omarchy-plugin-validate"
    if [ -x "$validate" ]; then
        "$validate" "$dir" || monarchy_die "plugin validation failed: $dir"
        return 0
    fi
    [ -f "$dir/manifest.json" ] || monarchy_die "missing $dir/manifest.json"
    jq -e '.schemaVersion == 1 and (.id | type == "string" and length > 0)' \
        "$dir/manifest.json" >/dev/null \
        || monarchy_die "invalid plugin manifest: $dir/manifest.json"
}

monarchy_plugin_dir_for_url() {
    local url=$1
    local plugins_dir remote dir
    plugins_dir=$(monarchy_plugin_user_dir)
    [ -d "$plugins_dir" ] || return 1
    for dir in "$plugins_dir"/*/; do
        [ -d "$dir" ] || continue
        [ -d "$dir/.git" ] || continue
        remote=$(git -C "$dir" remote get-url origin 2>/dev/null || true)
        if [ "$remote" = "$url" ]; then
            printf '%s\n' "${dir%/}"
            return 0
        fi
    done
    return 1
}

monarchy_seed_shell_json() {
    local dest src
    dest=$(monarchy_plugin_shell_json)
    if [ -f "$dest" ]; then
        return 0
    fi
    src=$(monarchy_plugin_default_shell_json)
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
    monarchy_log "seeded $dest from $src"
}

# A whole replacement bar, rather than a widget that takes a place in one.
# Those are switched with `omarchy bar use`, which only a live shell can do,
# so --enable on one is refused instead of written wrongly.
monarchy_plugin_is_bar() {
    local dir=$1
    jq -e '((.kinds // []) | index("bar")) != null' \
        "$dir/manifest.json" >/dev/null 2>&1
}

# The bar section a widget asks for, or nothing when the plugin is not a bar
# widget. Mirrors PluginRegistry.defaultBarWidgetSection: an absent or
# unrecognised defaultSection means center.
monarchy_plugin_bar_section() {
    local dir=$1
    local manifest="$dir/manifest.json"
    [ -f "$manifest" ] || monarchy_die "missing $manifest"
    jq -r '
        if ((.kinds // []) | index("bar-widget")) == null then ""
        else
            (.barWidget.defaultSection // "center")
            | if . == "left" or . == "center" or . == "right" then .
              else "center" end
        end
    ' "$manifest"
}

# The shape every writer below assumes, and the same guarantee the shell makes
# in PluginRegistry.ensureConfigShape. An existing version is kept rather than
# overwritten: it is the config's, not ours to set on every apply.
MONARCHY_SHELL_JSON_SHAPE='
      .version = (.version // 1)
    | .bar = (.bar // {})
    | .bar.layout = (.bar.layout // {})
    | .bar.layout.left = (.bar.layout.left // [])
    | .bar.layout.center = (.bar.layout.center // [])
    | .bar.layout.right = (.bar.layout.right // [])
    | .plugins = (.plugins // [])
'

# Place a bar widget. Reads shell.json on stdin, writes it on stdout.
#
# Insert just after the section's anchor, which is where the shell puts a
# widget enabled with no placement of its own (PluginRegistry.barTarget). A
# widget already anywhere in the bar is left exactly as it is, position and
# settings included: apply must not undo a hand placement.
#
# The plugins[] row is dropped either way. For a widget it was never right --
# the shell records a widget in bar.layout and nowhere else -- and while the
# row is there, findEntryLocation reads the widget as already recorded, so
# both `omarchy plugin enable` and `omarchy bar put` quietly decline to place
# it. Dropping it here is what migrates a shell.json an older monarchy wrote.
monarchy_shell_json_place_widget() {
    local id=$1
    local section=$2
    # shellcheck disable=SC2016  # $id and $section are jq's own, bound by --arg
    local program='
def entry_id: if type == "object" then (.id // "") else . end;
def anchors: {
    "left": "omarchy.workspaces",
    "center": "omarchy.weather",
    "right": "omarchy.tray"
};
def bar_ids:
    [(.bar.layout.left[]?), (.bar.layout.center[]?), (.bar.layout.right[]?)]
    | map(entry_id);
  .plugins = (.plugins | map(select((.id // "") != $id)))
| if (bar_ids | index($id)) then .
  else
    (.bar.layout[$section]) as $entries
    | ([$entries | to_entries[]
        | select(.value | entry_id == anchors[$section]) | .key] | first) as $anchor
    | (if $anchor == null then ($entries | length) else $anchor + 1 end) as $at
    | .bar.layout[$section] = ($entries[0:$at] + [{"id": $id}] + $entries[$at:])
  end
'
    jq --arg id "$id" --arg section "$section" \
        "$MONARCHY_SHELL_JSON_SHAPE | $program"
}

# Record a panel, overlay, menu or service. Reads shell.json on stdin, writes
# it on stdout. shell.json holds only the deviation from the built-ins, so a
# third-party plugin is a plugins[] row and nothing more.
monarchy_shell_json_add_plugin() {
    local id=$1
    # shellcheck disable=SC2016  # $id and $section are jq's own, bound by --arg
    local program='
  if any(.plugins[]?; .id == $id) then .
  else .plugins += [{"id": $id}]
  end
'
    jq --arg id "$id" "$MONARCHY_SHELL_JSON_SHAPE | $program"
}

monarchy_enable_plugin() {
    local id=$1
    local dir=$2
    local dest tmp section
    [ -n "$id" ] || monarchy_die "plugin id is required"
    [ -n "$dir" ] || monarchy_die "plugin directory is required for $id"
    if monarchy_plugin_is_bar "$dir"; then
        monarchy_die "plugin $id replaces the bar rather than taking a place in one; switch to it from a live session with: omarchy bar use $id"
    fi
    section=$(monarchy_plugin_bar_section "$dir")
    monarchy_seed_shell_json
    dest=$(monarchy_plugin_shell_json)
    # Same directory, so the mv below is an atomic rename. A live shell
    # watches this file and a cross-filesystem copy is one it can catch
    # half-written.
    tmp=$(mktemp "$dest.XXXXXX")
    if [ -n "$section" ]; then
        if ! monarchy_shell_json_place_widget "$id" "$section" <"$dest" >"$tmp"; then
            rm -f "$tmp"
            monarchy_die "failed to place widget $id in $dest"
        fi
        mv "$tmp" "$dest"
        monarchy_log "placed widget $id in the $section of the bar"
    else
        if ! monarchy_shell_json_add_plugin "$id" <"$dest" >"$tmp"; then
            rm -f "$tmp"
            monarchy_die "failed to enable plugin $id in $dest"
        fi
        mv "$tmp" "$dest"
        monarchy_log "enabled plugin $id"
    fi
}

monarchy_install_one_plugin() {
    local url=$1
    local enable=${2:-0}
    local plugins_dir dest stage id dir
    plugins_dir=$(monarchy_plugin_user_dir)
    mkdir -p "$plugins_dir"

    dir=""
    if dir=$(monarchy_plugin_dir_for_url "$url"); then
        id=$(monarchy_plugin_id_from_dir "$dir")
        monarchy_log "plugin $id already installed"
    else
        stage=$(mktemp -d)
        export GIT_TERMINAL_PROMPT=0
        if ! git clone -- "$url" "$stage" >/dev/null 2>&1; then
            rm -rf "$stage"
            monarchy_die "failed to clone plugin $url"
        fi
        monarchy_validate_plugin_dir "$stage"
        id=$(monarchy_plugin_id_from_dir "$stage")
        dest="$plugins_dir/$id"
        if [ -e "$dest" ] || [ -L "$dest" ]; then
            rm -rf "$stage"
            monarchy_log "plugin $id already installed"
        else
            mv "$stage" "$dest"
            monarchy_log "added plugin $id from $url"
        fi
        dir="$dest"
    fi

    if [ "$enable" = 1 ]; then
        monarchy_enable_plugin "$id" "$dir"
    fi
}

monarchy_install_plugins() {
    local file="$MONARCHY_MISC/plugins"
    local line url rest flag enable
    export OMARCHY_PATH
    export PATH="$MONARCHY_PATH/bin:${PATH:-/usr/bin}"
    monarchy_check_plugins
    while IFS= read -r line; do
        read -r url rest <<<"$line"
        [ -n "$url" ] || continue
        enable=0
        # shellcheck disable=SC2086
        for flag in $rest; do
            case "$flag" in
                --enable) enable=1 ;;
            esac
        done
        monarchy_install_one_plugin "$url" "$enable"
    done < <(monarchy_load_list "$file")
    # A live shell reloads shell.json on its own, so the offline write above
    # is all a running session needs; the rescan is for a plugin directory
    # that appeared since the shell last looked.
    if [ -x "$MONARCHY_PATH/bin/omarchy-shell" ]; then
        "$MONARCHY_PATH/bin/omarchy-shell" -q shell rescanPlugins || true
    fi
}
