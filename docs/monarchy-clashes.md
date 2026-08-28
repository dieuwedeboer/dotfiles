# Monarchy package and config clashes

Living matrix. Source of truth for `packages.deny` and overlay-bin policy. See `docs/monarchy.md` for architecture.

Pin: `berenddeboer/omarchy` `quattro-on-zfs` `bfcaa06f5cfa5c8cb89412503f615868c01df169` (438 `bin/` names: 290 allow, 7 wrap, 141 deny).

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
| Two DMs: CachyOS PLM vs Omarchy `sddm` | CachyOS | Install `sddm`, remove PLM | `monarchy_keep_sddm` |

## Major

| Clash | Resolution |
| --- | --- |
| `tldr` vs `tealdeer` | Deny `tldr` |
| `yay` vs `paru` | Deny `yay`. Overlay `yay` execs `paru` |
| bash vs fish | Do not change login shells |
| `mise-bin` | Allow. Omarchy menu can install it; curl-bash agents can migrate onto mise |
| Nautilus vs Dolphin | Install nautilus. No user-global mimeapps |
| `ufw-docker` | Deny. Never run `firewall.sh` |
| NVIDIA 580xx-dkms vs `chwd` | Never run Omarchy `nvidia.sh` |
| `tuxedo-drivers-nocompatcheck-dkms` | Deny the package and the script |
| `tlp-pd` vs `power-profiles-daemon` | Abort if TLP is installed. Omarchy calls `powerprofilesctl` |

## `packages.deny`

See `misc/monarchy/packages.deny`. Curated bricks only: two DMs (`plasma-login-manager`), metapackages (`omarchy` / `omarchy-settings*`), Limine, Snapper, stock `linux`/`linux-ptl*`, plus `tldr` (tealdeer). `yay` is allowed; overlay `yay` still execs `paru` when an Omarchy script calls it from session PATH.

## Overlay bin

- `misc/monarchy/bin.allow` — symlink to clone `bin/<name>`
- `misc/monarchy/bin.wrap` — `omarchy-update` and `omarchy-update-system-pkgs` call `setup-monarchy.sh --update`. Plymouth write-path names skip Limine and restyle the SDDM greeter from Monarchy `Main.qml`. `omarchy-refresh-sddm` copies the clone theme then overlays that QML (Unlock default). Apply then follows Style > Unlock if plymouth is already a named theme; the session theme does not restyle the greeter.
- `misc/monarchy/bin.deny` — brick list only (pacman.conf, Limine, ISO provisioner, factory reset, dataset upgrade). Stub, exit 2. Also installed under `/usr/local/bin` on apply.

Omarchy-first: `generate-inventories.py` allows every other `clone/bin` name, including `omarchy-install-*` and `omarchy-pkg-*`. Apply installs the omarchy-settings file tree via `settings.skip` (same idea as [omarchy-on-cachyos](https://github.com/mroboff/omarchy-on-cachyos) deleting installer steps). `omarchy` itself is the CLI router. `omarchy-refresh-pacman` stays deny, not a wrap.

Regenerate after a lock bump:

```bash
python3 scripts/lib/monarchy/generate-inventories.py /path/to/quattro-on-zfs
```
