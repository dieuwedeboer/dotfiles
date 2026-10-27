# shellcheck shell=bash
# Build and install the two local packages that let the official `omarchy`
# or `omarchy-dev` package run on this host. monarchy_load_channel says which.
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

# The version the locked package pins its settings package to. omarchy
# depends on omarchy-settings=<exact>, so our replacement has to provide that
# same version or the dep does not resolve. omarchy-dev depends on
# omarchy-settings-dev with no version, so for it this is empty.
monarchy_settings_required_version() {
    pacman -Si "$MONARCHY_OMARCHY_PACKAGE" 2>/dev/null | monarchy_parse_settings_pin
}

# The same pin, read from the omarchy that is installed now. On a release
# bump this is the old version while the sync DB already has the new one.
monarchy_installed_settings_pin() {
    pacman -Qi omarchy 2>/dev/null | monarchy_parse_settings_pin
}

# stdin: `pacman -Si` / `-Qi` output for omarchy or omarchy-dev.
monarchy_parse_settings_pin() {
    awk -F': ' '$1 ~ /^Depends On/ { print $2 }' \
        | tr ' ' '\n' \
        | sed -n 's/^omarchy-settings\(-dev\)\{0,1\}=\(.*\)$/\2/p' \
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
    ( cd "$build" && monarchy_spin "Building $name" \
        makepkg --force --clean --nodeps --noconfirm >/dev/null ) \
        || monarchy_die "makepkg failed for $name (see $build)"

    # Not a glob over $build: a source can itself be a package, as
    # omarchy-settings-monarchy's upstream.pkg.tar.zst is.
    local built
    built=$( cd "$build" && makepkg --packagelist 2>/dev/null | head -n1 )
    [ -n "$built" ] && [ -f "$built" ] || monarchy_die "makepkg produced no package for $name"
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
    local f p owner rc root_canon parent_canon expected_parent probed
    local -a clashes=() escapes=()
    MONARCHY_OVERWRITE_ARGS=()
    MONARCHY_HANDOVER_PATHS=()
    root_canon=$(realpath -m "${MONARCHY_ROOT:-/}" 2>/dev/null) || root_canon=/
    root_canon=${root_canon%/}

    # Captured rather than read from a process substitution, whose status is
    # lost. A probe that could not elevate prints nothing, which read exactly
    # like "no file exists yet": no --overwrite was planned and pacman then
    # refused the transaction with a message that named neither cause.
    probed=$(
        bsdtar tf "$pkg" 2>/dev/null \
            | while IFS= read -r f; do
                case "$f" in ''|.*|*/) continue ;; esac
                printf '%s\n' "${MONARCHY_ROOT:-}/$f"
            done \
            | monarchy_probe_paths
    ) || monarchy_die "could not check which of $(basename "$pkg")'s paths already exist (sudo refused?)"

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

        # Exit 1 is "no owner". Anything else (pacman segfaulted here once)
        # must not read as unowned, or the clash check is skipped and the
        # file is planned as an --overwrite.
        owner=$(pacman -Qoq "$p" 2>/dev/null) && rc=0 || rc=$?
        case "$rc" in
            0|1) ;;
            *) monarchy_die "pacman -Qoq failed (exit $rc) on $p; cannot tell who owns it" ;;
        esac
        if [ -n "$owner" ]; then
            case "$owner" in
                monarchy-boot-stub|omarchy-settings-monarchy) continue ;;
                # Upstream moved this file from the Omarchy package into the
                # settings package. pacman hands it over only when both
                # change in one transaction; see monarchy_ensure_settings_pkg.
                omarchy|omarchy-dev)
                    MONARCHY_HANDOVER_PATHS+=("$p")
                    continue ;;
            esac
            clashes+=("$p (owned by $(printf '%q' "$owner"))")
            continue
        fi
        MONARCHY_OVERWRITE_ARGS+=("--overwrite=$p")
    done <<<"$probed"

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

# Extra arguments after the package go to pacman as-is.
monarchy_install_built_pkg() {
    local pkg=$1
    shift
    monarchy_plan_overwrites "$pkg"
    monarchy_log "pacman -U $(basename "$pkg")"
    local -a needed=(--needed)
    [ "${MONARCHY_PKG_REINSTALL:-0}" = 1 ] && needed=()
    monarchy_sudo pacman -U --noconfirm "${needed[@]}" \
        "${MONARCHY_OVERWRITE_ARGS[@]}" "$@" "$pkg" \
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
        monarchy_trace "monarchy-boot-stub $have already installed"
        return 0
    fi
    monarchy_assert_can_makepkg
    local built
    built=$(monarchy_build_pkg monarchy-boot-stub)
    monarchy_install_built_pkg "$built"
}

# ---- omarchy-settings-monarchy ------------------------------------------

