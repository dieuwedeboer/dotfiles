# shellcheck shell=bash
# True when firmware lists GPP0 as an ACPI wakeup source.
# Kingfisher's Gigabyte B550 enables this and it wakes from USB noise.

gpp0_wakeup_detected() {
    [ -r /proc/acpi/wakeup ] || return 1
    grep -q '^GPP0' /proc/acpi/wakeup
}
