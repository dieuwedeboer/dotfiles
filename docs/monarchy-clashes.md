# Monarchy package and config clashes

Source of truth for `packages.deny` and overlay-bin policy. Architecture is `docs/monarchy.md`.

Pin: `berenddeboer/omarchy` `quattro-on-zfs` `1297c7bc98cba3183d6037e19761dcb99e0c902e` (442 `bin/` names: 411 allow, 11 wrap, 20 deny).

## Blocker

| Clash | Who owns it | Bridging resolution | Named function |
| --- | --- | --- | --- |
| `omarchy-refresh-pacman` replaces `/etc/pacman.conf` and CachyOS mirrorlists | CachyOS | Never call it. Marker-block `[omarchy]` only. Stub the command | `monarchy_preserve_pacman_conf`, `monarchy_add_omarchy_repo` |
| `linux` vs `linux-cachyos` + `linux-cachyos-zfs` | CachyOS | Deny stock `linux` | `monarchy_refuse_kernel_swap` |
| archzfs vs CachyOS ZFS (`linux-cachyos-zfs` and `zfs-dkms` both from Calamares) | CachyOS | Keep both CachyOS packages. No `[archzfs]` | `monarchy_refuse_archzfs` |
| Limine vs rEFInd + ZFSBootMenu | King | Never install limine. Stub `omarchy-refresh-limine` | `monarchy_refuse_bootloader` |
| Snapper vs sanoid + pacman ZFS hook | King | Never install snapper | `monarchy_refuse_snapper` |
| Omarchy ALPM update guard | would be Omarchy | Never install `omarchy` / `omarchy-dev` | `monarchy_disable_omarchy_update_guard` |
| `zroot/ROOT/default` vs `zpcachyos/ROOT/cos/root` | King | Never run `zfs.sh` / zfs-check | `monarchy_refuse_dataset_rename` |
| `omarchy-settings*` overwrites `/etc/os-release` | CachyOS | Never install those packages | `monarchy_skip_os_release_clobber` |
| Two DMs: CachyOS PLM vs Omarchy `sddm` | CachyOS | Install `sddm`, remove PLM | `monarchy_keep_sddm` |

## Major

