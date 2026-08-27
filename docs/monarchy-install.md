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

6. Reboot. Pick Omarchy for your user if the greeter did not default to it. Family picks Plasma from the dropdown.

## What apply does

- Snapshot via `/root/.local/bin/zfs-snapshot-pre-update.sh`. If that helper is missing or still has the varlog-only prune, apply installs the current copy from this repo, then asserts a `@pre-update-*` exists on `zpcachyos/ROOT/cos/root`.
- Clone `berenddeboer/omarchy` `quattro-on-zfs` at the lock commit to `/usr/local/src/monarchy/omarchy`
- Working prefix `/usr/local/share/omarchy` (data symlinks + overlay `bin/`)
- `/etc/omarchy.conf`
- Recv and locally sign Omarchy packaging key `40DFB630FF42BCFFB047046CF0134EE680CAC571` (prompts once; later runs skip). Append `[omarchy]` after CachyOS repos (`SigLevel = Required DatabaseOptional`) and install `omarchy-keyring`
- Install filtered leaf packages (`omarchy-base.packages` minus `packages.deny`). Hyprland and Quickshell come from CachyOS first-match
- Register `/usr/share/wayland-sessions/omarchy.desktop` (`TryExec=uwsm`, `DesktopNames=Hyprland`). Exec is the real `uwsm start … hyprland.desktop` once that file exists, otherwise the session probe
- Install `/usr/share/uwsm/env.d/10-monarchy` and Hyprland portal defaults if missing
- Seed `~/.config/hypr/*` (no overwrite), branding, `TERMINAL=ghostty`, and the first-run-done marker so `omarchy-provision-first-run` no-ops

It does **not** change Plymouth or rEFInd. Splash is a later PR.

`--no-packages` skips the leaf set (still does overlay, repo, and session).

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

Plasma Login Manager lists every file in `/usr/share/wayland-sessions/`. Omarchy is visible. Family members pick Plasma. Do not enable autologin. AccountsService `Session=` is an attempt, not a proven PLM API.

## Laptop test

After apply and reboot:

1. Greeter shows Plasma and Omarchy.
2. Your user can start Omarchy. Hyprland + Quickshell come up. Ghostty is the terminal.
3. Log out. Plasma still starts for a family account (or for you).
4. `grep '^\[omarchy\]' -n /etc/pacman.conf` is after `[cachyos]`. `/etc/os-release` still `ID=cachyos`.
5. `omarchy-refresh-pacman` prints `monarchy: blocked` and exits 2.
6. `pacman -Q sddm` fails (not installed). `systemctl is-enabled plasmalogin` is enabled.

If Hyprland fails to start, stay on Plasma, boot a `pre-update-*` snapshot from ZFSBootMenu, and keep `/var/log/monarchy-setup.log`.
