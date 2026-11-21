# shellcheck shell=bash
# The shared Minecraft launcher. Sourced by household.sh after games.sh, whose
# dataset, group and players this builds on.
#
# <pool>/games/xmcl, mounted at /games/xmcl, is XMCL's data root for every
# player on the box: versions, libraries, assets, Java, instances and worlds.
# Unlike its parent it is snapshotted. XMCL keeps worlds both in the shared
# saves folder and inside each instance, so there is no smaller subtree that
# holds every world, and the whole tree is a few gigabytes that seldom churn.
# See ADR 0014.
#
# The Microsoft logins are shared too. XMCL keeps the token cache in
# ~/.config/xmcl/secret and the account list in ~/.config/xmcl/user.json; each
# player's are links into /games/xmcl/accounts. Each player's keyring would
# encrypt the cache with a key no other player has, so XMCL is started with
# --password-store=basic and the tokens are protected by file permissions
# instead: /games/xmcl is the games group's only, with nothing for others.

XMCL_ROOT=$GAMES_ROOT/xmcl
XMCL_ACCOUNTS=$XMCL_ROOT/accounts
XMCL_DESKTOP_SRC=${XMCL_DESKTOP_SRC:-/usr/share/applications/xmcl.desktop}
XMCL_DESKTOP_DEST=${XMCL_DESKTOP_DEST:-/usr/local/share/applications/xmcl.desktop}

xmcl_dataset() {
    printf '%s/xmcl\n' "$(games_dataset)"
}

# A child of the games dataset, so it mounts at /games/xmcl by inheritance.
# games_ensure_dataset destroys snapshots one level deep only, which is the
# parent's own and never this one's.
xmcl_ensure_dataset() {
    local dataset prop
    dataset=$(xmcl_dataset)
    if ! zfs list -H -o name "$dataset" >/dev/null 2>&1; then
        monarchy_sudo zfs create \
            -o recordsize=128K \
            -o com.sun:auto-snapshot=true \
            "$dataset"
        monarchy_changed "created $dataset at $XMCL_ROOT"
    fi
    for prop in recordsize=128K com.sun:auto-snapshot=true; do
        if [ "$(zfs get -H -o value "${prop%%=*}" "$dataset")" != "${prop#*=}" ]; then
            monarchy_sudo zfs set "$prop" "$dataset"
            monarchy_changed "set $prop on $dataset"
        fi
    done
    if [ "$(zfs get -H -o value mountpoint "$dataset")" != "$XMCL_ROOT" ]; then
        monarchy_sudo zfs inherit mountpoint "$dataset"
        monarchy_changed "mounted $dataset at $XMCL_ROOT"
    fi
}

# As games_ensure_layout, but closed to others: the login tokens live here in
# plain text. Only the paths that are wrong get touched.
xmcl_ensure_layout() {
    local dir wrong
    for dir in "$XMCL_ROOT" "$XMCL_ACCOUNTS" "$XMCL_ACCOUNTS/secret"; do
        [ -d "$dir" ] || monarchy_sudo mkdir "$dir"
    done
    wrong=$(monarchy_sudo find "$XMCL_ROOT" -xdev ! -type l \
        \( ! -group "$GAMES_GROUP" -o ! -perm -0060 -o -perm /0007 -o \( -type d ! -perm -2070 \) \) \
        -print | wc -l)
    [ "$wrong" -gt 0 ] || return 0
    monarchy_sudo find "$XMCL_ROOT" -xdev ! -type l ! -group "$GAMES_GROUP" \
        -exec chgrp "$GAMES_GROUP" {} +
    monarchy_sudo find "$XMCL_ROOT" -xdev ! -type l \( ! -perm -0060 -o -perm /0007 \) \
        -exec chmod g+rwX,o-rwx {} +
    monarchy_sudo find "$XMCL_ROOT" -xdev -type d \
        -exec chmod g+sx {} + \
        -exec setfacl -d -m u::rwx,g::rwx,o::--- {} +
    monarchy_changed "gave only the $GAMES_GROUP group access to $wrong path(s) under $XMCL_ROOT"
}

