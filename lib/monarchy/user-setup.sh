#!/usr/bin/env bash
# Assign roles to the accounts on this box. Installed as
# /usr/local/bin/monarchy-user-setup. Interactive on purpose: creating
# accounts and setting passwords is not something an apply should do.
#
# Roles are defined in CONTEXT.md. The file this writes is never committed:
# usernames are personal information and the repo is public.
set -euo pipefail

CONF=${MONARCHY_USERS_CONF:-/etc/monarchy/users.conf}
ROLES="king queen kid serf"

as_root() { if [ "${EUID:-$(id -u)}" -eq 0 ]; then "$@"; else sudo "$@"; fi; }

current_role() {
    [ -f "$CONF" ] || return 0
    awk -v u="$1" '$1==u && $0 !~ /^[[:space:]]*#/ {print $2; exit}' "$CONF"
}

usage() {
    cat <<EOF
usage: monarchy-user-setup [--list]

  Walks every human account on this box and asks for its role.

    king   administers the box. One per machine.
    queen  co-adult, unrestricted, does not administer. One per machine.
    kid    supervised. Many.
    serf   anyone else, including guests. Many.

  An account left out is a serf, which is a valid state, not an error.
  Writes $CONF. Run 'monarchy-update' afterwards to apply it to the greeter.
EOF
}

case "${1:-}" in
    -h | --help) usage; exit 0 ;;
    --list)
        if [ ! -f "$CONF" ]; then
            echo "no $CONF; every account is a serf"
            exit 0
        fi
        printf '%-16s %s\n' USER ROLE
        grep -vE '^[[:space:]]*(#|$)' "$CONF" | while read -r u r _; do
            printf '%-16s %s\n' "$u" "$r"
        done
        exit 0
        ;;
    "") ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
esac

mapfile -t users < <(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1}' | sort)
[ "${#users[@]}" -gt 0 ] || { echo "no human accounts found" >&2; exit 1; }

echo "Roles: $ROLES"
echo "Enter to keep the current value, or leave blank for serf."
echo

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
{
    echo "# Written by monarchy-user-setup on $(date -I). Never commit this file."
    echo "# <username> <role>   roles: $ROLES"
} >"$tmp"

for u in "${users[@]}"; do
    cur=$(current_role "$u")
    while :; do
        printf '  %-16s role [%s]: ' "$u" "${cur:-serf}"
        read -r role </dev/tty || role=""
        role=${role:-${cur:-serf}}
        case " $ROLES " in
            *" $role "*) break ;;
            *) echo "    not a role. Pick one of: $ROLES" ;;
        esac
    done
    [ "$role" = serf ] && continue
    printf '%s %s\n' "$u" "$role" >>"$tmp"
done

as_root mkdir -p "$(dirname "$CONF")"
as_root install -m 644 "$tmp" "$CONF"
echo
echo "Wrote $CONF:"
grep -vE '^[[:space:]]*(#|$)' "$CONF" | sed 's/^/  /' || echo "  (all serfs)"
echo
echo "Set passwords for any new account with: passwd <user>"
echo "Then run monarchy-update so the greeter picks this up."
