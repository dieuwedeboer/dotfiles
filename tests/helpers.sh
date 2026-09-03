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

# Every monarchy_* name that check or apply reaches, following the unit verbs
# in MONARCHY_UNITS. Tests assert against this rather than against the literal
# body of monarchy_apply, which is now a loop.
monarchy_reaches() {
    local verb=$1
    python3 - "$LIB/update.sh" "$verb" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
verb = sys.argv[2]
units = re.search(r"MONARCHY_UNITS=\(([^)]*)\)", src).group(1).split()

def body(fn):
    m = re.search(rf"^{fn}\(\) \{{(.*)\}}\s*$", src, re.M)
    if m and "\n" not in m.group(1):
        return m.group(1)
    m = re.search(rf"^{fn}\(\) \{{\n(.*?)^\}}", src, re.S | re.M)
    return m.group(1) if m else ""

seen, out = set(), set()
def walk(fn):
    if fn in seen:
        return
    seen.add(fn)
    for name in re.findall(r"monarchy_[a-z_]+", body(fn)):
        out.add(name)
        walk(name)

walk(f"monarchy_{verb}")
for u in units:
    walk(f"monarchy_{u}_check")
    if verb == "apply":
        walk(f"monarchy_{u}_apply")
print("\n".join(sorted(out)))
PY
}
