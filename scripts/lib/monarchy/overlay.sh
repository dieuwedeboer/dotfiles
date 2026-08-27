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
