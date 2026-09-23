# shellcheck shell=bash
# Sourced into one shell by lib/monarchy.sh; common.sh state is in scope.
# shellcheck disable=SC2154

monarchy_wrap_stub_for() {
    local name=$1
    case "$name" in
        omarchy-update|omarchy-update-system-pkgs)
            printf '%s\n' "$monarchy_lib_dir/stubs/wrap-update.sh"
            ;;
        omarchy-plymouth-set|omarchy-plymouth-reset|omarchy-refresh-plymouth)
            printf '%s\n' "$monarchy_lib_dir/stubs/wrap-plymouth.sh"
            ;;
        omarchy-refresh-sddm)
            printf '%s\n' "$monarchy_lib_dir/stubs/wrap-sddm.sh"
            ;;
        omarchy-screensaver)
            printf '%s\n' "$monarchy_lib_dir/stubs/wrap-screensaver.sh"
            ;;
        omarchy-display-text-size)
            printf '%s\n' "$monarchy_lib_dir/stubs/wrap-display-text-size.sh"
            ;;
        omarchy-disk-speedtest)
            printf '%s\n' "$monarchy_lib_dir/stubs/wrap-disk-speedtest.sh"
            ;;
        omarchy-battery-status)
            printf '%s\n' "$monarchy_lib_dir/stubs/wrap-battery-status.sh"
            ;;
        omarchy-version|omarchy-version-branch|omarchy-version-channel)
            printf '%s\n' "$monarchy_lib_dir/stubs/wrap-version.sh"
            ;;
        omarchy-voxtype-config)
            printf '%s\n' "$monarchy_lib_dir/stubs/wrap-voxtype.sh"
            ;;
        omarchy-snapshot)
            printf '%s\n' "$monarchy_lib_dir/stubs/wrap-snapshot.sh"
            ;;
        *)
            monarchy_die "no wrap stub for $name"
            ;;
    esac
}

# $OMARCHY_PATH/bin is a full mirror of the packaged bin/, with our deny stubs
# and wraps installed over the top of the names we override.
#
# PATH precedence alone would be enough to make an override win: both
# $OMARCHY_PATH/bin and /usr/local/bin precede /usr/bin (and sudo's
# secure_path), so an allowed name needs no entry to resolve. Mirroring is not
# about precedence. It is that $OMARCHY_PATH/bin is an advertised path, not
# just a PATH element: packaged scripts resolve their siblings through it
# absolutely, and so do we.
#
#   omarchy-system-sleep-monitor  -> $OMARCHY_PATH/bin/omarchy-system-sleep-{monitor,lock}
#   omarchy-install-chromium-*    -> $OMARCHY_PATH/bin/omarchy-chromium-*-host
#   monarchy_validate_plugin_dir  -> $MONARCHY_PATH/bin/omarchy-plugin-validate
#   monarchy_install_plugins      -> $MONARCHY_PATH/bin/omarchy-shell
#
# A sparse overlay silently breaks every one of those. It broke the pre-suspend
# lock: omarchy-sleep-lock.service re-execs itself through OMARCHY_PATH, so it
# died on start, restarted forever, and never held the logind delay inhibitor.
# The session suspended unlocked and nothing said so. Mirror the whole tree;
# the cost is 441 symlinks.
#
# install(1) unlinks its destination before writing, so a stub laid over a
# mirrored symlink replaces the link rather than writing through it into the
# pacman-owned /usr/bin. The mirror must therefore come first.
monarchy_rebuild_overlay() {
    local dest="$MONARCHY_PATH/bin"
    local src_bin="$MONARCHY_SRC/bin"
    local stub="$monarchy_lib_dir/stubs/deny.sh"
    local yay="$monarchy_lib_dir/stubs/yay.sh"
    local name parent wrap_stub

    [ -d "$src_bin" ] || monarchy_die "omarchy package bin/ missing at $src_bin"
    [ -f "$stub" ] || monarchy_die "missing $stub"

    monarchy_log "rebuild overlay $dest"
    parent=$(dirname "$dest")
    monarchy_write_to "$parent" mkdir -p "$dest"
    monarchy_write_to "$parent" find "$dest" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    monarchy_write_to "$parent" cp -srT "$src_bin" "$dest"
    for name in "${MONARCHY_BIN_DENY[@]}"; do
        monarchy_write_to "$parent" install -m 755 "$stub" "$dest/$name"
    done
    for name in "${MONARCHY_BIN_WRAP[@]}"; do
        wrap_stub=$(monarchy_wrap_stub_for "$name")
        [ -f "$wrap_stub" ] || monarchy_die "missing $wrap_stub"
        monarchy_write_to "$parent" install -m 755 "$wrap_stub" "$dest/$name"
    done
    monarchy_write_to "$parent" install -m 755 "$yay" "$dest/yay"

    if [ "${MONARCHY_INSTALL_SUDO_STUBS:-1}" = 1 ]; then
        monarchy_sudo mkdir -p /usr/local/bin
        for name in "${MONARCHY_BIN_DENY[@]}"; do
            monarchy_sudo install -m 755 "$stub" "/usr/local/bin/$name"
        done
        for name in "${MONARCHY_BIN_WRAP[@]}"; do
            wrap_stub=$(monarchy_wrap_stub_for "$name")
            monarchy_sudo install -m 755 "$wrap_stub" "/usr/local/bin/$name"
        done
        # A previous apply symlinked every allowed name here, pointing into
        # the clone that no longer exists. Those are dangling now, and a
        # dangling /usr/local/bin entry shadows the real /usr/bin one.
        monarchy_prune_stale_overlay_links
        monarchy_install_update
    fi
}

