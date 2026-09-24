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
    # tests/run.sh lints lib/, tests/, hardware/ and install.sh with this, and
    # skips that arm when it is absent -- which reads as a pass.
    shellcheck
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

# Already installed is the ordinary case and says nothing. What a reader
# wants from a package step is the handful that were not there a minute ago,
# and the summary collects exactly those.
#
# One transaction per manager, not one per package. Installing forty packages
# forty times over meant forty dependency resolutions, forty download batches
# and forty screens of pacman output for a step that is usually a no-op. The
# absent set is worked out first and handed over in a single call.
packages_install() {
    local pkg installed
    local -a missing=()

    monarchy_step "pacman packages"
    for pkg in "${PACMAN_PACKAGES[@]}"; do
        pacman -Q "$pkg" &> /dev/null || missing+=("$pkg")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        monarchy_sudo pacman -S --noconfirm "${missing[@]}"
        monarchy_changed_many installed "pacman packages" "${missing[@]}"
    fi

    monarchy_step "AUR packages"
    if command -v paru &> /dev/null; then
        missing=()
        for pkg in "${AUR_PACKAGES[@]}"; do
            paru -Q "$pkg" &> /dev/null || missing+=("$pkg")
        done
        if [ "${#missing[@]}" -gt 0 ]; then
            paru -S --noconfirm "${missing[@]}"
            monarchy_changed_many installed "AUR packages" "${missing[@]}"
        fi
    else
        monarchy_warn "paru not found; AUR packages skipped"
    fi

    monarchy_step "flatpak packages"
    # One `flatpak list`, not one per name: it is the slow part of this step.
    installed=$(flatpak list --app --columns=application 2>/dev/null || true)
    missing=()
    for pkg in "${FLATPAK_PACKAGES[@]}"; do
        grep -Fqx "$pkg" <<<"$installed" || missing+=("$pkg")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        flatpak install -y "${missing[@]}"
        monarchy_changed_many installed "flatpak packages" "${missing[@]}"
    fi

    monarchy_step "unwanted packages"
    if pacman -Q cachyos-wallpapers &> /dev/null; then
        monarchy_sudo pacman -R --noconfirm cachyos-wallpapers
        monarchy_changed "removed cachyos-wallpapers"
    fi

    # Curl-pipe grok used ~/.grok/bin and stole the `agent` name from Cursor.
    if [ -L "$HOME/.local/bin/grok" ]; then
        grok_target=$(readlink -f "$HOME/.local/bin/grok" 2>/dev/null || true)
        case "$grok_target" in
            */.grok/*)
                rm -f "$HOME/.local/bin/grok"
                monarchy_changed "removed the curl-pipe grok symlink"
                ;;
        esac
    fi
    if [ -L "$HOME/.local/bin/agent" ]; then
        agent_target=$(readlink -f "$HOME/.local/bin/agent" 2>/dev/null || true)
        case "$agent_target" in
            */.grok/*)
                rm -f "$HOME/.local/bin/agent"
                monarchy_changed "removed the grok-as-agent symlink"
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
        monarchy_warn "$link points elsewhere, leaving it"
        return 1
    fi
    if [ -e "$link" ]; then
        monarchy_warn "$link is not a symlink, leaving it"
        return 1
    fi
    monarchy_sudo ln -sT "$MONARCHY_PATH" "$link"
    monarchy_changed "linked $link -> $MONARCHY_PATH"
}

# Runs after apply, not with the rest of the packages: the version file and
# the shell QML both come from the overlay.
packages_install_omarchy_aur() {
    [ "${#OMARCHY_AUR_PACKAGES[@]}" -gt 0 ] || return 0
    if [ "${MONARCHY_NO_PACKAGES:-0}" = 1 ]; then
        monarchy_log "Omarchy AUR packages skipped (--no-packages)"
        return 0
    fi
    if ! command -v paru &> /dev/null; then
        monarchy_warn "paru not found; Omarchy AUR packages skipped"
        return 0
    fi

    local version
    version=$(cat "$MONARCHY_PATH/version" 2>/dev/null || true)
    if [ -z "$version" ]; then
        monarchy_log "no $MONARCHY_PATH/version; Omarchy AUR packages skipped"
        return 0
    fi
    packages_link_omarchy_share || return 0

    monarchy_step "Omarchy AUR packages"
    local pkg
    local -a missing=()
    for pkg in "${OMARCHY_AUR_PACKAGES[@]}"; do
        paru -Q "$pkg" &> /dev/null || missing+=("$pkg")
    done
    [ "${#missing[@]}" -gt 0 ] || return 0
    # One transaction, then one retry each. These are AUR builds and this is
    # the step that fails: batching them meant a single unbuildable package
    # took the whole set down, where the old per-package loop installed
    # everything else and warned about the one. The batch keeps the common
    # case to one dependency resolution; the fallback keeps the bad case from
    # costing four packages instead of one.
    if paru -S --noconfirm "${missing[@]}" --assume-installed "omarchy=$version"; then
        monarchy_changed_many installed "Omarchy AUR packages" "${missing[@]}"
        return 0
    fi
    monarchy_log "batch install failed; retrying ${#missing[@]} packages one at a time"
    local -a done_pkgs=()
    for pkg in "${missing[@]}"; do
        if paru -S --noconfirm "$pkg" --assume-installed "omarchy=$version"; then
            done_pkgs+=("$pkg")
        else
            monarchy_warn "paru -S $pkg failed"
        fi
    done
    monarchy_changed_many installed "Omarchy AUR packages" "${done_pkgs[@]}"
}

packages_strip_curl_pipe_cursor() {
    local target
    if [ -L "$HOME/.local/bin/cursor-agent" ]; then
        target=$(readlink -f "$HOME/.local/bin/cursor-agent" 2>/dev/null || true)
        case "$target" in
            */.local/share/cursor-agent/*)
                rm -f "$HOME/.local/bin/cursor-agent"
                rm -rf "$HOME/.local/share/cursor-agent"
                monarchy_changed "removed the curl-pipe cursor-agent"
                ;;
        esac
    fi
}

packages_strip_omarchy_owned() {
    local pkg
    local -a remove=()
    if [ ! -f /etc/omarchy.conf ]; then
        monarchy_log "leaving emacs/bun/gh/spotify/discord/cursor-agent/pipx until Monarchy apply writes /etc/omarchy.conf"
        return 0
    fi

    for pkg in "${OMARCHY_OWNED_PACMAN[@]}"; do
        if monarchy_pkg_exactly "$pkg"; then
            remove+=("$pkg")
        fi
    done
    if [ "${#remove[@]}" -gt 0 ]; then
        monarchy_step "packages Omarchy now owns"
        if monarchy_sudo pacman -R --noconfirm "${remove[@]}"; then
            monarchy_changed_many removed "packages Omarchy now owns" "${remove[@]}"
        else
            monarchy_warn "pacman -R failed for ${remove[*]}"
        fi
    fi

    if command -v flatpak &> /dev/null; then
        for pkg in "${OMARCHY_OWNED_FLATPAKS[@]}"; do
            if flatpak list --app | grep -q "$pkg"; then
                if flatpak uninstall -y "$pkg" 2>/dev/null \
                    || monarchy_sudo flatpak uninstall -y "$pkg"; then
                    monarchy_changed "removed flatpak $pkg (Omarchy owns it)"
                else
                    monarchy_warn "flatpak uninstall failed for $pkg"
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
        monarchy_step "retired household packages"
        if monarchy_sudo pacman -R --noconfirm "${remove[@]}"; then
            monarchy_changed_many removed "retired household packages" "${remove[@]}"
        else
            monarchy_warn "pacman -R failed for ${remove[*]}"
        fi
    fi
    if [ -d "$HOME/.local/share/pipx/venvs" ] && \
        [ -n "$(ls -A "$HOME/.local/share/pipx/venvs" 2>/dev/null)" ]; then
        monarchy_log "leftover pipx venvs in $HOME/.local/share/pipx/venvs (not removing)"
    fi
}
