#!/usr/bin/env bash
# User-setup policy: Omarchy owns terminal default, mise, and menu-installed apps.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"
# shellcheck source=../../lib/monarchy/common.sh
source "$LIB/common.sh"
# shellcheck source=../../lib/monarchy/user.sh
source "$LIB/user.sh"


grep -q 'TERMINAL=ghostty' "$LIB/user.sh" \
    && fail "user.sh still forces TERMINAL=ghostty"
grep -q 'monarchy_clear_terminal_override' "$LIB/user.sh" \
    || fail "user.sh missing monarchy_clear_terminal_override"
grep -q 'omarchy-refresh-applications' "$LIB/user.sh" \
    || fail "user.sh does not run omarchy-refresh-applications"
grep -q 'monarchy_omarchy_pkg_add spotify' "$LIB/user.sh" \
    || fail "user.sh does not install Omarchy Spotify"
grep -q 'mise use -g bun' "$LIB/user.sh" \
    || fail "user.sh does not install bun via mise"
grep -q 'monarchy_drop_omarchy_emacs_package' "$LIB/user.sh" \
    || fail "user.sh does not drop omarchy-emacs (Omarchy 3, ignores Quattro palettes)"
grep -q 'monarchy_install_emacs_theme' "$LIB/user.sh" \
    || fail "user.sh does not install omarchy-emacs-theme"
grep -q 'monarchy_prefer_xdg_emacs' "$LIB/user.sh" \
    || fail "user.sh missing monarchy_prefer_xdg_emacs"
grep -q 'monarchy_ensure_emacs_dotfiles' "$LIB/user.sh" \
    && fail "user.sh should not restore ~/.emacs.d"
grep -q 'omarchy-emacs-setup' "$LIB/user.sh" \
    && fail "user.sh must not call the interactive emacs setup"

setup_body=$(awk '/^monarchy_setup_user\(\)/,/^}$/' "$LIB/user.sh")
echo "$setup_body" | grep -q 'monarchy_clear_terminal_override' \
    || fail "monarchy_setup_user does not clear the terminal override"
echo "$setup_body" | grep -q 'monarchy_seed_hyprland_config' \
    || fail "monarchy_setup_user does not seed Hyprland config"
grep -q 'monarchy_seed_hypr_boot_color' "$LIB/user.sh" \
    || fail "user.sh missing monarchy_seed_hypr_boot_color"
echo "$setup_body" | grep -q 'monarchy_seed_capslock' \
    || fail "monarchy_setup_user does not restore Caps Lock"
echo "$setup_body" | grep -q 'monarchy_user_omarchy_defaults' \
    || fail "monarchy_setup_user does not install Omarchy user defaults"
grep -q 'monarchy_user_emacs' "$LIB/user.sh" \
    || fail "user.sh missing monarchy_user_emacs"
echo "$setup_body" | grep -q 'monarchy_seed_uwsm_user_env' \
    && fail "monarchy_setup_user still seeds a UWSM terminal override"

packages="$REPO/lib/packages.sh"
grep -q 'x.ai/cli/install' "$packages" \
    && fail "packages.sh still curl-installs grok"
grep -q 'opencode.ai/install' "$packages" \
    && fail "packages.sh still curl-installs opencode"
install_pacman=$(awk '/^PACMAN_PACKAGES=/,/^)/' "$packages")
echo "$install_pacman" | grep -qx '    bun' \
    && fail "packages.sh still installs pacman bun"
echo "$install_pacman" | grep -qx '    emacs' \
    && fail "packages.sh still installs stock emacs"
echo "$install_pacman" | grep -qx '    github-cli' \
    && fail "packages.sh still installs github-cli"
grep -qx '    emacs' <<<"$(awk '/^OMARCHY_OWNED_PACMAN=/,/^)/' "$packages")" \
    || fail "packages.sh should uninstall stock emacs so emacs-wayland can replace it"
install_sh="$REPO/install.sh"
# shellcheck disable=SC2016  # grep pattern, not an expansion
grep -q 'ln -s "$DOTFILES_DIR/emacs"' "$install_sh" \
    && fail "install.sh still links ~/.emacs.d (chezmoi owns ~/.config/emacs)"
install_flatpak=$(awk '/^FLATPAK_PACKAGES=/,/^)/' "$packages")
echo "$install_flatpak" | grep -q 'com.spotify.Client' \
    && fail "packages.sh still installs Spotify as a flatpak"
echo "$install_flatpak" | grep -q 'com.discordapp.Discord' \
    && fail "packages.sh still installs Discord as a flatpak"
grep -q 'com.spotify.Client' "$packages" \
    || fail "packages.sh should still name Spotify so it can uninstall the flatpak"
