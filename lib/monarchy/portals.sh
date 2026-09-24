# shellcheck shell=bash

monarchy_install_uwsm_env() {
    local src="$MONARCHY_MISC/10-monarchy"
    local dest=/usr/share/uwsm/env.d/10-monarchy
    [ -f "$src" ] || monarchy_die "missing $src"
    if monarchy_install_if_changed 644 "$src" "$dest"; then
        monarchy_changed "installed $dest"
    else
        monarchy_trace "$dest already current"
    fi
}

monarchy_install_hyprland_portals() {
    local dest=/usr/share/xdg-desktop-portal/hyprland-portals.conf
    local src="$MONARCHY_MISC/hyprland-portals.conf"
    if [ -f "$dest" ]; then
        monarchy_trace "leaving existing $dest"
        return 0
    fi
    [ -f "$src" ] || monarchy_die "missing $src"
    monarchy_sudo mkdir -p /usr/share/xdg-desktop-portal
    monarchy_sudo install -m 644 "$src" "$dest"
    monarchy_changed "installed $dest"
    return 0
}
