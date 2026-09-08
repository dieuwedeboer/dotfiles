# shellcheck shell=bash
# Build and install the two local packages that let the official `omarchy`
# package run on this host.
#
#   monarchy-boot-stub          provides limine*/snapper so omarchy's hard deps
#                               resolve without the ESP-hijacking hook
#   omarchy-settings-monarchy   the official omarchy-settings minus its /etc
#                               clobber and minus monarchy/settings.skip
#
# Between them, `pacman -S omarchy` becomes a normal install. That is what
# retires the git clone: /usr/share/omarchy is then a pacman-owned tree with
# exactly the twelve names monarchy_link_working_prefix wants.

MONARCHY_PKGBUILDS="${MONARCHY_PKGBUILDS:-$MONARCHY_DOTFILES/pkgbuilds}"
MONARCHY_BUILD_DIR="${MONARCHY_BUILD_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/monarchy/build}"

# The version `omarchy` pins its settings package to. omarchy depends on
# omarchy-settings=<exact>, so our replacement has to provide that same
# version or the dep does not resolve.
monarchy_settings_required_version() {
    pacman -Si omarchy 2>/dev/null \
        | awk -F': ' '$1 ~ /^Depends On/ { print $2 }' \
        | tr ' ' '\n' \
        | sed -n 's/^omarchy-settings=\(.*\)$/\1/p' \
        | head -1
}

monarchy_repo_pkg_version() {
    pacman -Si "$1" 2>/dev/null \
        | awk -F': ' '$1 ~ /^Version/ { print $2; exit }' \
        | tr -d ' '
}

monarchy_installed_pkg_version() {
    pacman -Q "$1" 2>/dev/null | awk '{print $2}'
}

# makepkg refuses to run as root, and running the whole apply as root would
# also leave root-owned files in the user's cache. Fail loudly rather than
# half-building.
monarchy_assert_can_makepkg() {
    [ "${EUID:-$(id -u)}" -ne 0 ] \
        || monarchy_die "run install.sh as your user, not root: makepkg refuses to build as root"
    command -v makepkg >/dev/null 2>&1 || monarchy_die "makepkg is missing (install base-devel)"
}

monarchy_build_pkg() {
    local name=$1
    shift
    local build="$MONARCHY_BUILD_DIR/$name"
    local src="$MONARCHY_PKGBUILDS/$name/PKGBUILD"
    [ -f "$src" ] || monarchy_die "missing $src"

    rm -rf "$build"
    mkdir -p "$build"
    install -m 644 "$src" "$build/PKGBUILD"
    local extra
    for extra in "$@"; do
        install -m 644 "$extra" "$build/$(basename "$extra")"
    done

    # This function returns the built package path on stdout, so everything
    # else it emits has to go to stderr. monarchy_log echoes to stdout.
    monarchy_log "makepkg $name" >&2
    ( cd "$build" && makepkg --force --clean --nodeps --noconfirm >/dev/null ) \
        || monarchy_die "makepkg failed for $name (see $build)"

    local built
    built=$(find "$build" -maxdepth 1 -name '*.pkg.tar.*' ! -name '*.sig' -print -quit)
    [ -n "$built" ] || monarchy_die "makepkg produced no package for $name"
    printf '%s\n' "$built"
}

# Hand previously hand-installed files over to the package that now owns them.
#
# The old settings.sh copied ~286 files into /etc and /usr by hand, so pacman
# owns none of them and refuses to extract over them ("exists in filesystem").
# They are upstream's own content, copied from upstream, so taking ownership is
# correct -- but a file owned by a *different* package is a real clash and a
# judgement call, so that stops the apply instead.
#
# This plans `pacman -U --overwrite` arguments rather than deleting anything.
# An earlier version removed the colliding files first; when /usr/share/omarchy
# was still the legacy symlink, that resolved through it into the working
# prefix and then into the git clone, and deleted 223 tracked files. Letting
# pacman do the replacing means there is no window where a file is missing and
# no way for a delete to escape the package's own file list.
#
# MONARCHY_ROOT is empty on a real box and a temp prefix in the tests.
# Probe a list of paths with the privileges pacman will have.
#
# stdin: absolute paths, one per line.
# stdout: "<path>\t<canonical parent>" for each one that exists.
#
# This has to be elevated. /etc/sudoers.d is 0750 root:root, so an
# unprivileged `[ -e ]` is false for every file inside it -- the planner
# skipped all four omarchy sudoers drop-ins, planned no --overwrite for them,
# and pacman then refused the transaction on exactly those files. One
# elevation for the whole list rather than one per path.
monarchy_probe_paths() {
    # Single-quoted on purpose: the inner script runs under sudo and must not
    # expand in this shell.
    # shellcheck disable=SC2016
    monarchy_sudo bash -c '
        while IFS= read -r p; do
            if [ -e "$p" ] || [ -L "$p" ]; then
                printf "%s\t%s\n" "$p" "$(realpath -m "$(dirname "$p")" 2>/dev/null)"
            fi
        done'
}

