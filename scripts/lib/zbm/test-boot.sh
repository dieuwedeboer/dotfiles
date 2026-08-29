#!/usr/bin/env bash
# Cmdline merge and yaml edit. No sudo, no generate-zbm.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=boot.sh
source "$SCRIPT_DIR/boot.sh"

fail() {
    echo "test-boot: $*" >&2
    exit 1
}

got=$(zbm_merge_cmdline "rw quiet splash" "${ZBM_HOST_TOKENS[@]}")
[ "$got" = "rw quiet splash loglevel=0 systemd.show_status=false rd.udev.log_level=0 vt.global_cursor_default=0" ] \
    || fail "host merge got '$got'"

got=$(zbm_merge_cmdline "$got" "${ZBM_HOST_TOKENS[@]}")
[ "$got" = "rw quiet splash loglevel=0 systemd.show_status=false rd.udev.log_level=0 vt.global_cursor_default=0" ] \
    || fail "host merge not idempotent: '$got'"

got=$(zbm_merge_cmdline "rw quiet splash extra=1" loglevel=0)
[ "$got" = "rw quiet splash extra=1 loglevel=0" ] \
    || fail "should keep extra tokens: '$got'"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
cat >"$tmp" <<'EOF'
Global:
  ManageImages: true
Kernel:
  CommandLine: ro quiet loglevel=0
EOF

got=$(zbm_yaml_cmdline "$tmp")
[ "$got" = "ro quiet loglevel=0" ] || fail "yaml read got '$got'"

merged=$(zbm_merge_cmdline "$got" "${ZBM_IMAGE_TOKENS[@]}")
zbm_yaml_set_cmdline "$tmp" "$merged"
got=$(zbm_yaml_cmdline "$tmp")
[ "$got" = "ro quiet loglevel=0 vt.global_cursor_default=0 fbcon=logo-count:0 rd.udev.log_level=0" ] \
    || fail "yaml write got '$got'"

grep -q 'ManageImages: true' "$tmp" || fail "yaml write dropped Global"

echo "zbm boot tests passed"
