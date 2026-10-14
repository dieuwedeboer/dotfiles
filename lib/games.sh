# shellcheck shell=bash
# The shared game library. Sourced by household.sh; lib/monarchy.sh is in
# scope, so monarchy_users and the ledger are too.
#
# <pool>/games, mounted at /games, holds game files that every player shares
# and that no snapshot ever keeps. A game update rewrites tens of gigabytes,
# and every snapshot that still holds the old files keeps them on disk. The
# dataset sits beside ROOT, so the pre-update hook's recursive snapshot of
# ROOT/cos cannot reach it, and sanoid.conf does not list it. See ADR 0006.
#
# Steam's steamapps/common is shared: /games/steam/common is bind-mounted over
# each player's ~/.local/share/Steam/steamapps/common. Each player's
# steamapps/downloading is bind-mounted from their own directory under
# /games/steam/downloading. Manifests, temp files, shader caches and Proton
# prefixes stay in each player's own home, so every Steam client keeps its own
# state and Wine's prefix ownership check never meets another player's prefix.
# /games is laid out so more of steamapps, or another launcher, can move in
# later.
#
# Players are the king, queen and kids in users.conf. They share the games
# group, and /games is setgid with a default ACL, so whatever any player's
# Steam writes there stays group-writable regardless of umask.

GAMES_GROUP=games
GAMES_ROLES="king queen kid"
GAMES_ROOT=/games
GAMES_STEAM_COMMON=$GAMES_ROOT/steam/common
GAMES_STEAM_DOWNLOADING=$GAMES_ROOT/steam/downloading
GAMES_UNIT_DIR=${GAMES_UNIT_DIR:-/etc/systemd/system}
GAMES_UNIT_MARK="# monarchy: shared Steam game files"

games_dataset() {
    printf '%s/games\n' "${MONARCHY_ROOT_DATASET%%/*}"
}

