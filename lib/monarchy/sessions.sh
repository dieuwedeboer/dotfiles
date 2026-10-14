# shellcheck shell=bash
# Sourced into one shell by lib/monarchy.sh; common.sh state is in scope.
# shellcheck disable=SC2154

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

    # Roles come from /etc/monarchy/users.conf; no usernames live in this repo.
    local u r
    while read -r u r; do
        monarchy_accountsservice_session "$u" "$(monarchy_role_session "$r")"
    done < <(monarchy_users)
    # An account absent from users.conf is a serf and takes the default.
    if [ "$USER" != root ]; then
        monarchy_accountsservice_session "$USER" \
            "$(monarchy_role_session "$(monarchy_user_role "$USER")")"
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

# Keep XDG autostart from racing omarchy-fcitx5.service, on every account.
#
# fcitx5 ships /etc/xdg/autostart/org.fcitx.Fcitx5.desktop, and uwsm runs XDG
# autostart at every login. Whichever fcitx5 comes up second sees the first
# owning org.fcitx.Fcitx5 and exits 0. If that is the service, Restart=always
# turns it into a restart every two seconds for the whole session -- thousands
# of journal lines while the stray instance does the actual work.
#
# Omarchy's answer is a Hidden=true override in config/autostart, but it only
# reaches an account through /etc/skel, at creation. Its migration onto the
# service never writes it for an account that already existed, so every such
# account races at each login. This writes the same file upstream ships.
#
# Only where the service is enabled. The service is enabled per account, and
# hiding the autostart entry on an account without it leaves that account
# with no input method at all. The destination is the marker (ADR 0002): an
# override already there, Omarchy's or a hand-edited one, is left as it is.
#
# Written as the account, never as root into someone's home: a symlink there
# must not be able to redirect a root write.
monarchy_hide_fcitx5_autostart() {
    local src="$MONARCHY_PATH/config/autostart/org.fcitx.Fcitx5.desktop"
    local user home rc
    if [ ! -f "$src" ]; then
        monarchy_trace "no $src; fcitx5 autostart left as Omarchy ships it"
        return 0
    fi
    while IFS=: read -r user home; do
        [ -d "$home" ] || continue
        rc=0
        # Single quotes on purpose: $HOME is the account's, expanded in its
        # own shell, not this one's.
        # shellcheck disable=SC2016
        monarchy_as_account "$user" sh -c '
            ls "$HOME"/.config/systemd/user/*.wants/omarchy-fcitx5.service >/dev/null 2>&1 || exit 3
            dest="$HOME/.config/autostart/org.fcitx.Fcitx5.desktop"
            [ ! -e "$dest" ] && [ ! -L "$dest" ] || exit 4
            mkdir -p "$HOME/.config/autostart" && cp "$1" "$dest"
        ' sh "$src" || rc=$?
        case "$rc" in
            0) monarchy_changed "hid fcitx5 XDG autostart for $user; omarchy-fcitx5.service runs it" ;;
            3) monarchy_trace "$user has no omarchy-fcitx5.service; fcitx5 autostart left on" ;;
            4) monarchy_trace "$user already overrides fcitx5 autostart" ;;
            *) monarchy_warn "could not write the fcitx5 autostart override for $user" ;;
        esac
    done < <(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1 ":" $6}')
}

# Run a command as a given account, with that account's HOME. No sudo for the
# account already running apply: sudo to yourself still asks for a password.
# Plain sudo, not monarchy_sudo: as root that one drops the word sudo and
# would run `-u` as the command.
monarchy_as_account() {
    local user=$1
    shift
    if [ "$user" = "$(id -un)" ]; then
        "$@"
    else
        sudo -u "$user" -H -- "$@"
    fi
}
