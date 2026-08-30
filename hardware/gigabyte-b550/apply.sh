#!/usr/bin/env bash
# Gigabyte B550 GAMING X V2 (kingfisher desktop).
# it87 for the ITE IT8689E SuperIO, OpenRGB, CoolerControl.
set -e
[ "${VERBOSE:-0}" = 1 ] && set -x

HW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=detect.sh
source "$HW_DIR/detect.sh"

if ! gigabyte_b550_detected; then
    echo "  not a Gigabyte B550 GAMING X, skipping"
    exit 0
fi

echo "  DMI vendor: $(gigabyte_b550_dmi sys_vendor)"
echo "  DMI board:  $(gigabyte_b550_dmi board_name)"

echo "Installing openrgb..."
if ! pacman -Q openrgb &> /dev/null; then
    sudo pacman -S --noconfirm openrgb
else
    echo "  openrgb already installed"
fi

echo "Installing coolercontrol..."
if ! pacman -Q coolercontrol &> /dev/null; then
    sudo pacman -S --noconfirm coolercontrol
else
    echo "  coolercontrol already installed"
fi
if command -v systemctl &> /dev/null; then
    if ! systemctl is-enabled coolercontrold &> /dev/null; then
        sudo systemctl enable coolercontrold
        echo "  enabled coolercontrold"
    else
        echo "  coolercontrold already enabled"
    fi
fi

# Mainline it87 does not know this board's ITE IT8689E SuperIO chip, so fan RPM
# and temperature readings never reach userspace. Out-of-tree it87-dkms-git adds
# support, and ignore_resource_conflict=1 relaxes ACPI resource enforcement so
# the driver can probe the chip's I/O ports.
#
# Fan speed control is intentionally left to the BIOS. The IT8689E's pwmN_enable=2
# (thermal-cruise) mode runs the BIOS-programmed fan curves in hardware — flipping
# channels to enable=1 (manual) would freeze fans at a fixed PWM value and silently
# disable those curves. CPU_FAN and the pump are EC-managed regardless of the
# SuperIO chip, so no OS-side control is possible or desirable for them.

echo "Installing it87-dkms-git (SuperIO driver for ITE IT8689E)..."
if ! pacman -Q it87-dkms-git &> /dev/null; then
    if command -v paru &> /dev/null; then
        paru -S --noconfirm --needed it87-dkms-git
    else
        echo "  paru not found, skipping it87-dkms-git" >&2
        exit 1
    fi
else
    echo "  it87-dkms-git already installed"
fi

echo "Configuring it87 modprobe options..."
IT87_MODPROBE="/etc/modprobe.d/it87.conf"
IT87_OPTIONS="options it87 ignore_resource_conflict=1"
if [ ! -f "$IT87_MODPROBE" ] || ! sudo grep -q "^$IT87_OPTIONS" "$IT87_MODPROBE" 2>/dev/null; then
    echo "$IT87_OPTIONS" | sudo tee "$IT87_MODPROBE" > /dev/null
    echo "  wrote $IT87_MODPROBE"
else
    echo "  $IT87_MODPROBE already configured"
fi

echo "Ensuring it87 is loaded on boot..."
IT87_MODULES_LOAD="/etc/modules-load.d/it87.conf"
if [ ! -f "$IT87_MODULES_LOAD" ] || ! sudo grep -qx "it87" "$IT87_MODULES_LOAD" 2>/dev/null; then
    echo "it87" | sudo tee "$IT87_MODULES_LOAD" > /dev/null
    echo "  wrote $IT87_MODULES_LOAD"
else
    echo "  $IT87_MODULES_LOAD already lists it87"
fi
