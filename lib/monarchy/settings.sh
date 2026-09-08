# shellcheck shell=bash
# MONARCHY_PATH comes from common.sh; shellcheck reads this file alone.
# shellcheck disable=SC2153
# What is left of "install the omarchy-settings tree by hand".
#
# omarchy-settings-monarchy now owns that tree: it is the official package
# rebuilt without upstream's post_install (the `rm -f /etc/os-release` block)
# and without the paths in monarchy/settings.skip. Everything this file used
# to copy -- the etc/ tree, systemd user units, system-sleep hooks,
# fontconfig, the Omarchy font, xdg-terminal-exec, environment.d, icons -- is
# shipped by that package, so pacman owns it, `pacman -Qkk` verifies it, and
# removing the package removes it.
#
# The one thing a package cannot do is point at the working prefix, because
# upstream's /etc/profile.d/omarchy.sh hardcodes /usr/share/omarchy and the
# session has to read /usr/local/share/omarchy.

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

monarchy_install_profile_d() {
    local dest parent
    dest=$(monarchy_settings_dest etc/profile.d/omarchy.sh)
    parent=$(dirname "$dest")
    monarchy_write_to "$parent" mkdir -p "$parent"
    monarchy_write_to "$parent" tee "$dest" >/dev/null <<PROFILE
# Monarchy: bootstrap from the working prefix. Stock hardcodes
# /usr/share/omarchy, which is the package tree, not the overlay.
[ -r ${MONARCHY_PATH}/default/bash/env-bootstrap ] && . ${MONARCHY_PATH}/default/bash/env-bootstrap
PROFILE
    monarchy_write_to "$parent" chmod 644 "$dest"
}

# The skip list is now a package build input, so these assertions are about
# what omarchy-settings-monarchy must have excluded, not about what a copy
# loop must have avoided.
monarchy_assert_settings_assets() {
    local skip rel
    skip=$(monarchy_settings_skip_file)
    [ -f "$skip" ] || monarchy_die "missing $skip"
    for rel in \
        etc/limine-entry-tool.d \
        etc/snapper \
        etc/mkinitcpio.conf.d/omarchy_hooks.conf \
        usr/share/omarchy/default/applications/mimeapps.list \
        etc/docker/daemon.json \
        etc/profile.d/omarchy.sh; do
        grep -qx "$rel" "$skip" || monarchy_die "$skip must skip $rel"
    done
    # These are not files in the package; upstream copies them from
    # etc-overrides in the scriptlet the rebuild drops. If they ever become
    # real package files, the skip list has to grow and this will say so.
    monarchy_in_list omarchy-refresh-pacman "${MONARCHY_BIN_DENY[@]}" \
        || monarchy_die "omarchy-refresh-pacman must stay denied"
    return 0
}

monarchy_install_settings() {
    monarchy_assert_settings_assets
    monarchy_install_profile_d
    monarchy_log "settings owned by omarchy-settings-monarchy; profile.d repointed at $MONARCHY_PATH"
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

# $2=1 runs as root. install/config/*.sh write under /etc and /usr.
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
