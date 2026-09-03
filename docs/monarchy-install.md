# Monarchy install

Omarchy Quattro as a second Wayland session on a CachyOS+ZFS+KDE box. `./install.sh` is the one-shot path: packages, chezmoi, hardware, ZFS, then Monarchy apply. Plasma stays the family default. The king picks Omarchy at the greeter.

## Where to run it

Any machine that followed the README Calamares path (CachyOS, encrypted ZFS, KDE Plasma, rEFInd, ZFSBootMenu). First bring-up was zbook. kingfisher, bonw9, and leftover boxes still on the old package set use the same script.

`--check` is snapshot-free and writes nothing under `/etc` or `/usr/local`. Do not pass `--update` on a first apply. That path still re-pins the lock commit and does not migrate.

## New machine

1. CachyOS ISO, UEFI, Calamares: FAT32 ESP 1024MB at `/boot/efi`, encrypted ZFS, KDE Plasma. Do not pick "No Desktop". Do not pick CachyOS Hyprland.
2. ZFSBootMenu properties from the README: `bootfs=zpcachyos/ROOT/cos/root`, `rootprefix=root=ZFS=`. `install.sh` / `lib/zfs.sh` merge the quiet cmdline tokens (`docs/boot-flow.md`).
3. rEFInd + `zfsbootmenu` + `generate-zbm`.
4. Clone dotfiles and run:

```bash
./install.sh --check
./install.sh
```

`--check` is Monarchy only (dry-run). Bare `./install.sh` is the full setup, including Monarchy apply. Prompts once to locally sign the Omarchy packaging key unless `MONARCHY_TRUST_OMARCHY_KEY=1`. If pacman asks for a `totem-plparser` provider, take the default (`cachyos-extra-v3`).

5. Reboot. SDDM is now the greeter (Omarchy theme). Tab cycles users, Up/Down cycles sessions. Queen and kid accounts default to Plasma. The king defaults to Omarchy.

## Existing machine

Household daily drivers and less-used boxes that already have the old package set (pacman emacs/bun/gh, Spotify/Discord flatpaks, curl-pipe cursor-agent, python-pipx, omarchy-emacs) run the same `./install.sh`. Confirm TLP is absent (`pacman -Q tlp-pd` should fail). Apply aborts if it is installed. `cachy-update` (or `sudo pacman -Syu`) first: apply refuses to install Omarchy leaves while upgrades are pending.

`lib/packages.sh` installs the shared set, then Monarchy apply writes `/etc/omarchy.conf`, then the strip removes the competing copies. `--update` and `monarchy-update` run the same strip. Until that conf exists, emacs/bun/gh/spotify/discord/cursor-agent/pipx stay so a box that has not finished apply is still usable.

Optional dry-run first:

```bash
./install.sh --check
./install.sh
```

What changes:

- SDDM replaces plasma-login-manager. Family picker defaults to Plasma. The king defaults to Omarchy.
- The power key is ignored. A Bluetooth headset KEY_POWER has shut a host down. Shutdown is the System menu.
- Plymouth sits before zfs when `/etc/zfs/zroot.key` is in FILES. The ZBM passphrase is untouched.
- Hardware modules self-gate. kingfisher's Gigabyte B550 gets OpenRGB, it87, CoolerControl, GPP0 wakeup. An HP ZBook gets the battery helper. bonw9 gets tccd.
- UFW allow rules are always written (SSH, VLC Chromecast, Minecraft). `install.sh` does not enable or disable the firewall. `ufw enable` / `ufw disable` on the box is the switch and it persists. Home boxes stay off. zbook stays on.
- `ufw-docker` is denied. Omarchy `firewall.sh` is never run.

If Hyprland fails, stay on Plasma, boot a `pre-update-*` snapshot from ZFSBootMenu, keep `/var/log/monarchy-setup.log`.

## What apply does

