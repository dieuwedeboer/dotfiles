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
GLOW_THEME_CONF="$GLOW_THEME_DIR/theme.conf"
GLOW_REPO="https://github.com/antsif-a/glow"

# memtest86+-efi installs to /boot, which is on ZFS where the firmware cannot
# read it. rEFInd finds memtest86.efi in EFI/tools on its own.
MEMTEST_SRC="/boot/memtest86+/memtest86x64.efi"
MEMTEST_DEST="$REFIND_ESP/EFI/tools/memtest86.efi"

refind_install_theme() {
    if [ -d "$GLOW_THEME_DIR" ]; then
        monarchy_log "glow theme already installed at $GLOW_THEME_DIR"
        return
    fi

    if [ -f "$REFIND_CONF" ] && grep -q "^include themes/" "$REFIND_CONF"; then
        monarchy_log "a custom theme is already configured in $REFIND_CONF"
        return
    fi

    sudo mkdir -p "$THEMES_DIR"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    git clone "$GLOW_REPO" "$tmp_dir/glow"
    sudo cp -r "$tmp_dir/glow" "$GLOW_THEME_DIR"
    rm -rf "$tmp_dir"

    echo "include themes/glow/theme.conf" | sudo tee -a "$REFIND_CONF" > /dev/null

    monarchy_log "configured the rEFInd glow theme"
}

# Glow's showtools list leaves memtest out, and on rEFInd 0.14.2 an explicit
# showtools draws the tools row twice. rEFInd's default list has neither
# problem: it shows memtest when the binary is there and skips absent tools.
refind_default_tools() {
    [ -f "$GLOW_THEME_CONF" ] || return 0
    if grep -q '^showtools' "$GLOW_THEME_CONF"; then
        sudo sed -i 's/^showtools/# showtools/' "$GLOW_THEME_CONF"
        monarchy_log "glow theme now uses rEFInd's default tools row"
    fi
}

refind_install_memtest() {
    if [ ! -f "$MEMTEST_SRC" ]; then
        monarchy_warn "no $MEMTEST_SRC; memtest86+-efi is not installed, so rEFInd has no memtest"
        return
    fi
    if monarchy_install_if_changed 0755 "$MEMTEST_SRC" "$MEMTEST_DEST"; then
        monarchy_log "copied memtest86+ to $MEMTEST_DEST"
    else
        monarchy_log "memtest86+ already current at $MEMTEST_DEST"
    fi
}

if [ ! -d "$REFIND_EFI_DIR" ]; then
    monarchy_log "no rEFInd at $REFIND_EFI_DIR; theme setup skipped"
    exit 0
fi

refind_install_theme
refind_default_tools
refind_install_memtest
