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
echo "$setup_body" | grep -q 'monarchy_assert_chezmoi_hypr' \
    || fail "monarchy_setup_user does not assert chezmoi owns ~/.config/hypr"
echo "$setup_body" | grep -q 'monarchy_release_user_config' \
    || fail "monarchy_setup_user does not release its old blocks"
grep -q 'chezmoi apply' "$LIB/user.sh" \
    || fail "user.sh does not name the command to run when hypr has drifted"
# The die messages name the command, so match an actual invocation: a line
# that starts with it, rather than one that merely contains it in a string.
grep -qE '^[[:space:]]*chezmoi[[:space:]]+apply' "$LIB/user.sh" \
    && fail "user.sh must never invoke chezmoi apply itself; it prompts, and omarchy-update has no terminal"
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

hypr=$HOME/.config/hypr/hyprland.lua
mkdir -p "$(dirname "$hypr")"
printf 'require("hypr.looknfeel")\n' >"$hypr"
monarchy_seed_hypr_boot_color
[ -f "$HOME/.config/hypr/boot-color.lua" ] || fail "did not install boot-color.lua"
grep -q 'require("hypr.boot-color")' "$hypr" || fail "did not require boot-color from hyprland.lua"
monarchy_seed_hypr_boot_color
n=$(grep -c 'hypr.boot-color' "$hypr")
[ "$n" -eq 1 ] || fail "boot-color require is not idempotent ($n)"

# monarchy_seed_block is still live for the boot-color require in
# hyprland.lua, which is an overlay asset rather than chezmoi's. These cover
# the mechanism itself.
blk=$HOME/.config/hypr/scratch.lua
mkdir -p "$(dirname "$blk")"
printf -- '-- scratch\n' >"$blk"
chmod 644 "$blk"

# mktemp lands in /tmp, a different filesystem from $HOME here, so a
# cross-filesystem mv would copy mktemp's 600 over the file's 644.
monarchy_seed_block "$blk" modecheck <<'LUA'
-- body
LUA
mode=$(stat -c %a "$blk")
[ "$mode" = 644 ] || fail "seeding changed the file mode to $mode, expected 644"

# Byte-stable across repeated applies.
first=$(md5sum <"$blk")
monarchy_seed_block "$blk" modecheck <<'LUA'
-- body
LUA
monarchy_seed_block "$blk" modecheck <<'LUA'
-- body
LUA
[ "$(md5sum <"$blk")" = "$first" ] || fail "seed_block is not byte-stable across applies"

# An anchored legacy pattern must not eat a line the user wrote that merely
# mentions the same string.
cat >"$blk" <<'LUA'
-- scratch
-- reminder: pam_kwallet_init is handled elsewhere, do not add it here
o.launch_on_start("/usr/lib/pam_kwallet_init")
LUA
monarchy_seed_block "$blk" kwallet \
    '^o[.]launch_on_start[(]"/usr/lib/pam_kwallet_init"[)]$' <<'LUA'
o.launch_on_start("/usr/lib/pam_kwallet_init")
LUA
grep -q 'reminder: pam_kwallet_init is handled elsewhere' "$blk" \
    || fail "anchored legacy pattern deleted a user comment"
[ "$(grep -c 'launch_on_start' "$blk")" -eq 1 ] \
    || fail "legacy line was duplicated instead of migrated"

# A body line equal to a marker would end the block early on the next reseed.
# monarchy_die exits, so run it in a subshell with this test's EXIT trap
# cleared, and check the exit status rather than letting it take the test down.
if (
    trap - EXIT
    monarchy_seed_block "$blk" collide <<'LUA'
-- END monarchy: collide
LUA
) >/dev/null 2>&1; then
    fail "seed_block accepted a body containing its own end marker"
fi

# chezmoi owns the personal override files; monarchy asserts and never applies.
for f in bindings.lua looknfeel.lua input.lua autostart.lua; do
    [ -f "$REPO/chezmoi/dot_config/hypr/$f" ] \
        || fail "chezmoi does not carry hypr/$f"
done

echo "user tests passed"
