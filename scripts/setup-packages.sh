#!/usr/bin/env bash
set -e
[ "${VERBOSE:-0}" = 1 ] && set -x

echo "=== Arch Linux Setup Script ==="
echo "This script is idempotent and safe to re-run."

PACMAN_PACKAGES=(
    discover
    flatpak
    obsidian
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
    telegram-desktop
    signal-desktop
    libreoffice-fresh
    wl-clipboard
    python-pipx
    uv
    kdenlive
    audacity
    extra-cmake-modules
    aws-cli-v2
    glab
    coolercontrol
)

AUR_PACKAGES=(
    bible-kjv
    cura-bin
    cursor-bin
    ddev-bin
    google-chrome
    xmcl-launcher
    zoom
    sanoid
    zotero-bin
)

FLATPAK_PACKAGES=(
    com.adamcake.Bolt
)

# Omarchy (via setup-monarchy.sh) owns these: mise stubs for grok/opencode/gh/bun,
# native Spotify, Discord webapp, omarchy-emacs (emacs-wayland). Do not reinstall
# the competing copies.
OMARCHY_OWNED_PACMAN=(
    bun
    emacs
    github-cli
    opencode
)
OMARCHY_OWNED_FLATPAKS=(
    com.discordapp.Discord
    com.spotify.Client
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

echo "=== Uninstalling unwanted packages ==="

if pacman -Q cachyos-wallpapers &> /dev/null; then
    sudo pacman -R --noconfirm cachyos-wallpapers
fi

for pkg in "${OMARCHY_OWNED_PACMAN[@]}"; do
    if pacman -Q "$pkg" &> /dev/null; then
        echo "  removing $pkg (Omarchy/mise owns this)"
        sudo pacman -R --noconfirm "$pkg"
    fi
done

if command -v flatpak &> /dev/null; then
    for pkg in "${OMARCHY_OWNED_FLATPAKS[@]}"; do
        if flatpak list --app | grep -q "$pkg"; then
            echo "  removing flatpak $pkg (Omarchy owns this)"
            flatpak uninstall -y "$pkg"
        fi
    done
fi

# Curl-pipe grok used ~/.grok/bin and stole the `agent` name from Cursor.
if [ -L "$HOME/.local/bin/grok" ]; then
    grok_target=$(readlink -f "$HOME/.local/bin/grok" 2>/dev/null || true)
    case "$grok_target" in
        */.grok/*)
            echo "  removing curl-pipe grok symlink"
            rm -f "$HOME/.local/bin/grok"
            ;;
    esac
fi
if [ -L "$HOME/.local/bin/agent" ]; then
    agent_target=$(readlink -f "$HOME/.local/bin/agent" 2>/dev/null || true)
    case "$agent_target" in
        */.grok/*)
            echo "  removing grok-as-agent symlink"
            rm -f "$HOME/.local/bin/agent"
            ;;
    esac
fi

echo "=== Installing self-packaged user tools ==="

if ! command -v agent &> /dev/null && ! command -v cursor-agent &> /dev/null; then
    curl https://cursor.com/install -fsS | bash
else
    echo "  cursor cli already installed"
fi

echo "=== Package setup complete ==="