# Remove /usr/local/bin/omarchy-* symlinks that no longer resolve, and any
# that point somewhere other than a name we still override.
# The glob was omarchy-* and so never matched the bare router, `omarchy`.
# That one link outlived every prune, still pointing into the clone-era
# /usr/local/src/monarchy/omarchy, and it is the worst one to leave behind:
# `omarchy` is the CLI router behind every menu command, it is deliberately
# not overridden, and /usr/local/bin precedes /usr/bin. While the clone is on
# disk the stale router runs in any shell that does not have the overlay
# first; once the clone is removed the link dangles and shadows
# /usr/bin/omarchy, so `omarchy` stops working altogether.
#
# Only symlinks are pruned. Everything this overlay installs into
# /usr/local/bin is a real file, so a symlink there is clone-era by
# definition.
monarchy_prune_stale_overlay_links() {
    local dir="${MONARCHY_LOCAL_BIN:-/usr/local/bin}"
    local f name
    for f in "$dir"/omarchy "$dir"/omarchy-*; do
        [ -L "$f" ] || continue
        name=$(basename "$f")
        if monarchy_in_list "$name" "${MONARCHY_BIN_DENY[@]}" \
            || monarchy_in_list "$name" "${MONARCHY_BIN_WRAP[@]}"; then
            continue
        fi
        monarchy_sudo rm -f "$f"
        monarchy_log "pruned stale overlay link $f"
    done
}

# What the exhaustive allow list was actually protecting against: a binary
# that reconfigures the bootloader, replaces pacman.conf, or drives snapper
# appearing upstream under a name nobody classified.
#
# Matching on content rather than on a list of 438 names is both smaller and
# stronger: it still catches a hazard that arrives under a brand new name, and
# it catches one that gets *renamed*, which an allow list by construction
# cannot. Same shape as monarchy_check_migrations, which has always worked
# this way.
MONARCHY_BIN_HAZARD_RE='limine-entry-tool|limine-mkinitcpio|limine-install|limine-snapper|omarchy-refresh-pacman|use_omarchy_pacman_config|pacman-.*\.conf|zroot/ROOT|/etc/pam\.d/zfs-key|snapper -c|snapper create|snapper --csvout'

