#!/usr/bin/env bash
# limine-snapper-sync adds snapshots to the Limine menu. ZFSBootMenu lists
# ZFS snapshots itself, so there is nothing to sync.
echo "monarchy: $(basename -- "$0") has nothing to do; ZFSBootMenu lists snapshots itself" >&2
exit 0
