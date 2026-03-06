#!/usr/bin/env bash
set -e
set -x

echo "=== Kingfisher-specific Setup ==="

echo "Installing openrgb..."
if ! pacman -Q openrgb &> /dev/null; then
    sudo pacman -S --noconfirm openrgb
else
    echo "openrgb already installed"
fi

echo "Disabling firewall (rules preserved)..."
if command -v ufw &> /dev/null; then
    sudo ufw disable
fi

SERVICE_FILE="/etc/systemd/system/disable-gpp0-wakeup.service"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

if [ ! -f "$SERVICE_FILE" ]; then
    echo "Installing disable-gpp0-wakeup.service..."
    sudo cp "$DOTFILES_DIR/misc/disable-gpp0-wakeup.service" "$SERVICE_FILE"
    sudo systemctl daemon-reload
    sudo systemctl enable disable-gpp0-wakeup.service
else
    echo "disable-gpp0-wakeup.service already exists"
fi

echo "=== Kingfisher setup complete ==="