monarchy_check_bin_hazards() {
    local src_bin="$MONARCHY_SRC/bin"
    local f name unclassified=0
    [ -d "$src_bin" ] || monarchy_die "omarchy package bin/ missing at $src_bin"
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        if monarchy_in_list "$name" "${MONARCHY_BIN_DENY[@]}" \
            || monarchy_in_list "$name" "${MONARCHY_BIN_WRAP[@]}"; then
            continue
        fi
        echo "bin/$name touches limine, snapper or pacman.conf and is neither denied nor wrapped" >&2
        unclassified=1
    done < <(
        for f in "$src_bin"/*; do
            [ -f "$f" ] || continue
            grep -lE "$MONARCHY_BIN_HAZARD_RE" "$f" >/dev/null 2>&1 && basename "$f"
        done
    )
    [ "$unclassified" = 0 ] \
        || monarchy_die "classify the names above into monarchy/bin.deny or monarchy/bin.wrap"
    return 0
}

# Every name we claim to override must still exist upstream. A wrap or a deny
# stub for a binary that was removed is dead weight that hides a rename.
monarchy_check_overrides_exist() {
    local name missing=0
    for name in "${MONARCHY_BIN_DENY[@]}" "${MONARCHY_BIN_WRAP[@]}"; do
        [ -e "$MONARCHY_SRC/bin/$name" ] && continue
        echo "overridden name no longer in the omarchy package: $name" >&2
        missing=1
    done
    [ "$missing" = 0 ] || monarchy_die "drop or reclassify the names above"
    return 0
}

monarchy_overlay_lock_py() {
    printf '%s\n' "$monarchy_lib_dir/overlay-lock.py"
}

monarchy_overlay_power_py() {
    printf '%s\n' "$monarchy_lib_dir/overlay-power.py"
}

# Turn a prefix symlink-to-dir into a real directory of child symlinks so a
# single file can be replaced without writing into a pacman-owned path.
monarchy_explode_symlink_dir() {
    local dest=$1
    local target name tmp
    [ -L "$dest" ] || return 0
    target=$(readlink -f "$dest")
    [ -d "$target" ] || monarchy_die "expected directory behind $dest"
    tmp=$(mktemp -d)
    for name in "$target"/*; do
        [ -e "$name" ] || continue
        ln -sfn "$name" "$tmp/$(basename "$name")"
    done
    local parent
    parent=$(dirname "$dest")
    monarchy_write_to "$parent" rm -f "$dest"
    monarchy_write_to "$parent" mkdir -p "$dest"
    monarchy_write_to "$parent" mv "$tmp"/* "$dest"/
    # $tmp is ours either way: mktemp -d ran as the calling user, and the
    # move above emptied it. Strict, so a partial move is not swallowed.
    rmdir "$tmp"
}

monarchy_overlay_replace_dir() {
    local dest=$1
    local src_copy=$2
    local parent
    parent=$(dirname "$dest")
    monarchy_write_to "$parent" rm -rf "$dest"
    monarchy_write_to "$parent" mv "$src_copy" "$dest"
}

monarchy_overlay_replace_file() {
    local dest=$1
    local src_copy=$2
    local parent
    parent=$(dirname "$dest")
    monarchy_write_to "$parent" rm -f "$dest"
    monarchy_write_to "$parent" mv "$src_copy" "$dest"
}

monarchy_check_session_lock_overlay() {
    local py lock_dir menu
    py=$(monarchy_overlay_lock_py)
    [ -f "$py" ] || monarchy_die "missing $py"
    lock_dir="$MONARCHY_SRC/shell/plugins/lock"
    menu="$MONARCHY_SRC/default/omarchy/omarchy-menu.jsonc"
    [ -f "$lock_dir/LockView.qml" ] || monarchy_die "omarchy package lock plugin missing"
    [ -f "$menu" ] || monarchy_die "omarchy package omarchy-menu.jsonc missing"
    python3 "$py" check lock "$lock_dir" || monarchy_die "lock QML overlay no longer applies"
    python3 "$py" check menu "$menu" || monarchy_die "menu overlay no longer applies"
}

# Copy-and-patch lock plugin + system menu. Prefix must already be linked.
monarchy_overlay_session_lock() {
    local py lock_src plugins_tmp menu_src menu_dest menu_tmp
    py=$(monarchy_overlay_lock_py)
    lock_src="$MONARCHY_SRC/shell/plugins/lock"
    menu_src="$MONARCHY_SRC/default/omarchy/omarchy-menu.jsonc"
    [ -d "$lock_src" ] || monarchy_die "missing $lock_src"
    [ -f "$menu_src" ] || monarchy_die "missing $menu_src"

    monarchy_explode_symlink_dir "$MONARCHY_PATH/shell"
    # Copy the whole plugins tree. PluginRegistry finds manifests with
    # `find -type f` and does not follow directory symlinks, so exploding
    # plugins/ into child-dir-symlinks hides wallpaper, menu, and the rest.
    # Only lock/ is patched; the copy keeps the package tree untouched.
    plugins_tmp=$(mktemp -d)
    cp -a "$MONARCHY_SRC/shell/plugins"/. "$plugins_tmp"/
    python3 "$py" apply lock "$plugins_tmp/lock" || {
        rm -rf "$plugins_tmp"
        monarchy_die "lock QML overlay failed"
    }
    monarchy_overlay_replace_dir "$MONARCHY_PATH/shell/plugins" "$plugins_tmp"
    MONARCHY_SHELL_DIRTY=1
    monarchy_log "overlaid $MONARCHY_PATH/shell/plugins/lock"

    monarchy_explode_symlink_dir "$MONARCHY_PATH/default"
    monarchy_explode_symlink_dir "$MONARCHY_PATH/default/omarchy"
    menu_dest="$MONARCHY_PATH/default/omarchy/omarchy-menu.jsonc"
    menu_tmp=$(mktemp)
    cp -a "$menu_src" "$menu_tmp"
    python3 "$py" apply menu "$menu_tmp" || {
        rm -f "$menu_tmp"
        monarchy_die "menu overlay failed"
    }
    monarchy_overlay_replace_file "$menu_dest" "$menu_tmp"
    monarchy_log "overlaid $menu_dest"
}

# ---- the running shell --------------------------------------------------
#
# quickshell reads its QML once, at launch, and this session's log says
# "Configuration Loaded" exactly once no matter how long it runs. Rewriting
# $MONARCHY_PATH/shell therefore changes nothing a user can see until the
# shell is restarted -- which is how a corrected power panel sat on disk for a
# day while the bar went on showing the bug it had already fixed.
#
# Stock ends every `omarchy-update` with `omarchy-update-restart`, whose own
# comment gives the reason: "a stale process can lazy-load new files into old
# code". monarchy-update replaces that command, so it inherits the duty.
#
# Set by the two overlay steps that write under shell/, cleared by the
# restart, so --only on an unrelated unit never touches the shell.
MONARCHY_SHELL_DIRTY=0

monarchy_restart_shell() {
    [ "${MONARCHY_SHELL_DIRTY:-0}" = 1 ] || return 0
    MONARCHY_SHELL_DIRTY=0

    command -v omarchy-restart-shell >/dev/null 2>&1 || return 0
    # Only restart a shell that is up. omarchy-restart-shell launches one
    # through Hyprland when it finds none, which is wrong for an install run
    # from a TTY or over ssh: the session that owns the bar is not this one.
    OMARCHY_SHELL_IPC_TIMEOUT=0.5s omarchy-shell shell ping >/dev/null 2>&1 || {
        monarchy_log "no running shell; the overlay applies at next login"
        return 0
    }

    # Best-effort. A locked session refuses by design, and the next login gets
    # a fresh shell regardless -- neither is a reason to fail the apply.
    if omarchy-restart-shell; then
        monarchy_log "restarted the omarchy shell"
    else
        monarchy_log "shell restart declined; the overlay applies at next login"
    fi
    return 0
}

# ---- power panel --------------------------------------------------------
#
# The panel calls UPower's pending-charge a hold at a charge limit without
# checking that the machine has one. An EC that pulse-charges reports "Not
# charging" at any charge level, so the rows read "Charge limit -" and
# "Battery state: Holding" while the pack is filling. See overlay-power.py.

monarchy_check_power_panel_overlay() {
    local py dir
    py=$(monarchy_overlay_power_py)
    [ -f "$py" ] || monarchy_die "missing $py"
    dir="$MONARCHY_SRC/shell/plugins/panels/power"
    [ -f "$dir/Model.js" ] || monarchy_die "omarchy package power panel missing"
    python3 "$py" check "$dir" || monarchy_die "power panel overlay no longer applies"
}

# Runs after monarchy_overlay_session_lock, which recopies shell/plugins from
# the package tree on every apply -- so this patches a fresh copy each time
# rather than re-patching its own output.
monarchy_overlay_power_panel() {
    local py dir tmp name
    py=$(monarchy_overlay_power_py)
    dir="$MONARCHY_PATH/shell/plugins/panels/power"
    [ -d "$dir" ] && [ ! -L "$dir" ] \
        || monarchy_die "$dir is not a real directory; lock overlay must run first"
    tmp=$(mktemp -d)
    for name in Model.js Panel.qml; do
        # A symlink here would mean writing through into the pacman-owned
        # tree, which the next upgrade would revert without saying so.
        [ -f "$dir/$name" ] && [ ! -L "$dir/$name" ] \
            || monarchy_die "$dir/$name is not a real file"
        cp -a "$dir/$name" "$tmp/$name"
    done
    python3 "$py" apply "$tmp" || {
        rm -rf "$tmp"
        monarchy_die "power panel overlay failed"
    }
    for name in Model.js Panel.qml; do
        monarchy_overlay_replace_file "$dir/$name" "$tmp/$name"
    done
    rmdir "$tmp"
    MONARCHY_SHELL_DIRTY=1
    monarchy_log "overlaid $dir"
}

# ---- launcher.hides -----------------------------------------------------
#
# AppLibrary.qml reads exactly one path, $OMARCHY_PATH/default/omarchy/
# launcher.hides, and hides every desktop id in it. There is no user-level
# override and no second file it merges, so putting an application back in
# the launcher means owning that file.
#
# Owning it outright would mean never seeing a row upstream adds. So the
# overlay is subtractive: copy the omarchy list, drop the names in
# launcher.unhides, write the rest. A new upstream row still hides.

monarchy_launcher_hides_src() {
    printf '%s\n' "$MONARCHY_SRC/default/omarchy/launcher.hides"
}

# A row that upstream no longer hides is a no-op, and a no-op row is
# indistinguishable from one that works. Fail instead, the way
# monarchy_check_applications_drop does for a dropped .desktop.
monarchy_check_launcher_unhides() {
    local src name
    src=$(monarchy_launcher_hides_src)
    [ -f "$MONARCHY_MISC/launcher.unhides" ] || monarchy_die "missing launcher.unhides"
    [ -f "$src" ] || monarchy_die "omarchy package launcher.hides missing"
    for name in "${MONARCHY_LAUNCHER_UNHIDE[@]}"; do
        grep -qx -- "$name" "$src" \
            || monarchy_die "launcher.unhides $name is not hidden by the omarchy launcher.hides"
    done
    return 0
}

# Prefix must already be linked.
monarchy_overlay_launcher_hides() {
    local src dest tmp pat
    src=$(monarchy_launcher_hides_src)
    [ -f "$src" ] || monarchy_die "missing $src"

    monarchy_explode_symlink_dir "$MONARCHY_PATH/default"
    monarchy_explode_symlink_dir "$MONARCHY_PATH/default/omarchy"
    dest="$MONARCHY_PATH/default/omarchy/launcher.hides"
    # One pass, with the names as fixed whole-line patterns. -F so a name is
    # never read as a regex, -x so a row is only dropped on an exact match.
    # grep exits 1 when nothing is left to print, which is not an error here.
    tmp=$(mktemp)
    pat=$(mktemp)
    printf '%s\n' "${MONARCHY_LAUNCHER_UNHIDE[@]}" >"$pat"
    grep -vxF -f "$pat" "$src" >"$tmp" || :
    rm -f "$pat"
    monarchy_overlay_replace_file "$dest" "$tmp"
    monarchy_log "overlaid $dest (unhid ${#MONARCHY_LAUNCHER_UNHIDE[@]})"
}

monarchy_install_update() {
    [ -f "$MONARCHY_SETUP" ] || monarchy_die "missing $MONARCHY_SETUP"
    monarchy_sudo ln -sfn "$MONARCHY_SETUP" /usr/local/bin/monarchy-update
    monarchy_sudo rm -f /usr/local/bin/setup-monarchy
    monarchy_log "installed /usr/local/bin/monarchy-update"
}

monarchy_install_user_setup() {
    local src="$monarchy_lib_dir/user-setup.sh"
    [ -f "$src" ] || monarchy_die "missing $src"
    monarchy_sudo install -m 755 "$src" /usr/local/bin/monarchy-user-setup
    monarchy_log "installed /usr/local/bin/monarchy-user-setup"
}

monarchy_install_switch_user() {
    local src="$monarchy_lib_dir/switch-user.sh"
    [ -f "$src" ] || monarchy_die "missing $src"
    monarchy_sudo install -m 755 "$src" /usr/local/bin/monarchy-switch-user
    monarchy_log "installed /usr/local/bin/monarchy-switch-user"
}
