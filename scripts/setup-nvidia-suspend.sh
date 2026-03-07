#!/usr/bin/env bash
set -e
set -x

if ! command -v nvidia-smi &> /dev/null; then
    echo "nvidia-smi not found, skipping NVIDIA suspend setup"
    exit 0
fi

echo "=== NVIDIA Suspend Fix Setup ==="

echo "Enabling NVIDIA systemd suspend services..."
sudo systemctl enable nvidia-suspend.service
sudo systemctl enable nvidia-hibernate.service
sudo systemctl enable nvidia-resume.service

ZPOOL_NAME="zpcachyos"
KERNEL_PARAMS="nvidia.NVreg_PreserveVideoMemoryAllocations=1"

echo "Checking current ZFSBootMenu kernel command line..."
CURRENT_CMDLINE=$(sudo zfs get -H -o value org.zfsbootmenu:commandline "$ZPOOL_NAME" 2>/dev/null || echo "")

if echo "$CURRENT_CMDLINE" | grep -q "$KERNEL_PARAMS"; then
    echo "Kernel params already present, skipping"
else
    echo "Adding NVIDIA kernel params to ZFSBootMenu..."
    NEW_CMDLINE="$CURRENT_CMDLINE $KERNEL_PARAMS"
    sudo zfs set org.zfsbootmenu:commandline="$NEW_CMDLINE" "$ZPOOL_NAME"
    
    echo "Regenerating ZFSBootMenu..."
    sudo generate-zbm
fi

echo "=== NVIDIA suspend fix complete ==="
echo "Reboot required for changes to take effect"
