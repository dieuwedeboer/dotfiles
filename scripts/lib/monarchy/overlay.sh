# shellcheck shell=bash

monarchy_wrap_stub_for() {
    local name=$1
    case "$name" in
        omarchy-update|omarchy-update-system-pkgs)
            printf '%s\n' "$monarchy_lib_dir/stubs/wrap-update.sh"
            ;;
        omarchy-plymouth-set|omarchy-plymouth-reset|omarchy-refresh-plymouth)
            printf '%s\n' "$monarchy_lib_dir/stubs/wrap-plymouth.sh"
            ;;
        omarchy-refresh-sddm)
            printf '%s\n' "$monarchy_lib_dir/stubs/wrap-sddm.sh"
            ;;
        omarchy-screensaver)
            printf '%s\n' "$monarchy_lib_dir/stubs/wrap-screensaver.sh"
            ;;
        *)
            monarchy_die "no wrap stub for $name"
            ;;
    esac
}

monarchy_rebuild_overlay() {
    local dest="$MONARCHY_PATH/bin"
    local src_bin="$MONARCHY_SRC/bin"
    local stub="$monarchy_lib_dir/stubs/deny.sh"
    local yay="$monarchy_lib_dir/stubs/yay.sh"
    local name parent wrap_stub

    [ -d "$src_bin" ] || monarchy_die "clone bin/ missing at $src_bin"
    [ -f "$stub" ] || monarchy_die "missing $stub"

    monarchy_log "rebuild overlay $dest"
    parent=$(dirname "$dest")
    if [ -w "$parent" ] 2>/dev/null; then
        mkdir -p "$dest"
        find "$dest" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
        for name in "${MONARCHY_BIN_DENY[@]}"; do
            install -m 755 "$stub" "$dest/$name"
        done
        for name in "${MONARCHY_BIN_ALLOW[@]}"; do
            [ -e "$src_bin/$name" ] || monarchy_die "allowlisted $name missing from clone bin/"
            ln -sfn "$src_bin/$name" "$dest/$name"
        done
        for name in "${MONARCHY_BIN_WRAP[@]}"; do
            wrap_stub=$(monarchy_wrap_stub_for "$name")
            [ -f "$wrap_stub" ] || monarchy_die "missing $wrap_stub"
            install -m 755 "$wrap_stub" "$dest/$name"
        done
        install -m 755 "$yay" "$dest/yay"
    else
        monarchy_sudo mkdir -p "$dest"
        monarchy_sudo find "$dest" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
        for name in "${MONARCHY_BIN_DENY[@]}"; do
            monarchy_sudo install -m 755 "$stub" "$dest/$name"
        done
        for name in "${MONARCHY_BIN_ALLOW[@]}"; do
            [ -e "$src_bin/$name" ] || monarchy_die "allowlisted $name missing from clone bin/"
            monarchy_sudo ln -sfn "$src_bin/$name" "$dest/$name"
        done
        for name in "${MONARCHY_BIN_WRAP[@]}"; do
            wrap_stub=$(monarchy_wrap_stub_for "$name")
            [ -f "$wrap_stub" ] || monarchy_die "missing $wrap_stub"
            monarchy_sudo install -m 755 "$wrap_stub" "$dest/$name"
        done
        monarchy_sudo install -m 755 "$yay" "$dest/yay"
    fi

    if [ "${MONARCHY_INSTALL_SUDO_STUBS:-1}" = 1 ]; then
        monarchy_sudo mkdir -p /usr/local/bin
        for name in "${MONARCHY_BIN_DENY[@]}"; do
            monarchy_sudo install -m 755 "$stub" "/usr/local/bin/$name"
        done
        for name in "${MONARCHY_BIN_WRAP[@]}"; do
            wrap_stub=$(monarchy_wrap_stub_for "$name")
            monarchy_sudo install -m 755 "$wrap_stub" "/usr/local/bin/$name"
        done
        for name in "${MONARCHY_BIN_ALLOW[@]}"; do
            [ -e "$src_bin/$name" ] || monarchy_die "allowlisted $name missing from clone bin/"
            monarchy_sudo ln -sfn "$src_bin/$name" "/usr/local/bin/$name"
        done
        monarchy_sudo ln -sfn "$MONARCHY_SETUP" /usr/local/bin/setup-monarchy
    fi
}

monarchy_check_clone_bin_classified() {
    local name new=0
    local src_bin="$MONARCHY_SRC/bin"
    [ -d "$src_bin" ] || monarchy_die "clone bin/ missing at $src_bin"
    while IFS= read -r -d '' name; do
        name=$(basename "$name")
        if ! monarchy_inventory_has "$name"; then
            echo "unclassified bin name (new relative to lock): $name" >&2
            new=1
        fi
    done < <(find "$src_bin" -maxdepth 1 -type f -print0)
    [ "$new" = 0 ] || monarchy_die "clone bin/ has names not in allow/wrap/deny"
    return 0
}

