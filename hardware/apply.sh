#!/usr/bin/env bash
# Run every hardware module. Each apply.sh self-gates on DMI or a device node.
set -e
[ "${VERBOSE:-0}" = 1 ] && set -x

HW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for apply in "$HW_ROOT"/*/apply.sh; do
    [ -f "$apply" ] || continue
    name=$(basename "$(dirname "$apply")")
    echo "=== Hardware: $name ==="
    bash "$apply"
done
