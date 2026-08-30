# shellcheck shell=bash
# System76 Bonobo WS. DMI product_name is the Clevo board id "bonw9".
# Also match vendor System76 + family Bonobo so a firmware rename still hits.

bonw9_dmi() {
    local file=/sys/class/dmi/id/$1
    if [ -r "$file" ]; then
        tr -d '\n' <"$file"
    fi
}

bonw9_detected() {
    local vendor product family
    product=$(bonw9_dmi product_name)
    [ "$product" = "bonw9" ] && return 0

    vendor=$(bonw9_dmi sys_vendor)
    family=$(bonw9_dmi product_family)
    case "$vendor" in
        System76|system76) ;;
        *) return 1 ;;
    esac
    case "$family" in
        *Bonobo*|*bonobo*) return 0 ;;
    esac
    return 1
}
