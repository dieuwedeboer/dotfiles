#!/usr/bin/env bash
# The two local packages. No sudo, no network, no writes outside a temp dir.
#
# This is bricking surface: omarchy-settings-monarchy is the only thing
# standing between an `omarchy` install and upstream's post_install, which
# does `rm -f /etc/os-release` and overwrites nsswitch.conf on every upgrade.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"
# shellcheck source=../../lib/monarchy/common.sh
source "$LIB/common.sh"
# shellcheck source=../../lib/monarchy/denylist.sh
source "$LIB/denylist.sh"
# shellcheck source=../../lib/monarchy/pkgbuild.sh
source "$LIB/pkgbuild.sh"

PKGB="$REPO/pkgbuilds"
stub="$PKGB/monarchy-boot-stub/PKGBUILD"
settings="$PKGB/omarchy-settings-monarchy/PKGBUILD"
[ -f "$stub" ] || fail "missing $stub"
[ -f "$settings" ] || fail "missing $settings"

# ---- the boot stub ------------------------------------------------------

# Both halves matter. provides= is what lets `omarchy` resolve; conflicts= is
# what stops a later `pacman -S` quietly landing the real limine hook.
for dep in limine limine-mkinitcpio-hook limine-snapper-sync snapper; do
    n=$(grep -c "^  '$dep'$" "$stub" || true)
    [ "$n" -eq 2 ] || fail "$dep appears $n times in the stub; expected once in provides and once in conflicts"
done
grep -q '^provides=(' "$stub" || fail "stub has no provides"
grep -q '^conflicts=(' "$stub" || fail "stub has no conflicts"
# It must own nothing that could shadow a real binary.
grep -q 'usr/bin' "$stub" && fail "the stub must not install anything into /usr/bin"

# ---- the settings replacement -------------------------------------------

# shellcheck disable=SC2016  # grep patterns for the literal $pkgver/$pkgdir
grep -q 'provides=("omarchy-settings=\$pkgver")' "$settings" \
    || fail "settings package must provide omarchy-settings=\$pkgver"
grep -q "^conflicts=('omarchy-settings' 'omarchy-settings-dev')" "$settings" \
    || fail "settings package must conflict with omarchy-settings and -dev"
grep -q "^replaces=('omarchy-settings')" "$settings" \
    || fail "settings package must replace omarchy-settings"
# shellcheck disable=SC2016
grep -q 'rm -f "\$pkgdir/.PKGINFO" "\$pkgdir/.MTREE" "\$pkgdir/.BUILDINFO" "\$pkgdir/.INSTALL"' "$settings" \
    || fail "settings package must drop upstream's .INSTALL"
# shellcheck disable=SC2016
grep -q 'rm -rf "\$pkgdir/usr/share/omarchy/etc-overrides"' "$settings" \
    || fail "settings package must drop the etc-overrides tree"

# ---- the guards that keep the real ones out -----------------------------

monarchy_load_inventories
for p in snapper limine limine-mkinitcpio-hook limine-snapper-sync \
    omarchy-settings omarchy-settings-dev omarchy-dev; do
    monarchy_in_list "$p" "${MONARCHY_PKG_DENY[@]}" || fail "$p missing from packages.deny"
done
# omarchy is installed on purpose now; denying it would be the old design.
monarchy_in_list omarchy "${MONARCHY_PKG_DENY[@]}" \
    && fail "omarchy must not be in packages.deny any more"

monarchy_check_pkgbuilds || fail "monarchy_check_pkgbuilds rejected the shipped PKGBUILDs"

# ---- version tracking ---------------------------------------------------

# omarchy depends on omarchy-settings=<exact>, so the replacement has to
# provide that same bare version or the dep does not resolve.
parse=$(printf 'Name            : omarchy\nVersion         : 4.0.2-1\nDepends On      : omarchy-keyring  omarchy-settings=4.0.2  limine  snapper\n' \
    | monarchy_parse_settings_pin)
[ "$parse" = "4.0.2" ] || fail "settings version parse produced '$parse', expected 4.0.2"

