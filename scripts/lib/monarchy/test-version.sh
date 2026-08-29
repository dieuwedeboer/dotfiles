#!/usr/bin/env bash
# Fastfetch About lines: version, branch, package channel. No sudo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MISC="$SCRIPT_DIR/../../../misc/monarchy"
WRAP="$SCRIPT_DIR/stubs/wrap-version.sh"

fail() {
    echo "test-version: $*" >&2
    exit 1
}

[ -f "$WRAP" ] || fail "missing $WRAP"
grep -qx 'omarchy-version' "$MISC/bin.wrap" || fail "omarchy-version missing from bin.wrap"
grep -qx 'omarchy-version-branch' "$MISC/bin.wrap" \
    || fail "omarchy-version-branch missing from bin.wrap"
grep -qx 'omarchy-version-channel' "$MISC/bin.wrap" \
    || fail "omarchy-version-channel missing from bin.wrap"
if grep -qx 'omarchy-version' "$MISC/bin.allow"; then
    fail "omarchy-version still in bin.allow"
fi
if grep -qx 'omarchy-version-branch' "$MISC/bin.allow"; then
    fail "omarchy-version-branch still in bin.allow"
fi
if grep -qx 'omarchy-version-channel' "$MISC/bin.allow"; then
    fail "omarchy-version-channel still in bin.allow"
fi
grep -q '"omarchy-version"' "$SCRIPT_DIR/generate-inventories.py" \
    || fail "generate-inventories.py WRAP missing omarchy-version"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ln -s "$WRAP" "$tmp/omarchy-version"
ln -s "$WRAP" "$tmp/omarchy-version-branch"
ln -s "$WRAP" "$tmp/omarchy-version-channel"
chmod +x "$WRAP"

prefix=$tmp/prefix
mkdir -p "$prefix"
printf '4.0.0.alpha\n' >"$prefix/version"
pin=$tmp/omarchy.lock
cat >"$pin" <<'EOF'
remote=https://github.com/berenddeboer/omarchy.git
branch=quattro-on-zfs
commit=bfcaa06f5cfa5c8cb89412503f615868c01df169
hyprland=
quickshell=
EOF
pacman_conf=$tmp/pacman.conf
cat >"$pacman_conf" <<'EOF'
[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist
# BEGIN monarchy-omarchy
[omarchy]
SigLevel = Required DatabaseOptional
Server = https://pkgs.omarchy.org/stable/$arch
# END monarchy-omarchy
EOF

run_wrap() {
    local name=$1
    OMARCHY_PATH=$prefix MONARCHY_PIN=$pin PACMAN_CONF=$pacman_conf "$tmp/$name"
}

got=$(run_wrap omarchy-version)
[ "$got" = "4.0.0.alpha-git" ] || fail "omarchy-version: expected 4.0.0.alpha-git, got $got"

got=$(run_wrap omarchy-version-branch)
[ "$got" = "quattro-on-zfs @ bfcaa06" ] \
    || fail "omarchy-version-branch: expected quattro-on-zfs @ bfcaa06, got $got"

got=$(run_wrap omarchy-version-channel)
[ "$got" = "stable" ] || fail "omarchy-version-channel: expected stable, got $got"

# Mirror URLs must not leak back in. CachyOS owns /etc/pacman.d/mirrorlist.
printf 'Server = https://stable-mirror.omarchy.org/$arch\n' >"$tmp/mirrorlist"
got=$(run_wrap omarchy-version-channel)
[ "$got" = "stable" ] || fail "channel used the OS mirror: $got"

printf 'Server = https://pkgs.omarchy.org/edge/$arch\n' >"$pacman_conf"
got=$(run_wrap omarchy-version-channel)
[ "$got" = "edge" ] || fail "omarchy-version-channel edge: expected edge, got $got"

printf '[core]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n' >"$pacman_conf"
got=$(run_wrap omarchy-version-channel)
[ "$got" = "unknown" ] || fail "omarchy-version-channel unknown: expected unknown, got $got"

rm -f "$prefix/version"
set +e
run_wrap omarchy-version >/dev/null 2>&1
st=$?
set -e
[ "$st" -ne 0 ] || fail "omarchy-version succeeded with no version file"

rm -f "$pin"
set +e
run_wrap omarchy-version-branch >/dev/null 2>&1
st=$?
set -e
[ "$st" -ne 0 ] || fail "omarchy-version-branch succeeded with no pin"

set +e
OMARCHY_PATH=$prefix MONARCHY_PIN=$pin PACMAN_CONF=$pacman_conf "$WRAP" >/dev/null 2>&1
st=$?
set -e
[ "$st" -eq 2 ] || fail "wrap-version invoked by its own name exited $st, expected 2"

# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
# shellcheck source=clone.sh
source "$SCRIPT_DIR/clone.sh"
export MONARCHY_PATH=$prefix
export MONARCHY_CONF=$tmp/omarchy.conf
export MONARCHY_PIN=$tmp/written.lock
export MONARCHY_LOG=$tmp/log
export MONARCHY_MISC=$MISC
monarchy_write_omarchy_conf
[ -f "$MONARCHY_CONF" ] || fail "did not write $MONARCHY_CONF"
grep -qx "OMARCHY_PATH=$prefix" "$MONARCHY_CONF" \
    || fail "omarchy.conf missing OMARCHY_PATH"
[ -f "$MONARCHY_PIN" ] || fail "did not write $MONARCHY_PIN"
grep -qx 'branch=quattro-on-zfs' "$MONARCHY_PIN" \
    || fail "written pin missing branch=quattro-on-zfs"
grep -E '^commit=[0-9a-f]{40}$' "$MONARCHY_PIN" >/dev/null \
    || fail "written pin missing full commit"

echo "version test passed"
