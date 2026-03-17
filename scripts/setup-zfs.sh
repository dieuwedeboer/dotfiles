#!/usr/bin/env bash
set -e
set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

echo "=== Copying misc files to /etc ==="
sudo cp -f "$SCRIPT_DIR/../misc/sanoid.conf" /etc/sanoid/sanoid.conf
sudo mkdir -p /etc/pacman.d/hooks
sudo cp -f "$SCRIPT_DIR/../misc/zfs-snapshot.hook" /etc/pacman.d/hooks/

echo "=== Enabling Sanoid timer ==="
sudo systemctl enable --now sanoid.timer

echo "=== ZFS setup complete ==="
