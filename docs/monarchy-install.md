# Monarchy install

Optional Omarchy Quattro session on top of a finished CachyOS+ZFS+KDE box. Does not replace `scripts/install.sh`.

## Where to run it

Any machine that already ran `scripts/install.sh` (CachyOS, encrypted ZFS, KDE Plasma, rEFInd, ZFSBootMenu). First bring-up was zbook. kingfisher and bonw9 use the same script.

`--check` is snapshot-free and writes nothing under `/etc` or `/usr/local`.

## New machine

1. CachyOS ISO, UEFI, Calamares: FAT32 ESP 1024MB at `/boot/efi`, encrypted ZFS, KDE Plasma. Do not pick "No Desktop". Do not pick CachyOS Hyprland.
2. ZFSBootMenu properties from the README: `bootfs=zpcachyos/ROOT/cos/root`, `rootprefix=root=ZFS=`, `commandline="rw quiet splash"`.
3. rEFInd + `zfsbootmenu` + `generate-zbm`.
4. Clone dotfiles and run `./scripts/install.sh`. That does not install Monarchy.
5. Then:

```bash
./scripts/setup-monarchy.sh --check
./scripts/setup-monarchy.sh
```

6. Reboot. SDDM is now the greeter (Omarchy theme). Tab cycles users, Up/Down cycles sessions. Family accounts default to Plasma; Dieuwe defaults to Omarchy.

## What apply does

- Snapshot via `/root/.local/bin/zfs-snapshot-pre-update.sh`. If that helper is missing or still has the varlog-only prune, apply installs the current copy from this repo, then asserts a `@pre-update-*` exists on `zpcachyos/ROOT/cos/root`.
- Clone `berenddeboer/omarchy` `quattro-on-zfs` at the lock commit to `/usr/local/src/monarchy/omarchy`
- Working prefix `/usr/local/share/omarchy` (data symlinks + overlay `bin/`)
- `/etc/omarchy.conf`
- Recv and locally sign Omarchy packaging key `40DFB630FF42BCFFB047046CF0134EE680CAC571` (prompts once; later runs skip). Append `[omarchy]` after CachyOS repos (`SigLevel = Required DatabaseOptional`) and install `omarchy-keyring`
- Install filtered leaf packages (`omarchy-base.packages` minus `packages.deny`). Hyprland and Quickshell come from CachyOS first-match
- Register `/usr/share/wayland-sessions/omarchy.desktop` (`TryExec=uwsm`, `DesktopNames=Hyprland`). Exec is the real `uwsm start … hyprland.desktop` once that file exists, otherwise the session probe
- Install `/usr/share/uwsm/env.d/10-monarchy` (stock 10-omarchy with the working-prefix bootstrap + mise) and Hyprland portal defaults if missing
- Install omarchy-settings files (`etc/` drop-ins, user systemd units, fontconfig, icons) minus `misc/monarchy/settings.skip`. Enable cups/avahi/docker.socket/oomd when the units exist. Seed chromium native hosts, gnome-keyring, gtk theme, and user units
- Seed `~/.config/hypr/*` (no overwrite), branding (`screensaver.txt` from clone `logo.txt`, `about.txt` from `icon.txt`). Do not override `TERMINAL`. Run `omarchy-refresh-applications` (mise agent stubs + webapps), `omarchy-pkg-add spotify`, and `mise use -g bun`. `omarchy-provision-user` is allowed for a later finalize
- Run `omarchy-apply-lock` so `/etc/pam.d/omarchy-lock-password` exists. Super+Ctrl+L is a no-op without it (`lock-denied: missing-pam`). SDDM staying up after login is expected; it is not the locker
- Enable `sddm.service`, remove `plasma-login-manager`, install `/etc/sddm.conf.d/99-omarchy-sddm.conf` and the Omarchy greeter with the multi-user `Main.qml` overlay
- Install `/usr/local/bin/monarchy-switch-user`, overlay Super+Ctrl+U onto the lock screen and System menu, and seed the Hyprland bind. Family uses that chord on the lock screen to reach SDDM without the locked user's password
- Install logind drop-ins: `HandlePowerKey=ignore` (CachyOS default is poweroff; a Bluetooth headset KEY_POWER has shut zbook down) and `InhibitDelayMaxSec=15` for lid-close lock. Reloads logind, does not restart it
- Install the Omarchy Plymouth theme, put `plymouth` **after** `zfs` in mkinitcpio HOOKS, `mkinitcpio -P`. Does not steal the ZFS passphrase (that stays at ZFSBootMenu). Does not touch rEFInd.

