# Monarchy package and config clashes

Source of truth for `packages.deny` and overlay-bin policy. Architecture is `docs/monarchy.md`.

Source: the official `omarchy` package from `[omarchy]` stable (428 `bin/` names: 13 wrapped, 19 denied, the rest not overridden). No pin, no clone — pacman does the pinning.

## Blocker

| Clash | Who owns it | Bridging resolution | Named function |
| --- | --- | --- | --- |
| `omarchy-refresh-pacman` replaces `/etc/pacman.conf` and CachyOS mirrorlists | CachyOS | Never call it. Marker-block `[omarchy]` only. Stub the command | `monarchy_preserve_pacman_conf`, `monarchy_add_omarchy_repo` |
| `linux-omarchy` (and stock `linux`) vs `linux-cachyos` + `linux-cachyos-zfs` | CachyOS | Any kernel may boot while one with a packaged ZFS module stays installed (ADR 0008). `linux-omarchy` is installed with `zfs-dkms`. Stock `linux` stays in `packages.deny` | `monarchy_require_fallback_kernel`, `etc/pacman.d/hooks/zfs-*.hook` |
| archzfs vs CachyOS ZFS (`linux-cachyos-zfs` and `zfs-dkms` both from Calamares) | CachyOS | Keep both CachyOS packages. No `[archzfs]` | `monarchy_refuse_archzfs` |
| Limine vs rEFInd + ZFSBootMenu | King | Never install limine. Stub `omarchy-refresh-limine` | `monarchy_refuse_bootloader` |
| Snapper vs sanoid + pacman ZFS hook | King | Never install snapper | `monarchy_refuse_snapper` |
| Omarchy ALPM update guard | would be Omarchy | Mask `00-omarchy-update-guard.hook` | `monarchy_disable_omarchy_update_guard` |
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
| `vi` | Deny. CachyOS's `ex-vi-compat` already provides `vi` and conflicts with a package of that name |
| `superwhisper-bin` | Deny. Proprietary dictation app; Voxtype stays the dictation backend. Revisit if the household wants it |
| `hype`, `monologue` | Install. Basecamp slides and webcam recorder, wanted on this box |
| `usbguard` | Follow Omarchy, which dropped it with USB approval on 14 October 2026. It is no longer an Omarchy package; migration `1791769486.sh` removes it where Omarchy granted it |
| `gliff` | Install. Remote desktop over SSH; inert until used |
| Migrations in general | Run, unless one cannot run without a brick risk (ADR 0005). `migrations.deny` and `migrations.allow` hold the reviewed ones, each with its reason |
| Migration `1789325478.sh` installs `linux-omarchy` | Deny. It ends on `limine-entry-tool`, which this host lacks, so it can never complete. The kernel itself is wanted and comes from `PACMAN_PACKAGES` (ADR 0008) |
| Migration `1791403252.sh` moves `[omarchy]` above every other repo, then runs a full upgrade | Deny. `[omarchy]` stays after CachyOS (`monarchy_preserve_pacman_conf`); its packages would otherwise shadow CachyOS builds |
| Omarchy's Limine command-line fixes, `initramfs_async=0` and `systemd.tty.term.console=dumb` | Taken, on `org.zfsbootmenu:commandline` (`lib/zbm/boot.sh`), since `settings.skip` drops the Limine drop-ins that carry them upstream |
| NVIDIA 580xx-dkms vs `chwd` | Never run Omarchy `nvidia.sh` |
| `tuxedo-drivers-nocompatcheck-dkms` | Deny the package and the script |
| `tlp-pd` vs `power-profiles-daemon` | Abort if TLP is installed. Omarchy calls `powerprofilesctl` |
| AUR packages that `depends=('omarchy')` | Assume the metapackage at the overlay's version. See below |

## `packages.deny`

See `monarchy/packages.deny`. Curated bricks only: two DMs (`plasma-login-manager`), metapackages (`omarchy-dev` / `omarchy-settings*`, which the packaging unit installs or replaces itself), Limine, Snapper, stock `linux`/`linux-ptl*`, `tldr` (tealdeer), `ufw-docker` (kingfisher keeps ufw disabled), `vi` and `superwhisper-bin`. `yay` is allowed. Overlay `yay` still execs `paru` when an Omarchy script calls it from session PATH.

## AUR packages that depend on `omarchy`

The Omarchy ecosystem on the AUR declares `depends=('omarchy')`. That
metapackage is denied, and it is not what those packages want: it drags in
limine, `limine-mkinitcpio-hook`, `limine-snapper-sync` and snapper. What they
want is the shell QML. flea is the worked example — its PKGBUILD symlinks
`ui/Commons` and `ui/Ui` into `/usr/share/omarchy/shell/`, and says so in a
comment.

How this host handles it:

- `OMARCHY_AUR_PACKAGES` is installed with `paru -S --assume-installed
  omarchy=<version>`, reading the version from `$MONARCHY_PATH/version`. paru
  resolves without pulling the metapackage.
