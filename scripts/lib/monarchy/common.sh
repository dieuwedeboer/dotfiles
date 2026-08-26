# shellcheck shell=bash
# Shared logging, paths, and guards. Sourced from setup-monarchy.sh.

monarchy_lib_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MONARCHY_DOTFILES=$(cd "$monarchy_lib_dir/../../.." && pwd)
MONARCHY_MISC="${MONARCHY_MISC:-$MONARCHY_DOTFILES/misc/monarchy}"
MONARCHY_SETUP="${MONARCHY_SETUP:-$MONARCHY_DOTFILES/scripts/setup-monarchy.sh}"

MONARCHY_SRC="${MONARCHY_SRC:-/usr/local/src/monarchy/omarchy}"
MONARCHY_PATH="${MONARCHY_PATH:-/usr/local/share/omarchy}"
MONARCHY_CONF="${MONARCHY_CONF:-/etc/omarchy.conf}"
MONARCHY_LOG="${MONARCHY_LOG:-/var/log/monarchy-setup.log}"
MONARCHY_ROOT_DATASET="${MONARCHY_ROOT_DATASET:-zpcachyos/ROOT/cos/root}"
MONARCHY_ESP="${MONARCHY_ESP:-/boot/efi}"
MONARCHY_ZBM_DIR="${MONARCHY_ZBM_DIR:-$MONARCHY_ESP/EFI/zbm}"
MONARCHY_REFIND_DIR="${MONARCHY_REFIND_DIR:-$MONARCHY_ESP/EFI/refind}"
MONARCHY_CACHE="${MONARCHY_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/monarchy/omarchy}"
MONARCHY_BLOCKED_HOSTS="${MONARCHY_BLOCKED_HOSTS:-kingfisher bonw9}"

monarchy_log() {
    local line
    line="$(date -Iseconds) $*"
    echo "$line"
    if [ -w "$MONARCHY_LOG" ] || [ -w "$(dirname "$MONARCHY_LOG")" ] 2>/dev/null; then
        printf '%s\n' "$line" >>"$MONARCHY_LOG" 2>/dev/null || true
    fi
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

monarchy_load_lock() {
    local lock="$MONARCHY_MISC/omarchy.lock"
    [ -f "$lock" ] || monarchy_die "missing $lock"
    # shellcheck disable=SC1090
    set -a
    # lock is key=value, not shell. Parse it.
    set +a
    MONARCHY_LOCK_REMOTE=$(awk -F= '$1=="remote"{print substr($0,index($0,"=")+1)}' "$lock")
    MONARCHY_LOCK_BRANCH=$(awk -F= '$1=="branch"{print substr($0,index($0,"=")+1)}' "$lock")
    MONARCHY_LOCK_COMMIT=$(awk -F= '$1=="commit"{print substr($0,index($0,"=")+1)}' "$lock")
    MONARCHY_LOCK_HYPRLAND=$(awk -F= '$1=="hyprland"{print substr($0,index($0,"=")+1)}' "$lock")
    MONARCHY_LOCK_QUICKSHELL=$(awk -F= '$1=="quickshell"{print substr($0,index($0,"=")+1)}' "$lock")
    [ -n "$MONARCHY_LOCK_REMOTE" ] || monarchy_die "omarchy.lock missing remote"
    [ -n "$MONARCHY_LOCK_BRANCH" ] || monarchy_die "omarchy.lock missing branch"
    [ -n "$MONARCHY_LOCK_COMMIT" ] || monarchy_die "omarchy.lock missing commit"
}

monarchy_refuse_daily_driver() {
    local host
    host=$(hostname)
    local blocked
    for blocked in $MONARCHY_BLOCKED_HOSTS; do
        if [ "$host" = "$blocked" ] && [ -z "${MONARCHY_ALLOW_HOST:-}" ]; then
            monarchy_die "refusing to apply on $host (daily driver). First bring-up is an older laptop. Set MONARCHY_ALLOW_HOST=1 to override."
        fi
    done
}

monarchy_snapshot_first() {
    local helper=/root/.local/bin/zfs-snapshot-pre-update.sh
    if [ ! -x "$helper" ]; then
        monarchy_die "missing $helper; run scripts/setup-zfs.sh first"
    fi
    monarchy_log "snapshot via $helper"
    monarchy_sudo "$helper"
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

monarchy_pkg_installed() {
    command -v pacman >/dev/null 2>&1 || return 1
    pacman -Q "$1" >/dev/null 2>&1
}

monarchy_keep_plasmalogin() {
    if monarchy_pkg_installed sddm; then
        monarchy_die "sddm is installed; packages.deny forbids a second display manager"
    fi
    if command -v systemctl >/dev/null 2>&1; then
        systemctl is-enabled plasmalogin >/dev/null 2>&1 \
            || monarchy_die "plasmalogin is not enabled"
    fi
    return 0
}

monarchy_refuse_bootloader() {
    [ -d "$MONARCHY_REFIND_DIR" ] || monarchy_die "rEFInd missing at $MONARCHY_REFIND_DIR"
    [ -d "$MONARCHY_ZBM_DIR" ] || monarchy_die "ZFSBootMenu missing at $MONARCHY_ZBM_DIR"
    if monarchy_pkg_installed limine \
        || monarchy_pkg_installed limine-mkinitcpio-hook \
        || monarchy_pkg_installed limine-snapper-sync; then
        monarchy_die "limine packages are installed"
    fi
    return 0
}

monarchy_refuse_snapper() {
    if monarchy_pkg_installed snapper; then
        monarchy_die "snapper is installed"
    fi
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

monarchy_skip_os_release_clobber() {
    monarchy_assert_os_release
    monarchy_pkg_installed omarchy-settings && monarchy_die "omarchy-settings is installed"
    monarchy_pkg_installed omarchy-settings-dev && monarchy_die "omarchy-settings-dev is installed"
    monarchy_pkg_installed omarchy && monarchy_die "omarchy metapackage is installed"
    monarchy_pkg_installed omarchy-dev && monarchy_die "omarchy-dev is installed"
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

monarchy_skip_plymouth_zfs() {
    monarchy_pkg_installed plymouth-zfs && monarchy_die "plymouth-zfs is installed"
    if [ -f /etc/mkinitcpio.conf ]; then
        if grep -E '^HOOKS=' /etc/mkinitcpio.conf | grep -q 'plymouth.*zfs'; then
            monarchy_die "plymouth appears before zfs in mkinitcpio HOOKS"
        fi
    fi
    return 0
}

monarchy_refuse_dataset_rename() {
    [ -f /etc/pam.d/zfs-key ] && monarchy_die "/etc/pam.d/zfs-key exists; refusing Omarchy PAM homes"
    return 0
}

monarchy_disable_omarchy_update_guard() {
    local hook=/usr/share/libalpm/hooks/00-omarchy-update-guard.hook
    [ -e "$hook" ] && monarchy_die "Omarchy ALPM update guard is present at $hook"
    return 0
}

monarchy_keep_family_mime() {
    if [ -f /usr/share/applications/mimeapps.list ] && grep -q omarchy /usr/share/applications/mimeapps.list 2>/dev/null; then
        monarchy_die "Omarchy mimeapps landed in /usr/share/applications/mimeapps.list"
    fi
    return 0
}