- Snapshot via `/root/.local/bin/zfs-snapshot-pre-update.sh`. If that helper is missing or still has the varlog-only prune, apply installs the current copy from this repo, then asserts a `@pre-update-*` exists on `zpcachyos/ROOT/cos/root`.
- Clone `berenddeboer/omarchy` `quattro-on-zfs` at the lock commit to `/usr/local/src/monarchy/omarchy`
- Working prefix `/usr/local/share/omarchy` (data symlinks + overlay `bin/`)
- `/etc/omarchy.conf`
- Recv and locally sign Omarchy packaging key `40DFB630FF42BCFFB047046CF0134EE680CAC571` (prompts once. Later runs skip). Append `[omarchy]` after CachyOS repos (`SigLevel = Required DatabaseOptional`) and install `omarchy-keyring`
- Install filtered leaf packages (`omarchy-base.packages` minus `packages.deny`). Hyprland and Quickshell come from CachyOS first-match
- Register `/usr/share/wayland-sessions/omarchy.desktop` (`TryExec=uwsm`, `DesktopNames=Hyprland`). Exec is the real `uwsm start … hyprland.desktop` once that file exists, otherwise the session probe
- Install `/usr/share/uwsm/env.d/10-monarchy` (stock 10-omarchy with the working-prefix bootstrap + mise) and Hyprland portal defaults if missing
- Install omarchy-settings files (`etc/` drop-ins, user systemd units, fontconfig, icons) minus `monarchy/settings.skip`. Enable cups/avahi/docker.socket/oomd when the units exist. Seed chromium native hosts, gnome-keyring, gtk theme, and user units
- Seed `~/.config/hypr/*` (no overwrite), branding (`screensaver.txt` from clone `logo.txt`, `about.txt` from `icon.txt`). Do not override `TERMINAL`. Run `omarchy-refresh-applications` (mise agent stubs + webapps), drop Basecamp and HEY from `monarchy/applications.drop`, `omarchy-pkg-add` of spotify, signal-desktop, cursor-bin, cursor-cli, omakade, `omarchy-install-browser chrome`, `mise use -g bun`, `emacs-wayland`, and `berenddeboer/omarchy-emacs-theme` (chezmoi `~/.config/emacs/`). `omarchy-provision-user` is allowed for a later finalize
- Install `monarchy/plugins` into `~/.config/omarchy/plugins/<id>/`. The file is the list: Grok usage, Activity Monitor, Screens, Sandman, Omarchy Spotify, and Omamail, each with `--enable`. `--enable` writes `shell.json` `plugins[]`. Does not need a live Omarchy session. Add more rows to that list to grow the collection. `omarchy plugin update` is still the updater for a checkout that already exists. Sandman's hibernate helper is not installed; hibernation stays refused.
- Install `OMARCHY_AUR_PACKAGES` from `lib/packages.sh` (currently `flea`) with `paru -S --assume-installed omarchy=<overlay version>`, and link `/usr/share/omarchy` to the overlay so the paths those PKGBUILDs hardcode resolve. Runs after apply because both halves need the overlay on disk. See `docs/monarchy-clashes.md`
- Run `omarchy-apply-lock` so `/etc/pam.d/omarchy-lock-password` exists. Super+Ctrl+L is a no-op without it (`lock-denied: missing-pam`). SDDM staying up after login is expected. It is not the locker.
- Enable `sddm.service`, remove `plasma-login-manager`, install `/etc/sddm.conf.d/zz-omarchy-sddm.conf` and the Omarchy greeter with the multi-user `Main.qml` overlay
- Install `/usr/local/bin/monarchy-switch-user`, overlay Super+Ctrl+U onto the lock screen and System menu, and seed the Hyprland bind. Family uses that chord on the lock screen to reach SDDM without the locked user's password
- Install logind drop-ins: `HandlePowerKey=ignore` (CachyOS default is poweroff. A Bluetooth headset KEY_POWER has shut zbook down) and `InhibitDelayMaxSec=15` for lid-close lock. Reloads logind, does not restart it
- Install the Omarchy Plymouth theme. Put `plymouth` **before** `zfs` when `/etc/zfs/zroot.key` is in FILES, otherwise **after**. Install `plymouth quit --retain-splash`. `mkinitcpio -P`. Does not steal the ZFS passphrase (that stays at ZFSBootMenu). Does not touch rEFInd.

`--splash-only` is the same Plymouth step without redoing packages or user config.

`--no-packages` skips the leaf set (still does overlay, repo, and session).

After apply, `monarchy-update` is the PATH command (`install.sh --update`). The Omarchy menu's `omarchy-update` wraps it.

## Check (review only)

```bash
./install.sh --check
```

Uses a user cache clone if `/usr/local/src/monarchy/omarchy` is absent. Writes nothing under `/etc` or `/usr/local`.

## Rollback

