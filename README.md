# Dieuwe's Dotfiles

Repeatable system setup for Arch Linux (CachyOS).

## Table of Contents

- [Installation](#installation)
  - [Initial Setup](#initial-setup)
  - [ZFS with Native Encryption](#zfs-with-native-encryption)
  - [Bootloader (rEFInd + ZFSBootMenu)](#bootloader-refind--zfsbootmenu)
  - [Dotfiles](#dotfiles)
  - [Agent Configuration](#agent-configuration)
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

### ZFS Maintenance

**Pool feature upgrades:** after OpenZFS updates, `zpool status` will suggest `zpool upgrade`. The ZFSBootMenu EFI image embeds its own ZFS module, which must understand the pool's enabled features — so always regenerate the boot image *before* upgrading the pool, never the reverse:

```bash
sudo generate-zbm
sudo zpool upgrade zpcachyos
```

Feature flags can't be removed once enabled, and old ZBM images (and older live media) may refuse to import the pool afterwards. Keep a recent CachyOS live USB as the fallback boot path.

**Snapshots:** two independent mechanisms:

- `sanoid.timer` snapshots `zpcachyos/ROOT/cos/home` (`autosnap_*`, retention in `misc/sanoid.conf`). Data-only, not bootable.
- The pacman hook (`misc/zfs-snapshot.hook`) recursively snapshots `zpcachyos/ROOT/cos` before every transaction (`pre-update-*`, keeps 3 per dataset). The `root` snapshots are bootable recovery points: boot them read-only from the ZFSBootMenu menu; clone + promote to make a rollback permanent.

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
- Link agent instructions and skills (see [Agent Configuration](#agent-configuration))
- Install packages and configure system
- Optionally configure rEFInd with a custom theme (glow) if no custom theme is present

### Agent Configuration

`.agents/` in this repo is the single source of truth for coding-agent config, shared
across every agent on the machine. `install.sh` symlinks `~/.agents` to it, then points
each tool's expected path back at that:

| Path | Points to |
| --- | --- |
| `~/.agents` | `dotfiles/.agents` |
| `~/.claude/CLAUDE.md` | `~/.agents/AGENTS.md` |
| `~/.claude/skills` | `~/.agents/skills` |
| `~/.config/opencode/AGENTS.md` | `~/.agents/AGENTS.md` (via chezmoi `symlink_` entry) |

So `.agents/AGENTS.md` is the only file to edit for global agent instructions, and
skills installed into `~/.agents/skills` land in the repo as a normal git diff —
including updates to `.agents/.skill-lock.json`, which supersedes the old root
`skills-lock.json`.

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

---

## Legacy Setup

The `legacy-ubuntu` branch contains the old Ubuntu setup using Ansible.

It is no longer maintained.
