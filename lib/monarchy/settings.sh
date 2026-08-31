# shellcheck shell=bash
# Install the omarchy-settings file tree without the package.
# Skip list is monarchy/settings.skip (Limine, plymouth-before-zfs,
# os-release is never in this tree, mimeapps, stock SDDM conf, nsswitch).

MONARCHY_ROOT="${MONARCHY_ROOT:-}"

monarchy_settings_skip_file() {
    printf '%s\n' "$MONARCHY_MISC/settings.skip"
}

monarchy_settings_skipped() {
    local rel=$1
    local skip
    skip=$(monarchy_settings_skip_file)
    [ -f "$skip" ] || monarchy_die "missing $skip"
    grep -Fxq "$rel" "$skip"
}

monarchy_settings_dest() {
    local rel=$1
    printf '%s/%s\n' "${MONARCHY_ROOT}" "${rel#/}"
}

monarchy_install_file() {
    local src=$1 dest=$2 mode=${3:-644}
    [ -f "$src" ] || return 0
    monarchy_sudo mkdir -p "$(dirname "$dest")"
    monarchy_sudo install -m "$mode" "$src" "$dest"
}

monarchy_install_etc_tree() {
    local src="$MONARCHY_SRC/etc"
    local f rel dest mode
    [ -d "$src" ] || monarchy_die "missing $src"
    while IFS= read -r -d '' f; do
        rel=${f#"$MONARCHY_SRC/"}
        if monarchy_settings_skipped "$rel"; then
            continue
        fi
        dest=$(monarchy_settings_dest "$rel")
        mode=644
        case "$rel" in
            etc/sudoers.d/*) mode=440 ;;
        esac
        monarchy_install_file "$f" "$dest" "$mode"
    done < <(find "$src" -type f -print0)
}

monarchy_install_profile_d() {
    local dest
    dest=$(monarchy_settings_dest etc/profile.d/omarchy.sh)
    monarchy_sudo mkdir -p "$(dirname "$dest")"
    monarchy_sudo tee "$dest" >/dev/null <<EOF
# Monarchy: bootstrap from the working prefix. Stock hardcodes /usr/share/omarchy.
[ -r /usr/local/share/omarchy/default/bash/env-bootstrap ] && . /usr/local/share/omarchy/default/bash/env-bootstrap
EOF
    monarchy_sudo chmod 644 "$dest"
}

monarchy_install_user_units() {
    local src="$MONARCHY_SRC/default/systemd/user"
    local dest_dir f dest name tmp
    [ -d "$src" ] || return 0
    dest_dir=$(monarchy_settings_dest usr/lib/systemd/user)
    monarchy_sudo mkdir -p "$dest_dir"
    for f in "$src"/*.service; do
        [ -f "$f" ] || continue
        name=$(basename "$f")
        dest="$dest_dir/$name"
        tmp=$(mktemp)
        sed 's|/usr/bin/omarchy-|/usr/local/bin/omarchy-|g' "$f" >"$tmp"
        monarchy_sudo install -m 644 "$tmp" "$dest"
        rm -f "$tmp"
    done
    if [ -d "$src/app.slice.d" ]; then
        monarchy_sudo mkdir -p "$dest_dir/app.slice.d"
        for f in "$src/app.slice.d"/*; do
            [ -f "$f" ] || continue
            monarchy_install_file "$f" "$dest_dir/app.slice.d/$(basename "$f")"
        done
    fi
}

monarchy_install_system_sleep() {
    local src="$MONARCHY_SRC/default/systemd/system-sleep"
    local dest_dir f
    [ -d "$src" ] || return 0
    dest_dir=$(monarchy_settings_dest usr/lib/systemd/system-sleep)
    monarchy_sudo mkdir -p "$dest_dir"
    for f in "$src"/*; do
        [ -f "$f" ] || continue
        monarchy_install_file "$f" "$dest_dir/$(basename "$f")" 755
    done
}

monarchy_install_fontconfig() {
    local src="$MONARCHY_SRC/default/fontconfig/conf.avail/50-omarchy.conf"
    local avail dconf
    [ -f "$src" ] || return 0
    avail=$(monarchy_settings_dest usr/share/fontconfig/conf.avail/50-omarchy.conf)
    dconf=$(monarchy_settings_dest etc/fonts/conf.d/50-omarchy.conf)
    monarchy_install_file "$src" "$avail"
    monarchy_sudo mkdir -p "$(dirname "$dconf")"
    monarchy_sudo ln -sfn "$avail" "$dconf"
}

monarchy_install_omarchy_font() {
    local src="$MONARCHY_SRC/default/fonts/omarchy/omarchy.ttf"
    local dest
    [ -f "$src" ] || return 0
    dest=$(monarchy_settings_dest usr/share/fonts/omarchy/omarchy.ttf)
    monarchy_install_file "$src" "$dest"
}

monarchy_install_xdg_terminals() {
    local src="$MONARCHY_SRC/default/xdg-terminal-exec/hyprland-xdg-terminals.list"
    local dest
    [ -f "$src" ] || return 0
    dest=$(monarchy_settings_dest usr/share/xdg-terminal-exec/hyprland-xdg-terminals.list)
    monarchy_install_file "$src" "$dest"
}

monarchy_install_environment_d() {
    local src="$MONARCHY_SRC/default/environment.d"
    local dest_dir f
    [ -d "$src" ] || return 0
    dest_dir=$(monarchy_settings_dest usr/lib/environment.d)
    monarchy_sudo mkdir -p "$dest_dir"
    for f in "$src"/*; do
        [ -f "$f" ] || continue
        monarchy_install_file "$f" "$dest_dir/$(basename "$f")"
    done
}

monarchy_install_icons() {
    local src="$MONARCHY_SRC/applications/icons"
    local dest_dir f name
    [ -d "$src" ] || return 0
    dest_dir=$(monarchy_settings_dest usr/share/icons/hicolor/256x256/apps)
    monarchy_sudo mkdir -p "$dest_dir"
    for f in "$src"/*; do
        [ -f "$f" ] || continue
        name=$(basename "$f")
        monarchy_install_file "$f" "$dest_dir/$name"
    done
    if [ -f "$MONARCHY_SRC/icon.png" ]; then
        monarchy_install_file "$MONARCHY_SRC/icon.png" \
            "$(monarchy_settings_dest usr/share/pixmaps/omarchy.png)"
        monarchy_install_file "$MONARCHY_SRC/icon.png" \
            "$(monarchy_settings_dest usr/share/icons/hicolor/256x256/apps/omarchy.png)"
    fi
}

monarchy_assert_settings_assets() {
    local skip
    skip=$(monarchy_settings_skip_file)
    [ -f "$skip" ] || monarchy_die "missing $skip"
    grep -qx 'etc/mkinitcpio.conf.d/omarchy_hooks.conf' "$skip" \
        || monarchy_die "$skip must skip plymouth-before-zfs hooks"
    grep -qx 'etc/limine-entry-tool.d/omarchy-defaults.conf' "$skip" \
        || monarchy_die "$skip must skip Limine drop-ins"
    grep -qx 'default/applications/mimeapps.list' "$skip" \
        || monarchy_die "$skip must skip system mimeapps"
    grep -qx 'etc/docker/daemon.json' "$skip" \
        || monarchy_die "$skip must skip Omarchy docker daemon.json"
    grep -qx 'etc/skel/.bashrc' "$skip" \
        || monarchy_die "$skip must skip Omarchy skel bashrc"
    monarchy_in_list omarchy-install-app "${MONARCHY_BIN_ALLOW[@]}" \
        || monarchy_die "omarchy-install-app must be allowed"
    monarchy_in_list omarchy-refresh-pacman "${MONARCHY_BIN_DENY[@]}" \
        || monarchy_die "omarchy-refresh-pacman must stay denied"
}

monarchy_install_settings() {
    monarchy_assert_settings_assets
    monarchy_install_etc_tree
    monarchy_install_profile_d
    monarchy_install_user_units
    monarchy_install_system_sleep
    monarchy_install_fontconfig
    monarchy_install_omarchy_font
    monarchy_install_xdg_terminals
    monarchy_install_environment_d
    monarchy_install_icons
    monarchy_log "omarchy-settings files installed (skip list applied)"
}

monarchy_enable_omarchy_services() {
    local unit
    command -v systemctl >/dev/null 2>&1 || return 0
    for unit in cups.service cups-browsed.service avahi-daemon.service \
        docker.socket systemd-resolved.service NetworkManager.service \
        power-profiles-daemon.service sddm.service systemd-oomd.service; do
        if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
            monarchy_sudo systemctl enable "$unit" >/dev/null 2>&1 || true
        fi
    done
    if systemctl list-unit-files NetworkManager-wait-online.service >/dev/null 2>&1; then
        monarchy_sudo systemctl mask NetworkManager-wait-online.service >/dev/null 2>&1 || true
    fi
}

# $2=1 runs as root. Clone install/config/*.sh write under /etc and /usr.
monarchy_run_install_script() {
    local script=$1
    local as_root=${2:-0}
    local rc=0
    [ -f "$script" ] || return 0
    export OMARCHY_PATH="${OMARCHY_PATH:-$MONARCHY_PATH}"
    export OMARCHY_INSTALL="${OMARCHY_PATH}/install"
    export PATH="${OMARCHY_PATH}/bin:${PATH:-/usr/bin}"
    if [ "$as_root" = 1 ]; then
        monarchy_sudo bash "$script" && rc=0 || rc=$?
    else
        bash "$script" && rc=0 || rc=$?
    fi
    if [ "$rc" -eq 0 ]; then
        monarchy_log "ran $script"
    else
        monarchy_log "warning: $script exited $rc"
    fi
}

monarchy_run_omarchy_config() {
    local inst="${OMARCHY_PATH:-$MONARCHY_PATH}/install"
    monarchy_run_install_script "$inst/config/theme-system.sh" 1
    monarchy_run_install_script "$inst/config/ssh-command-path.sh" 1
    monarchy_run_install_script "$inst/config/ssh-keepalive.sh" 1
    monarchy_run_install_script "$inst/config/fix-powerprofilesctl-shebang.sh" 1
    monarchy_enable_omarchy_services
}

monarchy_enable_user_units() {
    command -v systemctl >/dev/null 2>&1 || return 0
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    systemctl --user enable --now \
        bt-agent.service \
        omarchy-recover-internal-monitor.service \
        omarchy-sleep-lock.service \
        omarchy-migrate-notify.service \
        omarchy-fcitx5.service \
        omarchy-crash-watch.service >/dev/null 2>&1 || true
    monarchy_log "enabled Omarchy user units (missing units ignored)"
}
