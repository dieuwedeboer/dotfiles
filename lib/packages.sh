#!/usr/bin/env bash
# Package install and Omarchy clash de-dupe. Sourced from install.sh.
# packages_install runs before Monarchy. packages_strip_omarchy_owned runs
# after apply/update, so converting machines keep pacman emacs/bun/gh, the
# Spotify or Discord flatpaks, curl-pipe cursor-agent, and python-pipx until
# apply has written /etc/omarchy.conf.

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
    libreoffice-fresh
    wl-clipboard
    uv
    kdenlive
    audacity
    extra-cmake-modules
    aws-cli-v2
    glab
)

AUR_PACKAGES=(
    bible-kjv
    cura-bin
    ddev-bin
    xmcl-launcher
    zoom
    sanoid
    zotero-bin
)

FLATPAK_PACKAGES=(
    com.adamcake.Bolt
)

# Omarchy owns these: mise stubs for grok/opencode/gh/bun, native Spotify,
# Discord webapp, omarchy-emacs (emacs-wayland), cursor-cli, Chrome via
# omarchy-install-browser. Do not reinstall the competing copies after apply.
# Keep this strip for boxes still converting from the pre-Monarchy package set.
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
# Household set dropped these. uv replaced pipx. Strip after apply so a
# converting box keeps pipx until the rest of the new set is in place.
RETIRED_PACMAN=(
    python-pipx
)

packages_install() {
    echo "=== Installing pacman packages ==="
    local pkg
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
}

packages_strip_curl_pipe_cursor() {
    local target
    if [ -L "$HOME/.local/bin/cursor-agent" ]; then
        target=$(readlink -f "$HOME/.local/bin/cursor-agent" 2>/dev/null || true)
        case "$target" in
            */.local/share/cursor-agent/*)
                echo "  removing curl-pipe cursor-agent"
                rm -f "$HOME/.local/bin/cursor-agent"
                rm -rf "$HOME/.local/share/cursor-agent"
                ;;
        esac
    fi
}

packages_strip_omarchy_owned() {
    local pkg
    if [ ! -f /etc/omarchy.conf ]; then
        echo "  leaving emacs/bun/gh/spotify/discord/cursor-agent/pipx until Monarchy apply writes /etc/omarchy.conf"
        return 0
    fi

    echo "=== Removing packages Omarchy now owns ==="
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

    packages_strip_curl_pipe_cursor

    echo "=== Removing retired household packages ==="
    for pkg in "${RETIRED_PACMAN[@]}"; do
        if pacman -Q "$pkg" &> /dev/null; then
            echo "  removing $pkg"
            sudo pacman -R --noconfirm "$pkg"
        fi
    done
    if [ -d "$HOME/.local/share/pipx/venvs" ] && \
        [ -n "$(ls -A "$HOME/.local/share/pipx/venvs" 2>/dev/null)" ]; then
        echo "  leftover pipx venvs in $HOME/.local/share/pipx/venvs (not removing)"
    fi
}
