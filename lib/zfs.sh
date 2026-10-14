#!/usr/bin/env bash
set -e
[ "${VERBOSE:-0}" = 1 ] && set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=zbm/boot.sh
source "$SCRIPT_DIR/zbm/boot.sh"
# This runs as a subprocess of install.sh, not sourced into it, so it borrows
# the voice but not the ledger: a change made here is logged, and the parent's
# summary does not see it. Naming the step is household.sh's job, and so is
# anything a person has to be told about.
# shellcheck source=monarchy/common.sh
source "$SCRIPT_DIR/monarchy/common.sh"

monarchy_log "/etc drop-ins"
sudo mkdir -p /etc/sanoid
sudo cp -f "$DOTFILES_DIR/etc/sanoid/sanoid.conf" /etc/sanoid/sanoid.conf
sudo mkdir -p /etc/pacman.d/hooks
# The kernel hooks run this; install it first so no hook lands without it.
sudo install -Dm755 "$DOTFILES_DIR/lib/zfs-kernel.sh" /usr/local/lib/monarchy/zfs-kernel
sudo cp -f "$DOTFILES_DIR"/etc/pacman.d/hooks/*.hook /etc/pacman.d/hooks/

monarchy_log "ARC cap"
# Upstream's default zfs_arc_max is all of RAM. On a desktop the ARC then holds
# the memory while applications are pushed into zram, and every touch of a
# swapped page stalls the session. A quarter of RAM, with a 512 MiB floor:
# 64 GiB gets 16 GiB, 8 GiB gets 2 GiB. It is a fact about this box's RAM, so
# rerunning this after a RAM change recomputes it. tmpfiles writes it at boot
# and here, live, without an initramfs rebuild.
mem_bytes=$(awk '/^MemTotal:/ {print $2 * 1024}' /proc/meminfo)
arc_max=$(( mem_bytes / 4 ))
[ "$arc_max" -lt 536870912 ] && arc_max=536870912
arc_conf=/etc/tmpfiles.d/zfs-arc.conf
printf 'w /sys/module/zfs/parameters/zfs_arc_max - - - - %s\n' "$arc_max" \
    | sudo tee "$arc_conf" >/dev/null
sudo systemd-tmpfiles --create "$arc_conf"

monarchy_log "pre-update snapshot script"
sudo mkdir -p /root/.local/bin
sudo install -m 755 "$DOTFILES_DIR/chezmoi/dot_local/bin/executable_zfs-snapshot-pre-update" /root/.local/bin/zfs-snapshot-pre-update.sh

monarchy_log "sanoid.timer"
sudo systemctl enable --now sanoid.timer

zbm_apply_quiet_boot

