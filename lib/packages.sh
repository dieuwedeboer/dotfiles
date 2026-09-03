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
    sanoid
    zotero-bin
)

# AUR packages for the Omarchy desktop whose PKGBUILD depends on the omarchy
# metapackage. That package is in packages.deny: it pulls limine,
# limine-mkinitcpio-hook, limine-snapper-sync and snapper. What these packages
# actually need is /usr/share/omarchy/shell, which the overlay has under
# $MONARCHY_PATH, so paru is told to assume omarchy at the overlay's own
# version and packages_link_omarchy_share makes the hardcoded path resolve.
# Installed after apply, because both halves need the overlay on disk.
OMARCHY_AUR_PACKAGES=(
    flea
)

FLATPAK_PACKAGES=(
    com.adamcake.Bolt
    info.beyondallreason.bar
)

# Omarchy owns these: mise stubs for grok/opencode/gh/bun, native Spotify,
# Discord and Zoom webapps, emacs-wayland + omarchy-emacs-theme, cursor-cli,
# Chrome via omarchy-install-browser. Do not reinstall the competing copies
# after apply. Keep this strip for boxes still converting from the
# pre-Monarchy package set.
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
# Household set dropped these. uv replaced pipx. omarchy-emacs is Omarchy 3
# and does not follow Quattro palettes; omarchy-emacs-theme does. AUR zoom
# lost to the Omarchy Zoom webapp (zoommtg://).
RETIRED_PACMAN=(
    python-pipx
    omarchy-emacs
    zoom
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

# Upstream Omarchy packages hardcode /usr/share/omarchy; the overlay lives at
# /usr/local/share/omarchy. flea symlinks ui/Commons and ui/Ui into the former
# at package time, so they dangle without this. One link serves the class.
# Refuses to touch anything already there: a real directory would mean the
# denied omarchy package got installed, which is a bigger problem than flea.
packages_link_omarchy_share() {
    local link=/usr/share/omarchy
    if [ -L "$link" ]; then
        [ "$(readlink "$link")" = "$MONARCHY_PATH" ] && return 0
        echo "  warning: $link points elsewhere, leaving it" >&2
        return 1
    fi
    if [ -e "$link" ]; then
        echo "  warning: $link is not a symlink, leaving it" >&2
        return 1
    fi
    echo "  linking $link -> $MONARCHY_PATH"
    monarchy_sudo ln -sT "$MONARCHY_PATH" "$link"
}

# Runs after apply, not with the rest of the packages: the version file and
# the shell QML both come from the overlay.
packages_install_omarchy_aur() {
    [ "${#OMARCHY_AUR_PACKAGES[@]}" -gt 0 ] || return 0
    if [ "${MONARCHY_NO_PACKAGES:-0}" = 1 ]; then
        echo "  skipping Omarchy AUR packages (--no-packages)"
        return 0
    fi
    if ! command -v paru &> /dev/null; then
        echo "  paru not found, skipping Omarchy AUR packages"
        return 0
    fi

    local version
    version=$(cat "$MONARCHY_PATH/version" 2>/dev/null || true)
    if [ -z "$version" ]; then
        echo "  no $MONARCHY_PATH/version, skipping Omarchy AUR packages"
        return 0
    fi
    packages_link_omarchy_share || return 0

    echo "=== Installing Omarchy AUR packages ==="
    local pkg
    for pkg in "${OMARCHY_AUR_PACKAGES[@]}"; do
        if paru -Q "$pkg" &> /dev/null; then
            echo "  $pkg already installed"
        else
            echo "  Installing $pkg (assuming omarchy=$version)..."
            paru -S --noconfirm "$pkg" --assume-installed "omarchy=$version" \
                || echo "  warning: paru -S $pkg failed"
        fi
    done
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
    local -a remove=()
    if [ ! -f /etc/omarchy.conf ]; then
        echo "  leaving emacs/bun/gh/spotify/discord/cursor-agent/pipx until Monarchy apply writes /etc/omarchy.conf"
        return 0
    fi

    for pkg in "${OMARCHY_OWNED_PACMAN[@]}"; do
        if monarchy_pkg_exactly "$pkg"; then
            remove+=("$pkg")
        fi
    done
    if [ "${#remove[@]}" -gt 0 ]; then
        echo "=== Removing packages Omarchy now owns ==="
        for pkg in "${remove[@]}"; do
            echo "  removing $pkg (Omarchy/mise owns this)"
        done
        monarchy_sudo pacman -R --noconfirm "${remove[@]}" \
            || echo "  warning: pacman -R failed for ${remove[*]}"
    fi

    if command -v flatpak &> /dev/null; then
        for pkg in "${OMARCHY_OWNED_FLATPAKS[@]}"; do
            if flatpak list --app | grep -q "$pkg"; then
                echo "  removing flatpak $pkg (Omarchy owns this)"
                if ! flatpak uninstall -y "$pkg" 2>/dev/null; then
                    monarchy_sudo flatpak uninstall -y "$pkg" \
                        || echo "  warning: flatpak uninstall failed for $pkg"
                fi
            fi
        done
    fi

    packages_strip_curl_pipe_cursor

    remove=()
    for pkg in "${RETIRED_PACMAN[@]}"; do
        if monarchy_pkg_exactly "$pkg"; then
            remove+=("$pkg")
        fi
    done
    if [ "${#remove[@]}" -gt 0 ]; then
        echo "=== Removing retired household packages ==="
        for pkg in "${remove[@]}"; do
            echo "  removing $pkg"
        done
        monarchy_sudo pacman -R --noconfirm "${remove[@]}" \
            || echo "  warning: pacman -R failed for ${remove[*]}"
    fi
    if [ -d "$HOME/.local/share/pipx/venvs" ] && \
        [ -n "$(ls -A "$HOME/.local/share/pipx/venvs" 2>/dev/null)" ]; then
        echo "  leftover pipx venvs in $HOME/.local/share/pipx/venvs (not removing)"
    fi
}