Boot `zpcachyos/ROOT/cos/root@pre-update-*` from ZFSBootMenu, or clone+promote. Pacman.conf backup is `/etc/pacman.conf.monarchy.bak`. There is no `--uninstall`.

## No-keyfile Plymouth UX

If the host has no `/etc/zfs/zroot.key`, plymouth stays after zfs and the mkinitcpio `zfs` hook prompts on the console. That is a second passphrase look, not a stolen ZBM prompt. Do not "fix" it with `plymouth-zfs`. With the keyfile in FILES, plymouth sits in front of zfs so import is under the splash (`docs/boot-flow.md`).

## Before an apply

```bash
./tests/run.sh      # no sudo, writes nothing; must be green
./install.sh --check # dry run against this host
```

There is no canary box, and `zfs-snapshot-pre-update` keeps three snapshots
with a 15-minute dedup window, so repeated applies burn the rollback. The
suite and `--check` are the cheap gates; use them first.

## Family greeter

SDDM runs the Omarchy theme with a Monarchy overlay. Tab cycles users. Up/Down cycles sessions. Queen and kid accounts default to Plasma. The king defaults to Omarchy. Do not enable autologin. Do not write `/var/lib/sddm/state.conf`. SDDM does not remember last session per user. Those static defaults are the picker.

## After apply

After reboot:

1. Greeter shows Plasma and Omarchy.
2. Your user can start Omarchy. Hyprland + Quickshell come up. Ghostty is the terminal.
3. Log out. Plasma still starts for a family account (or for you).
4. `grep '^\[omarchy\]' -n /etc/pacman.conf` is after `[cachyos]`. `/etc/os-release` still `ID=cachyos`.
5. `omarchy-refresh-pacman` prints `monarchy: blocked` and exits 2.
6. `pacman -Q sddm` succeeds. `systemctl is-enabled sddm` is enabled. `pacman -Q plasma-login-manager` fails. `/etc/sddm.conf.d/zz-omarchy-sddm.conf` sorts after leftover `kde_settings.conf` and sets `Current=omarchy`. Greeter `Main.qml` is the multi-user overlay on stock Unlock (`#1a1b26`) unless Style > Unlock has already restyled plymouth. Drop `background.jpg` in `monarchy/sddm/` to layer a wallpaper on that greeter.
7. `/etc/pam.d/omarchy-lock-password` exists. Super+Ctrl+L locks the Omarchy session.
8. Super+Ctrl+U (System menu too) locks if needed and returns to SDDM. The same chord on the lock screen is the family breakout. It does not need the locked user's password. Logging back into an open session from the greeter switches to that session's lock screen. It must not start a second compositor.
9. `~/.config/omarchy/branding/screensaver.txt` exists (Omarchy wordmark). Super+Esc → Screensaver shows it. A key dismisses it. `$OMARCHY_PATH/logo.txt` is a symlink so Style > Screensaver > Restore Default works.
10. `~/.config/omarchy/plugins/io.github.dougfour.grok-usage/` exists. Click the stock AI icon and switch to **Grok**. Needs `grok login` for weekly limits.
11. `~/.config/omarchy/plugins/stappmus.activity-monitor/` exists. Bar widget for CPU, memory, GPU, storage, and processes.
12. `~/.config/omarchy/plugins/im0001gt.screens/` exists. Bar widget for arranging displays, HDR, VRR, and named profiles.
13. `~/.config/omarchy/plugins/lgse.sandman/` exists. Bar widget for lid-close, screensaver, lock, displays-off, and sleep timeouts.
14. `~/.config/omarchy/plugins/quickshell.spotify/` exists. Bar widget for Spotify in Quickshell. Sign-in is in the widget. The desktop Spotify client from `omarchy-pkg-add spotify` stays.
15. `~/.config/omarchy/plugins/omamail/` exists. Unread badge in the bar; the inbox is a native window. Gmail, HEY, and IMAP. Super+Shift+G stays Signal.
16. `/usr/share/omarchy` is a symlink to `/usr/local/share/omarchy`, and `flea` launches with its file listing themed. Both `/usr/share/flea/ui/Commons` and `/usr/share/flea/ui/Ui` resolve through that link.

If Hyprland fails to start, stay on Plasma, boot a `pre-update-*` snapshot from ZFSBootMenu, and keep `/var/log/monarchy-setup.log`.
