#!/usr/bin/env bash
# Run the whole suite. No sudo. Nothing here writes under /etc or /usr.
#
# This is the gate to run before any apply. There is no canary box and
# zfs-snapshot-pre-update keeps only three snapshots, so an apply is an
# expensive way to find a bug that a test can find for free.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$TESTS_DIR/.." && pwd)"

pass=0
fail=0
failed=()

for t in "$TESTS_DIR"/*/test-*.sh; do
    [ -f "$t" ] || continue
    name="${t#"$TESTS_DIR"/}"
    if out=$(bash "$t" 2>&1); then
        printf '  ok    %s\n' "$name"
        pass=$((pass + 1))
    else
        printf '  FAIL  %s\n' "$name"
        printf '%s\n' "$out" | sed 's/^/          /'
        fail=$((fail + 1))
        failed+=("$name")
    fi
done

if command -v shellcheck >/dev/null 2>&1; then
    mapfile -t sh_files < <(
        find "$REPO/lib" "$REPO/tests" "$REPO/hardware" -name '*.sh' -type f
        printf '%s\n' "$REPO/install.sh"
    )
    if shellcheck -x -e SC1091 "${sh_files[@]}"; then
        printf '  ok    shellcheck\n'
        pass=$((pass + 1))
    else
        printf '  FAIL  shellcheck\n'
        fail=$((fail + 1))
        failed+=(shellcheck)
    fi
else
    printf '  skip  shellcheck (not installed)\n'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if [ "$fail" -ne 0 ]; then
    printf 'failed: %s\n' "${failed[*]}"
    exit 1
fi
