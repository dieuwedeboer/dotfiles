# Hyprland is held while Omarchy's titlebars plugin pins an older one

When the `omarchy-hyprland-titlebars` that `[omarchy]` serves depends on a
Hyprland version the repositories no longer offer, monarchy holds Hyprland
and what has to stay with it through `IgnorePkg` in `[options]` of
`pacman.conf`, between
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

- The held set is worked out from sonames each time (`lib/monarchy/hold.py`):
  a pending upgrade that would stop providing a library version a held
  package needs is held too, and so is one whose new build needs a library
  version only the newer stack provides. On 16 November 2026 that was
  `aquamarine`, `hyprgraphics`, `hyprland` and `hyprtoolkit`. A first version
  held `hyprland` alone, and pacman refused the upgrade because `aquamarine`
  0.16 and `hyprgraphics` 0.6 dropped the sonames 0.56.2 links against.
- The set grows whenever CachyOS bumps a library under Hyprland. A bump of
  `hyprutils` would take most of the stack with it. If the set gets large,
  denying the plugin is the cheaper answer.
- The compositor lags CachyOS until `[omarchy]` ships a plugin built for what
  CachyOS has, and each upgrade prints that hyprland was skipped.
- The hold follows the plugin's own dependency, so there is nothing to bump.
  With the plugin removed, the hold goes too.