games_ensure_dataset() {
    local dataset pool prop snap
    dataset=$(games_dataset)
    pool=${dataset%%/*}
    if ! command -v zfs >/dev/null 2>&1 || ! zfs list -H -o name "$pool" >/dev/null 2>&1; then
        monarchy_log "no pool $pool; shared game library skipped"
        return 1
    fi
    if ! zfs list -H -o name "$dataset" >/dev/null 2>&1; then
        monarchy_sudo zfs create \
            -o mountpoint="$GAMES_ROOT" \
            -o recordsize=1M \
            -o atime=off \
            -o acltype=posix \
            -o xattr=sa \
            -o com.sun:auto-snapshot=false \
            "$dataset"
        monarchy_changed "created $dataset at $GAMES_ROOT"
    fi
    for prop in mountpoint="$GAMES_ROOT" recordsize=1M atime=off acltype=posix xattr=sa com.sun:auto-snapshot=false; do
        if [ "$(zfs get -H -o value "${prop%%=*}" "$dataset")" != "${prop#*=}" ]; then
            monarchy_sudo zfs set "$prop" "$dataset"
            monarchy_changed "set $prop on $dataset"
        fi
    done
    # A recursive snapshot of the whole pool is the one way left to catch it.
    while read -r snap; do
        monarchy_sudo zfs destroy "$snap"
        monarchy_changed "destroyed $snap; games are never snapshotted"
    done < <(zfs list -H -o name -t snapshot -d 1 "$dataset")
}

# Group-owned, group-writable, setgid directories with a default ACL. Steam
# creates files with the default ACL and so keeps them group-writable, but
# games copied in by hand, or files Steam chmods itself, can drop out of it.
# Only the paths that are wrong get touched, so a correct tree costs one walk.
games_ensure_layout() {
    local dir wrong
    for dir in "$GAMES_ROOT" "$GAMES_ROOT/steam" "$GAMES_STEAM_COMMON" "$GAMES_STEAM_DOWNLOADING"; do
        [ -d "$dir" ] || monarchy_sudo mkdir "$dir"
    done
    wrong=$(monarchy_sudo find "$GAMES_ROOT" -xdev ! -type l \
        \( ! -group "$GAMES_GROUP" -o ! -perm -0060 -o \( -type d ! -perm -2070 \) \) \
        -print | wc -l)
    [ "$wrong" -gt 0 ] || return 0
    monarchy_sudo find "$GAMES_ROOT" -xdev ! -type l ! -group "$GAMES_GROUP" \
        -exec chgrp "$GAMES_GROUP" {} +
    monarchy_sudo find "$GAMES_ROOT" -xdev ! -type l ! -perm -0060 \
        -exec chmod g+rwX {} +
    monarchy_sudo find "$GAMES_ROOT" -xdev -type d ! -perm -2070 \
        -exec chmod g+sx {} + \
        -exec setfacl -d -m u::rwx,g::rwx,o::rx {} +
    monarchy_changed "gave the $GAMES_GROUP group write access to $wrong path(s) under $GAMES_ROOT"
}

games_players() {
    local user role
    while read -r user role; do
        case " $GAMES_ROLES " in
            *" $role "*) id -u "$user" >/dev/null 2>&1 && printf '%s\n' "$user" ;;
        esac
    done < <(monarchy_users)
}

# Membership is exactly the players: a kid moved to serf loses the library.
games_ensure_group() {
    local user member want=" $* "
    for user in "$@"; do
        if ! id -nG "$user" | tr ' ' '\n' | grep -qx "$GAMES_GROUP"; then
            monarchy_sudo gpasswd -a "$user" "$GAMES_GROUP" >/dev/null
            monarchy_changed "added $user to $GAMES_GROUP; it takes effect at their next login"
        fi
    done
    for member in $(getent group "$GAMES_GROUP" | cut -d: -f4 | tr , ' '); do
        case "$want" in
            *" $member "*) ;;
            *)
                monarchy_sudo gpasswd -d "$member" "$GAMES_GROUP" >/dev/null
                monarchy_changed "removed $member from $GAMES_GROUP: not a king, queen or kid in users.conf"
                ;;
        esac
    done
}

games_mount_unit() {
    cat <<EOF
$GAMES_UNIT_MARK
[Unit]
Description=$1
Requires=zfs-mount.service
After=zfs-mount.service

[Mount]
What=$2
Where=$3
Type=none
Options=bind

[Install]
WantedBy=local-fs.target
EOF
}

# One bind mount of what over where, added to games_wanted. A bind mount, not
# a symlink: Steam and its runtime container see an ordinary directory. A
# where that already holds files is never mounted over, because the hidden
# files would still take their space in /home.
games_ensure_mount() {
    local user=$1 description=$2 what=$3 where=$4 unit
    unit=$(systemd-escape --path --suffix=mount "$where")
    if ! monarchy_sudo mountpoint -q "$where" \
        && [ -n "$(monarchy_sudo find "$where" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
        monarchy_warn "$where is not empty; move its contents into $what with Steam closed, then rerun (README: Shared game library)"
        return 0
    fi
    games_wanted+=("$unit")
    monarchy_sudo runuser -u "$user" -- mkdir -p "$where"
    if ! games_mount_unit "$description" "$what" "$where" | monarchy_sudo cmp -s - "$GAMES_UNIT_DIR/$unit"; then
        games_mount_unit "$description" "$what" "$where" | monarchy_sudo tee "$GAMES_UNIT_DIR/$unit" >/dev/null
        games_reload=1
        monarchy_changed "wrote $unit"
    fi
}

# common is shared by every player. downloading is Steam's staging for
# installs and updates, kept off /home so no snapshot holds a half-finished
# download. Each player gets their own, because two clients staging the same
# game in one directory would clash.
games_ensure_mounts() {
    local user home steamapps downloads path unit
    games_wanted=()
    games_reload=0
    for user in "$@"; do
        home=$(getent passwd "$user" | cut -d: -f6)
        if [ ! -d "$home" ]; then
            monarchy_warn "$user has no home directory; no shared Steam games for them"
            continue
        fi
        steamapps=$home/.local/share/Steam/steamapps
        downloads=$GAMES_STEAM_DOWNLOADING/$user
        if [ ! -d "$downloads" ]; then
            monarchy_sudo install -d -o "$user" -g "$GAMES_GROUP" -m 2775 "$downloads"
            monarchy_sudo setfacl -d -m u::rwx,g::rwx,o::rx "$downloads"
            monarchy_changed "created $downloads"
        fi
        games_ensure_mount "$user" "Shared Steam game files" "$GAMES_STEAM_COMMON" "$steamapps/common"
        games_ensure_mount "$user" "Steam downloads, off /home" "$downloads" "$steamapps/downloading"
    done

    for path in "$GAMES_UNIT_DIR"/*.mount; do
        [ -f "$path" ] || continue
        head -n 1 "$path" | grep -qxF "$GAMES_UNIT_MARK" || continue
        unit=${path##*/}
        case " ${games_wanted[*]} " in
            *" $unit "*) continue ;;
        esac
        monarchy_sudo systemctl disable --now "$unit" 2>/dev/null || true
        monarchy_sudo rm -f "$path"
        games_reload=1
        monarchy_changed "removed $unit: no longer a player's library"
    done

    [ "$games_reload" = 0 ] || monarchy_sudo systemctl daemon-reload
    for unit in "${games_wanted[@]}"; do
        systemctl is-enabled -q "$unit" 2>/dev/null && systemctl is-active -q "$unit" && continue
        monarchy_sudo systemctl enable --now "$unit"
        monarchy_changed "mounted $unit"
    done
}

games_apply() {
    monarchy_step "shared game library"
    games_ensure_dataset || return 0
    games_ensure_layout
    local -a players
    mapfile -t players < <(games_players)
    games_ensure_group "${players[@]}"
    games_ensure_mounts "${players[@]}"
}
