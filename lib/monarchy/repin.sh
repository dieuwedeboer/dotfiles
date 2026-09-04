# shellcheck shell=bash
# Read-only review of what bumping monarchy/omarchy.lock would bring in.
# Writes nothing: not /etc, not /usr/local, not the repo. The bump stays a
# human decision because monarchy_check_migrations and
# monarchy_check_packages_deny exist to stop an apply when upstream adds
# something nobody has classified, and there is no canary box to find out on.
#
# Sourced into one shell by lib/monarchy.sh; common.sh state is in scope.
# shellcheck disable=SC2154,SC2153

MONARCHY_REPIN_TMP=

monarchy_repin_cleanup() {
    [ -n "$MONARCHY_REPIN_TMP" ] || return 0
    rm -rf "$MONARCHY_REPIN_TMP"
    MONARCHY_REPIN_TMP=
}

monarchy_repin_section() {
    printf '\n== %s ==\n' "$1"
}

# The branch tip, without fetching anything.
monarchy_repin_remote_head() {
    git ls-remote "$MONARCHY_LOCK_REMOTE" "refs/heads/$MONARCHY_LOCK_BRANCH" \
        2>/dev/null | awk 'NR==1{print $1}'
}

# Blobless: the whole commit graph for the ancestry question, file contents
# fetched only for the checkout below.
monarchy_repin_clone() {
    local dest=$1
    git clone --quiet --filter=blob:none --no-checkout \
        --branch "$MONARCHY_LOCK_BRANCH" \
        "$MONARCHY_LOCK_REMOTE" "$dest" \
        || monarchy_die "could not clone $MONARCHY_LOCK_REMOTE"
}

# A rebased fork leaves the pinned commit off the branch. GitHub still serves
# it, so ask for it by name and carry on without it if that fails: the
# position report degrades, the content diff does not.
monarchy_repin_fetch_pin() {
    local repo=$1
    git -C "$repo" fetch --quiet origin "$MONARCHY_LOCK_COMMIT" 2>/dev/null
}

monarchy_repin_position() {
    local repo=$1 head=$2
    local counts behind ahead
    if ! monarchy_repin_fetch_pin "$repo"; then
        echo "pinned commit is not served by the remote; it may have been"
        echo "garbage collected after a force-push. Content below still applies."
        return 0
    fi
    counts=$(git -C "$repo" rev-list --left-right --count \
        "$MONARCHY_LOCK_COMMIT...$head" 2>/dev/null) || return 0
    ahead=$(printf '%s' "$counts" | awk '{print $1}')
    behind=$(printf '%s' "$counts" | awk '{print $2}')
    printf 'branch is %s commits ahead of the pin\n' "$behind"
    if [ "$ahead" != 0 ]; then
        printf 'the pin holds %s commits the branch does not: rebased and force-pushed\n' "$ahead"
        echo "commits only on the pinned side:"
        git -C "$repo" log --format='  %h %ad %s' --date=short \
            "$head..$MONARCHY_LOCK_COMMIT" 2>/dev/null | head -20
    fi
}

# Every migration carries its own summary as the first echo. Cheaper to read
# than the diff and it is what the author wrote for a human.
monarchy_repin_migrations() {
    local repo=$1 head=$2
    local -a added=()
    mapfile -t added < <(git -C "$repo" diff --name-only --diff-filter=A \
        "$MONARCHY_LOCK_COMMIT" "$head" -- migrations/ 2>/dev/null)
    if [ "${#added[@]}" -eq 0 ]; then
        echo "none"
        return 0
    fi
    local f base
    for f in "${added[@]}"; do
        base=$(basename "$f")
        printf '  %s  %s\n' "$base" \
            "$(sed -n 's/^echo "\(.*\)"$/\1/p' "$repo/$f" 2>/dev/null | head -1)"
    done
    printf '\n%s new migrations. monarchy_check_migrations greps them for\n' "${#added[@]}"
    echo "limine and pacman.conf; read the rest for what they do to a box that"
    echo "boots rEFInd and snapshots with sanoid."
}

# Root-owned drop-ins are installed by apply and never reconciled, so a file
# upstream stops shipping stays on the box until someone removes it.
monarchy_repin_privileged() {
    local repo=$1 head=$2
    local out
    out=$(git -C "$repo" diff --name-status "$MONARCHY_LOCK_COMMIT" "$head" \
        -- etc/sudoers.d/ etc/systemd/system/ etc/udev/ 2>/dev/null)
    if [ -z "$out" ]; then
        echo "none"
        return 0
    fi
    printf '%s\n' "$out" | sed 's/^/  /'
    echo
    echo "A deleted row is the one to act on: apply installs files, it does not"
    echo "remove what upstream dropped. Check the box with: sudo ls /etc/sudoers.d/"
}