- The hardcoded `/usr/share/omarchy/shell` path resolves into the installed
  Omarchy package, which owns that tree. It used to be a symlink to
  `$MONARCHY_PATH`; `pkgbuild.sh` removes that legacy link.

Do **not** satisfy the dependency with a local package that
`provides=('omarchy')`. `monarchy_refuse_omarchy` checks with
`monarchy_pkg_installed`, which is `pacman -Q` and follows Provides, so a stub
makes every check and apply after it die with "omarchy metapackage is
installed".

This step runs after apply, not with `packages_install`: the version file and
the QML it links to are both produced by the overlay.

## Overlay bin

- `monarchy/bin.wrap`: `omarchy-update` and `omarchy-update-system-pkgs` exec `monarchy-update`. Plymouth write-path names skip Limine and restyle the SDDM greeter from Monarchy `Main.qml`. `omarchy-refresh-sddm` copies the packaged theme then overlays that QML (Unlock default). Apply then follows Style > Unlock if plymouth is already a named theme. The session theme does not restyle the greeter. `omarchy-display-text-size` runs the packaged binary then the user `display-text-size` hook (`apply-font-size`). `omarchy-snapshot` takes a ZFS snapshot instead of driving snapper. `omarchy-battery-status` fills in a time estimate UPower could not supply, from the same `power_supply` tree it already reads — the ZBook quirk in `hardware/hp-zbook`, but gated on the empty field rather than on DMI.
- `monarchy/bin.deny`: brick list only (pacman.conf, Limine, ISO and image provisioners, Limine-only USB authorisation, factory reset, dataset upgrade). Stub, exit 2. Also installed under `/usr/local/bin` on apply.

Omarchy-first: a name that is neither wrapped nor denied is mirrored into the overlay as a symlink onto the packaged tree and behaves exactly as upstream ships it, including `omarchy-install-*` and `omarchy-pkg-*`. The mirror is not about PATH precedence, which a stub wins anyway; it is that packaged scripts resolve siblings as `$OMARCHY_PATH/bin/<name>`. See `docs/monarchy.md`. `omarchy` itself is the CLI router and is not overridden. `omarchy-refresh-pacman` stays deny, not a wrap.

`omarchy-settings-monarchy` installs the settings tree; `settings.skip` is that package's exclude list, not a copy filter. See "Packages" in `docs/monarchy.md`.

## Overlay QML

Patched copies, each with a `--check` that fails apply if the upstream anchors
moved: the lock plugin and `omarchy-menu.jsonc` (`overlay-lock.py`,
Super+Ctrl+U) and the power panel (`overlay-power.py`). The power panel one
makes "Holding" require a charge limit to exist. UPower reports
`pending-charge` for any kernel `Not charging`, and an EC that pulses the
charge reports that at any charge level, so the panel called a filling pack
held at a limit the machine does not have. A machine with `charge_control_*`
decides exactly as upstream does.

Agent marks are added, not patched. The AI panel draws a tab's mark from its
own `assets/<id>.svg` and nowhere else, so a tab a plugin adds would show a
bare letter. `monarchy/agent-marks/` is copied into that directory, and the
check fails once omarchy ships a mark of the same name, so ours never hides
theirs. The Grok marks that lived there went when omarchy-dev started
shipping its own; the directory is empty until a plugin needs one again.

## New upstream binaries

There is nothing to regenerate. `monarchy_check_bin_hazards` greps the package
`bin/` for `limine-entry-tool`, `limine-mkinitcpio`, `limine-install`,
`limine-snapper`, `omarchy-refresh-pacman`, `use_omarchy_pacman_config`, a
`pacman-*.conf`, `zroot/ROOT`, `/etc/pam.d/zfs-key`, or a `snapper`
invocation, and halts an apply on any hit that is neither denied nor wrapped.
`monarchy_check_overrides_exist` halts on a wrap or deny whose name upstream
dropped.

Classifying a reported name into `monarchy/bin.deny` or `monarchy/bin.wrap` is
a file edit. That judgement stays human: `monarchy_check_migrations` and
`monarchy_check_packages_deny` halt on anything unclassified for the same
reason, and there is no canary box. `monarchy-update` is what then moves a box
onto the new package.

Deny is for damage, not for disappointment. A command that merely fails here —
nothing to talk to, no snapper, no Limine — is still mirrored untouched and
needs no row. Deny when running it would break the host. Wrap when the box
still needs what the name does by another route, as `omarchy-snapshot` needs a
ZFS snapshot instead of snapper; a wrap is a script that has to keep matching
how upstream calls it, so it earns that cost or it is a deny.

Deleted rows are the ones to act on. Apply installs files and never reconciles
them, so a `sudoers.d` rule upstream removed for security stays on the box, and
a package dropped from `omarchy-base.packages` stays installed, until a person
takes it out.
