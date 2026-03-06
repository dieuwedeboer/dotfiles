#!/usr/bin/env bash
set -e

echo "=== Arch Linux Setup Script ==="
echo "This script is idempotent and safe to re-run."

PACMAN_PACKAGES=(
    discover
    flatpak
    obsidian
    emacs
    nvim
    vlc
    qbittorrent
    gimp
    chezmoi
    direnv
    zellij
    starship
    pnpm
    docker
    docker-compose
    ghostty
    openfortivpn
    libreoffice-fresh
    wl-clipboard
    python-pipx
)

AUR_PACKAGES=(
    google-chrome
    bible-kjv
    zoom
    cura-bin
)

FLATPAK_PACKAGES=(
    com.xmcl.XMCL
    com.spotify.Client
    com.discord.Discord
)

echo "=== Installing pacman packages ==="
for pkg in "${PACMAN_PACKAGES[@]}"; do
    if pacman -Q "$pkg" &> /dev/null; then
        echo "  $pkg already installed"
    else
        echo "  Installing $pkg..."
        sudo pacman -S --noconfirm "$pkg"
    fi
done

echo "=== Installing AUR packages ==="
if command -v paru &> /dev/null; then
    for pkg in "${AUR_PACKAGES[@]}"; do
        if paru -Q "$pkg" &> /dev/null; then
            echo "  $pkg already installed"
        else
            echo "  Installing $pkg..."
            paru -S --noconfirm "$pkg"
        fi
    done
else
    echo "  paru not found, skipping AUR packages"
fi

echo "=== Installing flatpak packages ==="
for pkg in "${FLATPAK_PACKAGES[@]}"; do
    if flatpak list --app | grep -q "$pkg"; then
        echo "  $pkg already installed"
    else
        echo "  Installing $pkg..."
        flatpak install -y "$pkg"
    fi
done

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
        echo "  User already in docker group"
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
if pacman -Q cachyos-wallpapers &> /dev/null; then
    sudo pacman -R --noconfirm cachyos-wallpapers
else
    echo "  cachyos-wallpapers not installed"
fi

if [ -f /etc/mkinitcpio.conf ]; then
    if grep -q "fsck" /etc/mkinitcpio.conf; then
        sudo sed -i 's/fsck//' /etc/mkinitcpio.conf
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

echo "=== Installing additional tools ==="
if ! command -v opencode &> /dev/null; then
    curl -fsSL https://opencode.ai/install | sh
else
    echo "  opencode already installed"
fi

if ! command -v lando &> /dev/null; then
    /bin/bash -c "$(curl -fsSL https://get.lando.dev/setup-lando.sh)"
else
    echo "  lando already installed"
fi

echo "=== Setup complete ==="