# A release bump: the sync DB has omarchy 4.0.4 pinning settings 4.0.4, the
# installed omarchy still pins 4.0.2. Installing our 4.0.4 on its own breaks
# that dependency and pacman refuses; the full upgrade cannot go first
# because it wants the upstream omarchy-settings. The install has to carry
# --assume-installed for the old pin, then hand off to the full upgrade.
bump=$(mktemp -d)
(
    installed_omarchy=4.0.2
    # shellcheck disable=SC2329  # stubs called by the function under test
    pacman() {
        case "$*" in
            "-Si omarchy") printf 'Version         : 4.0.4-1\nDepends On      : omarchy-keyring  omarchy-settings=4.0.4  limine\n' ;;
            "-Si omarchy-settings") printf 'Version         : 4.0.4-1\n' ;;
            "-Qi omarchy") printf 'Version         : %s-1\nDepends On      : omarchy-keyring  omarchy-settings=%s  limine\n' "$installed_omarchy" "$installed_omarchy" ;;
            "-Q omarchy-settings-monarchy") echo "omarchy-settings-monarchy 4.0.2-1" ;;
            *) return 1 ;;
        esac
    }
    # shellcheck disable=SC2329
    monarchy_assert_can_makepkg() { :; }
    # shellcheck disable=SC2329
    monarchy_fetch_official_settings() { :; }
    # shellcheck disable=SC2329
    monarchy_build_pkg() { echo "$bump/omarchy-settings-monarchy-4.0.4-1-any.pkg.tar.zst"; }
    # shellcheck disable=SC2329
    monarchy_install_built_pkg() { printf '%s\n' "$@" >"$bump/args"; }
    # shellcheck disable=SC2034  # read by monarchy_ensure_settings_pkg
    MONARCHY_MISC="$bump"
    # shellcheck disable=SC2034
    MONARCHY_LOG="$bump/log"
    : >"$bump/settings.skip"

    if ( monarchy_ensure_settings_pkg ) >/dev/null 2>&1; then
        echo "a release bump did not stop to hand off to the full upgrade" >&2
        exit 1
    fi
    grep -qx -- '--assume-installed' "$bump/args" && grep -qx 'omarchy-settings=4.0.2' "$bump/args" || {
        echo "a release bump installed without --assume-installed omarchy-settings=4.0.2:" >&2
        cat "$bump/args" >&2
        exit 1
    }

    # Same version installed and in the repo: a plain rebuild, no assume.
    installed_omarchy=4.0.4
    rm -f "$bump/args"
    ( monarchy_ensure_settings_pkg ) >/dev/null 2>&1 \
        || { echo "a rebuild with no bump failed" >&2; exit 1; }
    grep -q -- '--assume-installed' "$bump/args" \
        && { echo "a rebuild with no bump passed --assume-installed" >&2; exit 1; }
    exit 0
) || fail "monarchy_ensure_settings_pkg mishandles an omarchy release bump"
rm -rf "$bump"

# ---- the exclusion list, against the real package ------------------------

# settings.skip is a build input: a path it names that upstream no longer
# ships is a build error, because a hazard that comes back under a new name
# must be reclassified rather than silently skipped. Prove that against the
# actual package rather than trusting the list.
skip="$MISC/settings.skip"
[ -f "$skip" ] || fail "missing $skip"
upstream=$(find /var/cache/pacman/pkg -maxdepth 1 -name 'omarchy-settings-*.pkg.tar.zst' \
    -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- || true)
if [ -z "$upstream" ] || ! command -v bsdtar >/dev/null 2>&1; then
    echo "test-pkgbuild: no cached omarchy-settings package; skipping the exclusion arm" >&2
else
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    bsdtar -xpf "$upstream" -C "$tmp" 2>/dev/null || fail "could not extract $upstream"

    # Every skip entry must exist upstream, or the build would abort.
    while read -r rel; do
        case "$rel" in ''|\#*) continue ;; esac
        [ -e "$tmp/$rel" ] || [ -L "$tmp/$rel" ] \
            || fail "settings.skip lists $rel, which is not in $(basename "$upstream")"
        rm -rf "${tmp:?}/$rel"
    done <"$skip"
    rm -rf "$tmp/usr/share/omarchy/etc-overrides"
    rm -f "$tmp/.PKGINFO" "$tmp/.MTREE" "$tmp/.BUILDINFO" "$tmp/.INSTALL"

    # What must not survive the rebuild.
    for gone in etc/os-release etc/nsswitch.conf etc/security/faillock.conf \
        etc/skel/.bashrc etc/limine-entry-tool.d etc/snapper \
        usr/share/omarchy/etc-overrides .INSTALL; do
        [ ! -e "$tmp/$gone" ] || fail "$gone survived the rebuild"
    done

    # What must survive, or the package is not worth installing.
    for kept in usr/share/omarchy/default usr/share/omarchy/config \
        usr/share/omarchy/applications usr/lib/systemd/user \
        usr/share/fonts/omarchy/omarchy.ttf etc/sudoers.d/omarchy-dns; do
        [ -e "$tmp/$kept" ] || fail "$kept was dropped; the skip list is too broad"
    done

    # The upstream scriptlet is the whole reason this package exists.
    if bsdtar -xOqf "$upstream" .INSTALL 2>/dev/null | grep -q 'rm -f /etc/os-release'; then
        :
    else
        fail "upstream omarchy-settings no longer clobbers /etc/os-release; re-check whether this package is still needed"
    fi