# Hand previously hand-installed files over to the package that now owns them.
#
# The old settings.sh copied files into /etc and /usr by hand, so pacman owns
# none of them and refuses to extract over them ("exists in filesystem").
# They are upstream's own content, copied from upstream, so taking ownership is
# correct -- but a file owned by a *different* package is a real clash and a
# judgement call, so that stops the apply instead.
#
# This plans `pacman -U --overwrite` arguments rather than deleting anything.
# An earlier version removed the colliding files first; when /usr/share/omarchy
# was still the legacy symlink, that resolved through it into the working
# prefix and then into the git clone, and deleted 223 tracked files. Letting
# pacman do the replacing means there is no window where a file is missing and
# no way for a delete to escape the package's own file list.
#
# MONARCHY_ROOT is empty on a real box and a temp prefix in the tests.
monarchy_plan_overwrites() {
    local pkg=$1
    local f p owner root_canon parent_canon expected_parent
    local -a clashes=() escapes=()
    MONARCHY_OVERWRITE_ARGS=()
    root_canon=$(realpath -m "${MONARCHY_ROOT:-/}" 2>/dev/null) || root_canon=/
    root_canon=${root_canon%/}

    while IFS=$'\t' read -r p parent_canon; do
        [ -n "$p" ] || continue
        f=${p#"${MONARCHY_ROOT:-}/"}

        # Refuse a path whose *directory chain* leaves the root through a
        # symlink. Overwriting through one touches a file the package does not
        # own. The leaf itself may be a symlink; that is a normal packaged
        # file and pacman replaces it in place.
        expected_parent="$root_canon/$(dirname "$f")"
        case "$(dirname "$f")" in .) expected_parent="$root_canon" ;; esac
        if [ "$parent_canon" != "$expected_parent" ]; then
            escapes+=("$p -> $parent_canon")
            continue
        fi

        owner=$(pacman -Qoq "$p" 2>/dev/null || true)
        if [ -n "$owner" ]; then
            case "$owner" in
                monarchy-boot-stub|omarchy-settings-monarchy|omarchy) continue ;;
            esac
            clashes+=("$p (owned by $owner)")
            continue
        fi
        MONARCHY_OVERWRITE_ARGS+=("--overwrite=$p")
    done < <(
        bsdtar tf "$pkg" 2>/dev/null \
            | while IFS= read -r f; do
                case "$f" in ''|.*|*/) continue ;; esac
                printf '%s\n' "${MONARCHY_ROOT:-}/$f"
            done \
            | monarchy_probe_paths
    )

    if [ "${#escapes[@]}" -gt 0 ]; then
        printf '  %s\n' "${escapes[@]}" >&2
        monarchy_die "the paths above resolve outside the install root through a symlink; clear the legacy /usr/share/omarchy link first"
    fi
    if [ "${#clashes[@]}" -gt 0 ]; then
        printf '  %s\n' "${clashes[@]}" >&2
        monarchy_die "the paths above are owned by another package; add them to monarchy/settings.skip or remove the owner"
    fi
    [ "${#MONARCHY_OVERWRITE_ARGS[@]}" -eq 0 ] \
        || monarchy_log "taking ownership of ${#MONARCHY_OVERWRITE_ARGS[@]} hand-installed path(s) for $(basename "$pkg")" >&2
}

monarchy_install_built_pkg() {
    local pkg=$1
    monarchy_plan_overwrites "$pkg"
    monarchy_log "pacman -U $(basename "$pkg")"
    monarchy_sudo pacman -U --noconfirm --needed \
        "${MONARCHY_OVERWRITE_ARGS[@]}" "$pkg" \
        || monarchy_die "pacman -U failed for $pkg"
}

