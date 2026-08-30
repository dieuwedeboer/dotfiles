# Dieuwe's Dotfiles

Repeatable system setup for Arch Linux (CachyOS).

## Table of Contents

- [Installation](#installation)
  - [Initial Setup](#initial-setup)
  - [ZFS with Native Encryption](#zfs-with-native-encryption)
  - [Bootloader (rEFInd + ZFSBootMenu)](#bootloader-refind--zfsbootmenu)
  - [Boot flow](#boot-flow)
  - [Dotfiles](#dotfiles)
  - [Agent Configuration](#agent-configuration)
  - [Monarchy (Omarchy session)](#monarchy-omarchy-session)
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
sudo zfs set org.zfsbootmenu:commandline="rw quiet splash loglevel=0 systemd.show_status=false rd.udev.log_level=0 vt.global_cursor_default=0" zpcachyos

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

The first `generate-zbm` in that chroot writes a stock image. After `./install.sh`, `lib/zfs.sh` merges the quiet tokens into the pool property and `/etc/zfsbootmenu/config.yaml`, then regenerates the image if the yaml changed. See [Boot flow](#boot-flow).

### Boot flow

Passphrase is ZFSBootMenu. Plymouth (Monarchy) covers the host initramfs after unlock. The 1-2s of console between rEFInd, ZBM, Plymouth, and Hyprland is documented and partly automated in `docs/boot-flow.md`.

`lib/zfs.sh` (from `install.sh`) keeps:

- `org.zfsbootmenu:commandline` on the pool: `rw quiet splash loglevel=0 systemd.show_status=false rd.udev.log_level=0 vt.global_cursor_default=0`
- ZBM `Kernel.CommandLine`: `ro quiet loglevel=0 vt.global_cursor_default=0 fbcon=logo-count:0 rd.udev.log_level=0`

Themed ZBM passphrase, HiDPI fonts, and a static ZBM splash are still planned in `docs/plans/zbm-ui.md`. They are not in the image yet.

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

### First Boot Setup

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
- Install Monarchy (Omarchy Quattro as a second session; family default stays Plasma)

`./install.sh --check` is a Monarchy dry-run. Operator notes, rollback, and the greeter dropdown warning are in `docs/monarchy-install.md`.

### Agent Configuration

Home-level agent config is chezmoi-managed. `~/.agents` is a real directory, not a
symlink into this repo. Vendored skill bodies are not git; the lock is.

| Path | Source |
| --- | --- |
| `~/.agents/AGENTS.md` | `chezmoi/dot_agents/AGENTS.md` |
| `~/.agents/.skill-lock.json` | `chezmoi/dot_agents/dot_skill-lock.json` |
| `~/.claude/CLAUDE.md` | chezmoi symlink to `~/.agents/AGENTS.md` (`dot_claude/symlink_CLAUDE.md.tmpl`) |
| `~/.claude/skills` | chezmoi symlink to `~/.agents/skills` (`dot_claude/symlink_skills.tmpl`) |
| `~/.config/opencode/AGENTS.md` | chezmoi symlink to `~/.agents/AGENTS.md` (`dot_config/opencode/symlink_AGENTS.md.tmpl`) |

`install.sh` restores missing skills from the lock with `npx skills add … -g`. To bump:

```bash
npx skills update -g -y
chezmoi re-add ~/.agents/.skill-lock.json
```

Hand-crafted global skills go in `chezmoi/dot_agents/skills/<name>/`. Skills that only apply when working in this repo go in `.agents/skills/` here.

`~/.claude/settings.json` is chezmoi-managed (`chezmoi/dot_claude/settings.json`) and
sets `permissions.defaultMode` to `acceptEdits`, so Claude Code auto-approves file
edits but still prompts before running commands. Note that changes made in-session via
`/config` write to the live file and will be reverted by the next `chezmoi apply` —
run `chezmoi re-add ~/.claude/settings.json` to keep them.

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

### Monarchy (Omarchy session)

Omarchy Quattro as a second Wayland session on the same CachyOS+ZFS+KDE box. Plasma stays the family default. Dieuwe picks Omarchy at the greeter. `./install.sh` applies it on a new box and on a converting machine.

Design and clash matrix: `docs/monarchy.md` and `docs/monarchy-clashes.md`. Install notes: `docs/monarchy-install.md`.

---

## Legacy Setup

The `legacy-ubuntu` branch contains the old Ubuntu setup using Ansible.

It is no longer maintained.
