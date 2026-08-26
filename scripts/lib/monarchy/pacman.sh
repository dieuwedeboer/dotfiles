# shellcheck shell=bash

monarchy_preserve_pacman_conf() {
    local conf=${MONARCHY_PACMAN_CONF:-/etc/pacman.conf}
    [ -f "$conf" ] || monarchy_die "missing $conf"
    grep -q '^\[cachyos\]' "$conf" || monarchy_die "$conf has no [cachyos] section"
    grep -q '^\[cachyos-v3\]' "$conf" || monarchy_die "$conf has no [cachyos-v3] section"

    local omarchy_line cachy_line
    omarchy_line=$(grep -n '^\[omarchy\]' "$conf" | head -1 | cut -d: -f1)
    cachy_line=$(grep -n '^\[cachyos\]' "$conf" | head -1 | cut -d: -f1)
    if [ -n "$omarchy_line" ] && [ -n "$cachy_line" ] && [ "$omarchy_line" -lt "$cachy_line" ]; then
        monarchy_die "[omarchy] appears before [cachyos] in $conf"
    fi

    local inc
    for inc in /etc/pacman.d/cachyos-v3-mirrorlist /etc/pacman.d/cachyos-mirrorlist /etc/pacman.d/mirrorlist; do
        [ -f "$inc" ] || monarchy_die "missing mirrorlist $inc"
        grep -Fq "$inc" "$conf" || monarchy_die "$conf does not Include $inc"
    done
    return 0
}

monarchy_refuse_archzfs() {
    local conf=${MONARCHY_PACMAN_CONF:-/etc/pacman.conf}
    grep -q '^\[archzfs\]' "$conf" && monarchy_die "[archzfs] is present in $conf"
    return 0
}

monarchy_refuse_omarchy_zfs_repo() {
    local conf=${MONARCHY_PACMAN_CONF:-/etc/pacman.conf}
    grep -q '^\[omarchy-zfs\]' "$conf" && monarchy_die "[omarchy-zfs] is present in $conf"
    return 0
}

monarchy_add_omarchy_repo() {
    local conf=${MONARCHY_PACMAN_CONF:-/etc/pacman.conf}
    local bak=/etc/pacman.conf.monarchy.bak
    local begin='# BEGIN monarchy-omarchy'
    local end='# END monarchy-omarchy'
    local block

    monarchy_preserve_pacman_conf
    monarchy_refuse_archzfs
    monarchy_refuse_omarchy_zfs_repo

    if [ ! -f "$bak" ]; then
        monarchy_sudo cp -a "$conf" "$bak"
    fi

    if command -v pacman >/dev/null 2>&1 && ! pacman -Q omarchy-keyring >/dev/null 2>&1; then
        monarchy_log "install omarchy-keyring"
        monarchy_sudo pacman -S --needed --noconfirm omarchy-keyring
    fi

    block=$(
        cat <<EOF
$begin
[omarchy]
SigLevel = Required DatabaseOptional
Server = https://pkgs.omarchy.org/stable/\$arch
$end
EOF
    )

    local tmp
    tmp=$(mktemp)
    if grep -q "^$begin\$" "$conf"; then
        awk -v b="$begin" -v e="$end" '
            $0==b { skip=1; next }
            $0==e { skip=0; next }
            !skip { print }
        ' "$conf" >"$tmp"
    else
        cp "$conf" "$tmp"
    fi
    printf '\n%s\n' "$block" >>"$tmp"
    monarchy_sudo install -m 644 "$tmp" "$conf"
    rm -f "$tmp"
    monarchy_preserve_pacman_conf
    monarchy_log "appended [omarchy] marker block"
}

monarchy_nvidia_keep_chwd() {
    if [ -x "$MONARCHY_SRC/install/hardware/nvidia.sh" ]; then
        :
    fi
    # Never invoked. Presence of the file is not a failure.
    true
}
