#!/usr/bin/env bash
set -e
[ "${VERBOSE:-0}" = 1 ] && set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=zbm/boot.sh
source "$SCRIPT_DIR/zbm/boot.sh"
# This runs as a subprocess of install.sh, not sourced into it, so it borrows
# the voice but not the ledger: a change made here is logged, and the parent's
# summary does not see it. Naming the step is household.sh's job.
# shellcheck source=monarchy/common.sh
source "$SCRIPT_DIR/monarchy/common.sh"

monarchy_log "ksystemstats_scripts plugin"
if [ ! -f /usr/lib/qt6/plugins/ksystemstats/ksystemstats_plugin_scripts.so ]; then
    tmpdir=$(mktemp -d)
    git clone --depth 1 https://github.com/KerJoe/ksystemstats_scripts.git "$tmpdir"
    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX:PATH=/usr -B "$tmpdir/build" "$tmpdir"
    cmake --build "$tmpdir/build"
    sudo cmake --install "$tmpdir/build"
    rm -rf "$tmpdir"
fi

# The zpool sensor is chezmoi's, and household_chezmoi applied it several
# steps before this script runs. This used to run `chezmoi apply` a second
# time for it, which doubled the slowest step of an update and gave a
# menu-driven run a second chance to hang on a prompt. Verify instead.
ZPOOL_SENSOR="$HOME/.local/share/ksystemstats-scripts/ZFS"
if [ ! -e "$ZPOOL_SENSOR" ]; then
    monarchy_log "warning: no $ZPOOL_SENSOR; the zpool sensor is chezmoi's. Run: chezmoi apply"
elif [ "${MONARCHY_CHEZMOI_APPLIED:-0}" = 1 ]; then
    # Only when chezmoi actually wrote something. Restarting a Plasma service
    # on every update, to load a sensor that has not changed since the last
    # one, is a blink in the bar for nothing.
    monarchy_log "restarting ksystemstats to load the zpool sensor"
    systemctl restart --user plasma-ksystemstats.service \
        || monarchy_log "warning: could not restart plasma-ksystemstats.service"
fi

monarchy_log "/etc drop-ins"
sudo mkdir -p /etc/sanoid
sudo cp -f "$DOTFILES_DIR/etc/sanoid/sanoid.conf" /etc/sanoid/sanoid.conf
sudo mkdir -p /etc/pacman.d/hooks
sudo cp -f "$DOTFILES_DIR/etc/pacman.d/hooks/zfs-snapshot.hook" /etc/pacman.d/hooks/

monarchy_log "pre-update snapshot script"
sudo mkdir -p /root/.local/bin
sudo install -m 755 "$DOTFILES_DIR/chezmoi/dot_local/bin/executable_zfs-snapshot-pre-update" /root/.local/bin/zfs-snapshot-pre-update.sh

monarchy_log "sanoid.timer"
sudo systemctl enable --now sanoid.timer

zbm_apply_quiet_boot

