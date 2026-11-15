# Hyprland is held while Omarchy's titlebars plugin pins an older one

When the `omarchy-hyprland-titlebars` that `[omarchy]` serves depends on a
Hyprland version the repositories no longer offer, monarchy writes
`IgnorePkg = hyprland` into `[options]` of `pacman.conf`, between
`# BEGIN monarchy-hold` and `# END monarchy-hold`. It removes the block once
the two agree. The `pacman` unit applies it, and so does the pre-update step,
against the sync DB it has just refreshed, before `omarchy update` runs
`pacman -Syu`.

## What forced it

On 16 November 2026 the upgrade to Omarchy 4.5.0 stopped:
`installing hyprland (0.57.2-1.1) breaks dependency 'hyprland=0.56.2' required
by omarchy-hyprland-titlebars`. The plugin is a compiled Hyprland plugin and
pins one exact version. Stock Omarchy takes Hyprland from Arch through its own
snapshot mirror (`stable-mirror.omarchy.org`), which held 0.56.2-4, so the two
move together. This box takes Hyprland from `cachyos-extra-v3`, which had moved
to 0.57.2.

## Considered

- **Point `[core]` and `[extra]` at Omarchy's snapshot mirror.** Changes
  nothing for Hyprland: `cachyos-extra-v3` sits above `[extra]` and carries it.
  Real parity would mean pinning the CachyOS repositories too.
- **Deny the plugin in `packages.deny`.** Simpler, and keeps CachyOS's
  Hyprland, but floating workspaces lose their titlebars until Omarchy
  rebuilds the plugin.

## Consequences

- Only `hyprland` is held. It is the only package anything pins by exact
  version. Its libraries are pinned by soname, so a library upgrade that would
  break the held Hyprland is refused by pacman rather than installed.
- The compositor lags CachyOS until `[omarchy]` ships a plugin built for what
  CachyOS has, and each upgrade prints that hyprland was skipped.
- The hold follows the plugin's own dependency, so there is nothing to bump.
  With the plugin removed, the hold goes too.