# ---- monarchy-boot-stub -------------------------------------------------

monarchy_boot_stub_wanted_version() {
    awk -F= '$1=="pkgver"{v=$2} $1=="pkgrel"{r=$2} END{print v "-" r}' \
        "$MONARCHY_PKGBUILDS/monarchy-boot-stub/PKGBUILD"
}

monarchy_ensure_boot_stub() {
    local want have
    want=$(monarchy_boot_stub_wanted_version)
    have=$(monarchy_installed_pkg_version monarchy-boot-stub)
    if [ "$have" = "$want" ]; then
        monarchy_log "monarchy-boot-stub $have already installed"
        return 0
    fi
    monarchy_assert_can_makepkg
    local built
    built=$(monarchy_build_pkg monarchy-boot-stub)
    monarchy_install_built_pkg "$built"
}

# ---- omarchy-settings-monarchy ------------------------------------------

# Fetch the official package straight from [omarchy] and verify it against
# pacman's keyring. `pacman -Sw omarchy-settings` cannot be used: our
# replacement conflicts with that name, so resolution refuses before it
# downloads anything.
monarchy_fetch_official_settings() {
    local full=$1 dest=$2
    local arch file url
    arch=$(pacman -Si omarchy-settings 2>/dev/null \
        | awk -F': ' '$1 ~ /^Architecture/ { print $2; exit }' | tr -d ' ')
    [ -n "$arch" ] || monarchy_die "could not read omarchy-settings Architecture from [omarchy]"
    # Path segment is the repo arch; the filename carries the package's own
    # arch, which for omarchy-settings is "any".
    file="omarchy-settings-${full}-${arch}.pkg.tar.zst"
    url="$MONARCHY_OMARCHY_SERVER/$(uname -m)/$file"

    monarchy_log "fetch $url"
    curl -fsSL -o "$dest" "$url" || monarchy_die "could not download $url"
    curl -fsSL -o "$dest.sig" "$url.sig" || monarchy_die "could not download $url.sig"

    # SigLevel for [omarchy] is Required. Bypassing pacman to fetch the file
    # must not also bypass the signature check.
    monarchy_sudo gpg --homedir /etc/pacman.d/gnupg --no-permission-warning \
        --verify "$dest.sig" "$dest" >/dev/null 2>&1 \
        || monarchy_die "signature check failed for $file"
    monarchy_log "signature verified for $file"
}

monarchy_ensure_settings_pkg() {
    local full ver required want have skip built tmp
    # Full upstream version incl. pkgrel ("4.0.2-1"): that is what names the
    # file on the mirror.
    full=$(monarchy_repo_pkg_version omarchy-settings)
    [ -n "$full" ] || monarchy_die "omarchy-settings not found in [omarchy]"
    # pkgver cannot hold a pkgrel, and omarchy depends on omarchy-settings=4.0.2
    # with no pkgrel either, so the provides has to be the bare version.
    ver=${full%-*}

    required=$(monarchy_settings_required_version)
    if [ -n "$required" ] && [ "$required" != "$ver" ]; then
        monarchy_die "omarchy needs omarchy-settings=$required but [omarchy] has $ver; run cachy-update first"
    fi

    want="${ver}-1"
    have=$(monarchy_installed_pkg_version omarchy-settings-monarchy)
    if [ "$have" = "$want" ]; then
        monarchy_log "omarchy-settings-monarchy $have already tracks omarchy-settings=$ver"
        return 0
    fi

    monarchy_assert_can_makepkg
    skip="$MONARCHY_MISC/settings.skip"
    [ -f "$skip" ] || monarchy_die "missing $skip"

    tmp=$(mktemp -d)
    monarchy_fetch_official_settings "$full" "$tmp/upstream.pkg.tar.zst"

    # makepkg sources PKGBUILD in a shell that inherits the environment; the
    # PKGBUILD reads pkgver from here so the version tracks upstream with no
    # file to bump.
    export MONARCHY_SETTINGS_PKGVER="$ver"
    built=$(monarchy_build_pkg omarchy-settings-monarchy \
        "$tmp/upstream.pkg.tar.zst" "$skip")
    unset MONARCHY_SETTINGS_PKGVER
    rm -rf "$tmp"
    monarchy_install_built_pkg "$built"
}

