# shellcheck shell=bash
# Shared logging, paths, and guards. Sourced from install.sh via lib/monarchy.sh.

monarchy_lib_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# The one voice every line below speaks in. Sourced here rather than only from
# lib/monarchy.sh so a test that pulls in this file alone still formats and
# still collects warnings; ui.sh loads once however many callers ask.
# shellcheck source=ui.sh
source "$monarchy_lib_dir/ui.sh"
MONARCHY_DOTFILES=$(cd "$monarchy_lib_dir/../.." && pwd)
MONARCHY_MISC="${MONARCHY_MISC:-$MONARCHY_DOTFILES/monarchy}"
MONARCHY_SETUP="${MONARCHY_SETUP:-$MONARCHY_DOTFILES/install.sh}"

# The omarchy package owns this tree. Between omarchy and
# omarchy-settings-monarchy it holds exactly the twelve names
# monarchy_link_working_prefix links into the working prefix.
MONARCHY_SRC="${MONARCHY_SRC:-/usr/share/omarchy}"
MONARCHY_PATH="${MONARCHY_PATH:-/usr/local/share/omarchy}"
MONARCHY_CONF="${MONARCHY_CONF:-/etc/omarchy.conf}"
MONARCHY_PIN="${MONARCHY_PIN:-/etc/omarchy.lock}"
MONARCHY_LOG="${MONARCHY_LOG:-/var/log/monarchy-setup.log}"
MONARCHY_ROOT_DATASET="${MONARCHY_ROOT_DATASET:-zpcachyos/ROOT/cos/root}"
MONARCHY_ESP="${MONARCHY_ESP:-/boot/efi}"
MONARCHY_ZBM_DIR="${MONARCHY_ZBM_DIR:-$MONARCHY_ESP/EFI/zbm}"
MONARCHY_REFIND_DIR="${MONARCHY_REFIND_DIR:-$MONARCHY_ESP/EFI/refind}"
MONARCHY_OMARCHY_SERVER="${MONARCHY_OMARCHY_SERVER:-https://pkgs.omarchy.org/stable}"
MONARCHY_ZFS_KEYFILE="${MONARCHY_ZFS_KEYFILE:-/etc/zfs/zroot.key}"
MONARCHY_MKINITCPIO_CONF="${MONARCHY_MKINITCPIO_CONF:-/etc/mkinitcpio.conf}"

# stdout always, plus one durable copy. The file is that copy when it can be
# written; journald is the fallback, so a line is never silently dropped.
#
# It used to be file-or-nothing, and the file lost. /var/log is root-owned and
# an apply runs as the user, so once a root-run had created
# /var/log/monarchy-setup.log every later [ -w ] test failed and the `|| true`
# swallowed it. Nothing was written for weeks and the log looked merely quiet.
#
# The old test was also wrong in its own terms: it accepted a writable *parent*
# for an existing unwritable file, where the append cannot open the file at
# all. The parent only matters when the file is not there yet. And the
# `2>/dev/null` sat on `[`, which writes nothing to stderr, so it hid nothing.
# The durable copy keeps its timestamp; the copy a person reads does not.
# A screenful of ISO-8601 in front of every sentence is what made the three
# voices unreadable, and the file is where you go when you need the clock.
#
# A line that starts `warning:` also lands in the ledger, so the nineteen
# call sites that already wrote that prefix get a summary entry without any
# of them having to call a second function.
monarchy_log() {
    local line
    line="$(date -Iseconds) $*"
    case "$*" in
        warning:*) monarchy_ui_note_warning "$*" ;;
    esac
    if [ "${VERBOSE:-0}" = 1 ]; then
        echo "$line"
    else
        printf '      %s%s%s\n' "${MONARCHY_UI_DIM:-}" "$*" "${MONARCHY_UI_OFF:-}"
    fi
    if [ -w "$MONARCHY_LOG" ] \
        || { [ ! -e "$MONARCHY_LOG" ] && [ -w "$(dirname "$MONARCHY_LOG")" ]; }; then
        printf '%s\n' "$line" >>"$MONARCHY_LOG" 2>/dev/null && return 0
    fi
    if command -v logger >/dev/null 2>&1; then
        logger -t monarchy "$line"
    fi
    return 0
}

