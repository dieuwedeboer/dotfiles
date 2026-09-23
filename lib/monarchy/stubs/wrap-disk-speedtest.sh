#!/usr/bin/env bash
# Run the clone disk speed test against a ZFS dataset.
#
# The clone script asks `findmnt -no SOURCE` for the block device behind the
# target directory, then samples that device's counters under /sys. On ZFS
# findmnt answers with the dataset (zpcachyos/ROOT/cos/home), not a /dev node,
# so the script stops at "Cannot find a disk behind ...". Nothing else about it
# is btrfs-only: O_DIRECT is honoured (zfs 2.3+, direct=standard), urandom
# stress data survives lz4, and the /sys counters are the same ones. Only the
# lookup fails.
#
# So put a findmnt shim ahead of the real one on PATH and let it answer that
# one question with the pool's backing device. Every other findmnt call passes
# through. A patched copy of the script would be one more thing to re-check at
# every upstream release; this only has to keep matching how the script asks.
set -euo pipefail

original="${MONARCHY_SRC:-/usr/local/src/monarchy/omarchy}/bin/omarchy-disk-speedtest"

if [ ! -x "$original" ]; then
    echo "monarchy: missing $original" >&2
    exit 1
fi

# The clone's own default, so the shim resolves the directory it will measure.
target_dir="${1:-${XDG_CACHE_HOME:-$HOME/.cache}/omarchy}"

# Anything the script can already resolve on its own is not ours to touch.
if [ "$(findmnt -no FSTYPE --target "$target_dir" 2>/dev/null || true)" != zfs ]; then
    exec "$original" "$@"
fi

pool=$(findmnt -no SOURCE --target "$target_dir")
pool=${pool%%/*}

# Top-level data vdevs only: a leaf under logs/cache/spare carries none of the
# pool's data traffic, and counting it would fail the single-device test below
# for no reason.
mapfile -t leaves < <(zpool list -vHP "$pool" | awk '
    $1 ~ /^(logs|cache|spare|special|dedup)$/ { aside = 1; next }
    !aside && $1 ~ /^\// { print $1 }
')

# One set of counters is all the script reads, so a striped or mirrored pool
# would be measured one disk short. Say that rather than report a low number.
if [ "${#leaves[@]}" -ne 1 ]; then
    echo "monarchy: $pool spans ${#leaves[@]} devices, disk speed test needs one" >&2
    exit 1
fi

dev=$(readlink -f "${leaves[0]}")

shim=$(mktemp -d)
trap 'rm -rf "$shim"' EXIT

cat >"$shim/findmnt" <<SHIM
#!/usr/bin/env bash
# SOURCE for a --target is the dataset lookup. Answer it with the disk.
want= tgt=
for arg in "\$@"; do
    [ "\$arg" = SOURCE ] && want=1
    [ "\$arg" = --target ] && tgt=1
done
if [ -n "\$want" ] && [ -n "\$tgt" ]; then
    printf '%s\n' "$dev"
    exit 0
fi
exec /usr/bin/findmnt "\$@"
SHIM
chmod 755 "$shim/findmnt"

PATH="$shim:$PATH" "$original" "$@"