| Clash | Resolution |
| --- | --- |
| `tldr` vs `tealdeer` | Deny `tldr` |
| `yay` vs `paru` | Deny `yay`. Overlay `yay` execs `paru` |
| bash vs fish | Do not change login shells |
| `mise-bin` | Allow. User setup runs `omarchy-refresh-applications` (mise stubs for grok, opencode, gh, …). `lib/packages.sh` uninstalls curl-pipe grok/opencode/cursor-agent, pacman `bun`/`github-cli`/`opencode`, python-pipx, and the Spotify/Discord flatpaks |
| Default terminal | Omarchy `xdg-terminal-exec`. Apply removes `~/.config/uwsm/env.d/20-monarchy-terminal` |
| Spotify | Omarchy `omarchy-pkg-add spotify` (`/usr/bin/spotify`). Not the Flathub client |
| Discord | Omarchy webapp `.desktop`. Not the Flathub client |
| Zoom | Omarchy webapp `.desktop` (`zoommtg://`). AUR `zoom` is stripped after apply |
| Chrome | `omarchy-install-browser chrome` (AUR `google-chrome` plus flags, theme, copy-url). Not a bare paru install |
| Cursor | `omarchy-pkg-add cursor-bin` (CachyOS first-match) and `omarchy-pkg-add cursor-cli` (`/usr/bin/cursor-agent`). Not AUR `cursor-bin` or `curl https://cursor.com/install` |
| Signal | `omarchy-pkg-add signal-desktop`. Same extra package, Omarchy installer owns it |
| pipx | Retired. `uv` is in the household set. Strip `python-pipx` after apply. Leave leftover `~/.local/share/pipx/venvs` |
| Emacs | `emacs-wayland` + [omarchy-emacs-theme](https://github.com/berenddeboer/omarchy-emacs-theme) (Quattro `themed/` + `theme-set.d`). Live config is chezmoi `~/.config/emacs/`. `~/.emacs.d` is moved aside. Stock `emacs` and `omarchy-emacs` are uninstalled |
| Nautilus vs Dolphin | Install nautilus. No user-global mimeapps |
| `ufw-docker` | Deny. Never run `firewall.sh` |
| NVIDIA 580xx-dkms vs `chwd` | Never run Omarchy `nvidia.sh` |
| `tuxedo-drivers-nocompatcheck-dkms` | Deny the package and the script |
| `tlp-pd` vs `power-profiles-daemon` | Abort if TLP is installed. Omarchy calls `powerprofilesctl` |
| AUR packages that `depends=('omarchy')` | Assume the metapackage at the overlay's version, link `/usr/share/omarchy`. See below |

## `packages.deny`

See `monarchy/packages.deny`. Curated bricks only: two DMs (`plasma-login-manager`), metapackages (`omarchy` / `omarchy-settings*`), Limine, Snapper, stock `linux`/`linux-ptl*`, `tldr` (tealdeer), and `ufw-docker` (kingfisher keeps ufw disabled). `yay` is allowed. Overlay `yay` still execs `paru` when an Omarchy script calls it from session PATH.

## AUR packages that depend on `omarchy`

The Omarchy ecosystem on the AUR declares `depends=('omarchy')`. That
metapackage is denied, and it is not what those packages want: it drags in
limine, `limine-mkinitcpio-hook`, `limine-snapper-sync` and snapper. What they
want is the shell QML. flea is the worked example — its PKGBUILD symlinks
`ui/Commons` and `ui/Ui` into `/usr/share/omarchy/shell/`, and says so in a
comment.

Both halves are handled in `lib/packages.sh`:

- `OMARCHY_AUR_PACKAGES` is installed with `paru -S --assume-installed
  omarchy=<version>`, reading the version from `$MONARCHY_PATH/version`. paru
  resolves without pulling the metapackage.
- `packages_link_omarchy_share` links `/usr/share/omarchy` to
  `$MONARCHY_PATH`, so the hardcoded path resolves. It refuses to replace
  anything already at that path.

Do **not** satisfy the dependency with a local package that
`provides=('omarchy')`. `monarchy_refuse_omarchy` checks with
`monarchy_pkg_installed`, which is `pacman -Q` and follows Provides, so a stub
makes every check and apply after it die with "omarchy metapackage is
installed".

This step runs after apply, not with `packages_install`: the version file and
the QML it links to are both produced by the overlay.

## Overlay bin

- `monarchy/bin.allow`: symlink to clone `bin/<name>`
- `monarchy/bin.wrap`: `omarchy-update` and `omarchy-update-system-pkgs` exec `monarchy-update`. Plymouth write-path names skip Limine and restyle the SDDM greeter from Monarchy `Main.qml`. `omarchy-refresh-sddm` copies the clone theme then overlays that QML (Unlock default). Apply then follows Style > Unlock if plymouth is already a named theme. The session theme does not restyle the greeter. `omarchy-display-text-size` runs the clone binary then the user `display-text-size` hook (`apply-font-size`).
- `monarchy/bin.deny`: brick list only (pacman.conf, Limine, ISO provisioner, factory reset, dataset upgrade). Stub, exit 2. Also installed under `/usr/local/bin` on apply.

Omarchy-first: `generate-inventories.py` allows every other `clone/bin` name, including `omarchy-install-*` and `omarchy-pkg-*`. Apply installs the omarchy-settings file tree via `settings.skip`. `omarchy` itself is the CLI router. `omarchy-refresh-pacman` stays deny, not a wrap.

Regenerate after a lock bump:

```bash
python3 lib/monarchy/generate-inventories.py /usr/local/src/monarchy/omarchy
```
