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
    monarchy_log "AccountsService Session=$session for $user (unverified PLM API)"
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

    monarchy_skip_autologin
    monarchy_log "installed $dest ($exec_line)"
    return 0
}
