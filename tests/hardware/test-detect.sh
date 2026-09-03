#!/usr/bin/env bash
# DMI fixtures for zbook_detected. No sudo.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"
# shellcheck source=../../hardware/hp-zbook/detect.sh
source "$HARDWARE/hp-zbook/detect.sh"


dmi=$(mktemp -d)
trap 'rm -rf "$dmi"' EXIT
export ZBOOK_DMI=$dmi

write_dmi() {
    printf '%s' "$1" >"$dmi/sys_vendor"
    printf '%s' "$2" >"$dmi/product_name"
    printf '%s' "$3" >"$dmi/product_family"
}

write_dmi "HP" "HP ZBook 14u G6" "103C_5336AN HP ZBook"
zbook_detected || fail "14u G6 should match"

write_dmi "HP" "HP ZBook Ultra 14 inch G1a" "ZBook"
zbook_detected || fail "ZBook Ultra should match"

write_dmi "Hewlett-Packard" "HP ZBook Firefly 14 G8" ""
zbook_detected || fail "Hewlett-Packard vendor should match"

write_dmi "HP" "HP EliteBook 840 G6" "103C_5336AN HP EliteBook"
zbook_detected && fail "EliteBook should not match"

write_dmi "Gigabyte Technology Co., Ltd." "B550 GAMING X V2" ""
zbook_detected && fail "kingfisher should not match"

write_dmi "System76" "bonw9" "Oryx Pro"
zbook_detected && fail "bonw9 should not match"

echo "zbook detect tests passed"
