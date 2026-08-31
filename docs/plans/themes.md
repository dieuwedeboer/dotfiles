# Plan: extra themes as a URL list

- **Status:** plan. Not scheduled. Kingfisher is still a local directory, not a git extra.
- **Audience:** anyone about to ship Dieuwe's Omarchy themes through this overlay
- **Live wallpaper split is already done on kingfisher.** Theme pack holds `pexels-shilpnirmit-20579688.jpg`. The other 60 JPEGs are in `~/.config/omarchy/backgrounds/kingfisher/`. `~/Pictures/Wallpapers` is the same dump and is obsolete.

One extra-theme git repo per theme. The overlay installs them the way it installs plugins: a URL list, clone if missing, leave an existing checkout alone. Every listed theme is installed on every box that runs Dieuwe user setup. Palette and 3–6 shipped wallpapers live in the theme repo. The rest of a machine's photos stay in that theme's user overlay.

## What this is not

A theme monorepo. `omarchy theme install <url>` clones the repo as `~/.config/omarchy/themes/<name>/` and expects `colors.toml` at that root. The picker only lists immediate children of `themes/`. A bundle repo would install as one extra named after the repo.

Chezmoi of `~/.config/omarchy/themes/`. Git clones and Aether both write there.

Git-lfs in a theme repo. Install is a plain `git clone`.

Tying a palette to wallpaper cycle. Omarchy has one `colors.toml` per theme. Super+Ctrl+Space only swaps the image. Different palettes are different themes, each with its own repo.

Aether's `aether` theme as the shipped name. Apply writes `~/.config/omarchy/themes/aether/` and switches to it.

## Omarchy extra-theme contract

Repo name `omarchy-<name>-theme` so install lands as `<name>`. Root is the theme:

```
colors.toml
icons.theme
preview.png
unlock.png              # optional, Style > Unlock
preview-unlock.png      # optional
backgrounds/            # 3–6 webp, long edge around 2560
CREDITS.md              # photographer, license, source URL per shipped image
README.md               # omarchy theme install <url>
```

Do not ship `*.lua`, terminal configs, or `vscode.json`. Extra-theme staging drops them and regenerates from `colors.toml`.

`omarchy-theme-install` names the theme from the URL: basename, strip `.git`, strip leading `omarchy-` and trailing `-theme`, lowercase. Use that same derivation here so `omarchy theme remove` and `omarchy theme update` see the same extra.

A cloned extra has a `.git` directory. A symlink is the author's working copy and is not pulled. A plain directory is treated as something Dieuwe wrote.

## Overlay list

`monarchy/themes`, same shape as `monarchy/plugins`:

```
# Third-party Omarchy extra themes. Installed by install.sh into
# ~/.config/omarchy/themes/<name>/. Same contract as:
#   omarchy theme install <url>
# Apply clones missing extras. It does not call omarchy-theme-install,
# which rm -rf's the dest. --default is first-run omarchy-theme-set
# when theme.name is empty. At most one --default.
https://github.com/dieuwedeboer/omarchy-kingfisher-theme.git --default
```

Third-party extras are more rows. No hostname flags. The list is the collection, not a per-machine picker.

`--check` validates the file the way `monarchy_check_plugins` does: every line is a git URL, flags are known, at most one `--default`.

## Install, skip, update

Dieuwe user setup, next to `monarchy_install_plugins`. All boxes that run that setup get the whole list.

Do not call `omarchy-theme-install`. It deletes the dest first.

Mirror plugins:

1. If a checkout already has `origin` equal to the listed URL, skip clone.
2. Else clone to a staging dir with `GIT_TERMINAL_PROMPT=0`.
3. Theme name from the URL, dest `~/.config/omarchy/themes/<name>/`.
4. If dest exists (directory or symlink), leave it and drop the staging clone.
5. Else `mv` staging into dest.
6. After the list, if `--default` is set and `~/.local/state/omarchy/current/theme.name` is empty, `omarchy-theme-set` that name. Re-apply must not override a theme Dieuwe already picked.

`--update` / later user setup does not `git pull`. `omarchy theme update` is the updater for extras that already exist, same as `omarchy plugin update`. Call it from user setup after the clones so a box that already had kingfisher picks up palette tweaks. Skip dests that are symlinks; those are working copies.

First-run today sets Tokyo Night when `theme.name` is empty. Once kingfisher is listed `--default`, that is the first-run theme. Tokyo Night stays as the fallback if the extra clone failed.

## Cutover on kingfisher the machine

`~/.config/omarchy/themes/kingfisher` is a hand-written dir with no `.git`. Step 4 above would skip forever and never clone the extra.

Before the first extras apply that lists kingfisher:

- Keep `~/.config/omarchy/backgrounds/kingfisher/` (the 60 extras).
- Move the hand-written theme dir aside (`kingfisher.bak` or delete once the extra clone is verified).
- Leave the live wallpaper file available so the session does not go blank: either it is one of the 3–6 images in the new repo, or it stays in the overlay.

A symlink from dest to a local working copy is left alone, on purpose. That is how Dieuwe authors on one box without apply fighting git.

## What belongs in the theme repo

One palette. Aether can extract it from the active wallpaper (`aether --generate <jpg> --extract-mode … --no-apply --output /tmp/…`, then copy `colors.toml`). GUI Apply writes the `aether` theme and switches to it. After a session Dieuwe likes, copy `colors.toml` / `icons.theme` / `preview.png` into the theme repo and `omarchy theme set kingfisher`. Save the Aether blueprint as `kingfisher` so it can be reopened.

3–6 wallpapers in `backgrounds/`, converted to webp, sized like Omarchy's own packs (those are 2–9MB total, not 84MB of 4K JPEG). Pexels is fine to ship if CREDITS names photographer and photo id. Anything whose license is unclear stays in the overlay and never in git.

`preview.png` for the switcher. `unlock.png` only if that theme should appear under Style > Unlock.

Personal 4K dumps stay in `~/.config/omarchy/backgrounds/<name>/`. `Install > Style > Background` opens that folder. Omarchy already merges overlay + theme pack when cycling. Overlay is per-machine and is not this repo's problem.

## Public listing

Optional and per theme. PR to [omacom-io/omarchy-site](https://github.com/omacom-io/omarchy-site): a 16:9 desktop screenshot as `assets/themes/<name>.webp` (about 1200px, under ~100KB) and an alphabetical `<figure>` in `themes/index.html` pointing at that theme's GitHub URL. Real session, shipped wallpaper, nothing personal.

Household-only is the same extra, private remote, SSH URL on the list. `omarchy-theme-install` already accepts `git@host:org/repo.git`.

## Implementation when this lands

- `monarchy/themes` list file
- `lib/monarchy/themes.sh` (check, name-from-url, clone-if-missing, optional default set)
- `monarchy_check_themes` from `--check`
- `monarchy_install_themes` from `monarchy_setup_user`, then the existing `monarchy_user_theme` uses the `--default` name instead of hard-coded Tokyo Night
- `docs/monarchy.md` and `docs/monarchy-install.md` rows next to plugins
- Theme repos themselves stay outside this tree

## Suggested order

1. Finish kingfisher's palette in Aether, pick 3–6 images, convert, CREDITS.
2. Publish `omarchy-kingfisher-theme` (public or private).
3. Cut over the live kingfisher dir as above.
4. Land `monarchy/themes` + install helper. Add more URLs later the same way plugins grew.
