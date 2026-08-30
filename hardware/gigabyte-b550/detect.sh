# shellcheck shell=bash
# Gigabyte B550 GAMING X V2 (kingfisher). it87, OpenRGB, CoolerControl.

gigabyte_b550_dmi() {
    local file=/sys/class/dmi/id/$1
    if [ -r "$file" ]; then
        tr -d '\n' <"$file"
    fi
}

gigabyte_b550_detected() {
    local vendor board product
    vendor=$(gigabyte_b550_dmi sys_vendor)
    board=$(gigabyte_b550_dmi board_name)
    product=$(gigabyte_b550_dmi product_name)

    case "$vendor" in
        *Gigabyte*|*GIGABYTE*) ;;
        *) return 1 ;;
    esac
    case "$board $product" in
        *B550*GAMING*X*) return 0 ;;
    esac
    return 1
}
