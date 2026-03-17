#!/usr/bin/env bash
set -e
set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Welcome back, commander ==="

echo "Installing system packages..."
"$SCRIPT_DIR/setup-packages.sh"

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

echo "=== Configuring rEFInd theme ==="
"$SCRIPT_DIR/setup-refind-theme.sh"

echo "=== Symlinking emacs configuration ==="
if [ ! -L "$HOME/.emacs.d" ]; then
    if [ -d "$HOME/.emacs.d" ]; then
        echo "Moving existing emacs.d to ~/.emacs.d.bk..."
        mv "$HOME/.emacs.d" "$HOME/.emacs.d.bk"
    fi
    echo "Linking emacs config..."
    ln -s "$DOTFILES_DIR/emacs" "$HOME/.emacs.d"
else
    echo "Emacs config already linked."
fi

echo "=== Configuring NVIDIA suspend fix ==="
"$SCRIPT_DIR/setup-nvidia-suspend.sh"

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
if command -v ufw &> /dev/null; then
    if sudo ufw status | grep -q "Status: active"; then
        sudo ufw allow 8010/tcp comment 'VLC Chromecast HTTP stream'
        sudo ufw allow 1900/udp comment 'VLC Chromecast discovery (UPnP)'
        sudo ufw allow 22/tcp comment 'SSH'
        sudo ufw allow 25565/tcp comment 'Mincraft servers'
        sudo ufw allow 4445/udp comment 'Minecraft LAN discovery'
        #sudo ufw allow from 192.168.1.0/24 comment 'Trust local network'
    else
        echo "  ufw is disabled on this machine"
    fi
fi

echo "=== System tweaks ==="
# these are one-off post-install things so split into separate script
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

HOSTNAME=$(hostname)

if [ "$HOSTNAME" = "kingfisher" ]; then
    echo "Detected Kingfisher machine, running setup-kingfisher.sh..."
    "$SCRIPT_DIR/setup-kingfisher.sh"
fi

echo "=== Configuring ZFS monitoring and snapshots ==="
"$SCRIPT_DIR/setup-zfs.sh"

echo "=== Installing Plasma icograph system monitor face ==="
ICOGRAPH_DIR="$DOTFILES_DIR/plasma/icograph"
TARGET_DIR="$HOME/.local/share/ksysguard/sensorfaces/org.kde.plasma.systemmonitor.icograph"
mkdir -p "$(dirname "$TARGET_DIR")"
if [ -L "$TARGET_DIR" ]; then
    rm "$TARGET_DIR"
elif [ -d "$TARGET_DIR" ]; then
    rm -rf "$TARGET_DIR"
fi
ln -s "$ICOGRAPH_DIR" "$TARGET_DIR"
echo "  icograph installed to: $TARGET_DIR"

echo "=== System installation complete ==="
