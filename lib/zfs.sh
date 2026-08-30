#!/usr/bin/env bash
set -e
[ "${VERBOSE:-0}" = 1 ] && set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=zbm/boot.sh
source "$SCRIPT_DIR/zbm/boot.sh"

echo "=== ZFS Setup Script ==="

echo "=== Installing ksystemstats_scripts plugin ==="
if [ ! -f /usr/lib/qt6/plugins/ksystemstats/ksystemstats_plugin_scripts.so ]; then
    tmpdir=$(mktemp -d)
    git clone --depth 1 https://github.com/KerJoe/ksystemstats_scripts.git "$tmpdir"
    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX:PATH=/usr -B "$tmpdir/build" "$tmpdir"
    cmake --build "$tmpdir/build"
    sudo cmake --install "$tmpdir/build"
    rm -rf "$tmpdir"
fi

echo "=== Applying chezmoi to ensure zpool sensor exists ==="
chezmoi apply

echo "=== Restarting ksystemstats to load new sensors ==="
systemctl restart --user plasma-ksystemstats.service

echo "=== Copying /etc drop-ins ==="
sudo mkdir -p /etc/sanoid
sudo cp -f "$DOTFILES_DIR/etc/sanoid/sanoid.conf" /etc/sanoid/sanoid.conf
sudo mkdir -p /etc/pacman.d/hooks
sudo cp -f "$DOTFILES_DIR/etc/pacman.d/hooks/zfs-snapshot.hook" /etc/pacman.d/hooks/

echo "=== Installing pre-update snapshot script ==="
sudo mkdir -p /root/.local/bin
sudo install -m 755 "$DOTFILES_DIR/chezmoi/dot_local/bin/executable_zfs-snapshot-pre-update" /root/.local/bin/zfs-snapshot-pre-update.sh

echo "=== Enabling Sanoid timer ==="
sudo systemctl enable --now sanoid.timer

zbm_apply_quiet_boot

echo "=== ZFS setup complete ==="
