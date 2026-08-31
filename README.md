# Monarchy - a man's $HOME is his castle

Repeatable system setup for Arch Linux (CachyOS with ZFS) running Omarchy.

My setup is build with a few intentional principles.

1. Multi-user setup with multiple Wayland desktop environments.
2. Full native ZFS encryption of home, root, and boot.
3. An opinionated and beautiful experience for all users out of the box.

This requires a kernel with zfs modules: linux-cachoys-zfs

This setup requires a bootloader that can decrypt a zpool: zfsbootmenu

## Table of Contents

- [Installation](#installation)
  - [Initial Setup](#initial-setup)
  - [ZFS with Native Encryption](#zfs-with-native-encryption)
  - [Bootloader (rEFInd + ZFSBootMenu)](#bootloader-refind--zfsbootmenu)
  - [Dotfiles](#dotfiles)
  - [Agent Configuration](#agent-configuration)
  - [Monarchy (Omarchy session)](#monarchy-omarchy-session)
- [Legacy Setup](#legacy-setup)

## Installation

### Initial Setup

It is possible to build a system using stock Arch, ArchZFS, and a
custom ISO, but CachyOS wraps all that for you and ships many other
gaming packages and little niceties that give new users a sane experience.

1. Boot into a CachyOS Live USB (UEFI mode)
2. Use the GUI installer:
   - Create FAT32 EFI partition (1024MB, mount at `/boot/efi`)
   - Create ZFS root partition with encryption enabled
   - Select KDE Plasma* as desktop environment
3. Run some manual commands below
   - Clone this repo on the USB home

*Select hyprland if no family members want a Classic Windows experience.

### ZFS with Native Encryption

After initial install, configure ZFSBootMenu properties:

```bash
sudo zfs get encryption
sudo zfs set org.zfsbootmenu:bootfs="zpcachyos/ROOT/cos/root" zpcachyos
sudo zfs set org.zfsbootmenu:rootprefix="root=ZFS=" zpcachyos
sudo zfs set org.zfsbootmenu:commandline="rw quiet splash loglevel=0 systemd.show_status=false rd.udev.log_level=0 vt.global_cursor_default=0" zpcachyos
# Check mountpoint first, likly set to /tmp after a fresh install
sudo zfs get mountpoint
sudo zfs mount zpcachyos/ROOT/cos/root
```

### Bootloader chain (rEFInd + ZFSBootMenu)

Why run two bootloaders? You don't have to, skip refind and simply set
up zfsbootmenu if you like. I run this bootloader chain because I
sometimes dualboot and refind has a nice theme that's easier for
others to use over the motherboard's built-in boot menus. With a total
encryption approach you must use zfsbootmenu to decrypt the boot
partition and kernels. On laptops used for travel I simplify to
zbm-only with secure boot (this is not yet in the dotfiles).

Bootloaders should be configured from a chroot.

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

The first `generate-zbm` in that chroot writes a stock image. After `./install.sh`, `lib/zfs.sh` merges the quiet tokens into the pool property and `/etc/zfsbootmenu/config.yaml`, then regenerates the image if the yaml changed. See [Boot flow](#boot-flow).

### ZFS Maintenance

**Pool feature upgrades:** after OpenZFS updates, `zpool status` will suggest `zpool upgrade`. The ZFSBootMenu EFI image embeds its own ZFS module, which must understand the pool's enabled features — so always regenerate the boot image *before* upgrading the pool, never the reverse:

```bash
sudo generate-zbm
sudo zpool upgrade zpcachyos
```

Feature flags can't be removed once enabled, and old ZBM images (and older live media) may refuse to import the pool afterwards. Keep a recent CachyOS live USB as the fallback boot path.

**Snapshots:** two independent mechanisms:

- `sanoid.timer` snapshots `zpcachyos/ROOT/cos/home` (`autosnap_*`, retention in `etc/sanoid/sanoid.conf`). Data-only, not bootable.
- The pacman hook (`etc/pacman.d/hooks/zfs-snapshot.hook`) recursively snapshots `zpcachyos/ROOT/cos` before every transaction (`pre-update-*`, keeps 3 per dataset). The `root` snapshots are bootable recovery points: boot them read-only from the ZFSBootMenu menu; clone + promote to make a rollback permanent.

### First Boot Setups (todo: shift this to the chroot step)

1. Enable CachyOS updater from greeter and install the gaming packages.
2. Create user accounts for family members.
3. Run the setup script:

```bash
git clone git@github.com:dieuwedeboer/dotfiles.git
cd dotfiles
./install.sh
```

The install script will:
- Install chezmoi if not present
- Link dotfiles via chezmoi
- Apply chezmoi (including agent instructions) and restore global skills from the lock (see [Agent Configuration](#agent-configuration))
- Install packages and configure system
- Optionally configure rEFInd with a custom theme (glow) if no custom theme is present
- Quiet the ZFSBootMenu and host kernel command lines (`docs/boot-flow.md`)
- Apply hardware quirks when DMI or a device node matches
- Install Monarchy (Omarchy Quattro as a second session. Family default stays Plasma)

`./install.sh --check` is a Monarchy dry-run. After the first install, `monarchy-update` is the command that refreshes the overlay. Operator notes and rollback are in `docs/monarchy-install.md`.

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
