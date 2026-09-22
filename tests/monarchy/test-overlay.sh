#!/usr/bin/env bash
# Rebuild the overlay into a temp prefix. No sudo. No /etc edits.
#
# This used to need the real tree on disk, because the overlay was a symlink
# farm over a git clone and the test had to compare against it. The tree is
# synthetic now, so the test is deterministic, but the overlay is still a full
# mirror: $OMARCHY_PATH/bin is an advertised path that packaged scripts
# resolve their siblings through, not just a PATH element.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"
# shellcheck source=../../lib/monarchy/common.sh
source "$LIB/common.sh"
# shellcheck source=../../lib/monarchy/denylist.sh
source "$LIB/denylist.sh"
# shellcheck source=../../lib/monarchy/overlay.sh
source "$LIB/overlay.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

monarchy_load_inventories

# A stand-in for /usr/share/omarchy: every name we override, plus plain ones
# that must end up in the overlay as symlinks. The sleep pair is the
# regression: omarchy-system-sleep-monitor re-execs itself and the lock helper
# as "$OMARCHY_PATH/bin/<name>", so a sparse overlay killed the service that
# holds logind's delay inhibitor and the box suspended unlocked.
PLAIN=(omarchy omarchy-install-app omarchy-pkg-add omarchy-apply-lock omarchy-plymouth-set-by-theme
    omarchy-system-sleep-monitor omarchy-system-sleep-lock
    omarchy-plugin-validate omarchy-shell)
mkdir -p "$tmp/src/bin"
for name in "${MONARCHY_BIN_DENY[@]}" "${MONARCHY_BIN_WRAP[@]}" "${PLAIN[@]}"; do
    printf '#!/bin/sh\necho %s\n' "$name" >"$tmp/src/bin/$name"
    chmod +x "$tmp/src/bin/$name"
done

export MONARCHY_SRC=$tmp/src
export MONARCHY_PATH=$tmp/prefix
export MONARCHY_INSTALL_SUDO_STUBS=0
export MONARCHY_LOG=$tmp/log
mkdir -p "$MONARCHY_PATH"

monarchy_check_overrides_exist
monarchy_check_bin_hazards
monarchy_rebuild_overlay

dest=$MONARCHY_PATH/bin

# Deny stubs: real files, exit 2.
[ -x "$dest/omarchy-refresh-pacman" ] || fail "deny stub missing"
[ ! -L "$dest/omarchy-refresh-pacman" ] || fail "deny name is a symlink"
set +e
"$dest/omarchy-refresh-pacman" >/dev/null 2>&1
st=$?
set -e
[ "$st" -eq 2 ] || fail "deny stub exit is $st, expected 2"
[ ! -L "$dest/omarchy-apply-system" ] || fail "omarchy-apply-system must stay a deny stub"

# Wraps: real files, the right stub behind each name.
[ -x "$dest/omarchy-update" ] || fail "wrap missing"
grep -q 'monarchy-update' "$dest/omarchy-update" || fail "update wrap is not wrap-update"
[ -x "$dest/omarchy-refresh-plymouth" ] || fail "plymouth wrap missing"
grep -q 'wrap-plymouth does not handle' "$dest/omarchy-refresh-plymouth" \
    || fail "refresh-plymouth is not wrap-plymouth"
[ -x "$dest/omarchy-refresh-sddm" ] || fail "sddm wrap missing"
[ ! -L "$dest/omarchy-refresh-sddm" ] || fail "refresh-sddm wrap is a symlink"
grep -q 'monarchy_refresh_sddm' "$dest/omarchy-refresh-sddm" || fail "refresh-sddm is not wrap-sddm"
[ -x "$dest/omarchy-screensaver" ] || fail "screensaver wrap missing"
grep -q 'monarchy_seed_branding' "$dest/omarchy-screensaver" \
    || fail "screensaver wrap does not seed branding"
[ -x "$dest/omarchy-disk-speedtest" ] || fail "disk-speedtest wrap missing"
grep -q 'zpool list' "$dest/omarchy-disk-speedtest" \
    || fail "disk-speedtest wrap does not resolve the pool"
[ -x "$dest/omarchy-version" ] || fail "version wrap missing"
grep -q 'wrap-version does not handle' "$dest/omarchy-version" || fail "omarchy-version is not wrap-version"
# The one script the ZFS fork actually improved, kept without the fork.
[ -x "$dest/omarchy-snapshot" ] || fail "snapshot wrap missing"
grep -q 'ZFSBootMenu' "$dest/omarchy-snapshot" || fail "snapshot wrap is not the ZFS one"
[ -x "$dest/omarchy-voxtype-config" ] || fail "voxtype-config wrap missing"
[ ! -L "$dest/omarchy-voxtype-config" ] || fail "voxtype-config wrap is a symlink"
grep -q 'omarchy-voxtype-install' "$dest/omarchy-voxtype-config" \
    || fail "voxtype-config wrap does not route missing voxtype to install"