`--splash-only` is the same Plymouth step without redoing packages or user config.

`--no-packages` skips the leaf set (still does overlay, repo, and session).

## Check (review only)

```bash
./scripts/setup-monarchy.sh --check
```

Uses a user cache clone if `/usr/local/src/monarchy/omarchy` is absent. Writes nothing under `/etc` or `/usr/local`.

Overlay unit test (no sudo):

```bash
./scripts/lib/monarchy/test-overlay.sh /tmp/quattro-on-zfs
./scripts/lib/monarchy/test-branding.sh
./scripts/lib/monarchy/test-user.sh
./scripts/lib/monarchy/test-lock.sh
./scripts/lib/monarchy/test-switch-user.sh
./scripts/lib/monarchy/test-logind.sh
./scripts/lib/monarchy/test-sddm.sh
./scripts/lib/monarchy/test-splash.sh
./scripts/lib/monarchy/test-settings.sh
```

## Rollback

Boot `zpcachyos/ROOT/cos/root@pre-update-*` from ZFSBootMenu, or clone+promote. Pacman.conf backup is `/etc/pacman.conf.monarchy.bak`. There is no `--uninstall` in v1.

## No-keyfile Plymouth UX

If the host has no `/etc/zfs/zroot.key`, the mkinitcpio `zfs` hook prompts on the console before Plymouth (plymouth is after the zfs hook). That is a second passphrase look, not a stolen ZBM prompt. Do not "fix" it with `plymouth-zfs`.

## Family greeter

SDDM runs the Omarchy theme with a Monarchy overlay. Tab cycles users. Up/Down cycles sessions. amie and olivier default to Plasma; Dieuwe defaults to Omarchy. Do not enable autologin. Do not write `/var/lib/sddm/state.conf`. SDDM does not remember last session per user; those static defaults are the picker until Dieuwe reviews that (see `docs/monarchy.md` Open questions).

## After apply

After reboot:

1. Greeter shows Plasma and Omarchy.
2. Your user can start Omarchy. Hyprland + Quickshell come up. Ghostty is the terminal.
3. Log out. Plasma still starts for a family account (or for you).
4. `grep '^\[omarchy\]' -n /etc/pacman.conf` is after `[cachyos]`. `/etc/os-release` still `ID=cachyos`.
5. `omarchy-refresh-pacman` prints `monarchy: blocked` and exits 2.
6. `pacman -Q sddm` succeeds. `systemctl is-enabled sddm` is enabled. `pacman -Q plasma-login-manager` fails. `/etc/sddm.conf.d/99-omarchy-sddm.conf` sets `Current=omarchy`. Greeter `Main.qml` is the multi-user overlay on stock Unlock (`#1a1b26`) unless Style > Unlock has already restyled plymouth.
7. `/etc/pam.d/omarchy-lock-password` exists. Super+Ctrl+L locks the Omarchy session.
8. Super+Ctrl+U (System menu too) locks if needed and returns to SDDM. The same chord on the lock screen is the family breakout. It does not need the locked user's password.
9. `~/.config/omarchy/branding/screensaver.txt` exists (Omarchy wordmark). Super+Esc → Screensaver shows it; a key dismisses it. `$OMARCHY_PATH/logo.txt` is a symlink so _Style > Screensaver > Restore Default_ works.

If Hyprland fails to start, stay on Plasma, boot a `pre-update-*` snapshot from ZFSBootMenu, and keep `/var/log/monarchy-setup.log`.
