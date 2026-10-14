# shellcheck shell=bash

monarchy_filtered_packages() {
    local list="$MONARCHY_SRC/install/omarchy-base.packages"
    [ -f "$list" ] || monarchy_die "missing $list"
    local pkg
    while read -r pkg; do
        [ -n "$pkg" ] || continue
        case "$pkg" in
            \#*) continue ;;
        esac
        if monarchy_in_list "$pkg" "${MONARCHY_PKG_DENY[@]}"; then
            continue
        fi
        printf '%s\n' "$pkg"
    done <"$list"
}

# /var/lib/monarchy holds this box's set. The repo copy is what every channel
# has classified as installed, so a stable box and an edge box add to it
# rather than overwrite each other's (ADR 0009). A row upstream drops
# everywhere is pruned by hand.
monarchy_record_packages() {
    local tmp repo_copy="$MONARCHY_MISC/packages.installed"
    tmp=$(mktemp)
    monarchy_filtered_packages >"$tmp"
    monarchy_sudo mkdir -p /var/lib/monarchy
    monarchy_sudo install -m 644 "$tmp" /var/lib/monarchy/packages.installed
    if [ -w "$MONARCHY_MISC" ]; then
        [ -f "$repo_copy" ] && cat "$repo_copy" >>"$tmp"
        sort -u "$tmp" -o "$tmp"
        install -m 644 "$tmp" "$repo_copy"
    fi
    rm -f "$tmp"
}

monarchy_install_packages() {
    if [ "${MONARCHY_NO_PACKAGES:-0}" = 1 ]; then
        monarchy_trace "skipping packages (--no-packages)"
        return 0
    fi

    local -a pkgs=()
    mapfile -t pkgs < <(monarchy_filtered_packages)
    [ "${#pkgs[@]}" -gt 0 ] || monarchy_die "filtered package list is empty"

    local denied
    for denied in plasma-login-manager tldr snapper limine \
        limine-mkinitcpio-hook limine-snapper-sync omarchy-dev \
        omarchy-settings omarchy-settings-dev ufw-docker; do
        if monarchy_in_list "$denied" "${pkgs[@]}"; then
            monarchy_die "denied package $denied leaked into install set"
        fi
    done
    monarchy_in_list sddm "${pkgs[@]}" \
        || monarchy_die "sddm missing from filtered package list"

    # TLP's tlp-pd Provides/Conflicts power-profiles-daemon. Omarchy's
    # session calls powerprofilesctl; keep the real daemon, not TLP.
    if monarchy_in_list power-profiles-daemon "${pkgs[@]}" && monarchy_pkg_installed tlp-pd; then
        monarchy_die "tlp-pd conflicts with power-profiles-daemon. Remove TLP first: sudo pacman -Rns tlp-pd tlp-rdw tlp && sudo systemctl unmask power-profiles-daemon.service"
    fi

    monarchy_refuse_partial_upgrade

    # pacman -T follows Provides (neovim satisfies nvim) in one query.
    local -a need=()
    mapfile -t need < <(pacman -T "${pkgs[@]}" || true)
    if [ "${#need[@]}" -eq 0 ]; then
        monarchy_trace "filtered leaf packages already installed (${#pkgs[@]})"
    else
        monarchy_log "pacman -S --needed ${#need[@]} of ${#pkgs[@]} filtered leaf packages"
        monarchy_sudo pacman -S --needed --noconfirm "${need[@]}"
        monarchy_trace "packages installed"
    fi
    monarchy_record_packages
    monarchy_skip_os_release_clobber
    return 0
}
