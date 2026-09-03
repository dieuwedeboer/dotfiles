#!/usr/bin/env bash
# No personal names in the repo. See the No names rule in AGENTS.md.
#
# The names come from /etc/monarchy/users.conf on this box, so this test holds
# none itself: it works in a fork, for whoever lives there, without knowing who
# that is. With no users.conf there is nothing to check and the test is a no-op
# rather than a false pass, which it says out loud.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"

conf=${MONARCHY_USERS_CONF:-/etc/monarchy/users.conf}

# chezmoi/ is the user's own home directory content and is out of scope:
# a dotfile that greets its owner by name is not a leak of anyone else.
scan=(lib monarchy docs tests install.sh README.md AGENTS.md CONTEXT.md)

if [ ! -f "$conf" ]; then
    echo "no-names: no $conf, nothing to check (run monarchy-user-setup)"
    exit 0
fi

names=$(grep -vE '^[[:space:]]*(#|$)' "$conf" | awk '{print $1}' | sort -u)
[ -n "$names" ] || { echo "no-names: $conf lists no accounts"; exit 0; }

found=0
while read -r name; do
    [ -n "$name" ] || continue
    # A role word is not a name: king/queen/kid/serf are the placeholders the
    # repo is supposed to use, and users.conf.example uses them as usernames.
    case "$name" in
        king | queen | kid | serf | kid[0-9]*) continue ;;
    esac
    hits=$(grep -rniE "\\b${name}\\b" "${scan[@]}" 2>/dev/null \
        | grep -v '^docs/plans/monarchy-hardening.md' || true)
    if [ -n "$hits" ]; then
        printf '%s\n' "$hits" | sed 's/^/  /' >&2
        found=1
    fi
done <<<"$names"

[ "$found" = 0 ] || fail "an account name from $conf appears in the repo"
echo "no-names: clean"
