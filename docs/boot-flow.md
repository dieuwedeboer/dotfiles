# Boot flow: ZFSBootMenu, Plymouth, greeter

How this box should look from firmware to a session, and what is still left to build. Applies to every CachyOS+ZFS machine that follows `scripts/install.sh`. Monarchy adds Plymouth and the Omarchy greeter on top; it does not own the passphrase.

Live investigation notes and prototypes live in `~/projects/zfsbootmenu` (upstream clone, not this repo).

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

## Quick wins (this commit)

Shipped in `scripts/setup-zfs.sh` (every machine) and `scripts/setup-monarchy.sh` (Plymouth + greeter).

| Win | Where | What |
| --- | --- | --- |
| Quiet host cmdline | `org.zfsbootmenu:commandline` on the pool | Merge `rw quiet splash loglevel=0 systemd.show_status=false rd.udev.log_level=0 vt.global_cursor_default=0` |
| Quiet ZBM image | `/etc/zfsbootmenu/config.yaml` `Kernel.CommandLine` | Merge `ro quiet loglevel=0 vt.global_cursor_default=0 fbcon=logo-count:0 rd.udev.log_level=0`, then `generate-zbm` if the file changed |
| Plymouth covers pool import | mkinitcpio HOOKS | `plymouth` immediately **before** `zfs` when the keyfile is in `FILES` and exists on disk. Otherwise **after** `zfs` so a missing keyfile still prompts on the console |
| Hold the splash | `plymouth-quit.service.d` | `plymouth quit --retain-splash` so SDDM paints over the logo, not a tty |
| Greeter first frame | `misc/monarchy/sddm/hyprland.lua` | `misc.background_color = rgb(26, 27, 38)` |
| Session first frame | `~/.config/hypr/boot-color.lua` | Same `background_color`, required from `hyprland.lua` |

`monarchy_skip_plymouth_zfs` still refuses the AUR package. It allows plymouth-before-zfs only when the keyfile is actually in the host initramfs.

## Later: ZBM passphrase and fonts

No ZBM source fork. `load-key.d` runs inside `load_key()` before `zfs load-key -L prompt`. If the hook unlocks `ZBM_ENCRYPTION_ROOT`, ZBM skips the stock prompt.

The hook is bash + tput, not fzf. Host fzf 0.74.3 has no `--password`. `zfs load-key -L prompt` reads `/dev/tty`, so the hook writes a 0600 temp file and loads with `file://`.

Paint: black screen, cyan Omarchy wordmark centered as a block, `Unlock <dataset>`, a box-drawing field, `•` bullets (U+2022 is in `ter-v32b`), enter / esc / backspace / ctrl-u. Wrong passphrase retries inside the hook.

The wordmark is 81 columns of `▄█▀`. Autosize targets at least 110 columns, so it fits. Stock `ter-v32b.psf` has █, box drawing, and `•`. It does not map U+2580 (▀) or U+2584 (▄). Patch those glyphs by splitting █, then `setfont`. Prototype: `~/projects/zfsbootmenu/contrib/psf-add-halfblocks.py` (PSF2; `ter-v14b.psf` is PSF1).

Install path when this lands:

- `misc/zbm/load-key.d/10-themed-passphrase.sh`
- generate-zbm pre-hook that patches `ter-v*.psf`
- copy into `/etc/zfsbootmenu/hooks` (the default `zfsbootmenu_hook_root` even when that line is commented)
- `zbm.hookroot=` on the ESP for iteration without rebuilding

`--demo` and `--preview` stay in the clone until the hook is copied here.

## Later: HiDPI console

Mask `early-setup.d/30-console-autosize.sh`. Stock walks Terminus largest-first and keeps the first font with at least 110 columns, so 3K panels stick on 16x32.

`setfont --double` turns `ter-v32b` into 32x64. 3440x1440 becomes about 107x22. That misses the 110-column floor, so the replacement hook targets a *range* (keep the double if columns stay around 90+). 90 columns still fits the 81-column wordmark. Patch half-blocks, then double.

Kernel `fbcon=margin` only tints leftover pixels. Linux vt cannot letterbox an 80x24 cell grid on a 3440 framebuffer without DRM mode-setting, which ZBM does not have. Character-cell margin via fzf `--margin` can wait; doubling the font does more on 3K.

Do not drop GOP to 1080p unless the panel letterboxes that mode. Stretching 16:9 onto 21:9 is the other way this looks ugly.

## Later: static ZBM frames

Plymouth cannot live in the ZBM image. A spinner there is text, same paint as the passphrase hook.

- `early-setup.d`: clear, hide cursor, draw the wordmark before `50-import-pools`
- `teardown.d`: same frame instead of `Booting vmlinuz…` so kexec's last picture is the logo

That does not survive kexec. Early host Plymouth is what covers pool import on the other side.

## What will not be done

- `plymouth-zfs`
- `EFI.Enabled` / UKI `SplashImage`
- GPU drivers in the ZBM image
- Forking `zfsbootmenu-core.sh`
- Putting Plymouth in generate-zbm

## File map

| Path | Role |
| --- | --- |
| `docs/boot-flow.md` | This plan |
| `scripts/lib/zbm/boot.sh` | Quiet cmdline merge, yaml edit, `generate-zbm` |
| `scripts/setup-zfs.sh` | Calls `zbm_apply_quiet_boot` on every `install.sh` |
| `misc/monarchy/plymouth-quit-retain.conf` | systemd drop-in |
| `misc/monarchy/sddm/hyprland.lua` | Greeter compositor, `#1a1b26` first frame |
| `misc/monarchy/hypr/boot-color.lua` | Session first frame |
| `scripts/lib/monarchy/splash.sh` | Plymouth side of `zfs`, retain-splash |

## Operator notes

`./scripts/install.sh` already runs `setup-zfs.sh`. After this lands, a new box gets the quiet host/ZBM cmdlines without a hand-edited `zfs set`. First-boot still needs rEFInd + `pacman -S zfsbootmenu` + one `generate-zbm` in the Calamares chroot before the first reboot; `setup-zfs.sh` regenerates later if the yaml still lacks the tokens.

Monarchy apply/splash-only rebuilds the *host* initramfs (`mkinitcpio -P`). It never runs `generate-zbm`.

Skip a baked-in ZBM hook at the next boot with `zbm.skip_hooks=<name>` or `zbm.autosize=0`.