# stdin: an upstream package. Prints the values of one .PKGINFO key, one per
# line.
monarchy_pkginfo_values() {
    bsdtar -xOf - .PKGINFO 2>/dev/null \
        | awk -F' = ' -v k="$1" '$1==k { print $2 }'
}

# Fetch the official settings package for the locked Omarchy package straight
# from [omarchy] and verify it against pacman's keyring. `pacman -Sw
# omarchy-settings` cannot be used: our
# replacement conflicts with that name, so resolution refuses before it
# downloads anything.
monarchy_fetch_official_settings() {
    local full=$1 dest=$2
    local arch file url
    arch=$(pacman -Si "$MONARCHY_SETTINGS_UPSTREAM" 2>/dev/null \
        | awk -F': ' '$1 ~ /^Architecture/ { print $2; exit }' | tr -d ' ')
    [ -n "$arch" ] || monarchy_die "could not read $MONARCHY_SETTINGS_UPSTREAM Architecture from [omarchy]"
    # Path segment is the repo arch; the filename carries the package's own
    # arch, which for omarchy-settings is "any".
    file="${MONARCHY_SETTINGS_UPSTREAM}-${full}-${arch}.pkg.tar.zst"
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
    full=$(monarchy_repo_pkg_version "$MONARCHY_SETTINGS_UPSTREAM")
    [ -n "$full" ] || monarchy_die "$MONARCHY_SETTINGS_UPSTREAM not found in [omarchy]"
    # pkgver cannot hold a pkgrel, and omarchy depends on omarchy-settings=4.0.2
    # with no pkgrel either, so the provides has to be the bare version.
    ver=${full%-*}

    required=$(monarchy_settings_required_version)
    if [ -n "$required" ] && [ "$required" != "$ver" ]; then
        monarchy_die "$MONARCHY_OMARCHY_PACKAGE needs $MONARCHY_SETTINGS_UPSTREAM=$required but [omarchy] has $ver; the repo is mid-publish, try again shortly"
    fi

    want="${ver}-1"
    have=$(monarchy_installed_pkg_version omarchy-settings-monarchy)
    skip="$MONARCHY_MISC/settings.skip"
    [ -f "$skip" ] || monarchy_die "missing $skip"
    local reinstall=0
    if [ "$have" = "$want" ]; then
        # The same version, built before a row was added to settings.skip,
        # still carries what the row excludes.
        if ! monarchy_settings_owns_skipped "$skip"; then
            monarchy_trace "omarchy-settings-monarchy $have already tracks $MONARCHY_SETTINGS_UPSTREAM=$ver"
            return 0
        fi
        monarchy_log "omarchy-settings-monarchy $have carries a path settings.skip now excludes; rebuilding"
        reinstall=1
    fi

    monarchy_assert_can_makepkg

    tmp=$(mktemp -d)
    monarchy_fetch_official_settings "$full" "$tmp/upstream.pkg.tar.zst"

    # makepkg sources PKGBUILD in a shell that inherits the environment; the
    # PKGBUILD reads pkgver from here so the version tracks upstream with no
    # file to bump.
    export MONARCHY_SETTINGS_PKGVER="$ver"
    export MONARCHY_SETTINGS_UPSTREAM
    MONARCHY_SETTINGS_DEPENDS=$(monarchy_pkginfo_values depend <"$tmp/upstream.pkg.tar.zst" | tr '\n' ' ')
    [ -n "$MONARCHY_SETTINGS_DEPENDS" ] \
        || monarchy_die "could not read depends from $MONARCHY_SETTINGS_UPSTREAM's .PKGINFO"
    # Upstream provides the two settings names unversioned; the PKGBUILD
    # provides them versioned itself.
    MONARCHY_SETTINGS_PROVIDES=$(monarchy_pkginfo_values provides <"$tmp/upstream.pkg.tar.zst" \
        | grep -Ev '^omarchy-settings(-dev)?(=|$)' | tr '\n' ' ' || true)
    export MONARCHY_SETTINGS_DEPENDS MONARCHY_SETTINGS_PROVIDES
    built=$(monarchy_build_pkg omarchy-settings-monarchy \
        "$tmp/upstream.pkg.tar.zst" "$skip")
    unset MONARCHY_SETTINGS_PKGVER MONARCHY_SETTINGS_DEPENDS MONARCHY_SETTINGS_PROVIDES
    rm -rf "$tmp"

    # A release bump. The installed omarchy still pins the old settings
    # version, so installing ours alone "breaks dependency" and pacman
    # refuses; the new omarchy cannot come first either, because -Syu then
    # wants the upstream omarchy-settings we conflict with. Deadlock, unless
    # pacman is told the old version stays satisfied for this one
    # transaction. The full upgrade that follows replaces omarchy and the
    # pin matches again. Pulling the new omarchy in here instead would be a
    # partial upgrade, which cachy-update owns.
    local pinned
    local -a assume=()
    pinned=$(monarchy_installed_settings_pin)
    if [ -n "$pinned" ] && [ "$pinned" != "$ver" ]; then
        assume=(--assume-installed "omarchy-settings=$pinned")
    fi

    # A file upstream moved out of the Omarchy package and into settings is
    # still owned by the installed Omarchy package, and pacman refuses ours on
    # its own. It hands a file between packages only inside one transaction,
    # so the new Omarchy package comes along in this one. --overwrite instead
    # would leave the file listed under both, and the upgrade that drops it
    # from Omarchy would then delete it. ADR 0004.
    local -a handover=()
    monarchy_plan_overwrites "$built"
    if [ "${#MONARCHY_HANDOVER_PATHS[@]}" -gt 0 ] \
        && monarchy_pkg_exactly "$MONARCHY_OMARCHY_PACKAGE"; then
        printf '  %s\n' "${MONARCHY_HANDOVER_PATHS[@]}"
        monarchy_log "the paths above move from $MONARCHY_OMARCHY_PACKAGE to settings; upgrading both together"
        local locked
        locked=$(monarchy_fetch_locked_pkg) || exit 1
        handover=("$locked")
        assume=()
    fi
    MONARCHY_PKG_REINSTALL=$reinstall monarchy_install_built_pkg "$built" "${assume[@]}" "${handover[@]}"
    if [ "${#handover[@]}" -gt 0 ]; then
        monarchy_reload_hyprland "after upgrading $MONARCHY_OMARCHY_PACKAGE"
        monarchy_changed "$MONARCHY_OMARCHY_PACKAGE upgraded with omarchy-settings-monarchy, to hand over moved files"
    fi

    # Switching between omarchy and omarchy-dev is the other way out of the
    # old pin: monarchy_ensure_omarchy_pkg replaces the package that holds it.
    if [ ${#assume[@]} -gt 0 ] && monarchy_pkg_exactly "$MONARCHY_OMARCHY_PACKAGE"; then
        # This is a handoff, not a failure: the settings package now tracks
        # the new version and what it is waiting for is the full upgrade. When
        # that upgrade is the next thing this run does, saying so and carrying
        # on is the whole point. Dying here instead would abort the update
        # immediately before the step it is asking for.
        if [ "${MONARCHY_EXPECT_FULL_UPGRADE:-0}" = 1 ]; then
            monarchy_changed "omarchy-settings-monarchy now tracks $MONARCHY_SETTINGS_UPSTREAM=$ver; the upgrade below brings $MONARCHY_OMARCHY_PACKAGE up to it"
            return 0
        fi
        monarchy_die "omarchy-settings-monarchy now tracks $MONARCHY_SETTINGS_UPSTREAM=$ver; installed $MONARCHY_OMARCHY_PACKAGE still pins $pinned. Run 'omarchy update' (or sudo pacman -Syu) to bring it up to that, then re-run monarchy-update"
    fi
}

# While pacman replaces /usr/share/omarchy/default/hypr, a running Hyprland
# that autoreloads registers no binds and drops into emergency mode, and
# nothing reloads it once the tree is back.
monarchy_reload_hyprland() {
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null 2>&1; then
        hyprctl reload >/dev/null 2>&1 || monarchy_warn "hyprctl reload failed $1; run it by hand"
    fi
}

# Download the sync DB's version of the locked Omarchy package, without its
# dependencies, verified by pacman against the repo's SigLevel, and print its
# path in the cache.
monarchy_fetch_locked_pkg() {
    local file dir
    file=$(pacman -Sddp --print-format '%n %f' "$MONARCHY_OMARCHY_PACKAGE" 2>/dev/null \
        | awk -v n="$MONARCHY_OMARCHY_PACKAGE" '$1==n { print $2 }')
    [ -n "$file" ] || monarchy_die "$MONARCHY_OMARCHY_PACKAGE not found in [omarchy]"
    monarchy_log "pacman -Sw $MONARCHY_OMARCHY_PACKAGE" >&2
    monarchy_sudo pacman -Sddw --noconfirm "$MONARCHY_OMARCHY_PACKAGE" >&2 \
        || monarchy_die "could not download $MONARCHY_OMARCHY_PACKAGE"
    while IFS= read -r dir; do
        [ -f "${dir%/}/$file" ] && { printf '%s\n' "${dir%/}/$file"; return 0; }
    done < <(pacman-conf CacheDir)
    monarchy_die "downloaded $file but it is in no pacman CacheDir"
}

# Whether the installed settings package owns any path settings.skip lists.
monarchy_settings_owns_skipped() {
    local skip=$1 owned rel
    owned=$(pacman -Qlq omarchy-settings-monarchy 2>/dev/null) || return 1
    while read -r rel; do
        case "$rel" in ''|\#*) continue ;; esac
        grep -qxF -e "/$rel" -e "/$rel/" <<<"$owned" && return 0
    done <"$skip"
    return 1
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

# Upstream pauses Hyprland's config autoreload before a settings upgrade and
# reloads after it, from two hooks that name omarchy-settings and
# omarchy-settings-dev. A Target is a package name, not a provides, so neither
# fires for omarchy-settings-monarchy: the upgrade rewrites default/hypr under
# a running session, an autoreload lands mid-write, and Hyprland drops to its
# emergency config. Same-named copies in HookDir take precedence; each is
# upstream's hook with our package added as a Target, rebuilt from the
# packaged one so it follows upstream's Exec.
MONARCHY_SETTINGS_HOOKS=(10-omarchy-hyprland-reload-pause.hook 90-omarchy-hyprland-reload-resume.hook)

monarchy_retarget_settings_hooks() {
    local name src dest tmp
    monarchy_sudo mkdir -p /etc/pacman.d/hooks
    for name in "${MONARCHY_SETTINGS_HOOKS[@]}"; do
        src=/usr/share/libalpm/hooks/$name
        dest=/etc/pacman.d/hooks/$name
        [ -f "$src" ] || continue
        tmp=$(mktemp)
        awk '{ print } /^Target = omarchy-settings-dev$/ { print "Target = omarchy-settings-monarchy" }' "$src" >"$tmp"
        grep -qx 'Target = omarchy-settings-monarchy' "$tmp" \
            || monarchy_die "$src no longer targets omarchy-settings-dev; reclassify it"
        if ! monarchy_sudo cmp -s "$tmp" "$dest"; then
            monarchy_sudo install -m 644 "$tmp" "$dest"
            monarchy_changed "retargeted $name at omarchy-settings-monarchy"
        fi
        rm -f "$tmp"
    done
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
    local want=$MONARCHY_OMARCHY_PACKAGE other
    # Idempotent; monarchy_build_packages already did this before the stub.
    monarchy_clear_legacy_prefix_symlink
    if monarchy_pkg_exactly "$want"; then
        monarchy_trace "$want $(monarchy_installed_pkg_version "$want") already installed"
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
        if [ "${MONARCHY_EXPECT_FULL_UPGRADE:-0}" = 1 ]; then
            monarchy_trace "omarchy is not installed; the upgrade below pulls it in through flea"
            return 0
        fi
        monarchy_die "omarchy is not installed and pacman has $pending pending upgrades. monarchy-boot-stub and omarchy-settings-monarchy are in place and /usr/share/omarchy is clear, so a full upgrade now resolves: run 'omarchy update' (or sudo pacman -Syu), then re-run monarchy-update"
    fi

    # omarchy and omarchy-dev conflict, and --noconfirm answers no to removing
    # the other one. Each provides `omarchy`, so -Rdd leaves nothing broken
    # for longer than this function.
    case "$want" in
        omarchy) other=omarchy-dev ;;
        *) other=omarchy ;;
    esac
    if monarchy_pkg_exactly "$other"; then
        monarchy_log "pacman -Rdd $other, to replace it with $want"
        monarchy_sudo pacman -Rdd --noconfirm "$other" \
            || monarchy_die "pacman -Rdd $other failed"
    fi

    monarchy_log "pacman -S $want"
    monarchy_sudo pacman -S --needed --noconfirm "$want" \
        || monarchy_die "pacman -S $want failed; the other Omarchy package is removed, so install one by hand before logging out"

    # Between -Rdd and -S there is no /usr/share/omarchy/default/hypr.
    monarchy_reload_hyprland "after replacing $other"
}

# ---- unit verbs ---------------------------------------------------------

monarchy_check_pkgbuilds() {
    local name
    for name in monarchy-boot-stub omarchy-settings-monarchy; do
        [ -f "$MONARCHY_PKGBUILDS/$name/PKGBUILD" ] \
            || monarchy_die "missing $MONARCHY_PKGBUILDS/$name/PKGBUILD"
    done
    grep -q "provides=(\"omarchy-settings=\$pkgver\" \"omarchy-settings-dev=\$pkgver\")" \
        "$MONARCHY_PKGBUILDS/omarchy-settings-monarchy/PKGBUILD" \
        || monarchy_die "omarchy-settings-monarchy must provide omarchy-settings=\$pkgver and omarchy-settings-dev=\$pkgver"
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
    monarchy_retarget_settings_hooks
    monarchy_ensure_settings_pkg
    monarchy_mask_omarchy_update_guard
    monarchy_ensure_omarchy_pkg
}
