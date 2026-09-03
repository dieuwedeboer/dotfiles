# shellcheck shell=bash
# Sourced into one shell by lib/monarchy.sh; common.sh state is in scope.
# shellcheck disable=SC2153,SC2154
#
# Account roles. The repo holds what each role gets; the box holds who is who.
# Usernames never appear in this repo: they are personal information, the repo
# is public, and a name in here would break the moment an account is renamed.

MONARCHY_USERS_CONF="${MONARCHY_USERS_CONF:-/etc/monarchy/users.conf}"
MONARCHY_ROLES="king queen kid serf"

# Roles that get Plasma at the greeter. Everyone else takes the default,
# which is Omarchy. See "Session preference" in CONTEXT.md.
MONARCHY_PLASMA_ROLES="queen kid"

monarchy_valid_role() {
    case " $MONARCHY_ROLES " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

# Emit "<username> <role>" per configured account. Missing file is not an
# error: every account is then a serf, which is the documented default.
monarchy_users() {
    local conf=${1:-$MONARCHY_USERS_CONF}
    [ -f "$conf" ] || return 0
    local user role
    while read -r user role _; do
        case "$user" in
            '' | \#*) continue ;;
        esac
        [ -n "$role" ] || continue
        if ! monarchy_valid_role "$role"; then
            monarchy_log "warning: unknown role '$role' for an account in $conf; treating as serf"
            role=serf
        fi
        printf '%s %s\n' "$user" "$role"
    done <"$conf"
}

monarchy_user_role() {
    local want=$1
    local user role
    while read -r user role; do
        [ "$user" = "$want" ] && { printf '%s\n' "$role"; return 0; }
    done < <(monarchy_users)
    printf 'serf\n'
}

monarchy_role_session() {
    case " $MONARCHY_PLASMA_ROLES " in
        *" $1 "*) printf 'plasma.desktop\n' ;;
        *) printf 'omarchy.desktop\n' ;;
    esac
}

# Accounts the greeter should default to Plasma, one per line, sorted.
# Only accounts that exist on this box: a stale row must not appear in the
# greeter's list.
monarchy_plasma_users() {
    local user role
    while read -r user role; do
        [ "$(monarchy_role_session "$role")" = plasma.desktop ] || continue
        getent passwd "$user" >/dev/null 2>&1 || continue
        printf '%s\n' "$user"
    done < <(monarchy_users) | sort -u
}

# Roles decide the greeter default, so an empty users.conf quietly gives every
# account Omarchy. With a terminal, ask now. Without one, say so and carry on:
# an absent file means every account is a serf, which is a valid state.
monarchy_ensure_users_conf() {
    local setup
    [ ! -f "$MONARCHY_USERS_CONF" ] || return 0
    setup=/usr/local/bin/monarchy-user-setup
    [ -x "$setup" ] || setup="$monarchy_lib_dir/user-setup.sh"
    if ! monarchy_can_prompt || [ ! -f "$setup" ]; then
        monarchy_log "warning: no $MONARCHY_USERS_CONF; every account is a serf and defaults to Omarchy. Run monarchy-user-setup"
        return 0
    fi
    monarchy_log "no $MONARCHY_USERS_CONF; asking for roles"
    bash "$setup" </dev/tty || monarchy_log "warning: monarchy-user-setup did not complete"
}