grep -q 'com.discordapp.Discord' "$packages" \
    || fail "packages.sh should still name Discord so it can uninstall the flatpak"

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

input=$HOME/.config/hypr/input.lua
mkdir -p "$(dirname "$input")"
printf -- '-- Keep only your personal input overrides here.\n' >"$input"
monarchy_seed_capslock
grep -Eq '^[[:space:]]*kb_options[[:space:]]*=[[:space:]]*"caps:capslock"' "$input" \
    || fail "capslock seed missing caps:capslock"
grep -Eq '^[[:space:]]*kb_options.*compose:caps' "$input" \
    && fail "capslock seed left compose:caps active"
monarchy_seed_capslock
n=$(grep -c 'caps:capslock' "$input")
[ "$n" -eq 1 ] || fail "capslock seed is not idempotent ($n)"

printf -- '-- Keep only your personal input overrides here.\n\nhl.config({\n  input = {\n    kb_options = "compose:caps,shift:both_capslock_cancel",\n  },\n})\n' >"$input"
monarchy_seed_capslock
grep -Eq '^[[:space:]]*kb_options[[:space:]]*=[[:space:]]*"caps:capslock"' "$input" \
    || fail "capslock seed did not override compose:caps"
monarchy_seed_capslock
n=$(grep -c 'caps:capslock' "$input")
[ "$n" -eq 1 ] || fail "capslock override is not idempotent ($n)"

printf -- '-- Keep only your personal input overrides here.\n\nhl.config({\n  input = {\n    kb_options = "compose:ralt",\n  },\n})\n' >"$input"
monarchy_seed_capslock
grep -q 'compose:ralt' "$input" || fail "capslock seed clobbered a custom kb_options"
grep -q 'caps:capslock' "$input" && fail "capslock seed appended over a custom kb_options"

hypr=$HOME/.config/hypr/hyprland.lua
mkdir -p "$(dirname "$hypr")"
printf 'require("hypr.looknfeel")\n' >"$hypr"
monarchy_seed_hypr_boot_color
[ -f "$HOME/.config/hypr/boot-color.lua" ] || fail "did not install boot-color.lua"
grep -q 'require("hypr.boot-color")' "$hypr" || fail "did not require boot-color from hyprland.lua"
monarchy_seed_hypr_boot_color
n=$(grep -c 'hypr.boot-color' "$hypr")
[ "$n" -eq 1 ] || fail "boot-color require is not idempotent ($n)"

# Marked blocks must be idempotent by construction, and must migrate a box an
# older apply already wrote to rather than duplicating the line. The switch-user
# bind below is the pre-block form that lacked locked = true.
blk=$HOME/.config/hypr/bindings.lua
mkdir -p "$(dirname "$blk")"
cat >"$blk" <<'LUA'
-- Keep only your personal keybinding overrides here.
o.bind("SUPER + F1", "Mine", "true")

-- Switch user: lock, then SDDM greeter. locked=true so the chord works on the lock screen.
o.bind("SUPER + CTRL + U", "Switch user", "monarchy-switch-user")

-- Omarchy default is HEY email. Someone uses emacsclient.
hl.unbind("SUPER + SHIFT + E")
o.bind("SUPER + SHIFT + E", "Emacs", "emacsclient -c --no-wait")

hl.unbind("SUPER + SHIFT + ALT + E")
LUA

seed_all() {
    monarchy_seed_switch_user_bind >/dev/null
    monarchy_seed_emacs_bind >/dev/null
    monarchy_seed_hypr_unbind "SUPER + SHIFT + ALT + E" >/dev/null
}
seed_all
first=$(md5sum <"$blk")
seed_all
seed_all
[ "$(md5sum <"$blk")" = "$first" ] || fail "seeded blocks are not byte-stable across applies"

grep -Fqx -- '-- BEGIN monarchy: switch-user' "$blk" || fail "no switch-user marker"
grep -Fqx -- '-- END monarchy: switch-user' "$blk" || fail "unterminated switch-user marker"
[ "$(grep -c 'monarchy-switch-user' "$blk")" -eq 1 ] \
    || fail "legacy switch-user bind was duplicated instead of migrated"
grep -q 'locked = true' "$blk" || fail "migrated bind lost locked = true"
[ "$(grep -c 'emacsclient -c' "$blk")" -eq 1 ] \
    || fail "legacy emacs bind was duplicated instead of migrated"
[ "$(grep -c 'SUPER + SHIFT + ALT + E' "$blk")" -eq 1 ] \
    || fail "legacy unbind was duplicated; chord + is being read as a quantifier"
[ "$(grep -c 'SUPER + F1' "$blk")" -eq 1 ] || fail "seeding removed the user's own bind"

echo "user tests passed"
