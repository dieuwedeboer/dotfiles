#!/usr/bin/env bash
# Overlay wrapper for omarchy-snapshot.
#
# Stock omarchy-snapshot is snapper + limine-snapper-restore. On this host
# snapper is provided by monarchy-boot-stub and ships no binary, so the stock
# script would exit 127 ("no snapshot tool") and the System > Snapshot menu
# item would silently do nothing.
#
# This is the one script berenddeboer/omarchy actually improved for ZFS. Doing
# it here means the improvement survives without tracking the fork.
set -euo pipefail

helper=${MONARCHY_SNAPSHOT_HELPER:-/root/.local/bin/zfs-snapshot-pre-update.sh}
command=${1:-}

case "$command" in
    create)
        if ! sudo test -x "$helper"; then
            echo "monarchy: missing $helper; run monarchy-update once" >&2
            exit 1
        fi
        echo -e "\e[32mCreate system snapshot\e[0m"
        sudo "$helper"
        echo "Snapshots can be selected in ZFSBootMenu at boot."
        ;;
    restore)
        # limine-snapper-restore rewrites ESP boot entries. Rolling back a ZFS
        # root is a boot-time operation, not something to do from inside the
        # running session.
        echo "Restore is a boot-time operation on ZFS." >&2
        echo "Reboot, pick the dataset at the ZFSBootMenu prompt, then promote it." >&2
        exit 2
        ;;
    *)
        echo "Usage: omarchy-snapshot <create|restore>" >&2
        exit 1
        ;;
esac
