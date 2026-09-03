#!/usr/bin/env bash
# First run: ./install.sh from this clone (household bootstrap + Monarchy).
# After that, PATH has monarchy-update (this file, --update).
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
        -h|--help)
            cat <<'EOF'
usage: install.sh [--check] [--update] [--no-packages] [--splash-only] [-v]
       monarchy-update [same flags]

  (none)          Full setup from a CachyOS+ZFS+KDE base: packages,
                  chezmoi, rEFInd glow, services, hardware quirks, ZFS
                  snapshots, then Monarchy apply. First run from the
                  git clone. Not installed on PATH.
  --check         Monarchy dry-run. Writes nothing under /etc or /usr/local.
  --update        Monarchy snapshot, fetch, check, then apply.
  --no-packages   Monarchy apply without pacman leaf packages.
  --splash-only   Omarchy Plymouth theme, plymouth around zfs, retain-splash.

  After the first install, /usr/local/bin/monarchy-update is this file
  with --update. omarchy-update (Omarchy menu) wraps that.

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
            ;;
        update)
            monarchy_update
            packages_strip_omarchy_owned
            ;;
        splash) monarchy_splash_only ;;
        *)
            echo "unknown monarchy mode: $1" >&2
            exit 2
            ;;
    esac
}

if [ "$MODE" != full ]; then
    monarchy_cli "$MODE"
    exit 0
fi

echo "=== Welcome back, commander ==="

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
    echo "Applying chezmoi..."
    chezmoi apply
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

echo "=== Monarchy (Omarchy session on this CachyOS box) ==="
monarchy_cli apply

echo "=== System installation complete ==="
echo "Reboot so SDDM is the greeter. Plasma stays the family default."
echo "The king's user defaults to Omarchy. See docs/monarchy-install.md"
