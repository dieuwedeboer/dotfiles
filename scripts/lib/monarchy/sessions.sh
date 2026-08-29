# shellcheck shell=bash

monarchy_accountsservice_session() {
    local user=$1
    local session=$2
    local dir=/var/lib/AccountsService/users
    local f="$dir/$user"

    getent passwd "$user" >/dev/null 2>&1 || return 0

    monarchy_sudo mkdir -p "$dir"
    if [ -f "$f" ]; then
        if grep -q '^Session=' "$f"; then
            local tmp
            tmp=$(mktemp)
            awk -v s="$session" '
                BEGIN { done=0 }
                /^Session=/ { print "Session=" s; done=1; next }
                { print }
                END { if (!done) print "Session=" s }
            ' "$f" >"$tmp"
            monarchy_sudo install -m 644 "$tmp" "$f"
            rm -f "$tmp"
        else
            printf '\nSession=%s\n' "$session" | monarchy_sudo tee -a "$f" >/dev/null
        fi
    else
        printf '[User]\nSession=%s\n' "$session" | monarchy_sudo tee "$f" >/dev/null
        monarchy_sudo chmod 644 "$f"
    fi
    monarchy_log "AccountsService Session=$session for $user"
}

monarchy_install_omarchy_session() {
    local dest=/usr/share/wayland-sessions/omarchy.desktop
    local src="$MONARCHY_MISC/omarchy.desktop"
    local probe="$monarchy_lib_dir/session-probe.sh"
    local exec_line

    [ -f "$src" ] || monarchy_die "missing $src"

    if command -v pacman >/dev/null 2>&1; then
        if ! monarchy_pkg_installed uwsm; then
            monarchy_log "install uwsm so TryExec=uwsm is visible"
            monarchy_sudo pacman -S --needed --noconfirm uwsm
        fi
    fi

    monarchy_sudo install -m 755 "$probe" /usr/local/bin/monarchy-session-probe

    if [ -f /usr/share/wayland-sessions/hyprland.desktop ]; then
        exec_line='Exec=uwsm start -g -1 -e -D Hyprland hyprland.desktop'
    else
        exec_line='Exec=/usr/local/bin/monarchy-session-probe'
    fi

    local tmp
    tmp=$(mktemp)
    awk -v e="$exec_line" '
        /^Exec=/ { print e; next }
        { print }
    ' "$src" >"$tmp"
    monarchy_sudo mkdir -p /usr/share/wayland-sessions
    monarchy_sudo install -m 644 "$tmp" "$dest"
    rm -f "$tmp"

    [ -f /usr/share/wayland-sessions/plasma.desktop ] || \
        monarchy_log "warning: plasma.desktop missing; family Plasma session may not appear"

    monarchy_accountsservice_session dieuwe omarchy.desktop
    monarchy_accountsservice_session amie plasma.desktop
    monarchy_accountsservice_session olivier plasma.desktop
    if [ "$USER" != "dieuwe" ] && [ "$USER" != "root" ]; then
        monarchy_accountsservice_session "$USER" omarchy.desktop
    fi

    monarchy_hide_stock_hyprland_sessions
    monarchy_skip_autologin
    monarchy_log "installed $dest ($exec_line)"
    return 0
}

# Keep hyprland.desktop on disk: omarchy.desktop Exec is
# `uwsm start … hyprland.desktop`, and uwsm refuses Hidden=true.
# NoDisplay=true drops it from SDDM's sessionModel. Same for hyprland-uwsm.
monarchy_hide_stock_hyprland_sessions() {
    local dir="${MONARCHY_WAYLAND_SESSIONS_DIR:-/usr/share/wayland-sessions}"
    local name f
    for name in hyprland.desktop hyprland-uwsm.desktop; do
        f="$dir/$name"
        [ -f "$f" ] || continue
        if grep -q '^Hidden=true' "$f"; then
            monarchy_die "$f is Hidden=true; uwsm start … hyprland.desktop would refuse it"
        fi
        if grep -q '^NoDisplay=true' "$f"; then
            continue
        fi
        monarchy_set_desktop_nodisplay "$f"
        monarchy_log "hid $f from SDDM (NoDisplay=true)"
    done
}

monarchy_set_desktop_nodisplay() {
    local f=$1
    local tmp
    tmp=$(mktemp)
    awk '
        BEGIN { seen = 0 }
        /^NoDisplay=/ { print "NoDisplay=true"; seen = 1; next }
        { print }
        END { if (!seen) print "NoDisplay=true" }
    ' "$f" >"$tmp"
    if [ -w "$f" ]; then
        install -m 644 "$tmp" "$f"
    else
        monarchy_sudo install -m 644 "$tmp" "$f"
    fi
    rm -f "$tmp"
}

monarchy_check_hidden_hyprland_sessions() {
    local dir="${MONARCHY_WAYLAND_SESSIONS_DIR:-/usr/share/wayland-sessions}"
    local name f
    for name in hyprland.desktop hyprland-uwsm.desktop; do
        f="$dir/$name"
        [ -f "$f" ] || continue
        if ! grep -q '^NoDisplay=true' "$f"; then
            monarchy_die "$f is still visible in SDDM (need NoDisplay=true)"
        fi
        if grep -q '^Hidden=true' "$f"; then
            monarchy_die "$f is Hidden=true; uwsm start … hyprland.desktop would refuse it"
        fi
    done
}

# Omarchy-settings would have installed these. Without them, CachyOS
# HandlePowerKey=poweroff: a short KEY_POWER (laptop button or a Bluetooth
# AVRCP device) shuts the machine down. Reload logind, do not restart it.
monarchy_apply_logind() {
    local src dest name
    local dir="$MONARCHY_MISC/logind"
    [ -d "$dir" ] || monarchy_die "missing $dir"
    monarchy_sudo mkdir -p /etc/systemd/logind.conf.d
    for src in "$dir"/*.conf; do
        [ -f "$src" ] || continue
        name=$(basename "$src")
        dest="/etc/systemd/logind.conf.d/${name%%-*}-monarchy-${name#*-}"
        monarchy_sudo install -m 644 "$src" "$dest"
        monarchy_log "installed $dest"
    done
    grep -q '^HandlePowerKey=ignore' /etc/systemd/logind.conf.d/10-monarchy-ignore-power-button.conf \
        || monarchy_die "logind drop-in missing HandlePowerKey=ignore"
    monarchy_sudo systemctl reload systemd-logind
    monarchy_log "reloaded systemd-logind"
}

monarchy_check_logind() {
    local src="$MONARCHY_MISC/logind/10-ignore-power-button.conf"
    [ -f "$src" ] || monarchy_die "missing $src"
    grep -q '^HandlePowerKey=ignore' "$src" \
        || monarchy_die "$src must set HandlePowerKey=ignore"
    [ -f "$MONARCHY_MISC/logind/20-inhibit-delay.conf" ] \
        || monarchy_die "missing inhibit-delay logind drop-in"
}
