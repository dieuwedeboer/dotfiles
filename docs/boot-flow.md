# Boot flow: ZFSBootMenu, Plymouth, greeter

How this box should look from firmware to a session. Applies to every CachyOS+ZFS machine that follows `install.sh`. Monarchy adds Plymouth and the Omarchy greeter on top; it does not own the passphrase.

Themed ZBM passphrase, HiDPI fonts, and static ZBM frames are still planned in `docs/plans/zbm-ui.md`. Live investigation notes live in `~/projects/zfsbootmenu` (upstream clone, not this repo).

## What is wrong today

The passphrase prompt is OpenZFS `zfs load-key -L prompt` after `tput clear`. It sits at the top of the screen. The countdown and fzf menus are centered. That mismatch is the ZBM UI bug.

On a 3K or ultrawide panel, ZBM autosize stops at `ter-v32b` (16x32). The console then fills the whole GOP framebuffer, so the TUI looks like a tiny ruler stretched across the glass.

Between rEFInd, ZBM, Plymouth, and Hyprland the console wins 1-2 second races:

1. rEFInd chainloads ZBM Components (kernel+initramfs, not a UKI). No `SplashImage`. Cursor on black while kmods load.
2. Host cmdline is only `rw quiet splash`. The mkinitcpio `zfs` hook prints `ZFS: Importing pool` before Plymouth starts (`HOOKS=... zfs plymouth filesystems`).
3. `sddm.service` is `After=plymouth-quit.service`, so Plymouth tears down onto a tty, then Hyprland starts. Greeter `hyprland.lua` never sets `misc.background_color`.

ZBM cannot run Plymouth. GPU drivers are omitted so kexec can reinit the card. `EFI.Enabled` stays false. AUR `plymouth-zfs` is forbidden; that hook steals `zfs load-key` into a Plymouth passphrase dialog.

## Constraints

- Passphrase stays in ZBM. Host initramfs must not prompt when `/etc/zfs/zroot.key` is in `FILES`.
- No `plymouth-zfs`. No ZBM UKI. No GPU drivers in the ZBM image.
- Do not vendor-fork ZFSBootMenu. User hooks under `/etc/zfsbootmenu/hooks` mask system hooks of the same name.
- `#1a1b26` / `#ffffff` are the Unlock color tokens. Plymouth, greeter QML, and Hyprland first-frame should match.

## Shipped

Shipped in `lib/zfs.sh` (every machine) and Monarchy apply from `install.sh` (Plymouth + greeter).

| Win | Where | What |
| --- | --- | --- |
| Quiet host cmdline | `org.zfsbootmenu:commandline` on the pool | Merge `rw quiet splash loglevel=0 systemd.show_status=false rd.udev.log_level=0 vt.global_cursor_default=0` |
| Quiet ZBM image | `/etc/zfsbootmenu/config.yaml` `Kernel.CommandLine` | Merge `ro quiet loglevel=0 vt.global_cursor_default=0 fbcon=logo-count:0 rd.udev.log_level=0`, then `generate-zbm` if the file changed |
| Plymouth covers pool import | mkinitcpio HOOKS | `plymouth` immediately **before** `zfs` when the keyfile is in `FILES` and exists on disk. Otherwise **after** `zfs` so a missing keyfile still prompts on the console |
| Hold the splash | `plymouth-quit.service.d` | `plymouth quit --retain-splash` so SDDM paints over the logo, not a tty |
| Greeter first frame | `monarchy/sddm/hyprland.lua` | `misc.background_color = rgb(26, 27, 38)` |
| Session first frame | `~/.config/hypr/boot-color.lua` | Same `background_color`, required from `hyprland.lua` |

`monarchy_skip_plymouth_zfs` still refuses the AUR package. It allows plymouth-before-zfs only when the keyfile is actually in the host initramfs.

Unshipped ZBM UI work is `docs/plans/zbm-ui.md`.

## What will not be done

- `plymouth-zfs`
- `EFI.Enabled` / UKI `SplashImage`
- GPU drivers in the ZBM image
- Forking `zfsbootmenu-core.sh`
- Putting Plymouth in generate-zbm

## File map

| Path | Role |
| --- | --- |
| `docs/boot-flow.md` | Current quiet-boot and Plymouth behaviour |
| `docs/plans/zbm-ui.md` | Themed passphrase, HiDPI font, static frames |
| `lib/zbm/boot.sh` | Quiet cmdline merge, yaml edit, `generate-zbm` |
| `lib/zfs.sh` | Calls `zbm_apply_quiet_boot` on every `install.sh` |
| `monarchy/plymouth-quit-retain.conf` | systemd drop-in |
| `monarchy/sddm/hyprland.lua` | Greeter compositor, `#1a1b26` first frame |
| `monarchy/hypr/boot-color.lua` | Session first frame |
| `lib/monarchy/splash.sh` | Plymouth side of `zfs`, retain-splash |

## Operator notes

`./install.sh` runs `lib/zfs.sh`. A new box gets the quiet host/ZBM cmdlines without a hand-edited `zfs set`. First-boot still needs rEFInd + `pacman -S zfsbootmenu` + one `generate-zbm` in the Calamares chroot before the first reboot; `lib/zfs.sh` regenerates later if the yaml still lacks the tokens.

Monarchy apply/splash-only rebuilds the *host* initramfs (`mkinitcpio -P`). It never runs `generate-zbm`.

Skip a baked-in ZBM hook at the next boot with `zbm.skip_hooks=<name>` or `zbm.autosize=0`.
