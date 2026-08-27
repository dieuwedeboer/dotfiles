#!/usr/bin/env bash
# Branding seed and prefix links. No sudo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
# shellcheck source=clone.sh
source "$SCRIPT_DIR/clone.sh"
# shellcheck source=user.sh
source "$SCRIPT_DIR/user.sh"

fail() {
    echo "test-branding: $*" >&2
    exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export HOME=$tmp/home
export MONARCHY_SRC=$tmp/src
export MONARCHY_PATH=$tmp/prefix
export MONARCHY_LOG=$tmp/log
export MONARCHY_SETUP=$SCRIPT_DIR/../../setup-monarchy.sh
mkdir -p "$HOME" "$MONARCHY_SRC/default" "$MONARCHY_SRC/bin" "$MONARCHY_PATH"

printf 'LOGOART\n' >"$MONARCHY_SRC/logo.txt"
printf 'ICONART\n' >"$MONARCHY_SRC/icon.txt"
printf 'PNG\n' >"$MONARCHY_SRC/icon.png"
printf 'SVG\n' >"$MONARCHY_SRC/logo.svg"

monarchy_seed_branding
branding="$HOME/.config/omarchy/branding"
[ "$(cat "$branding/screensaver.txt")" = "LOGOART" ] || fail "screensaver.txt is not clone logo.txt"
[ "$(cat "$branding/about.txt")" = "ICONART" ] || fail "about.txt is not clone icon.txt"
[ "$(cat "$branding/logo.txt")" = "LOGOART" ] || fail "logo.txt not seeded"
[ "$(cat "$branding/icon.txt")" = "ICONART" ] || fail "icon.txt not seeded"

printf 'CUSTOM\n' >"$branding/screensaver.txt"
monarchy_seed_branding
[ "$(cat "$branding/screensaver.txt")" = "CUSTOM" ] || fail "seed overwrote an existing screensaver.txt"

monarchy_link_working_prefix
[ -L "$MONARCHY_PATH/logo.txt" ] || fail "prefix logo.txt is not a symlink"
[ "$(readlink "$MONARCHY_PATH/logo.txt")" = "$MONARCHY_SRC/logo.txt" ] || fail "prefix logo.txt target"
[ -L "$MONARCHY_PATH/icon.txt" ] || fail "prefix icon.txt is not a symlink"
[ -L "$MONARCHY_PATH/icon.png" ] || fail "prefix icon.png is not a symlink"
[ -L "$MONARCHY_PATH/logo.svg" ] || fail "prefix logo.svg is not a symlink"
[ -L "$MONARCHY_PATH/default" ] || fail "prefix default is not a symlink"

# Missing logo.txt must fail closed. An empty branding dir plus a crash-looping
# ttfx is how workspace 2 got stuck. monarchy_die exits the shell, so this
# check runs in a subshell.
rm -f "$MONARCHY_SRC/logo.txt"
if ( monarchy_seed_branding ) >/dev/null 2>&1; then
    fail "seed should die when clone logo.txt is missing"
fi
printf 'LOGOART\n' >"$MONARCHY_SRC/logo.txt"

# Wrap seeds branding then runs the clone binary, never the overlay name.
printf 'CUSTOM\n' >"$branding/screensaver.txt"
rm -f "$branding/screensaver.txt"
cat >"$MONARCHY_SRC/bin/omarchy-screensaver" <<'SH'
#!/bin/bash
printf 'RAN:%s\n' "$(cat "$HOME/.config/omarchy/branding/screensaver.txt")"
SH
chmod +x "$MONARCHY_SRC/bin/omarchy-screensaver"
got=$("$SCRIPT_DIR/stubs/wrap-screensaver.sh")
[ "$got" = "RAN:LOGOART" ] || fail "wrap did not seed then exec clone screensaver (got '$got')"

clone=${1:-/usr/local/src/monarchy/omarchy}
if [ -f "$clone/bin/omarchy-screensaver" ]; then
    grep -q 'branding/screensaver.txt' "$clone/bin/omarchy-screensaver" \
        || fail "clone omarchy-screensaver no longer reads screensaver.txt"
    grep -q '\$OMARCHY_PATH/logo.txt' "$clone/bin/omarchy-branding-screensaver" \
        || fail "clone screensaver reset no longer copies \$OMARCHY_PATH/logo.txt"
    grep -q '\$OMARCHY_PATH/icon.txt' "$clone/bin/omarchy-branding-about" \
        || fail "clone about reset no longer copies \$OMARCHY_PATH/icon.txt"
fi

echo "branding tests passed"
