#!/bin/bash
# Install script for icograph Plasma system monitor display style
# This creates a symlink from the dotfiles to the local ksysguard sensor faces directory

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICOGRAPH_DIR="$SCRIPT_DIR"
TARGET_DIR="$HOME/.local/share/ksysguard/sensorfaces/org.kde.plasma.systemmonitor.icograph"

echo "Installing icograph sensor face..."

# Create parent directory if it doesn't exist
mkdir -p "$(dirname "$TARGET_DIR")"

# Remove existing symlink or directory if it exists
if [ -L "$TARGET_DIR" ]; then
    echo "Removing existing symlink..."
    rm "$TARGET_DIR"
elif [ -d "$TARGET_DIR" ]; then
    echo "Removing existing directory..."
    rm -rf "$TARGET_DIR"
fi

# Create symlink
ln -s "$ICOGRAPH_DIR" "$TARGET_DIR"

echo "Successfully installed icograph to: $TARGET_DIR"
echo ""
echo "To use the new display style:"
echo "1. Add or configure a System Monitor widget in Plasma"
echo "2. In the widget settings, select 'IcoGraph' as the display style"
echo ""
echo "To uninstall, run: rm $TARGET_DIR"