# Take ownership of the log once, at the top of an apply, rather than
# elevating on every monarchy_log call. Self-healing: it re-runs whenever the
# file is not writable by whoever is running, so a change of administrator
# fixes itself on the next apply.
#
# touch before chown, never `install /dev/null`, which would truncate the
# history this exists to keep. Failure to elevate is not fatal: monarchy_log
# falls back to journald, and refusing to apply because a log file could not
# be chowned would be the wrong trade.
#
# This only fixes the file for the administrator. A deny stub run by another
# account still cannot write it, and does not need to: deny.sh calls
# `logger -t monarchy` first and unconditionally, so a block is recorded for
# every account no matter who runs it.
monarchy_ensure_log() {
    [ -d "$(dirname "$MONARCHY_LOG")" ] || return 0
    [ ! -w "$MONARCHY_LOG" ] || return 0
    # if/else rather than a && b || c: any one of the three failing has to
    # reach the warning, and the chain form reads as if-then-else when it is
    # not one.
    if ! { monarchy_sudo touch "$MONARCHY_LOG" \
        && monarchy_sudo chown "$(id -u):$(id -g)" "$MONARCHY_LOG" \
        && monarchy_sudo chmod 0644 "$MONARCHY_LOG"; }; then
        monarchy_log "warning: cannot write $MONARCHY_LOG; logging to journald only"
    fi
    return 0
}

monarchy_die() {
    monarchy_log "error: $*"
    echo "monarchy: $*" >&2
    exit 1
}

