# Monarchy package and config clashes

Living matrix. Source of truth for `packages.deny` and overlay-bin policy. See `docs/monarchy.md` for architecture.

Pin: `berenddeboer/omarchy` `quattro-on-zfs` `bfcaa06f5cfa5c8cb89412503f615868c01df169` (438 `bin/` names: 286 allow, 2 wrap, 150 deny).

## Blocker

| Clash | Who owns it | Bridging resolution | Named function |
| --- | --- | --- | --- |
| `omarchy-refresh-pacman` replaces `/etc/pacman.conf` and CachyOS mirrorlists | CachyOS | Never call it. Marker-block `[omarchy]` only. Stub the command | `monarchy_preserve_pacman_conf`, `monarchy_add_omarchy_repo` |
| `linux` vs `linux-cachyos` + `linux-cachyos-zfs` | CachyOS | Deny stock `linux` | `monarchy_refuse_kernel_swap` |
| archzfs vs CachyOS ZFS (`linux-cachyos-zfs` and `zfs-dkms` both from Calamares) | CachyOS | Keep both CachyOS packages. No `[archzfs]` | `monarchy_refuse_archzfs` |
| Limine vs rEFInd + ZFSBootMenu | Dieuwe | Never install limine. Stub `omarchy-refresh-limine` | `monarchy_refuse_bootloader` |
| Snapper vs sanoid + pacman ZFS hook | Dieuwe | Never install snapper | `monarchy_refuse_snapper` |
| Omarchy ALPM update guard | would be Omarchy | Never install `omarchy` / `omarchy-dev` | `monarchy_disable_omarchy_update_guard` |
| `zroot/ROOT/default` vs `zpcachyos/ROOT/cos/root` | Dieuwe | Never run `zfs.sh` / zfs-check | `monarchy_refuse_dataset_rename` |
| `omarchy-settings*` overwrites `/etc/os-release` | CachyOS | Never install those packages | `monarchy_skip_os_release_clobber` |
| `sddm` vs plasma-login-manager | CachyOS | Deny `sddm`. Keep PLM | `monarchy_keep_plasmalogin` |

## Major

| Clash | Resolution |
| --- | --- |
| `tldr` vs `tealdeer` | Deny `tldr` |
| `yay` vs `paru` | Deny `yay`. Overlay `yay` execs `paru` |
| bash vs fish | Do not change login shells |
| `mise-bin` | Deny. Skip `mise.sh` |
| Nautilus vs Dolphin | Install nautilus. No user-global mimeapps |
| `ufw-docker` | Deny. Never run `firewall.sh` |
| NVIDIA 580xx-dkms vs `chwd` | Never run Omarchy `nvidia.sh` |
| `tuxedo-drivers-nocompatcheck-dkms` | Deny the package and the script |
| `tlp-pd` vs `power-profiles-daemon` | Abort if TLP is installed. Omarchy calls `powerprofilesctl` |

## `packages.deny`

See `misc/monarchy/packages.deny`. Hard list includes `sddm`, `tldr`, `yay`, `mise-bin`, `ufw-docker`, `snapper`, `limine*`, stock `linux`/`linux-headers`, NVIDIA dkms variants, `omarchy`/`omarchy-dev`/`omarchy-settings*`, `kernel-modules-hook`, `btrfs-progs`, `zram-generator`.

## Overlay bin

- `misc/monarchy/bin.allow` — symlink to clone `bin/<name>`
- `misc/monarchy/bin.wrap` — `omarchy-update` and `omarchy-update-system-pkgs` call `setup-monarchy.sh --update`
- `misc/monarchy/bin.deny` — stub, exit 2. Also installed under `/usr/local/bin` on apply

`omarchy` itself is allowlisted (CLI router). `omarchy-refresh-pacman` is deny, not a wrap.

Regenerate after a lock bump:

```bash
python3 scripts/lib/monarchy/generate-inventories.py /path/to/quattro-on-zfs
```
