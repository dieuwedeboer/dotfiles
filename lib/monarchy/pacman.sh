# shellcheck shell=bash

# Official Omarchy packaging key. Recv + local-sign before the first
# `pacman -S omarchy-keyring`; SigLevel Required cannot install it otherwise.
MONARCHY_OMARCHY_KEY="${MONARCHY_OMARCHY_KEY:-40DFB630FF42BCFFB047046CF0134EE680CAC571}"
MONARCHY_OMARCHY_KEY_UID="${MONARCHY_OMARCHY_KEY_UID:-Omarchy <pkgs@omarchy.org>}"

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

# pacman -Sy refreshes every DB. Installing leaves after that without
# upgrading already-installed dependents is a partial upgrade: ffmpeg 9
# lands while chromaprint, vlc-plugin-ffmpeg, jellyfin-ffmpeg, gst-libav
# still need the old sonames. CachyOS updater owns -Syu.
monarchy_refuse_partial_upgrade() {
    local pending n
    pending=$(pacman -Qu 2>/dev/null || true)
    [ -n "$pending" ] || return 0
    n=$(printf '%s\n' "$pending" | grep -c .)
    monarchy_die "pacman has $n pending upgrades. Run cachy-update (or sudo pacman -Syu), then re-run install.sh. Installing Omarchy leaves against a refreshed DB pulls new ffmpeg/gstreamer without their dependents"
}

monarchy_omarchy_key_present() {
    monarchy_sudo pacman-key --list-keys "$MONARCHY_OMARCHY_KEY" >/dev/null 2>&1
}

monarchy_omarchy_key_locally_signed() {
    local short
    short=$(printf '%s' "$MONARCHY_OMARCHY_KEY" | tail -c 16)
    monarchy_sudo gpg --homedir /etc/pacman.d/gnupg --no-permission-warning \
        --list-sigs --with-colons "$MONARCHY_OMARCHY_KEY" 2>/dev/null \
        | awk -F: -v s="$short" 'BEGIN { s=toupper(s) }
            $1=="sig" && toupper($5) != s { found=1 }
            END { exit !found }'
}

monarchy_omarchy_key_fpr() {
    monarchy_sudo gpg --homedir /etc/pacman.d/gnupg --no-permission-warning \
        --list-keys --with-colons "$MONARCHY_OMARCHY_KEY" 2>/dev/null \
        | awk -F: '$1=="fpr" { print $10; exit }'
}

monarchy_recv_omarchy_key() {
    local ks
    local -a servers=(
        keys.openpgp.org
        hkps://keys.openpgp.org
        keyserver.ubuntu.com
    )
    for ks in "${servers[@]}"; do
        monarchy_log "pacman-key --recv-keys from $ks"
        if monarchy_sudo pacman-key --recv-keys "$MONARCHY_OMARCHY_KEY" --keyserver "$ks"; then
            return 0
        fi
    done
    monarchy_die "could not download Omarchy packaging key $MONARCHY_OMARCHY_KEY"
}

monarchy_confirm_omarchy_key() {
    local reply
    if [ -n "${MONARCHY_TRUST_OMARCHY_KEY:-}" ]; then
        monarchy_log "MONARCHY_TRUST_OMARCHY_KEY set; signing without prompt"
        return 0
    fi
    echo >&2
    echo "Monarchy needs to locally sign the Omarchy packaging key:" >&2
    echo "  fingerprint: $MONARCHY_OMARCHY_KEY" >&2
    echo "  expected uid: $MONARCHY_OMARCHY_KEY_UID" >&2
    echo "This is a one-time trust. Later install.sh runs skip the prompt." >&2
    echo -n "Locally sign this key? [y/N] " >&2
    if [ -r /dev/tty ]; then
        read -r reply </dev/tty
    elif [ -t 0 ]; then
        read -r reply
    else
        monarchy_die "no TTY to confirm Omarchy key; re-run from a terminal or set MONARCHY_TRUST_OMARCHY_KEY=1"
    fi
    case "$reply" in
        y|Y|yes|YES) return 0 ;;
        *) monarchy_die "declined to trust Omarchy packaging key" ;;
    esac
}

monarchy_trust_omarchy_key() {
    command -v pacman-key >/dev/null 2>&1 || monarchy_die "pacman-key is missing"
    if monarchy_omarchy_key_present && monarchy_omarchy_key_locally_signed; then
        monarchy_log "Omarchy packaging key already locally signed"
        return 0
    fi
    if ! monarchy_omarchy_key_present; then
        monarchy_recv_omarchy_key
    fi
    local fpr
    fpr=$(monarchy_omarchy_key_fpr)
    [ "$fpr" = "$MONARCHY_OMARCHY_KEY" ] \
        || monarchy_die "downloaded key fingerprint '$fpr' != $MONARCHY_OMARCHY_KEY"
    monarchy_sudo pacman-key --finger "$MONARCHY_OMARCHY_KEY" || true
    if monarchy_omarchy_key_locally_signed; then
        monarchy_log "Omarchy packaging key already locally signed"
        return 0
    fi
    monarchy_confirm_omarchy_key
    monarchy_log "pacman-key --lsign-key $MONARCHY_OMARCHY_KEY"
    monarchy_sudo pacman-key --lsign-key "$MONARCHY_OMARCHY_KEY" \
        || monarchy_die "pacman-key --lsign-key failed"
}

monarchy_install_omarchy_keyring() {
    if monarchy_pkg_installed omarchy-keyring; then
        monarchy_log "omarchy-keyring already installed"
    else
        monarchy_log "pacman -Sy then install omarchy-keyring"
        monarchy_sudo pacman -Sy --noconfirm
        monarchy_sudo pacman -S --needed --noconfirm omarchy-keyring \
            || monarchy_die "omarchy-keyring install failed (is [omarchy] in pacman.conf?)"
    fi
    if [ -f /usr/share/pacman/keyrings/omarchy.gpg ]; then
        monarchy_sudo pacman-key --populate omarchy
    fi
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

    # Recv+lsign before the package install: SigLevel Required cannot
    # fetch omarchy-keyring until this key is locally signed.
    monarchy_trust_omarchy_key

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
    monarchy_install_omarchy_keyring
}

monarchy_nvidia_keep_chwd() {
    if [ -x "$MONARCHY_SRC/install/hardware/nvidia.sh" ]; then
        :
    fi
    # Never invoked. Presence of the file is not a failure.
    true
}
