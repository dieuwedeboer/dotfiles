# shellcheck shell=bash
# HP ZBook DMI probe. Source this file; do not execute it.
#
# True for this 14u G6 and for later ZBooks (Ultra, Firefly, Fury, …) as
# long as the vendor is HP and "ZBook" appears in product_name or
# product_family. EliteBook / ProBook stay out.

zbook_dmi_root() {
    printf '%s\n' "${ZBOOK_DMI:-/sys/class/dmi/id}"
}

zbook_dmi_field() {
    local file
    file="$(zbook_dmi_root)/$1"
    if [ -r "$file" ]; then
        tr -d '\n' <"$file"
    fi
}

zbook_detected() {
    local vendor product family
    vendor=$(zbook_dmi_field sys_vendor)
    product=$(zbook_dmi_field product_name)
    family=$(zbook_dmi_field product_family)

    case "$vendor" in
        HP | Hewlett-Packard) ;;
        *) return 1 ;;
    esac

    case "$product $family" in
        *[Zz][Bb]ook*) return 0 ;;
    esac
    return 1
}
