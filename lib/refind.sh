#!/usr/bin/env bash
set -e

REFIND_ESP="/boot/efi"
REFIND_EFI_DIR="$REFIND_ESP/EFI/refind"
REFIND_CONF="$REFIND_EFI_DIR/refind.conf"
THEMES_DIR="$REFIND_EFI_DIR/themes"
GLOW_THEME_DIR="$THEMES_DIR/glow"
GLOW_REPO="https://github.com/antsif-a/glow"

if [ ! -d "$REFIND_EFI_DIR" ]; then
    echo "rEFInd not found at $REFIND_EFI_DIR, skipping theme setup"
    exit 0
fi

if [ -d "$GLOW_THEME_DIR" ]; then
    echo "Glow theme already installed at $GLOW_THEME_DIR, skipping"
    exit 0
fi

if [ -f "$REFIND_CONF" ]; then
    if grep -q "^include themes/" "$REFIND_CONF"; then
        echo "Custom theme already configured in $REFIND_CONF, skipping"
        exit 0
    fi
fi

echo "=== Setting up rEFInd glow theme ==="

sudo mkdir -p "$THEMES_DIR"

TMP_DIR=$(mktemp -d)
git clone "$GLOW_REPO" "$TMP_DIR/glow"
sudo cp -r "$TMP_DIR/glow" "$GLOW_THEME_DIR"
rm -rf "$TMP_DIR"

echo "include themes/glow/theme.conf" | sudo tee -a "$REFIND_CONF" > /dev/null

echo "rEFInd glow theme configured successfully"
