# shellcheck shell=bash
# The working prefix: the tree the session actually reads.
#
# MONARCHY_SRC is /usr/share/omarchy, owned by the omarchy and
# omarchy-settings-monarchy packages. MONARCHY_PATH is
# /usr/local/share/omarchy: symlinks into that tree, plus the overlay bin/,
# plus the two patched copies.
#
# The indirection is the point. overlay-lock.py has to patch the lock QML and
# omarchy-menu.jsonc, and a pacman-owned path is not somewhere to write: the
# next `pacman -Syu` would silently revert both. Exploding a prefix symlink
# into a directory of child symlinks lets exactly one file be replaced while
# the rest still track the package.

# The twelve names the session expects under OMARCHY_PATH. omarchy ships bin,
# install, migrations, shell, themes, version; omarchy-settings-monarchy ships
# applications, config, default and the branding files. Between them the set
# is complete, which is why the clone could go.
MONARCHY_PREFIX_NAMES=(
    default shell themes migrations config install applications version
    logo.txt logo.svg icon.txt icon.png
)

monarchy_assert_source_tree() {
    [ -d "$MONARCHY_SRC" ] \
        || monarchy_die "no Omarchy tree at $MONARCHY_SRC; is the omarchy package installed?"
    # pacman refuses to extract through a symlinked directory, so a leftover
    # bridge here is not a cosmetic problem: it aborts the whole transaction.
    [ ! -L "$MONARCHY_SRC" ] \
        || monarchy_die "$MONARCHY_SRC is a symlink; the omarchy package must own it"
    local n
    local -a missing=()
    for n in "${MONARCHY_PREFIX_NAMES[@]}"; do
        [ -e "$MONARCHY_SRC/$n" ] || missing+=("$n")
    done
    [ "${#missing[@]}" -eq 0 ] \
        || monarchy_die "$MONARCHY_SRC is missing: ${missing[*]} (omarchy-settings-monarchy not installed?)"
    return 0
}

monarchy_write_omarchy_conf() {
    local tmp src parent
    tmp=$(mktemp)
    printf 'OMARCHY_PATH=%s\n' "$MONARCHY_PATH" >"$tmp"
    parent=$(dirname "$MONARCHY_CONF")
    monarchy_write_to "$parent" mkdir -p "$parent"
    monarchy_write_to "$parent" install -m 644 "$tmp" "$MONARCHY_CONF"
    rm -f "$tmp"

    src="$MONARCHY_MISC/omarchy.lock"
    [ -f "$src" ] || monarchy_die "missing $src"
    parent=$(dirname "$MONARCHY_PIN")
    monarchy_write_to "$parent" mkdir -p "$parent"
    monarchy_write_to "$parent" install -m 644 "$src" "$MONARCHY_PIN"
}

monarchy_link_working_prefix() {
    local name dest ln_cmd mkdir_cmd
    if [ -w "$MONARCHY_PATH" ] 2>/dev/null || [ -w "$(dirname "$MONARCHY_PATH")" ] 2>/dev/null; then
        mkdir_cmd=(mkdir -p)
        ln_cmd=(ln -sfn)
    else
        mkdir_cmd=(monarchy_sudo mkdir -p)
        ln_cmd=(monarchy_sudo ln -sfn)
    fi
    "${mkdir_cmd[@]}" "$MONARCHY_PATH"
    for name in "${MONARCHY_PREFIX_NAMES[@]}"; do
        if [ -e "$MONARCHY_SRC/$name" ]; then
            dest="$MONARCHY_PATH/$name"
            # A previous apply may have exploded this symlink into a directory.
            if [ -d "$dest" ] && [ ! -L "$dest" ]; then
                if [ -w "$MONARCHY_PATH" ] 2>/dev/null; then
                    rm -rf "$dest"
                else
                    monarchy_sudo rm -rf "$dest"
                fi
            fi
            "${ln_cmd[@]}" "$MONARCHY_SRC/$name" "$dest"
        fi
    done
}
