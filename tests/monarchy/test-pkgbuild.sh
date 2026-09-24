#!/usr/bin/env bash
# The local packages, and the file planning that installs them. No sudo, no
# network, no writes outside a temp dir.
#
# Two failures here strand someone or cannot be undone:
#
#   * the bootloader packages. The real limine hook shadows the stock
#     mkinitcpio one and hands ESP entries to limine-entry-tool; snapper wants
#     btrfs. Either one lands and the next kernel upgrade produces a machine
#     that does not boot.
#   * monarchy_plan_overwrites walks a package's file list against the install
#     root to decide what pacman may overwrite. With the legacy
#     /usr/share/omarchy symlink in place, every path under it resolved out of
#     the root and into the git clone -- and planning to overwrite files there
#     is not a mistake you get to take back.
#
# The rest of the packaging story -- version pins, release-bump handoffs,
# whether monarchy_build_pkg returns one line -- fails loudly with nothing
# changed on disk, and is uncovered. See CODING_STANDARDS.md.
#
# What settings.skip excludes from the rebuilt omarchy-settings is not checked
# here either. Doing it properly means diffing against the upstream package,
# which is never installed on these boxes on purpose, so the arm that tried it
# was gated on a pacman cache entry that is not there and had been skipping
# silently for a long time. The guard that actually holds is in the build: a
# settings.skip row naming a path upstream no longer ships aborts the package
# build, so a hazard returning under a new name has to be reclassified.
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

monarchy_load_inventories

# --- the guards that keep the bootloader packages out --------------------

for p in snapper limine limine-mkinitcpio-hook limine-snapper-sync \
    omarchy-settings omarchy-settings-dev omarchy-dev; do
    monarchy_in_list "$p" "${MONARCHY_PKG_DENY[@]}" || fail "$p missing from packages.deny"
done

monarchy_check_pkgbuilds || fail "monarchy_check_pkgbuilds rejected the shipped PKGBUILDs"

# --- planning overwrites -------------------------------------------------

# The old settings.sh copied ~286 files into /etc by hand, so pacman owns none
# of them and refuses to extract over them. They are planned as
# `pacman -U --overwrite` arguments rather than deleted.
if command -v bsdtar >/dev/null 2>&1; then
    rt=$(mktemp -d)
    mkdir -p "$rt/root/etc" "$rt/pkg/etc" "$rt/pkg/usr/share/omarchy/themes" "$rt/elsewhere/themes"
    printf 'hand-installed\n' >"$rt/root/etc/unowned.conf"
    printf 'someone elses\n' >"$rt/root/etc/owned.conf"
    printf 'x\n' >"$rt/pkg/etc/unowned.conf"
    printf 'x\n' >"$rt/pkg/etc/owned.conf"
    printf 'x\n' >"$rt/pkg/usr/share/omarchy/themes/preview.png"
    ( cd "$rt/pkg" && bsdtar -cf "$rt/fake.pkg.tar" etc usr ) || fail "could not build a fake package"

    # shellcheck disable=SC2034  # read by monarchy_plan_overwrites
    MONARCHY_ROOT="$rt/root"
    elevated=$rt/elevated
    : >"$elevated"
    # /etc/sudoers.d is 0750 root:root, so an unprivileged `[ -e ]` is false
    # for every file inside it. The planner skipped all four omarchy drop-ins,
    # planned no --overwrite, and pacman refused the transaction on exactly
    # those files. The existence probe has to run with pacman's privileges.
    # shellcheck disable=SC2329  # called indirectly by the function under test
    monarchy_sudo() { echo called >>"$elevated"; "$@"; }

    # 1. Unowned collisions become --overwrite arguments, and nothing is
    #    deleted or touched.
    # shellcheck disable=SC2329
    pacman() { return 1; }
    monarchy_plan_overwrites "$rt/fake.pkg.tar" >/dev/null 2>&1 \
        || fail "planning refused a tree of purely unowned files"
    [ "$(cat "$rt/root/etc/unowned.conf")" = "hand-installed" ] \
        || fail "planning changed a file; it must only plan"
    printf '%s\n' "${MONARCHY_OVERWRITE_ARGS[@]}" \
        | grep -qx -- "--overwrite=$rt/root/etc/unowned.conf" \
        || fail "the unowned collision did not become an --overwrite argument"
    [ -s "$elevated" ] || fail "planning probed paths without elevating"

    # 2. A file owned by another package is a clash to stop on, not a
    #    cleanup to plan around.
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
    [ "$(cat "$rt/root/etc/owned.conf")" = "someone elses" ] \
        || fail "planning changed another package's file"

    # 3. THE REGRESSION. With a legacy /usr/share/omarchy symlink in place,
    #    every path under it resolves out of the install root and into the
    #    clone. Planning must refuse rather than follow it.
    # shellcheck disable=SC2329
    pacman() { return 1; }
    printf 'clone file\n' >"$rt/elsewhere/themes/preview.png"
    mkdir -p "$rt/root/usr/share"
    ln -s "$rt/elsewhere" "$rt/root/usr/share/omarchy"
    if ( monarchy_plan_overwrites "$rt/fake.pkg.tar" ) >/dev/null 2>&1; then
        fail "planning followed the legacy /usr/share/omarchy symlink out of the install root"
    fi
    [ "$(cat "$rt/elsewhere/themes/preview.png")" = "clone file" ] \
        || fail "planning changed a file behind the legacy symlink"

    unset -f pacman monarchy_sudo
    unset MONARCHY_ROOT
    rm -rf "$rt"
fi

# --- the override lists, against the real package ------------------------

# test-overlay builds its tree from bin.deny and bin.wrap, so by construction
# every name in them exists there and a stale entry can never fail. A stale
# entry hides a rename, and a renamed hazard is one the classification guard
# never sees. omarchy-upgrade-to-quattro-zfs-check survived the move off the
# fork this way; the first thing to notice was a failed apply on the box.
tree=$(require_omarchy_tree)
stale=""
for name in "${MONARCHY_BIN_DENY[@]}" "${MONARCHY_BIN_WRAP[@]}"; do
    [ -e "$tree/bin/$name" ] || stale="$stale $name"
done
[ -z "$stale" ] \
    || fail "bin.deny or bin.wrap names binaries the omarchy package does not ship:$stale"

echo "pkgbuild tests passed"
