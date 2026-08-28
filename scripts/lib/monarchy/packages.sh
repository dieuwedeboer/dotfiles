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

monarchy_record_packages() {
    local tmp
    tmp=$(mktemp)
    monarchy_filtered_packages >"$tmp"
    monarchy_sudo mkdir -p /var/lib/monarchy
    monarchy_sudo install -m 644 "$tmp" /var/lib/monarchy/packages.installed
    if [ -w "$MONARCHY_MISC" ]; then
        install -m 644 "$tmp" "$MONARCHY_MISC/packages.installed"
    fi
    rm -f "$tmp"
}

monarchy_install_packages() {
    if [ "${MONARCHY_NO_PACKAGES:-0}" = 1 ]; then
        monarchy_log "skipping packages (--no-packages)"
        return 0
    fi

    local -a pkgs=()
    mapfile -t pkgs < <(monarchy_filtered_packages)
    [ "${#pkgs[@]}" -gt 0 ] || monarchy_die "filtered package list is empty"

    local denied
    for denied in plasma-login-manager tldr snapper limine omarchy omarchy-dev omarchy-settings omarchy-settings-dev; do
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

    monarchy_log "pacman -Sy then install ${#pkgs[@]} filtered leaf packages"
    monarchy_sudo pacman -Sy --noconfirm
    monarchy_sudo pacman -S --needed --noconfirm "${pkgs[@]}"
    monarchy_record_packages
    monarchy_skip_os_release_clobber
    monarchy_log "packages installed"
    return 0
}
