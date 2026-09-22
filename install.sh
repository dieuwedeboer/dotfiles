#!/usr/bin/env bash
# One entry point. Bare ./install.sh on a fresh box is household bootstrap
# plus Monarchy apply. After /etc/omarchy.conf exists, bare ./install.sh is
# the same as --update: household refresh (packages, chezmoi, hardware, ZFS)
# then snapshot, rebuild packages, classify, apply. PATH has monarchy-update
# (this file, --update).
set -e
VERBOSE=0
MODE=full
for arg in "$@"; do
    case "$arg" in
        -v|-r|--verbose) VERBOSE=1 ;;
        --check) MODE=check ;;
        --update) MODE=update ;;
        --no-packages)
            # read by monarchy_install_packages and monarchy_keep_sddm
            # shellcheck disable=SC2034
            MONARCHY_NO_PACKAGES=1
            if [ "$MODE" = full ]; then
                MODE=apply
            fi
            ;;
        --splash-only) MODE=splash ;;
        --only=*)
            MONARCHY_ONLY=${arg#--only=}
            export MONARCHY_ONLY
            ;;
        -h|--help)
            cat <<'EOF'
usage: install.sh [--check] [--update] [--no-packages] [--splash-only] [-v]
       monarchy-update [same flags]

  (none)          Household refresh, then Monarchy. On a fresh box: packages,
                  chezmoi, rEFInd glow, services, hardware, ZFS, then apply.
                  Once /etc/omarchy.conf exists, the same as --update.
  --check         Monarchy dry-run. Writes nothing under /etc or /usr/local.
  --update        Household refresh, then snapshot, rebuild packages,
                  classify, apply. After the first install this is the
                  command; monarchy-update is this file with --update.
  --no-packages   Monarchy apply without pacman leaf packages. Still refreshes
                  chezmoi-managed dotfiles.
  --splash-only   Omarchy Plymouth theme, plymouth around zfs, retain-splash.
  --only=<unit>   Run one unit only. Combines with --check and --update.
                  Skips the household refresh. Units: guards pacman packaging
                  prefix overlay leaves settings sddm session logind portals
                  user splash

  omarchy-update (Omarchy menu) wraps monarchy-update. That path has no
  terminal, so chezmoi apply is skipped rather than hanging on a prompt.

  MONARCHY_TRUST_OMARCHY_KEY=1 skips the packaging-key prompt.
EOF
            exit 0
            ;;
        *)
            echo "unknown argument: $arg" >&2
            exit 2
            ;;
    esac
done
[ "$VERBOSE" = 1 ] && set -x
export VERBOSE

DOTFILES_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
LIB_DIR="$DOTFILES_DIR/lib"

# Overlay installs this file as /usr/local/bin/monarchy-update.
if [ "$(basename -- "$0")" = monarchy-update ] && [ "$MODE" = full ]; then
    MODE=update
fi

# A provisioned box: bare ./install.sh is the same as --update.
if [ "$MODE" = full ] && [ -z "${MONARCHY_ONLY:-}" ] && [ -f /etc/omarchy.conf ]; then
    MODE=update
fi

# shellcheck source=lib/monarchy.sh
source "$LIB_DIR/monarchy.sh"
# shellcheck source=lib/packages.sh
source "$LIB_DIR/packages.sh"

monarchy_cli() {
    case "$1" in
        check) monarchy_check ;;
        apply)
            monarchy_apply
            packages_strip_omarchy_owned
            packages_install_omarchy_aur
            ;;
        update)
            monarchy_update
            packages_strip_omarchy_owned
            packages_install_omarchy_aur
            ;;
        splash) monarchy_splash_only ;;
        *)
            echo "unknown monarchy mode: $1" >&2
            exit 2
            ;;
    esac
}

