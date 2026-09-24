# shellcheck shell=bash
# The household half of a run: packages, agent home, chezmoi-managed
# dotfiles, rEFInd, services, groups, firewall, system tweaks, hardware
# quirks, ZFS. Everything that is true of the box regardless of Omarchy.
#
# Sourced by install.sh, which is argument parsing and dispatch and nothing
# else. This used to be a hundred-line function inside install.sh -- the last
# implementation body still living there while every other one lived in lib/
# -- so the entry point could not be read without reading the work.
#
# Idempotent. Runs on a first install and on every --update, so the two entry
# points cannot drift. --only skips it: that flag is for iterating on one
# overlay unit, not for refreshing the box.
#
# Requires lib/monarchy.sh and lib/packages.sh already sourced, and
# DOTFILES_DIR and LIB_DIR set.

# chezmoi apply prompts when a target has been modified. The Omarchy menu
# wraps omarchy-update with no terminal, so that path reports drift and
# continues rather than hanging. An interactive ./install.sh or a hand-run
# monarchy-update has a tty and just applies. See ADR 0001.
household_chezmoi() {
    monarchy_step "dotfiles (chezmoi)"
    if [ ! -L "$HOME/.local/share/chezmoi" ]; then
        if [ -d "$HOME/.local/share/chezmoi" ]; then
            monarchy_changed "moved an existing chezmoi aside to ~/.local/share/chezmoi.bk"
            mv "$HOME/.local/share/chezmoi" "$HOME/.local/share/chezmoi.bk"
        fi
        ln -s "$DOTFILES_DIR/chezmoi" "$HOME/.local/share/chezmoi"
        monarchy_changed "linked ~/.local/share/chezmoi at $DOTFILES_DIR/chezmoi"
    fi

    if ! command -v chezmoi >/dev/null 2>&1; then
        monarchy_warn "chezmoi not installed; dotfiles not applied"
        return 0
    fi

    local status
    status=$(chezmoi status 2>/dev/null || true)
    if [ -z "$status" ]; then
        monarchy_log "chezmoi already applied"
        return 0
    fi
    if monarchy_can_prompt; then
        chezmoi apply
        # Read by lib/zfs.sh, which restarts ksystemstats only when there is
        # something new for it to load. It runs as a subprocess, so this is
        # the only way the fact reaches it.
        export MONARCHY_CHEZMOI_APPLIED=1
        monarchy_changed "applied chezmoi-managed dotfiles"
    else
        monarchy_warn "chezmoi has drifted and there is no terminal to apply on. Run: chezmoi apply"
    fi
}

household_services() {
    monarchy_step "services and groups"
    command -v systemctl >/dev/null 2>&1 || return 0
    local unit
    for unit in docker.socket sshd; do
        if ! systemctl is-enabled "$unit" >/dev/null 2>&1; then
            monarchy_sudo systemctl enable "$unit"
            monarchy_changed "enabled $unit"
        fi
    done

    if command -v getent >/dev/null 2>&1; then
        if ! getent group docker | grep -q "$USER"; then
            monarchy_sudo usermod -aG docker "$USER"
            monarchy_changed "added $USER to the docker group"
        fi
    fi
}

household_firewall() {
    monarchy_step "firewall"
    if ! command -v ufw >/dev/null 2>&1; then
        monarchy_log "ufw not installed; skipped"
        return 0
    fi
    # shellcheck source=ufw.sh
    source "$LIB_DIR/ufw.sh"
    ufw_apply_rules
    monarchy_log "rules written; enable/disable left alone, it persists"
}

household_tweaks() {
    monarchy_step "system tweaks"
    if [ -f /etc/mkinitcpio.conf ] && grep -q "^HOOKS.*fsck" /etc/mkinitcpio.conf; then
        monarchy_sudo sed -i '/^HOOKS/s/fsck//' /etc/mkinitcpio.conf
        monarchy_changed "removed the fsck hook from mkinitcpio.conf"
    fi
    if [ -f /etc/vconsole.conf ] && ! grep -q "KEYMAP=en" /etc/vconsole.conf; then
        echo "KEYMAP=en" | monarchy_sudo tee /etc/vconsole.conf >/dev/null
        monarchy_changed "set KEYMAP=en in vconsole.conf"
    fi
}

household_refresh() {
    monarchy_section "Household"

    # packages_install emits its own steps: pacman, AUR, flatpak, unwanted.
    packages_install

    # shellcheck source=agents.sh
    source "$LIB_DIR/agents.sh"
    monarchy_step "agent home (~/.agents)"
    agents_materialize_home

    household_chezmoi

    monarchy_step "agent skills from lock"
    agents_restore_skills

    monarchy_step "rEFInd theme"
    "$LIB_DIR/refind.sh"

    household_services
    household_firewall
    household_tweaks

    monarchy_step "hardware quirks"
    "$DOTFILES_DIR/hardware/apply.sh"

    monarchy_step "ZFS monitoring and snapshots"
    "$LIB_DIR/zfs.sh"
}
