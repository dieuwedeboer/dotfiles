# shellcheck shell=bash

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

monarchy_enable_plugin() {
    local id=$1
    local dest tmp
    [ -n "$id" ] || monarchy_die "plugin id is required"
    monarchy_seed_shell_json
    dest=$(monarchy_plugin_shell_json)
    tmp=$(mktemp)
    if ! jq --arg id "$id" '
        .version = 1
        | .plugins = (.plugins // [])
        | if any(.plugins[]?; .id == $id) then .
          else .plugins += [{"id": $id}]
          end
    ' "$dest" >"$tmp"; then
        rm -f "$tmp"
        monarchy_die "failed to enable plugin $id in $dest"
    fi
    mv "$tmp" "$dest"
}

monarchy_install_one_plugin() {
    local url=$1
    local enable=${2:-0}
    local plugins_dir dest stage id existing
    plugins_dir=$(monarchy_plugin_user_dir)
    mkdir -p "$plugins_dir"

    existing=""
    if existing=$(monarchy_plugin_dir_for_url "$url"); then
        id=$(monarchy_plugin_id_from_dir "$existing")
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
    fi

    if [ "$enable" = 1 ]; then
        monarchy_enable_plugin "$id"
        monarchy_log "enabled plugin $id"
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
    if [ -x "$MONARCHY_PATH/bin/omarchy-shell" ]; then
        "$MONARCHY_PATH/bin/omarchy-shell" -q shell rescanPlugins || true
    fi
}
