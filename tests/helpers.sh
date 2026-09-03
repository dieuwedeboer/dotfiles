# shellcheck shell=bash
# Shared paths for the suite. Source this first, before any lib file.
#
# Tests run the real functions against temp prefixes. They never sudo, never
# write under /etc or /usr, and never call mkinitcpio or systemctl.

_helpers_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$_helpers_dir/.." && pwd)
unset _helpers_dir

# Consumed by the tests that source this file.
# shellcheck disable=SC2034
LIB="$REPO/lib/monarchy"
# shellcheck disable=SC2034
ZBM_LIB="$REPO/lib/zbm"
# shellcheck disable=SC2034
MISC="$REPO/monarchy"
# shellcheck disable=SC2034
HARDWARE="$REPO/hardware"

# Named after the sourcing test file, so failures say which test spoke.
TEST_NAME=$(basename "${BASH_SOURCE[1]:-test}" .sh)

fail() {
    echo "$TEST_NAME: $*" >&2
    exit 1
}