# The package's own entry with the flag added, regenerated when the package
# changes it. /usr/local/share/applications comes first in XDG_DATA_DIRS, so
# every launcher and the xmcl:// handler start XMCL through this one.
xmcl_ensure_desktop_entry() {
    local tmp
    if [ ! -f "$XMCL_DESKTOP_SRC" ]; then
        monarchy_warn "$XMCL_DESKTOP_SRC is missing; XMCL logins will not be shared until xmcl-launcher is installed"
        return 0
    fi
    tmp=$(mktemp)
    sed -E 's#^(Exec=[^ ]*xmcl)( |$)#\1 --password-store=basic\2#' "$XMCL_DESKTOP_SRC" >"$tmp"
    if monarchy_install_if_changed 644 "$tmp" "$XMCL_DESKTOP_DEST"; then
        monarchy_changed "wrote $XMCL_DESKTOP_DEST: XMCL keeps its logins where every player can read them"
    fi
    rm -f "$tmp"
}

xmcl_running_for() {
    pgrep -u "$1" -f '^/opt/xmcl/xmcl' >/dev/null 2>&1
}

# One of a player's own XMCL files becomes a link into the shared accounts.
# A login of their own is moved aside, not deleted: it cannot be read by
# anyone else, so they sign in once more on the shared one.
xmcl_ensure_account_link() {
    local user=$1 path=$2 target=$3
    if [ -L "$path" ] && [ "$(monarchy_sudo readlink "$path")" = "$target" ]; then
        return 0
    fi
    if monarchy_sudo test -e "$path" -o -L "$path"; then
        if xmcl_running_for "$user"; then
            monarchy_left_alone "$path: XMCL is open for $user; close it and rerun to share the Minecraft logins"
            return 0
        fi
        monarchy_sudo mv -T "$path" "$path.before-monarchy"
        monarchy_changed "moved $path aside to $path.before-monarchy; $user signs in to Minecraft once more"
    fi
    monarchy_sudo runuser -u "$user" -- ln -s "$target" "$path"
    monarchy_changed "linked $path to $target"
}

# The data root is not a preference: every player's is /games/xmcl, so that a
# kid cannot split a box's Minecraft in two from XMCL's settings. ADR 0014
# makes this the exception to ADR 0002. The root file is owned by root and
# immutable. XMCL changes the data location by moving the files first and
# writing this file last; when the write fails it moves them back.
xmcl_lock_root() {
    local file=$1 attrs
    attrs=$(monarchy_sudo lsattr -d "$file" 2>/dev/null | awk '{print $1}')
    if [ "$(monarchy_sudo cat "$file" 2>/dev/null)" = "$XMCL_ROOT" ] \
        && [ "$(monarchy_sudo stat -c %u "$file")" = 0 ] \
        && [[ $attrs == *i* ]]; then
        return 1
    fi
    [[ $attrs != *i* ]] || monarchy_sudo chattr -i "$file"
    printf '%s' "$XMCL_ROOT" | monarchy_sudo tee "$file" >/dev/null
    monarchy_sudo chown root:root "$file"
    monarchy_sudo chmod 644 "$file"
    monarchy_sudo chattr +i "$file"
}

# A name in dir that nothing has yet, so two players' instances or worlds of
# the same name both survive the move.
xmcl_free_name() {
    local dir=$1 name=$2 user=$3 n=2 try
    [ -e "$dir/$name" ] || { printf '%s\n' "$name"; return; }
    try="$name ($user)"
    while [ -e "$dir/$try" ]; do
        try="$name ($user $n)"
        n=$((n + 1))
    done
    printf '%s\n' "$try"
}