# ---- the official omarchy package ---------------------------------------

# Upstream's guard aborts every pacman upgrade unless it is driven through
# omarchy-update. Monarchy drives updates through monarchy-update, so the
# guard has to go. HookDir wins over /usr/share/libalpm/hooks by filename, so
# an empty file at the same name is the documented way to switch a hook off.
monarchy_mask_omarchy_update_guard() {
    local masked=/etc/pacman.d/hooks/00-omarchy-update-guard.hook
    monarchy_sudo mkdir -p /etc/pacman.d/hooks
    if monarchy_sudo test -f "$masked" && [ ! -s "$masked" ]; then
        return 0
    fi
    monarchy_sudo install -m 644 /dev/null "$masked"
    monarchy_log "masked Omarchy ALPM update guard at $masked"
}

# The bridge that used to point /usr/share/omarchy at the working prefix.
# pacman will not extract through a symlinked directory: with this in place
# every file in the omarchy package reports "exists in filesystem", because
# the check resolves through the link into the prefix. Clearing it is a
# precondition for any transaction that includes omarchy, not just ours --
# a plain `pacman -Syu` that pulls omarchy in via flea fails the same way.
monarchy_clear_legacy_prefix_symlink() {
    [ -L /usr/share/omarchy ] || return 0
    monarchy_log "removing legacy /usr/share/omarchy symlink"
    monarchy_sudo rm -f /usr/share/omarchy
}

monarchy_ensure_omarchy_pkg() {
    # Idempotent; monarchy_build_packages already did this before the stub.
    monarchy_clear_legacy_prefix_symlink
    if monarchy_pkg_exactly omarchy; then
        monarchy_log "omarchy $(monarchy_installed_pkg_version omarchy) already installed"
        return 0
    fi

    # Installing omarchy on its own against a refreshed DB is the partial
    # upgrade monarchy_refuse_partial_upgrade exists to prevent. It is also
    # unnecessary: flea already depends on omarchy, so a full upgrade pulls it
    # in -- and now that the stub, the settings package and the symlink are
    # sorted, that upgrade resolves cleanly. Hand off rather than force it.
    local pending
    pending=$(pacman -Qu 2>/dev/null | grep -c . || true)
    if [ "${pending:-0}" -gt 0 ]; then
        monarchy_die "omarchy is not installed and pacman has $pending pending upgrades. monarchy-boot-stub and omarchy-settings-monarchy are in place and /usr/share/omarchy is clear, so a full upgrade now resolves: run cachy-update (or sudo pacman -Syu), then re-run monarchy-update"
    fi

    monarchy_log "pacman -S omarchy"
    monarchy_sudo pacman -S --needed --noconfirm omarchy \
        || monarchy_die "pacman -S omarchy failed"
}

# ---- unit verbs ---------------------------------------------------------

monarchy_check_pkgbuilds() {
    local name
    for name in monarchy-boot-stub omarchy-settings-monarchy; do
        [ -f "$MONARCHY_PKGBUILDS/$name/PKGBUILD" ] \
            || monarchy_die "missing $MONARCHY_PKGBUILDS/$name/PKGBUILD"
    done
    grep -q "provides=(\"omarchy-settings=\$pkgver\")" \
        "$MONARCHY_PKGBUILDS/omarchy-settings-monarchy/PKGBUILD" \
        || monarchy_die "omarchy-settings-monarchy must provide omarchy-settings=\$pkgver"
    local dep
    for dep in limine limine-mkinitcpio-hook limine-snapper-sync snapper; do
        grep -q "'$dep'" "$MONARCHY_PKGBUILDS/monarchy-boot-stub/PKGBUILD" \
            || monarchy_die "monarchy-boot-stub must provide and conflict with $dep"
    done
    return 0
}

monarchy_build_packages() {
    # First, before any collision planning or install: while this symlink
    # exists, every /usr/share/omarchy path resolves into the working prefix
    # and on into the clone.
    monarchy_clear_legacy_prefix_symlink
    monarchy_ensure_boot_stub
    monarchy_ensure_settings_pkg
    monarchy_mask_omarchy_update_guard
    monarchy_ensure_omarchy_pkg
}
