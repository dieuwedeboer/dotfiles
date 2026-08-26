# Monarchy install

Optional Omarchy Quattro session on top of a finished CachyOS+ZFS+KDE box. Does not replace `scripts/install.sh`.

## Where to run it

Build and review happen on kingfisher. First apply is an **older laptop**, not kingfisher or bonw9.

`setup-monarchy.sh` (without `--check`) refuses those two hostnames unless `MONARCHY_ALLOW_HOST=1`. `--check` is snapshot-free and is safe on kingfisher.

## New machine

1. CachyOS ISO, UEFI, Calamares: FAT32 ESP 1024MB at `/boot/efi`, encrypted ZFS, KDE Plasma. Do not pick "No Desktop". Do not pick CachyOS Hyprland.
2. ZFSBootMenu properties from the README: `bootfs=zpcachyos/ROOT/cos/root`, `rootprefix=root=ZFS=`, `commandline="rw quiet splash"`.
3. rEFInd + `zfsbootmenu` + `generate-zbm`.
4. Clone dotfiles and run `./scripts/install.sh`. That does not install Monarchy.
5. On the bring-up laptop:

```bash
./scripts/setup-monarchy.sh --check
./scripts/setup-monarchy.sh
```

6. Reboot. PR 2 does not yet register the greeter session (PR 3) or install Hyprland packages (PR 4a). After those land: family picks Plasma from the dropdown. If AccountsService `Session=` does not stick, pick Omarchy once on your user.

## What PR 2 apply does

- Snapshot via `/root/.local/bin/zfs-snapshot-pre-update.sh` (requires `setup-zfs.sh` already run)
- Clone `berenddeboer/omarchy` `quattro-on-zfs` at the lock commit to `/usr/local/src/monarchy/omarchy`
- Working prefix `/usr/local/share/omarchy` (data symlinks + overlay `bin/`)
- `/etc/omarchy.conf`
- Append `[omarchy]` after CachyOS repos (`SigLevel = Required DatabaseOptional`) and install `omarchy-keyring`
- Deny stubs and update wrappers under overlay `bin/` and `/usr/local/bin`

It does **not** install Hyprland, uwsm, or a greeter session file. It does **not** change Plymouth or rEFInd.

## Check on kingfisher (review only)

```bash
./scripts/setup-monarchy.sh --check
```

Uses a user cache clone if `/usr/local/src/monarchy/omarchy` is absent. Writes nothing under `/etc` or `/usr/local`.

Overlay unit test (no sudo):

```bash
./scripts/lib/monarchy/test-overlay.sh /tmp/quattro-on-zfs
```

## Rollback

Boot `zpcachyos/ROOT/cos/root@pre-update-*` from ZFSBootMenu, or clone+promote. Pacman.conf backup is `/etc/pacman.conf.monarchy.bak`. There is no `--uninstall` in v1.

## No-keyfile Plymouth UX

If the host has no `/etc/zfs/zroot.key`, the mkinitcpio `zfs` hook prompts on the console before Plymouth (Plymouth is PR 5, after the zfs hook). That is a second passphrase look, not a stolen ZBM prompt. Do not "fix" it with `plymouth-zfs`.

## Family greeter

Plasma Login Manager lists every file in `/usr/share/wayland-sessions/`. After PR 3, Omarchy is visible. Family members pick Plasma. Do not enable autologin.