# Household packages, chezmoi-managed dotfiles, rEFInd, services, hardware,
# ZFS. Idempotent. Runs on first install and on every --update so the two
# entry points cannot drift. --only skips it: that flag is for iterating on
# one overlay unit, not for refreshing the box.
#
# chezmoi apply prompts when a target has been modified. The Omarchy menu
# wraps omarchy-update with no terminal, so that path reports drift and
# continues rather than hanging. An interactive ./install.sh or a hand-run
# monarchy-update has a tty and just applies. See ADR 0001.
household_refresh() {
    echo "Installing system packages..."
    packages_install

    # shellcheck source=lib/agents.sh
    source "$LIB_DIR/agents.sh"
    echo "=== Agent home (~/.agents) ==="
    agents_materialize_home

    echo "=== Applying dotfiles via chezmoi ==="
    if [ ! -L "$HOME/.local/share/chezmoi" ]; then
        if [ -d "$HOME/.local/share/chezmoi" ]; then
            echo "Moving existing chezmoi to ~/.local/share/chezmoi.bk..."
            mv "$HOME/.local/share/chezmoi" "$HOME/.local/share/chezmoi.bk"
        fi
        echo "Linking dotfiles via chezmoi..."
        ln -s "$DOTFILES_DIR/chezmoi" "$HOME/.local/share/chezmoi"
    else
        echo "Chezmoi already linked."
    fi

    if command -v chezmoi &> /dev/null; then
        if monarchy_can_prompt; then
            echo "Applying chezmoi..."
            chezmoi apply
        else
            local status
            status=$(chezmoi status 2>/dev/null || true)
            if [ -n "$status" ]; then
                echo "chezmoi has drifted (no terminal to apply). Run: chezmoi apply"
            else
                echo "Chezmoi already applied (non-interactive)."
            fi
        fi
    else
        echo "Warning: chezmoi not installed, skipped dotfiles setup"
    fi

    echo "=== Restoring agent skills from lock ==="
    agents_restore_skills

    echo "=== Configuring rEFInd theme ==="
    "$LIB_DIR/refind.sh"

    echo "=== Enabling services ==="
    if command -v systemctl &> /dev/null; then
        if ! systemctl is-enabled docker.socket &> /dev/null; then
            sudo systemctl enable docker.socket
        else
            echo "  docker.socket already enabled"
        fi

        if ! systemctl is-enabled sshd &> /dev/null; then
            sudo systemctl enable sshd
        else
            echo "  sshd already enabled"
        fi
    fi

    echo "=== Configuring user groups ==="
    if command -v getent &> /dev/null; then
        if ! getent group docker | grep -q "$USER"; then
            sudo usermod -aG docker "$USER"
        else
            echo "  user already in docker group"
        fi
    fi

    echo "=== Configuring firewall ==="
    # shellcheck source=lib/ufw.sh
    source "$LIB_DIR/ufw.sh"
    if command -v ufw &> /dev/null; then
        ufw_apply_rules
        echo "  rules written; not toggling enable/disable (ufw enable|disable persists)"
    else
        echo "  ufw not installed, skipping"
    fi

    echo "=== System tweaks ==="
    if [ -f /etc/mkinitcpio.conf ]; then
        if grep -q "^HOOKS.*fsck" /etc/mkinitcpio.conf; then
            sudo sed -i '/^HOOKS/s/fsck//' /etc/mkinitcpio.conf
        else
            echo "  fsck hook already removed"
        fi
    fi

    if [ -f /etc/vconsole.conf ]; then
        if ! grep -q "KEYMAP=en" /etc/vconsole.conf; then
            echo "KEYMAP=en" | sudo tee /etc/vconsole.conf
        else
            echo "  vconsole.conf already configured"
        fi
    fi

    echo "=== Hardware quirks ==="
    "$DOTFILES_DIR/hardware/apply.sh"

    echo "=== Configuring ZFS monitoring and snapshots ==="
    "$LIB_DIR/zfs.sh"
}

case "$MODE" in
    check|splash)
        monarchy_cli "$MODE"
        exit 0
        ;;
esac

echo "=== Welcome back, commander ==="
if [ -z "${MONARCHY_ONLY:-}" ]; then
    household_refresh
fi

echo "=== Monarchy (Omarchy session on this CachyOS box) ==="
case "$MODE" in
    update) monarchy_cli update ;;
    apply|full) monarchy_cli apply ;;
    *)
        echo "unknown monarchy mode: $MODE" >&2
        exit 2
        ;;
esac

echo "=== System installation complete ==="
echo "Reboot so SDDM is the greeter. Plasma stays the family default."
echo "The king's user defaults to Omarchy. See docs/monarchy-install.md"
