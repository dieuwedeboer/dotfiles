#!/usr/bin/env bash
set -e
[ "${VERBOSE:-0}" = 1 ] && set -x

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
    bun
    docker
    docker-compose
    ghostty
    openfortivpn
    telegram-desktop
    signal-desktop
    libreoffice-fresh
    wl-clipboard
    python-pipx
    uv
    opencode
    kdenlive
    audacity
    extra-cmake-modules
    aws-cli-v2
    github-cli
)

AUR_PACKAGES=(
    antigravity-cli
    bible-kjv
    cura-bin
    cursor-bin
    google-chrome
    xmcl-launcher
    zoom
    sanoid
)

FLATPAK_PACKAGES=(
    com.adamcake.Bolt
    com.discordapp.Discord
    com.spotify.Client
)

NODE_PACKAGES=(
    opencode-ai
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

echo "=== Installing global node packages ==="
for pkg in "${NODE_PACKAGES[@]}"; do
    if [ -d "$HOME/.bun/install/global/node_modules/$pkg" ]; then
        echo "  $pkg already installed"
    else
        echo "  Installing $pkg..."
        bun add -g "$pkg"
    fi
done

echo "=== Installing self-packaged user tools ==="

if ! command -v lando &> /dev/null; then
    /bin/bash -c "$(curl -fsSL https://get.lando.dev/setup-lando.sh)"
else
    echo "  lando already installed"
fi

if ! command -v agent &> /dev/null; then
    curl https://cursor.com/install -fsS | bash
else
    echo "  cursor cli (agent) already installed"
fi

echo "=== Uninstalling unwanted packages ==="

if pacman -Q cachyos-wallpapers &> /dev/null; then
    sudo pacman -R --noconfirm cachyos-wallpapers
else
    echo "  nothing to remove"
fi

echo "=== Package setup complete ==="
