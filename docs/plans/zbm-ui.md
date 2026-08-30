# Plan: ZFSBootMenu passphrase, fonts, and static frames

- **Status:** plan. Not scheduled. Live prototypes live in `~/projects/zfsbootmenu` (upstream clone, not this repo).
- **Audience:** anyone about to theme the ZBM unlock prompt
- **Current quiet-boot work** is already shipped. See `docs/boot-flow.md`.

Do not vendor-fork ZFSBootMenu. User hooks under `/etc/zfsbootmenu/hooks` mask system hooks of the same name. `#1a1b26` / `#ffffff` are the Unlock color tokens.

## ZBM passphrase and fonts

No ZBM source fork. `load-key.d` runs inside `load_key()` before `zfs load-key -L prompt`. If the hook unlocks `ZBM_ENCRYPTION_ROOT`, ZBM skips the stock prompt.

The hook is bash + tput, not fzf. Host fzf 0.74.3 has no `--password`. `zfs load-key -L prompt` reads `/dev/tty`, so the hook writes a 0600 temp file and loads with `file://`.

Paint: black screen, cyan Omarchy wordmark centered as a block, `Unlock <dataset>`, a box-drawing field, `•` bullets (U+2022 is in `ter-v32b`), enter / esc / backspace / ctrl-u. Wrong passphrase retries inside the hook.

The wordmark is 81 columns of `▄█▀`. Autosize targets at least 110 columns, so it fits. Stock `ter-v32b.psf` has █, box drawing, and `•`. It does not map U+2580 (▀) or U+2584 (▄). Patch those glyphs by splitting █, then `setfont`. Prototype: `~/projects/zfsbootmenu/contrib/psf-add-halfblocks.py` (PSF2; `ter-v14b.psf` is PSF1).

Install path when this lands:

- `etc/zfsbootmenu/hooks/load-key.d/10-themed-passphrase.sh`
- generate-zbm pre-hook that patches `ter-v*.psf`
- copy into `/etc/zfsbootmenu/hooks` (the default `zfsbootmenu_hook_root` even when that line is commented)
- `zbm.hookroot=` on the ESP for iteration without rebuilding

`--demo` and `--preview` stay in the clone until the hook is copied here.

## HiDPI console

Mask `early-setup.d/30-console-autosize.sh`. Stock walks Terminus largest-first and keeps the first font with at least 110 columns, so 3K panels stick on 16x32.

`setfont --double` turns `ter-v32b` into 32x64. 3440x1440 becomes about 107x22. That misses the 110-column floor, so the replacement hook targets a *range* (keep the double if columns stay around 90+). 90 columns still fits the 81-column wordmark. Patch half-blocks, then double.

Kernel `fbcon=margin` only tints leftover pixels. Linux vt cannot letterbox an 80x24 cell grid on a 3440 framebuffer without DRM mode-setting, which ZBM does not have. Character-cell margin via fzf `--margin` can wait; doubling the font does more on 3K.

Do not drop GOP to 1080p unless the panel letterboxes that mode. Stretching 16:9 onto 21:9 is the other way this looks ugly.

## Static ZBM frames

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
