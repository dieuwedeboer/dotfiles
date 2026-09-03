# shellcheck shell=bash
# The arrays below are read by overlay.sh, packages.sh and update.sh.
# shellcheck disable=SC2034

monarchy_load_list() {
    local file=$1
    [ -f "$file" ] || monarchy_die "missing $file"
    grep -vE '^[[:space:]]*(#|$)' "$file"
}

monarchy_load_inventories() {
    mapfile -t MONARCHY_BIN_ALLOW < <(monarchy_load_list "$MONARCHY_MISC/bin.allow")
    mapfile -t MONARCHY_BIN_WRAP < <(monarchy_load_list "$MONARCHY_MISC/bin.wrap")
    mapfile -t MONARCHY_BIN_DENY < <(monarchy_load_list "$MONARCHY_MISC/bin.deny")
    mapfile -t MONARCHY_PKG_DENY < <(monarchy_load_list "$MONARCHY_MISC/packages.deny")
    mapfile -t MONARCHY_MIGRATE_DENY < <(monarchy_load_list "$MONARCHY_MISC/migrations.deny")
    mapfile -t MONARCHY_APP_DROP < <(monarchy_load_list "$MONARCHY_MISC/applications.drop")
}

monarchy_in_list() {
    local needle=$1
    shift
    local item
    for item in "$@"; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

monarchy_inventory_has() {
    local name=$1
    monarchy_in_list "$name" "${MONARCHY_BIN_ALLOW[@]}" \
        || monarchy_in_list "$name" "${MONARCHY_BIN_WRAP[@]}" \
        || monarchy_in_list "$name" "${MONARCHY_BIN_DENY[@]}"
}