# Every absolute path into the old root becomes the same path under the new
# one: instance.json keeps the instance's own path and its Java, and XMCL
# links an instance's versions, libraries and saves back to the root.
xmcl_repoint_instance() {
    local dir=$1 old=$2 link target tmp
    while IFS= read -r -d '' link; do
        target=$(monarchy_sudo readlink "$link")
        case "$target" in
            "$old" | "$old"/*) monarchy_sudo ln -sfn "$XMCL_ROOT${target#"$old"}" "$link" ;;
        esac
    done < <(monarchy_sudo find "$dir" -mindepth 1 -maxdepth 1 -type l -print0)
    [ -f "$dir/instance.json" ] || return 0
    tmp=$(mktemp)
    # shellcheck disable=SC2016  # jq variables, not shell ones
    if monarchy_sudo jq --arg old "$old" --arg new "$XMCL_ROOT" --arg dir "$dir" '
        walk(if type == "string" and (. == $old or startswith($old + "/"))
             then $new + .[($old | length):] else . end)
        | if has("path") then .path = $dir else . end' "$dir/instance.json" >"$tmp"; then
        monarchy_sudo tee "$dir/instance.json" <"$tmp" >/dev/null
    else
        monarchy_warn "$dir/instance.json is not JSON XMCL wrote; left as it was"
    fi
    rm -f "$tmp"
}

# Moves a player's own data root into /games/xmcl. Instances and worlds are
# moved one by one and never overwrite: a clash gets the player's name added.
# Everything else in a root can be downloaded again, so it is merged without
# overwriting, and what is left of the old root is kept aside rather than
# deleted, for the king to look at and remove.
xmcl_adopt_root() {
    local user=$1 old=$2 kind src name dest entry aside
    for kind in instances saves; do
        [ -d "$old/$kind" ] && [ ! -L "$old/$kind" ] || continue
        monarchy_sudo mkdir -p "$XMCL_ROOT/$kind"
        while IFS= read -r -d '' src; do
            name=${src##*/}
            dest=$XMCL_ROOT/$kind/$(xmcl_free_name "$XMCL_ROOT/$kind" "$name" "$user")
            monarchy_sudo mv -T "$src" "$dest"
            [ "$kind" = instances ] && xmcl_repoint_instance "$dest" "$old"
            if [ "${dest##*/}" = "$name" ]; then
                monarchy_changed "moved $user's Minecraft $kind/$name into $XMCL_ROOT"
            else
                monarchy_changed "moved $user's Minecraft $kind/$name into $XMCL_ROOT as ${dest##*/}: the name was taken"
            fi
        done < <(monarchy_sudo find "$old/$kind" -mindepth 1 -maxdepth 1 -print0)
    done
    for entry in assets jre libraries labymod-neo modpacks mods resourcepacks shaderpacks versions; do
        [ -d "$old/$entry" ] && [ ! -L "$old/$entry" ] || continue
        monarchy_sudo mkdir -p "$XMCL_ROOT/$entry"
        monarchy_sudo cp -a --update=none "$old/$entry/." "$XMCL_ROOT/$entry/"
    done
    for entry in authlib-injection.json ely-authlib.json launcher_profiles.json options.txt servers.dat; do
        [ -f "$old/$entry" ] && [ ! -e "$XMCL_ROOT/$entry" ] || continue
        monarchy_sudo cp -a "$old/$entry" "$XMCL_ROOT/$entry"
    done
    case "$old" in
        "$XMCL_ROOT" | "$XMCL_ROOT"/* | */.config/xmcl) return 0 ;;
    esac
    aside="$old.before-monarchy"
    [ ! -e "$aside" ] || aside="$aside-$(date +%Y%m%d%H%M%S)"
    monarchy_sudo mv -T "$old" "$aside"
    monarchy_changed "kept the rest of $user's old Minecraft data at $aside; every instance and world in it was moved, and it can be deleted"
}

xmcl_ensure_player() {
    local user=$1 home config root
    home=$(getent passwd "$user" | cut -d: -f6)
    if [ ! -d "$home" ]; then
        monarchy_warn "$user has no home directory; no shared Minecraft for them"
        return 0
    fi
    config=$home/.config/xmcl
    monarchy_sudo runuser -u "$user" -- mkdir -p "$config"
    root=$(monarchy_sudo cat "$config/root" 2>/dev/null || true)
    if [ -n "$root" ] && [ "$root" != "$XMCL_ROOT" ] && monarchy_sudo test -d "$root"; then
        if xmcl_running_for "$user"; then
            monarchy_left_alone "$user's Minecraft data is still in $root: XMCL is open for $user; close it and rerun"
            return 0
        fi
        xmcl_adopt_root "$user" "$root"
    fi
    if xmcl_lock_root "$config/root"; then
        monarchy_changed "locked $user's XMCL data location to $XMCL_ROOT"
    fi
    xmcl_ensure_account_link "$user" "$config/secret" "$XMCL_ACCOUNTS/secret"
    xmcl_ensure_account_link "$user" "$config/user.json" "$XMCL_ACCOUNTS/user.json"
}

xmcl_apply() {
    monarchy_step "shared Minecraft (XMCL)"
    if ! zfs list -H -o name "$(games_dataset)" >/dev/null 2>&1; then
        monarchy_log "no $(games_dataset); shared Minecraft skipped"
        return 0
    fi
    xmcl_ensure_dataset
    xmcl_ensure_desktop_entry
    local user
    while read -r user; do
        xmcl_ensure_player "$user"
    done < <(games_players)
    # Last, so that what was just moved in is given to the group.
    xmcl_ensure_layout
}