fi

# ---- taking ownership of hand-installed paths ---------------------------

# The old settings.sh copied ~286 files into /etc by hand, so pacman owns none
# of them and refuses to extract over them. These are planned as
# `pacman -U --overwrite` arguments rather than deleted.
# shellcheck disable=SC2016  # grep patterns for literal $pkg / $p in the source
grep -q 'monarchy_plan_overwrites "$pkg"' "$LIB/pkgbuild.sh" \
    || fail "monarchy_install_built_pkg does not plan overwrites"
# shellcheck disable=SC2016  # grep pattern for the literal array expansion
grep -qF 'MONARCHY_OVERWRITE_ARGS[@]}" "$@" "$pkg"' "$LIB/pkgbuild.sh" \
    || fail "pacman -U is not passed the planned --overwrite arguments"
# shellcheck disable=SC2016
grep -q 'rm -f "\$p"' "$LIB/pkgbuild.sh" \
    && fail "pkgbuild.sh still deletes colliding paths; let pacman replace them"

# The symlink has to go before any collision planning, not just before
# `pacman -S omarchy`.
bp_body=$(awk '/^monarchy_build_packages\(\)/,/^}$/' "$LIB/pkgbuild.sh")
clear_at=$(printf '%s\n' "$bp_body" | grep -n 'monarchy_clear_legacy_prefix_symlink' | head -1 | cut -d: -f1)
stub_at=$(printf '%s\n' "$bp_body" | grep -n 'monarchy_ensure_boot_stub' | head -1 | cut -d: -f1)
[ -n "$clear_at" ] || fail "monarchy_build_packages does not clear the legacy symlink"
[ "$clear_at" -lt "$stub_at" ] \
    || fail "the legacy symlink is cleared after the first package install; that is the bug that deleted the clone"

# settings.skip must exclude the one path that collides with another package
# rather than with an unowned file.
grep -qx 'etc/skel/.config/alacritty/alacritty.toml' "$skip" \
    || fail "settings.skip must exclude the cachyos-alacritty-config skel file"

if command -v bsdtar >/dev/null 2>&1 && command -v realpath >/dev/null 2>&1; then
    rt=$(mktemp -d)
    mkdir -p "$rt/root/etc" "$rt/pkg/etc" "$rt/pkg/usr/share/omarchy/themes" "$rt/elsewhere/themes"
    printf 'hand-installed\n' >"$rt/root/etc/unowned.conf"
    printf 'someone elses\n' >"$rt/root/etc/owned.conf"
    printf 'x\n' >"$rt/pkg/etc/unowned.conf"
    printf 'x\n' >"$rt/pkg/etc/owned.conf"
    printf 'x\n' >"$rt/pkg/usr/share/omarchy/themes/preview.png"
    ( cd "$rt/pkg" && bsdtar -cf "$rt/fake.pkg.tar" etc usr ) || fail "could not build a fake package"

    # Read by monarchy_plan_overwrites, not by this file.
    # shellcheck disable=SC2034
    MONARCHY_ROOT="$rt/root"
    # shellcheck disable=SC2329  # called indirectly by the function under test
    monarchy_sudo() { "$@"; }

    # 1. Unowned collisions become --overwrite arguments, and nothing is deleted.
    # shellcheck disable=SC2329
    pacman() { return 1; }
    monarchy_plan_overwrites "$rt/fake.pkg.tar" >/dev/null 2>&1 \
        || fail "planning refused a tree of purely unowned files"
    [ -s "$rt/root/etc/unowned.conf" ] || fail "planning deleted a file; it must only plan"
    printf '%s\n' "${MONARCHY_OVERWRITE_ARGS[@]}" | grep -qx -- "--overwrite=$rt/root/etc/unowned.conf" \
        || fail "the unowned collision did not become an --overwrite argument"

    # 2. A file owned by another package is a clash, not a cleanup.
    # shellcheck disable=SC2329
    pacman() {
        case "$*" in
            *-Qoq*owned.conf) echo cachyos-alacritty-config; return 0 ;;
            *) return 1 ;;
        esac
    }
    if ( monarchy_plan_overwrites "$rt/fake.pkg.tar" ) >/dev/null 2>&1; then
        fail "planning ignored a file owned by another package"
    fi
    [ -s "$rt/root/etc/owned.conf" ] || fail "planning removed another package's file"

    # 3. THE REGRESSION. With a legacy /usr/share/omarchy symlink in place,
    #    every path under it resolves into the working prefix and on into the
    #    git clone. Planning must refuse, not follow it.
    # shellcheck disable=SC2329
    pacman() { return 1; }
    printf 'clone file\n' >"$rt/elsewhere/themes/preview.png"
    mkdir -p "$rt/root/usr/share"
    ln -s "$rt/elsewhere" "$rt/root/usr/share/omarchy"
    if ( monarchy_plan_overwrites "$rt/fake.pkg.tar" ) >/dev/null 2>&1; then
        fail "planning followed the legacy /usr/share/omarchy symlink out of the install root"
    fi
    [ -s "$rt/elsewhere/themes/preview.png" ] \
        || fail "planning touched a file behind the legacy symlink"

    # 4. THE OTHER REGRESSION. /etc/sudoers.d is 0750 root:root, so an
    #    unprivileged `[ -e ]` is false for every file inside it. The planner
    #    skipped all four omarchy sudoers drop-ins, planned no --overwrite,
    #    and pacman refused the transaction on exactly those files. The
    #    existence probe has to run with pacman's privileges.
    grep -q 'monarchy_sudo bash -c' "$LIB/pkgbuild.sh" \
        || fail "monarchy_probe_paths does not elevate; it will miss files in root-only directories"
    probe_body=$(awk '/^monarchy_probe_paths\(\)/,/^}$/' "$LIB/pkgbuild.sh")
    printf '%s\n' "$probe_body" | grep -q 'monarchy_sudo' \
        || fail "monarchy_probe_paths must probe through monarchy_sudo"

    rm -f "$rt/root/usr/share/omarchy"
    elevated=$rt/elevated
    : >"$elevated"
    # shellcheck disable=SC2329
    monarchy_sudo() { echo called >>"$elevated"; "$@"; }
    # shellcheck disable=SC2329
    pacman() { return 1; }
    monarchy_plan_overwrites "$rt/fake.pkg.tar" >/dev/null 2>&1 \
        || fail "planning failed after the symlink was removed"
    [ -s "$elevated" ] || fail "planning probed paths without elevating"

    unset -f pacman monarchy_sudo
    unset MONARCHY_ROOT
    rm -rf "$rt"