monarchy_repin_inventories() {
    local repo=$1 dest=$2
    python3 "$MONARCHY_DOTFILES/lib/monarchy/generate-inventories.py" \
        --dest "$dest" "$repo" \
        || monarchy_die "generate-inventories.py refused the new checkout"
    local list changed=0
    for list in bin.allow bin.wrap bin.deny; do
        if ! diff -q "$MONARCHY_MISC/$list" "$dest/$list" >/dev/null 2>&1; then
            changed=1
            printf '%s:\n' "$list"
            diff "$MONARCHY_MISC/$list" "$dest/$list" \
                | sed -n 's/^> /  + /p;s/^< /  - /p'
        fi
    done
    [ "$changed" = 1 ] || echo "unchanged"
}

# Both guards die on an unclassified row. A subshell turns that into a report.
monarchy_repin_guards() {
    local repo=$1
    local out rc
    out=$(MONARCHY_SRC=$repo; export MONARCHY_SRC
        monarchy_check_migrations 2>&1) && rc=0 || rc=$?
    if [ "$rc" = 0 ]; then
        echo "monarchy_check_migrations: pass"
    else
        echo "monarchy_check_migrations: NEEDS CLASSIFYING"
        printf '%s\n' "$out" | sed 's/^/  /'
    fi
    out=$(MONARCHY_SRC=$repo; export MONARCHY_SRC
        monarchy_check_packages_deny 2>&1) && rc=0 || rc=$?
    if [ "$rc" = 0 ]; then
        echo "monarchy_check_packages_deny: pass"
    else
        echo "monarchy_check_packages_deny: NEEDS CLASSIFYING"
        printf '%s\n' "$out" | sed 's/^/  /'
    fi
}

monarchy_repin_packages() {
    local repo=$1
    local out
    out=$(MONARCHY_SRC=$repo; export MONARCHY_SRC
        monarchy_filtered_packages 2>/dev/null) || {
        echo "could not read install/omarchy-base.packages"
        return 0
    }
    if diff -q "$MONARCHY_MISC/packages.installed" <(printf '%s\n' "$out") \
        >/dev/null 2>&1; then
        echo "unchanged"
        return 0
    fi
    diff "$MONARCHY_MISC/packages.installed" <(printf '%s\n' "$out") \
        | sed -n 's/^> /  + /p;s/^< /  - /p'
    echo
    echo "A removed row stays installed on the box. Check whether a migration"
    echo "takes it out, or take it out by hand."
}

monarchy_repin_check() {
    monarchy_load_lock
    monarchy_load_inventories

    local head
    head=$(monarchy_repin_remote_head)
    [ -n "$head" ] || monarchy_die "no $MONARCHY_LOCK_BRANCH on $MONARCHY_LOCK_REMOTE"

    printf 'pin  %s\n' "$MONARCHY_LOCK_COMMIT"
    printf 'head %s  (%s %s)\n' "$head" "$MONARCHY_LOCK_REMOTE" "$MONARCHY_LOCK_BRANCH"

    if [ "$head" = "$MONARCHY_LOCK_COMMIT" ]; then
        echo
        echo "pin is current. Nothing to review."
        return 0
    fi

    MONARCHY_REPIN_TMP=$(mktemp -d)
    trap monarchy_repin_cleanup EXIT
    local repo="$MONARCHY_REPIN_TMP/clone"
    local inv="$MONARCHY_REPIN_TMP/inventories"
    mkdir -p "$inv"

    monarchy_repin_clone "$repo"

    monarchy_repin_section "Position"
    monarchy_repin_position "$repo" "$head"

    git -C "$repo" checkout --quiet --detach "$head" \
        || monarchy_die "could not check out $head"

    monarchy_repin_section "Classification guards"
    monarchy_repin_guards "$repo"

    monarchy_repin_section "bin/ inventories"
    monarchy_repin_inventories "$repo" "$inv"

    monarchy_repin_section "packages.installed"
    monarchy_repin_packages "$repo"

    monarchy_repin_section "New migrations"
    monarchy_repin_migrations "$repo" "$head"

    monarchy_repin_section "Privileged drop-ins"
    monarchy_repin_privileged "$repo" "$head"

    monarchy_repin_section "To bump"
    echo "Nothing above has been written. The .claude/skills/repin procedure"
    echo "is the steps; it ends at a commit, and monarchy-update applies it."
    return 0
}