monarchy_check_inventory_complete() {
    local src_bin="$MONARCHY_SRC/bin"
    local n clone_n
    n=$((${#MONARCHY_BIN_ALLOW[@]} + ${#MONARCHY_BIN_WRAP[@]} + ${#MONARCHY_BIN_DENY[@]}))
    clone_n=$(find "$src_bin" -maxdepth 1 -type f | wc -l)
    [ "$n" -eq "$clone_n" ] || monarchy_die "inventory has $n names, clone bin/ has $clone_n"
}

monarchy_overlay_lock_py() {
    printf '%s\n' "$monarchy_lib_dir/overlay-lock.py"
}

# Turn a prefix symlink-to-dir into a real directory of child symlinks so a
# single file can be replaced without writing into the clone.
monarchy_explode_symlink_dir() {
    local dest=$1
    local target name tmp
    [ -L "$dest" ] || return 0
    target=$(readlink -f "$dest")
    [ -d "$target" ] || monarchy_die "expected directory behind $dest"
    tmp=$(mktemp -d)
    for name in "$target"/*; do
        [ -e "$name" ] || continue
        ln -sfn "$name" "$tmp/$(basename "$name")"
    done
    if [ -w "$(dirname "$dest")" ] 2>/dev/null; then
        rm -f "$dest"
        mkdir -p "$dest"
        mv "$tmp"/* "$dest"/
        rmdir "$tmp"
    else
        monarchy_sudo rm -f "$dest"
        monarchy_sudo mkdir -p "$dest"
        monarchy_sudo mv "$tmp"/* "$dest"/
        rmdir "$tmp" 2>/dev/null || true
    fi
}

monarchy_overlay_replace_dir() {
    local dest=$1
    local src_copy=$2
    if [ -w "$(dirname "$dest")" ] 2>/dev/null; then
        rm -rf "$dest"
        mv "$src_copy" "$dest"
    else
        monarchy_sudo rm -rf "$dest"
        monarchy_sudo mv "$src_copy" "$dest"
    fi
}

monarchy_overlay_replace_file() {
    local dest=$1
    local src_copy=$2
    if [ -w "$(dirname "$dest")" ] 2>/dev/null; then
        rm -f "$dest"
        mv "$src_copy" "$dest"
    else
        monarchy_sudo rm -f "$dest"
        monarchy_sudo mv "$src_copy" "$dest"
    fi
}

monarchy_check_session_lock_overlay() {
    local py lock_dir menu
    py=$(monarchy_overlay_lock_py)
    [ -f "$py" ] || monarchy_die "missing $py"
    lock_dir="$MONARCHY_SRC/shell/plugins/lock"
    menu="$MONARCHY_SRC/default/omarchy/omarchy-menu.jsonc"
    [ -f "$lock_dir/LockView.qml" ] || monarchy_die "clone lock plugin missing"
    [ -f "$menu" ] || monarchy_die "clone omarchy-menu.jsonc missing"
    python3 "$py" check lock "$lock_dir" || monarchy_die "lock QML overlay no longer applies"
    python3 "$py" check menu "$menu" || monarchy_die "menu overlay no longer applies"
}

# Copy-and-patch lock plugin + system menu. Prefix must already be linked.
monarchy_overlay_session_lock() {
    local py lock_src plugins_tmp menu_src menu_dest menu_tmp
    py=$(monarchy_overlay_lock_py)
    lock_src="$MONARCHY_SRC/shell/plugins/lock"
    menu_src="$MONARCHY_SRC/default/omarchy/omarchy-menu.jsonc"
    [ -d "$lock_src" ] || monarchy_die "missing $lock_src"
    [ -f "$menu_src" ] || monarchy_die "missing $menu_src"

    monarchy_explode_symlink_dir "$MONARCHY_PATH/shell"
    # Copy the whole plugins tree. PluginRegistry finds manifests with
    # `find -type f` and does not follow directory symlinks, so exploding
    # plugins/ into child-dir-symlinks hides wallpaper, menu, and the rest.
    # Only lock/ is patched; the copy keeps the clone itself untouched.
    plugins_tmp=$(mktemp -d)
    cp -a "$MONARCHY_SRC/shell/plugins"/. "$plugins_tmp"/
    python3 "$py" apply lock "$plugins_tmp/lock" || {
        rm -rf "$plugins_tmp"
        monarchy_die "lock QML overlay failed"
    }
    monarchy_overlay_replace_dir "$MONARCHY_PATH/shell/plugins" "$plugins_tmp"
    monarchy_log "overlaid $MONARCHY_PATH/shell/plugins/lock"

    monarchy_explode_symlink_dir "$MONARCHY_PATH/default"
    monarchy_explode_symlink_dir "$MONARCHY_PATH/default/omarchy"
    menu_dest="$MONARCHY_PATH/default/omarchy/omarchy-menu.jsonc"
    menu_tmp=$(mktemp)
    cp -a "$menu_src" "$menu_tmp"
    python3 "$py" apply menu "$menu_tmp" || {
        rm -f "$menu_tmp"
        monarchy_die "menu overlay failed"
    }
    monarchy_overlay_replace_file "$menu_dest" "$menu_tmp"
    monarchy_log "overlaid $menu_dest"
}

monarchy_install_switch_user() {
    local src="$monarchy_lib_dir/switch-user.sh"
    [ -f "$src" ] || monarchy_die "missing $src"
    monarchy_sudo install -m 755 "$src" /usr/local/bin/monarchy-switch-user
    monarchy_log "installed /usr/local/bin/monarchy-switch-user"
}