fi

# ---- monarchy_build_pkg returns a path, and only a path ------------------

# It returns the built package path on stdout while also logging, and
# monarchy_log echoes to stdout. Capturing both produced a two-line "path"
# and `pacman -U` failed with "could not find or read package". Nothing in
# the suite noticed, because building needs makepkg -- so stub it.
bp=$(mktemp -d)
mkdir -p "$bp/bin" "$bp/pkgbuilds/fakepkg"
cat >"$bp/bin/makepkg" <<'MK'
#!/bin/sh
echo "makepkg chatter on stdout"
: >"fakepkg-1-1-any.pkg.tar.zst"
MK
chmod +x "$bp/bin/makepkg"
printf 'pkgname=fakepkg\npkgver=1\n' >"$bp/pkgbuilds/fakepkg/PKGBUILD"

(
    PATH="$bp/bin:$PATH"
    # Read by monarchy_build_pkg, which is sourced, not defined here.
    # shellcheck disable=SC2034
    MONARCHY_PKGBUILDS="$bp/pkgbuilds"
    # shellcheck disable=SC2034
    MONARCHY_BUILD_DIR="$bp/build"
    # shellcheck disable=SC2034
    MONARCHY_LOG="$bp/log"
    out=$(monarchy_build_pkg fakepkg 2>/dev/null)
    lines=$(printf '%s\n' "$out" | grep -c .)
    [ "$lines" -eq 1 ] || {
        echo "monarchy_build_pkg returned $lines lines, expected 1:" >&2
        printf '%s\n' "$out" >&2
        exit 1
    }
    [ -f "$out" ] || { echo "returned path is not a file: $out" >&2; exit 1; }
    case "$out" in
        *.pkg.tar.zst) ;;
        *) echo "returned path is not a package: $out" >&2; exit 1 ;;
    esac
) || fail "monarchy_build_pkg does not return a bare package path on stdout"
rm -rf "$bp"

# ---- the override lists against the REAL package ------------------------

# test-overlay builds its tree from bin.deny and bin.wrap, so by construction
# every name in them exists there and a stale entry can never fail. Check the
# lists against the tree the packages actually install.
# omarchy-upgrade-to-quattro-zfs-check survived the move off the fork this
# way: it only ever existed in berenddeboer/omarchy, and the first thing to
# notice was a failed apply on the box.
tree=$(require_omarchy_tree)
[ -d "$tree/bin" ] || fail "$tree has no bin/"
stale=0
for name in "${MONARCHY_BIN_DENY[@]}" "${MONARCHY_BIN_WRAP[@]}"; do
    [ -e "$tree/bin/$name" ] && continue
    echo "  overridden name not in the omarchy package: $name" >&2
    stale=1
done
[ "$stale" = 0 ] || fail "monarchy/bin.deny or bin.wrap names a binary the package does not ship"

echo "pkgbuild tests passed"