monarchy_sudo() {
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Run one command against a destination, elevating only when the directory
# that has to be written is not already writable. The overlay is built as the
# user on a temp prefix in tests and as root on a real box; this is the only
# difference between those two paths.
# True when there is a real terminal to ask on. The Omarchy menu wraps
# omarchy-update, which execs monarchy-update with no tty, and chezmoi apply
# prompts whenever a target has been modified. With a tty we can fix things;
# without one we can only report and stop.
monarchy_can_prompt() {
    [ "${MONARCHY_NONINTERACTIVE:-0}" != 1 ] || return 1
    [ -t 0 ] && [ -t 1 ]
}

monarchy_write_to() {
    local dir=$1
    shift
    if [ -w "$dir" ]; then
        "$@"
    else
        monarchy_sudo "$@"
    fi
}

monarchy_load_lock() {
    local lock="$MONARCHY_MISC/omarchy.lock"
    [ -f "$lock" ] || monarchy_die "missing $lock"
    # lock is key=value, not shell. Parse it.
    MONARCHY_LOCK_PACKAGE=$(awk -F= '$1=="package"{print substr($0,index($0,"=")+1)}' "$lock")
    MONARCHY_LOCK_CHANNEL=$(awk -F= '$1=="channel"{print substr($0,index($0,"=")+1)}' "$lock")
    [ -n "$MONARCHY_LOCK_PACKAGE" ] || monarchy_die "omarchy.lock missing package"
    [ -n "$MONARCHY_LOCK_CHANNEL" ] || monarchy_die "omarchy.lock missing channel"
}

monarchy_assert_root_pre_update_snapshot() {
    if ! zfs list -t snapshot -H -o name -d 1 "$MONARCHY_ROOT_DATASET" 2>/dev/null \
        | grep -q '@pre-update-'; then
        monarchy_die "no pre-update snapshot on $MONARCHY_ROOT_DATASET after running the helper"
    fi
}

monarchy_install_snapshot_helper() {
    local helper=/root/.local/bin/zfs-snapshot-pre-update.sh
    local src="$MONARCHY_DOTFILES/chezmoi/dot_local/bin/executable_zfs-snapshot-pre-update"
    [ -f "$src" ] || monarchy_die "missing $src"
    if monarchy_sudo test -x "$helper" && monarchy_sudo grep -q ROOT_DATASET "$helper"; then
        return 0
    fi
    monarchy_log "installing snapshot helper to $helper"
    monarchy_sudo mkdir -p /root/.local/bin
    monarchy_sudo install -m 755 "$src" "$helper"
}

monarchy_snapshot_first() {
    local helper=/root/.local/bin/zfs-snapshot-pre-update.sh
    if [ "${MONARCHY_SNAPSHOT_DONE:-0}" = 1 ]; then
        return 0
    fi
    monarchy_install_snapshot_helper
    if ! monarchy_sudo test -x "$helper"; then
        monarchy_die "missing $helper"
    fi
    monarchy_log "snapshot via $helper"
    monarchy_sudo "$helper"
    monarchy_assert_root_pre_update_snapshot
    MONARCHY_SNAPSHOT_DONE=1
}

monarchy_assert_zfs_layout() {
    local fstype source
    fstype=$(findmnt -n -o FSTYPE / 2>/dev/null || true)
    source=$(findmnt -n -o SOURCE / 2>/dev/null || true)
    [ "$fstype" = "zfs" ] || monarchy_die "root fstype is '$fstype', expected zfs"
    [ "$source" = "$MONARCHY_ROOT_DATASET" ] || monarchy_die "root dataset is '$source', expected $MONARCHY_ROOT_DATASET"
    [ "$source" != "zroot/ROOT/default" ] || monarchy_die "refusing Omarchy-native dataset $source"
}

monarchy_assert_os_release() {
    local id
    id=$(awk -F= '$1=="ID"{gsub(/"/,""); print $2}' /etc/os-release 2>/dev/null || true)
    [ "$id" = "cachyos" ] || monarchy_die "/etc/os-release ID is '$id', expected cachyos"
}

# pacman -Q follows Provides: neovim satisfies nvim, emacs-wayland
# satisfies emacs. Use this when asking "is this name already covered?"
monarchy_pkg_installed() {
    command -v pacman >/dev/null 2>&1 || return 1
    pacman -Q "$1" >/dev/null 2>&1
}

# True only if a package with this exact name is installed. Needed before
# pacman -R: emacs-wayland provides emacs, but -R emacs then says
# "target not found".
monarchy_pkg_exactly() {
    command -v pacman >/dev/null 2>&1 || return 1
    local got
    got=$(pacman -Qq "$1" 2>/dev/null) || return 1
    [ "$got" = "$1" ]
}

monarchy_refuse_bootloader() {
    [ -d "$MONARCHY_REFIND_DIR" ] || monarchy_die "rEFInd missing at $MONARCHY_REFIND_DIR"
    [ -d "$MONARCHY_ZBM_DIR" ] || monarchy_die "ZFSBootMenu missing at $MONARCHY_ZBM_DIR"
    # monarchy-boot-stub *provides* these names, and monarchy_pkg_installed
    # follows Provides, so it would refuse our own stub. Only a package
    # actually called limine* is a problem.
    local p
    for p in limine limine-mkinitcpio-hook limine-snapper-sync; do
        monarchy_pkg_exactly "$p" && monarchy_die "the real $p is installed"
    done
    # The hook that made this a brick risk rather than dead weight: HookDir
    # wins over /usr/share/libalpm/hooks by filename, so this shadows the
    # stock mkinitcpio hook and hands ESP entries to limine-entry-tool.
    [ -f /etc/pacman.d/hooks/90-mkinitcpio-install.hook ] \
        && monarchy_die "limine's mkinitcpio hook is shadowing the stock one"
    return 0
}

monarchy_refuse_snapper() {
    monarchy_pkg_exactly snapper && monarchy_die "the real snapper is installed"
    return 0
}

monarchy_refuse_kernel_swap() {
    if monarchy_pkg_installed linux && ! monarchy_pkg_installed linux-cachyos; then
        monarchy_die "stock linux is installed without linux-cachyos"
    fi
    local pkgbase=""
    if [ -r /usr/lib/modules/"$(uname -r)"/pkgbase ]; then
        pkgbase=$(cat /usr/lib/modules/"$(uname -r)"/pkgbase)
    fi
    case "$pkgbase" in
        linux-cachyos*) ;;
        "") monarchy_log "warning: could not read running pkgbase" ;;
        *) monarchy_die "running pkgbase is '$pkgbase', expected linux-cachyos*" ;;
    esac
    return 0
}

