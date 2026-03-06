# Dieuwe's Dotfiles

Repeatable system setup for Arch Linux (CachyOS).

## Table of Contents

- [Installation](#installation)
  - [Initial Setup](#initial-setup)
  - [ZFS with Native Encryption](#zfs-with-native-encryption)
  - [Bootloader (rEFInd + ZFSBootMenu)](#bootloader-refind--zfsbootmenu)
  - [Dotfiles](#dotfiles)
- [Legacy Setup](#legacy-setup)

## Installation

### Initial Setup

1. Boot into CachyOS live USB (UEFI mode)
2. Use the GUI installer:
   - Create FAT32 EFI partition (1024MB, mount at `/boot/efi`)
   - Create ZFS root partition with encryption enabled
   - Select KDE Plasma as desktop environment
3. If installer crashes, try: `rm -r ~/.cache` and `sudo calamares`

### ZFS with Native Encryption

After initial install, configure ZFSBootMenu properties:

```bash
sudo zfs get encryption
sudo zfs set org.zfsbootmenu:bootfs="zpcachyos/ROOT/cos/root" zpcachyos
sudo zfs set org.zfsbootmenu:rootprefix="root=ZFS=" zpcachyos
sudo zfs set org.zfsbootmenu:commandline="rw quiet splash" zpcachyos

sudo zfs get mountpoint
sudo zfs mount zpcachyos/ROOT/cos/root
```

### Bootloader (rEFInd + ZFSBootMenu)

```bash
sudo arch-chroot /tmp/calamares-root-XXX
mount /dev/nvme0n1p1 /boot/efi
refind-install
pacman -S zfsbootmenu
generate-zbm --enable
generate-zbm
exit
sudo zpool export zpcachyos
reboot
```

In ZFSBootMenu, press `Ctrl+D` to set pool as default.

### First Boot Setup

1. Enable CachyOS updater from greeter and install the gaming packages.
2. Create user accounts for family members.
3. Run the setup script:

```bash
git clone git@github.com:dieuwedeboer/dotfiles.git
cd dotfiles
./scripts/install.sh
```

The install script will:
- Install chezmoi if not present
- Link dotfiles via chezmoi
- Link emacs config
- Install packages and configure system

### Double Password Solution

Avoid typing the ZFS password twice at boot:

```bash
sudo nano /etc/zfs/zroot.key
# Enter password (plain text, no newline at end!)
sudo chmod 600 /etc/zfs/zroot.key
sudo zfs change-key -o keylocation=file:///etc/zfs/zroot.key -o keyformat=passphrase zpcachyos
echo 'FILES+=(/etc/zfs/zroot.key)' | sudo tee -a /etc/mkinitcpio.conf
sudo mkinitcpio -P
```

---

## Legacy Setup

The `ansible/workstation` directory contains the old Ubuntu setup using Ansible. It is no longer maintained.
