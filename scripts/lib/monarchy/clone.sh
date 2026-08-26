# shellcheck shell=bash

monarchy_clone_git() {
    local dest=$1
    local as_root=${2:-0}
    local git=(git)
    [ "$as_root" = 1 ] && git=(sudo git)

    if [ -d "$dest/.git" ]; then
        "${git[@]}" -C "$dest" remote set-url origin "$MONARCHY_LOCK_REMOTE"
        "${git[@]}" -C "$dest" fetch --quiet origin "$MONARCHY_LOCK_COMMIT"
        "${git[@]}" -C "$dest" checkout --quiet --detach "$MONARCHY_LOCK_COMMIT"
        return 0
    fi

    mkdir -p "$(dirname "$dest")"
    if [ "$as_root" = 1 ]; then
        monarchy_sudo mkdir -p "$(dirname "$dest")"
        monarchy_sudo git clone --branch "$MONARCHY_LOCK_BRANCH" --single-branch \
            "$MONARCHY_LOCK_REMOTE" "$dest"
        monarchy_sudo git -C "$dest" fetch --quiet origin "$MONARCHY_LOCK_COMMIT"
        monarchy_sudo git -C "$dest" checkout --quiet --detach "$MONARCHY_LOCK_COMMIT"
    else
        git clone --branch "$MONARCHY_LOCK_BRANCH" --single-branch \
            "$MONARCHY_LOCK_REMOTE" "$dest"
        git -C "$dest" fetch --quiet origin "$MONARCHY_LOCK_COMMIT"
        git -C "$dest" checkout --quiet --detach "$MONARCHY_LOCK_COMMIT"
    fi
}

# For --check, prefer the live clone, then a user cache. Never writes /usr/local.
monarchy_ensure_clone_for_check() {
    if [ -d "$MONARCHY_SRC/.git" ]; then
        monarchy_log "check clone: $MONARCHY_SRC"
        return 0
    fi
    monarchy_log "check clone missing at $MONARCHY_SRC; using cache $MONARCHY_CACHE"
    MONARCHY_SRC=$MONARCHY_CACHE
    monarchy_clone_git "$MONARCHY_SRC" 0
}

monarchy_sync_omarchy_clone() {
    monarchy_log "clone $MONARCHY_LOCK_REMOTE $MONARCHY_LOCK_BRANCH @ $MONARCHY_LOCK_COMMIT"
    monarchy_clone_git "$MONARCHY_SRC" 1
}

monarchy_write_omarchy_conf() {
    local tmp
    tmp=$(mktemp)
    printf 'OMARCHY_PATH=%s\n' "$MONARCHY_PATH" >"$tmp"
    monarchy_sudo mkdir -p "$(dirname "$MONARCHY_CONF")"
    monarchy_sudo install -m 644 "$tmp" "$MONARCHY_CONF"
    rm -f "$tmp"
}

monarchy_link_working_prefix() {
    local name
    monarchy_sudo mkdir -p "$MONARCHY_PATH"
    for name in default shell themes migrations config install applications version; do
        if [ -e "$MONARCHY_SRC/$name" ]; then
            monarchy_sudo ln -sfn "$MONARCHY_SRC/$name" "$MONARCHY_PATH/$name"
        fi
    done
}