# `omarchy` is installed on purpose now. What must never be installed is a
# settings package that carries upstream's post_install: it does
# `rm -f /etc/os-release` and overwrites nsswitch.conf, faillock.conf,
# plymouthd.conf and /etc/skel/.bashrc on every upgrade.
# omarchy-settings-monarchy provides the name without the scriptlet, and
# monarchy_pkg_exactly does not match a package by what it provides.
monarchy_skip_os_release_clobber() {
    monarchy_assert_os_release
    local p
    for p in omarchy-settings omarchy-settings-dev omarchy-dev; do
        monarchy_pkg_exactly "$p" && monarchy_die "$p is installed; it clobbers /etc/os-release"
    done
    return 0
}

monarchy_skip_autologin() {
    local f
    for f in /etc/plasmalogin.conf /etc/plasmalogin.conf.d/* /etc/sddm.conf.d/*; do
        [ -f "$f" ] || continue
        if grep -Eq '^[[:space:]]*User=[[:space:]]*[^[:space:]]+' "$f"; then
            if grep -Eq '^\[Autologin\]' "$f"; then
                monarchy_die "autologin User= set in $f"
            fi
        fi
    done
    return 0
}

# Keyfile is on disk and listed in mkinitcpio FILES, so the host zfs hook
# will not prompt. Plymouth may sit in front of zfs in that case only.
monarchy_zfs_keyfile_in_initramfs() {
    local conf=${1:-$MONARCHY_MKINITCPIO_CONF}
    local key=${2:-$MONARCHY_ZFS_KEYFILE}
    [ -f "$key" ] || return 1
    [ -f "$conf" ] || return 1
    grep -E '^FILES=' "$conf" | grep -Fq "$key"
}

monarchy_skip_plymouth_zfs() {
    monarchy_pkg_installed plymouth-zfs && monarchy_die "plymouth-zfs is installed"
    if [ -f "$MONARCHY_MKINITCPIO_CONF" ]; then
        if grep -E '^HOOKS=' "$MONARCHY_MKINITCPIO_CONF" | grep -q 'plymouth.*zfs'; then
            monarchy_zfs_keyfile_in_initramfs \
                || monarchy_die "plymouth appears before zfs without $MONARCHY_ZFS_KEYFILE in FILES"
        fi
    fi
    return 0
}

monarchy_refuse_dataset_rename() {
    [ -f /etc/pam.d/zfs-key ] && monarchy_die "/etc/pam.d/zfs-key exists; refusing Omarchy PAM homes"
    return 0
}

# The omarchy package ships this hook, and it is AbortOnFail on every
# upgrade. Monarchy drives updates through monarchy-update, so the hook has
# to be switched off -- an empty file of the same name under HookDir is the
# documented way. Absent upstream hook means nothing to mask.
monarchy_disable_omarchy_update_guard() {
    local hook=/usr/share/libalpm/hooks/00-omarchy-update-guard.hook
    local masked=/etc/pacman.d/hooks/00-omarchy-update-guard.hook
    [ -e "$hook" ] || return 0
    [ -f "$masked" ] || monarchy_die "Omarchy update guard is active; $masked missing"
    [ -s "$masked" ] && monarchy_die "$masked must be empty to mask the update guard"
    return 0
}

monarchy_keep_family_mime() {
    if [ -f /usr/share/applications/mimeapps.list ] && grep -q omarchy /usr/share/applications/mimeapps.list 2>/dev/null; then
        monarchy_die "Omarchy mimeapps landed in /usr/share/applications/mimeapps.list"
    fi
    return 0
}

# --- the seed ledger ------------------------------------------------------
#
# Apply seeds. It may turn on a thing that has never been on; it may not turn
# back on a thing that was on and is now off. See
# docs/adr/0002-apply-seeds-it-does-not-reverse.md.
#
# Most of the user unit needs no ledger for this, because the thing it would
# create is its own marker: monarchy_copy_if_missing looks at the destination,
# and a plugin directory under ~/.config/omarchy/plugins says the plugin has
# already been seeded. Two cases have no such marker, because "off" and "never
# touched" are the same state on disk:
#
#   units  a systemd --user unit reports `disabled` whether the operator
#          disabled it or it has simply never been enabled
#   pkg    an absent package was either never installed or removed on purpose
#
# For those the ledger is the marker. It lives in the user's state directory,
# next to the migration markers Omarchy itself keeps, because which widgets
# and packages this person wants is a fact about this account -- not about
# this repo, which holds only what each role gets.
# The two inventories the ledger governs, named here rather than inline at
# their call sites so the bootstrap below and the seeding itself cannot drift
# into disagreeing about what a seeded box has had done to it.
#
# Units: the Omarchy user units a fresh account gets switched on once. A unit
# upstream adds later is not in this list, gets no bootstrap marker, and so
# still gets its one seeding on the next apply.
MONARCHY_SEEDED_UNITS=(
    bt-agent.service
    omarchy-recover-internal-monitor.service
    omarchy-sleep-lock.service
    omarchy-migrate-notify.service
    omarchy-fcitx5.service
    omarchy-crash-watch.service
)

# Packages installed through omarchy-pkg-add on a fresh account. Leaf
# packages from omarchy-base.packages are not here: those are pacman's, and
# monarchy_install_packages owns that list.
MONARCHY_SEEDED_PKGS=(
    spotify
    signal-desktop
    cursor-bin
    cursor-cli
    omakade
)

monarchy_seed_dir() {
    printf '%s\n' "$HOME/.local/state/monarchy/seeded/${1:?seed kind is required}"
}

monarchy_seeded() {
    local kind=$1 name=$2
    [ -e "$(monarchy_seed_dir "$kind")/$name" ]
}

monarchy_mark_seeded() {
    local kind=$1 name=$2 dir
    dir=$(monarchy_seed_dir "$kind")
    mkdir -p "$dir"
    : >"$dir/$name"
}

# A box that has already been through user setup has had every seeding this
# ledger governs done to it, long before the ledger existed. Without this it
# would get exactly one more unwanted re-impose -- the disabled unit switched
# back on, the removed package reinstalled -- and only then start behaving.
#
# The signal is Omarchy's own first-run marker, which monarchy_mark_first_run_done
# writes at the end of every user apply. Ledger absent and that marker present
# means an established box, so everything is recorded as seeded without
# anything being enabled or installed to record it.
monarchy_seed_ledger_bootstrap() {
    local root="$HOME/.local/state/monarchy/seeded"
    local first_run="$HOME/.local/state/omarchy/first-run-user"
    [ ! -d "$root" ] || return 0
    [ -f "$first_run" ] || return 0
    local name
    for name in "${MONARCHY_SEEDED_UNITS[@]}"; do
        monarchy_mark_seeded units "$name"
    done
    for name in "${MONARCHY_SEEDED_PKGS[@]}"; do
        monarchy_mark_seeded pkg "$name"
    done
    monarchy_log "recorded an established box as already seeded; nothing re-imposed"
}
