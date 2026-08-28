#!/usr/bin/env bash
# User-setup policy: Omarchy owns terminal default, mise, and menu-installed apps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
# shellcheck source=user.sh
source "$SCRIPT_DIR/user.sh"

fail() {
    echo "test-user: $*" >&2
    exit 1
}

grep -q 'TERMINAL=ghostty' "$SCRIPT_DIR/user.sh" \
    && fail "user.sh still forces TERMINAL=ghostty"
grep -q 'monarchy_clear_terminal_override' "$SCRIPT_DIR/user.sh" \
    || fail "user.sh missing monarchy_clear_terminal_override"
grep -q 'omarchy-refresh-applications' "$SCRIPT_DIR/user.sh" \
    || fail "user.sh does not run omarchy-refresh-applications"
grep -q 'omarchy-pkg-add spotify' "$SCRIPT_DIR/user.sh" \
    || fail "user.sh does not install Omarchy Spotify"
grep -q 'mise use -g bun' "$SCRIPT_DIR/user.sh" \
    || fail "user.sh does not install bun via mise"
grep -q 'omarchy-pkg-add omarchy-emacs' "$SCRIPT_DIR/user.sh" \
    || fail "user.sh does not install omarchy-emacs"
grep -q 'monarchy_prefer_xdg_emacs' "$SCRIPT_DIR/user.sh" \
    || fail "user.sh missing monarchy_prefer_xdg_emacs"
grep -q 'monarchy_ensure_emacs_dotfiles' "$SCRIPT_DIR/user.sh" \
    && fail "user.sh should not restore ~/.emacs.d"
grep -q 'omarchy-emacs-setup' "$SCRIPT_DIR/user.sh" \
    && fail "user.sh must not call the interactive emacs setup"

setup_body=$(awk '/^monarchy_setup_user\(\)/,/^}$/' "$SCRIPT_DIR/user.sh")
echo "$setup_body" | grep -q 'monarchy_clear_terminal_override' \
    || fail "monarchy_setup_user does not clear the terminal override"
echo "$setup_body" | grep -q 'monarchy_user_omarchy_defaults' \
    || fail "monarchy_setup_user does not install Omarchy user defaults"
grep -q 'monarchy_user_emacs' "$SCRIPT_DIR/user.sh" \
    || fail "user.sh missing monarchy_user_emacs"
echo "$setup_body" | grep -q 'monarchy_seed_uwsm_user_env' \
    && fail "monarchy_setup_user still seeds a UWSM terminal override"

packages="$SCRIPT_DIR/../../setup-packages.sh"
grep -q 'x.ai/cli/install' "$packages" \
    && fail "setup-packages.sh still curl-installs grok"
grep -q 'opencode.ai/install' "$packages" \
    && fail "setup-packages.sh still curl-installs opencode"
install_pacman=$(awk '/^PACMAN_PACKAGES=/,/^)/' "$packages")
echo "$install_pacman" | grep -qx '    bun' \
    && fail "setup-packages.sh still installs pacman bun"
echo "$install_pacman" | grep -qx '    emacs' \
    && fail "setup-packages.sh still installs stock emacs"
echo "$install_pacman" | grep -qx '    github-cli' \
    && fail "setup-packages.sh still installs github-cli"
grep -qx '    emacs' <<<"$(awk '/^OMARCHY_OWNED_PACMAN=/,/^)/' "$packages")" \
    || fail "setup-packages.sh should uninstall stock emacs so emacs-wayland can replace it"
install_sh="$SCRIPT_DIR/../../install.sh"
grep -q 'ln -s "$DOTFILES_DIR/emacs"' "$install_sh" \
    && fail "install.sh still links ~/.emacs.d (chezmoi owns ~/.config/emacs)"
install_flatpak=$(awk '/^FLATPAK_PACKAGES=/,/^)/' "$packages")
echo "$install_flatpak" | grep -q 'com.spotify.Client' \
    && fail "setup-packages.sh still installs Spotify as a flatpak"
echo "$install_flatpak" | grep -q 'com.discordapp.Discord' \
    && fail "setup-packages.sh still installs Discord as a flatpak"
grep -q 'com.spotify.Client' "$packages" \
    || fail "setup-packages.sh should still name Spotify so it can uninstall the flatpak"
grep -q 'com.discordapp.Discord' "$packages" \
    || fail "setup-packages.sh should still name Discord so it can uninstall the flatpak"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME=$tmp/home
export MONARCHY_LOG=$tmp/log
mkdir -p "$HOME/.config/uwsm/env.d"
printf 'export TERMINAL=ghostty\n' >"$HOME/.config/uwsm/env.d/20-monarchy-terminal"
monarchy_clear_terminal_override
[ ! -f "$HOME/.config/uwsm/env.d/20-monarchy-terminal" ] \
    || fail "did not remove 20-monarchy-terminal"
monarchy_clear_terminal_override

mkdir -p "$HOME"
ln -s /tmp/old-emacs "$HOME/.emacs.d"
monarchy_prefer_xdg_emacs
[ ! -e "$HOME/.emacs.d" ] && [ ! -L "$HOME/.emacs.d" ] \
    || fail "did not move ~/.emacs.d aside"
[ -L "$HOME/.emacs.d.bak" ] || fail "did not keep ~/.emacs.d.bak"
monarchy_prefer_xdg_emacs
[ -L "$HOME/.emacs.d.bak" ] || fail "idempotent prefer_xdg clobbered the backup"

echo "user tests passed"
