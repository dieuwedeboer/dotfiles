#!/usr/bin/env bash
# limine-mkinitcpio and limine-update rebuild the initramfs and the Limine
# boot entries. ZFSBootMenu boots the kernels and images in /boot directly,
# so the rebuild here is mkinitcpio's own, as on every kernel upgrade.
# Kernel arguments are ignored: every preset is rebuilt.
echo "monarchy: $(basename -- "$0") -> mkinitcpio -P (ZFSBootMenu boots /boot directly)" >&2
if [ "$(id -u)" -eq 0 ]; then
    exec mkinitcpio -P
fi
exec sudo mkinitcpio -P
