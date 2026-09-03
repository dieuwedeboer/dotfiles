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


# The clone is the thing most of these tests compare the overlay against.
# test-overlay.sh has always required it; without this the lock and
# switch-user tests skip their drift checks and still print "passed", which
# is worse than not running them.
require_clone() {
    local clone=${1:-$MONARCHY_SRC_DEFAULT}
    [ -d "$clone" ] \
        || fail "no clone at $clone; run ./install.sh --check first, or pass one as \$1"
    printf '%s\n' "$clone"
}

MONARCHY_SRC_DEFAULT="${MONARCHY_SRC:-/usr/local/src/monarchy/omarchy}"