[ -x "$dest/omarchy-battery-status" ] || fail "battery-status wrap missing"
[ ! -L "$dest/omarchy-battery-status" ] || fail "battery-status wrap is a symlink"
grep -q 'estimate_time' "$dest/omarchy-battery-status" \
    || fail "battery-status wrap does not fill in the time estimate"
[ -x "$dest/yay" ] || fail "yay wrapper missing"

# Drive the wrap with a fake PATH so missing voxtype cannot reach
# `voxtype configure` + omarchy-restart-shell, and a present voxtype still
# execs the packaged binary.
vox=$(mktemp -d)
mkdir -p "$vox/bin" "$vox/src/bin"
cat >"$vox/src/bin/omarchy-voxtype-config" <<'EOF'
#!/bin/sh
echo packaged-config
EOF
cat >"$vox/bin/omarchy-launch-floating-terminal-with-presentation" <<'EOF'
#!/bin/sh
printf 'launch:%s\n' "$*"
EOF
cat >"$vox/bin/omarchy-restart-shell" <<'EOF'
#!/bin/sh
echo restarted
EOF
chmod +x "$vox/bin"/* "$vox/src/bin"/*
# Only the fake bin dir. Including /usr/bin would pick up a host voxtype-bin
# and make the missing-binary path untestable. Absolute bash so the PATH
# override does not hide the interpreter.
vox_path="$vox/bin"
vox_bash=$(command -v bash)
vox_out=$(MONARCHY_SRC=$vox/src PATH="$vox_path" "$vox_bash" "$LIB/stubs/wrap-voxtype.sh")
[ "$vox_out" = "launch:omarchy-voxtype-install" ] \
    || fail "missing voxtype did not launch install: $vox_out"
printf '#!/bin/sh\necho voxtype\n' >"$vox/bin/voxtype"
chmod +x "$vox/bin/voxtype"
vox_out=$(MONARCHY_SRC=$vox/src PATH="$vox_path" "$vox_bash" "$LIB/stubs/wrap-voxtype.sh")
[ "$vox_out" = "packaged-config" ] \
    || fail "present voxtype did not exec packaged config: $vox_out"
rm -rf "$vox"

# A name we do not override is mirrored, as a symlink onto the packaged tree.
# Resolving is the whole point: a dangling entry would be worse than none,
# because it shadows /usr/bin as well as failing an absolute call.
for name in "${PLAIN[@]}"; do
    [ -L "$dest/$name" ] || fail "$name is not mirrored into the overlay as a symlink"
    [ -x "$dest/$name" ] || fail "$name does not resolve through the overlay"
    [ "$(readlink "$dest/$name")" = "$MONARCHY_SRC/bin/$name" ] \
        || fail "$name does not point at the packaged tree"
done

# Every packaged name is reachable at $OMARCHY_PATH/bin, override or not.
while IFS= read -r name; do
    [ -e "$dest/$name" ] || fail "packaged name $name is missing from the overlay"
done < <(cd "$MONARCHY_SRC/bin" && ls)

# install(1) unlinks before writing, so laying a stub over a mirrored symlink
# must replace the link, never write through it into the packaged tree. That
# ordering is why the mirror can come first.
grep -q 'monarchy_refresh_sddm' "$MONARCHY_SRC/bin/omarchy-refresh-sddm" \
    && fail "wrap wrote through the overlay symlink into the packaged tree"
grep -qx '#!/bin/sh' "$MONARCHY_SRC/bin/omarchy-refresh-pacman" \
    || fail "deny stub wrote through the overlay symlink into the packaged tree"

wrap_n=${#MONARCHY_BIN_WRAP[@]}
deny_n=${#MONARCHY_BIN_DENY[@]}
src_n=$(find "$MONARCHY_SRC/bin" -maxdepth 1 \( -type f -o -type l \) | wc -l)
overlay_n=$(find "$dest" -maxdepth 1 \( -type f -o -type l \) | wc -l)
expected=$((src_n + 1)) # + yay, which upstream does not ship
[ "$overlay_n" -eq "$expected" ] || fail "overlay has $overlay_n entries, expected $expected"

# The hazard scan is what replaced "every name must be in an inventory". It
# has to fail on an unclassified binary that drives limine, snapper or
# pacman.conf, and it is the only thing standing between a renamed brick and
# the overlay now.
printf '#!/bin/sh\nlimine-entry-tool --add-kernel "$@"\n' >"$tmp/src/bin/omarchy-something-new"
chmod +x "$tmp/src/bin/omarchy-something-new"
if ( monarchy_check_bin_hazards ) >/dev/null 2>&1; then
    fail "hazard scan passed an unclassified binary that calls limine-entry-tool"
fi
rm -f "$tmp/src/bin/omarchy-something-new"
monarchy_check_bin_hazards || fail "hazard scan failed on a clean tree"

# A wrap or deny for a name upstream dropped is dead weight that hides a rename.
rm -f "$tmp/src/bin/omarchy-refresh-pacman"
if ( monarchy_check_overrides_exist ) >/dev/null 2>&1; then
    fail "override check passed a denied name that is no longer in the package"
fi
printf '#!/bin/sh\n' >"$tmp/src/bin/omarchy-refresh-pacman"

# ---- ordering, read statically out of update.sh -------------------------

units=$(sed -n 's/^MONARCHY_UNITS=(\(.*\))$/\1/p' "$LIB/update.sh")
[ -n "$units" ] || fail "MONARCHY_UNITS not found"
idx_of() { printf '%s\n' "$units" | tr ' ' '\n' | grep -nx "$1" | cut -d: -f1; }
pacman_i=$(idx_of pacman); packaging_i=$(idx_of packaging)
prefix_i=$(idx_of prefix); overlay_i=$(idx_of overlay); leaves_i=$(idx_of leaves)
for n in pacman_i packaging_i prefix_i overlay_i leaves_i; do
    [ -n "${!n}" ] || fail "${n%_i} must be a unit"
done
# [omarchy] before anything is downloaded; the package before the prefix that
# is linked out of it; the prefix before the overlay that sits on it; and
# install/omarchy-base.packages only exists once omarchy is installed.
[ "$pacman_i" -lt "$packaging_i" ] || fail "packaging runs before the [omarchy] repo is added"
[ "$packaging_i" -lt "$prefix_i" ] || fail "prefix runs before the omarchy package is installed"
[ "$prefix_i" -lt "$overlay_i" ] || fail "overlay runs before the working prefix exists"
[ "$packaging_i" -lt "$leaves_i" ] || fail "leaves runs before omarchy-base.packages exists"

prefix_apply=$(awk '/^monarchy_prefix_apply\(\)/,/^}$/' "$LIB/update.sh")
line_of() {
    printf '%s\n' "$prefix_apply" \
        | grep -nE "^[[:space:]]*$1[[:space:]]*$" \
        | head -1 | cut -d: -f1 || true
}
assert_at=$(line_of 'monarchy_prefix_assert')
link_at=$(line_of 'monarchy_link_working_prefix')
[ -n "$assert_at" ] || fail "monarchy_prefix_apply does not assert the package tree"
[ -n "$link_at" ] || fail "monarchy_prefix_apply does not link the working prefix"
[ "$assert_at" -lt "$link_at" ] || fail "working prefix linked before the tree is asserted"

# apply must classify the tree before it builds anything from it.
monarchy_reaches apply | grep -qx 'monarchy_check_bin_hazards' \
    || fail "apply does not reach monarchy_check_bin_hazards"
monarchy_reaches apply | grep -qx 'monarchy_check_overrides_exist' \
    || fail "apply does not reach monarchy_check_overrides_exist"

# ---- write_to dispatch --------------------------------------------------

# monarchy_write_to is the whole difference between building the overlay as
# the user on a temp prefix and as root on a real box. The temp-prefix run
# above only exercises the writable path, so drive the dispatch directly with
# monarchy_sudo stubbed out. Skipped as root, where -w is always true.
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    wt=$(mktemp -d)
    calls=$wt/calls
    : >"$calls"
    # Called indirectly, by monarchy_write_to.
    # shellcheck disable=SC2329
    monarchy_sudo() { printf 'sudo %s\n' "$*" >>"$calls"; }

    mkdir -p "$wt/open"
    monarchy_write_to "$wt/open" touch "$wt/open/f"
    [ -f "$wt/open/f" ] || fail "write_to did not run the command on a writable dir"
    [ ! -s "$calls" ] || fail "write_to elevated for a writable dir"

    mkdir -p "$wt/closed"
    chmod 500 "$wt/closed"
    monarchy_write_to "$wt/closed" touch "$wt/closed/f"
    grep -q '^sudo touch ' "$calls" || fail "write_to did not elevate for an unwritable dir"
    [ ! -e "$wt/closed/f" ] || fail "write_to ran unelevated against an unwritable dir"

    chmod 700 "$wt/closed"
    rm -rf "$wt"
    unset -f monarchy_sudo
fi

echo "overlay test passed ($src_n mirrored, $wrap_n wrap, $deny_n deny, no allow list)"
