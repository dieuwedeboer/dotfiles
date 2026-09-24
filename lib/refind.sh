#!/usr/bin/env bash
set -e

# A subprocess of install.sh, so it borrows the voice but not the ledger.
# shellcheck source=monarchy/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/monarchy/common.sh"

REFIND_ESP="/boot/efi"
REFIND_EFI_DIR="$REFIND_ESP/EFI/refind"
REFIND_CONF="$REFIND_EFI_DIR/refind.conf"
THEMES_DIR="$REFIND_EFI_DIR/themes"
GLOW_THEME_DIR="$THEMES_DIR/glow"
GLOW_REPO="https://github.com/antsif-a/glow"

if [ ! -d "$REFIND_EFI_DIR" ]; then
    monarchy_log "no rEFInd at $REFIND_EFI_DIR; theme setup skipped"
    exit 0
fi

if [ -d "$GLOW_THEME_DIR" ]; then
    monarchy_log "glow theme already installed at $GLOW_THEME_DIR"
    exit 0
fi

if [ -f "$REFIND_CONF" ]; then
    if grep -q "^include themes/" "$REFIND_CONF"; then
        monarchy_log "a custom theme is already configured in $REFIND_CONF"
        exit 0
    fi
fi

sudo mkdir -p "$THEMES_DIR"

TMP_DIR=$(mktemp -d)
git clone "$GLOW_REPO" "$TMP_DIR/glow"
sudo cp -r "$TMP_DIR/glow" "$GLOW_THEME_DIR"
rm -rf "$TMP_DIR"

echo "include themes/glow/theme.conf" | sudo tee -a "$REFIND_CONF" > /dev/null

monarchy_log "configured the rEFInd glow theme"
