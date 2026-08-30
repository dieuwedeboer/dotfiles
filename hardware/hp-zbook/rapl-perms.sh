#!/usr/bin/env bash
# Called from udev when intel-rapl shows up. energy_uj is 0400 because of
# PLATYPUS; this box is a single-user laptop, so wheel can read package
# and psys counters without root. Not wall power (see hardware/hp-zbook/apply.sh).
set -euo pipefail

while IFS= read -r -d '' f; do
    chgrp wheel "$f" 2>/dev/null || continue
    chmod g+r "$f" 2>/dev/null || continue
done < <(find /sys/class/powercap -name energy_uj -print0 2>/dev/null || true)
