# shellcheck shell=bash
# The household half of a run: packages, agent home, dotfiles linked by
# mise, rEFInd, services, groups, firewall, system tweaks, hardware
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

# mise links every file in home/ into $HOME, so a live edit is an edit to this
# checkout and shows up in `git status`. mise never commits and never prompts;
# the king commits, by hand. See ADR 0011.
#
# An older mise rejects [bootstrap.hooks] post-dotfiles, and an unknown key in
# a conf.d file stops every mise command from parsing -- the coding agents'
# shims included. So the config is linked in only once mise can read it.
HOUSEHOLD_MISE_MIN=2026.10.4

# Run from $HOME so a mise.toml in whatever directory the run started from
# cannot add itself to the config.
household_mise() {
    (cd "$HOME" && mise "$@")
}

household_dotfiles() {
    monarchy_step "dotfiles (mise)"
    local root="$DOTFILES_DIR/home"
    local conf="$HOME/.config/mise/conf.d/20-dotfiles.toml"
    local have

    household_retire_chezmoi

    # Not a die: the files from the last apply are still in place.
    if ! command -v mise >/dev/null 2>&1; then
        monarchy_warn "mise not installed; dotfiles not applied"
        return 0
    fi
    have=$(household_mise --version 2>/dev/null | awk '{print $1}')
    if [ "$(printf '%s\n%s\n' "$HOUSEHOLD_MISE_MIN" "$have" | sort -V | head -n1)" != "$HOUSEHOLD_MISE_MIN" ]; then
        monarchy_warn "mise $have is older than $HOUSEHOLD_MISE_MIN; dotfiles not applied"
        return 0
    fi

    if [ "$(readlink "$conf" 2>/dev/null)" != "$DOTFILES_DIR/mise/dotfiles.toml" ]; then
        mkdir -p "$(dirname "$conf")"
        ln -sfn "$DOTFILES_DIR/mise/dotfiles.toml" "$conf"
        monarchy_changed "linked $conf"
    fi
    # Where the checkout sits is a fact about the box, so it goes in the
    # king's ~/.config/mise/config.toml and never in the repo.
    if [ "$(household_mise settings get dotfiles.root 2>/dev/null)" != "$root" ]; then
        household_mise settings set dotfiles.root "$root"
        monarchy_changed "set mise dotfiles.root to $root"
    fi

    household_dotfiles_fold_back "$root" || return 0

    local before=0
    household_mise dot status --missing >/dev/null 2>&1 || before=1
    if ! household_mise dot apply --yes --force; then
        monarchy_warn "mise dot apply failed; re-running is the fix. Run: mise dot apply --yes"
        return 0
    fi
    if ! household_mise dot status --missing >/dev/null 2>&1; then
        monarchy_warn "dotfiles are not all in place. Run: mise dot status"
    elif [ "$before" = 1 ]; then
        monarchy_changed "linked dotfiles from $root"
    fi

    local dirty
    dirty=$(git -C "$DOTFILES_DIR" status --short -- home mise | awk '{print $NF}' | paste -sd' ' -)
    if [ -n "$dirty" ]; then
        monarchy_left_alone "uncommitted dotfile changes, commit or discard them: $dirty"
    fi
}

# A tool that saves by rename -- sed -i, most editors, KConfig -- swaps the
# link for a regular file, and chezmoi left a copy at every target. --force
# would throw either away, so a live file is copied over its source first and
# turns up in `git diff`. mise's own status names only the first such file in
# a group, so this walks home/ itself.
household_dotfiles_fold_back() {
    local root=$1 rel target src conflict=""
    local -a stale=()
    while IFS= read -r -d '' rel; do
        rel=${rel#./}
        [ "$rel" != .claude/settings.json ] || continue
        target="$HOME/$rel"
        src=$(readlink -f "$root/$rel")
        # A link carries no content of its own, whoever made it.
        if [ -L "$target" ] || [ ! -f "$target" ]; then
            continue
        fi
        cmp -s "$target" "$src" && continue
        # Content this repo has committed before is a stale copy, not an edit.
        # That is every chezmoi copy on a box whose checkout has since been
        # pulled; folding those back would revert the pull.
        if git -C "$root" cat-file -e "$(git hash-object "$target")" 2>/dev/null; then
            stale+=("$target")
            continue
        fi
        if [ -n "$(git -C "$root" status --porcelain -- "$src")" ]; then
            conflict="$conflict $target"
            continue
        fi
        cp -- "$target" "$src"
        monarchy_changed "folded $target back into the checkout"
    done < <(cd "$root" && find . \( -type f -o -type l \) -print0)
    if [ "${#stale[@]}" -gt 0 ]; then
        monarchy_left_alone "${#stale[@]} older committed copies, linked over: $(monarchy_ui_some "${stale[@]}")"
    fi
    if [ -n "$conflict" ]; then
        monarchy_warn "these and their sources in $root both have uncommitted changes:$conflict. Keep one, then re-run; dotfiles not applied"
        return 1
    fi
}

# What chezmoi left behind that would otherwise keep running: the source link
# (a chezmoi still installed would apply a tree that is gone) and its drift
# hook, which Omarchy fires after every update. Its state database goes too;
# rollback is `chezmoi init`, not that file.
household_retire_chezmoi() {
    local hook="$HOME/.config/omarchy/hooks/post-update.d/chezmoi-drift"
    if [ -L "$HOME/.local/share/chezmoi" ]; then
        rm -f "$HOME/.local/share/chezmoi"
        monarchy_changed "removed the ~/.local/share/chezmoi link"
    fi
    if [ -f "$hook" ] && [ ! -L "$hook" ]; then
        rm -f "$hook"
        monarchy_changed "removed the chezmoi-drift hook"
    fi
    if [ -f "$HOME/.config/chezmoi/chezmoistate.boltdb" ]; then
        rm -f "$HOME/.config/chezmoi/chezmoistate.boltdb"
        rmdir "$HOME/.config/chezmoi" 2>/dev/null || true
        monarchy_changed "removed chezmoi's state"
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

    household_dotfiles

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

    # shellcheck source=games.sh
    source "$LIB_DIR/games.sh"
    games_apply
}
