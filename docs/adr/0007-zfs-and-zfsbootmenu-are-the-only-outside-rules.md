# ZFS and ZFSBootMenu are the only hard rules from outside Omarchy

Monarchy is Omarchy on a ZFS root. Two things from outside Omarchy are hard
rules: the root is a ZFS pool, and ZFSBootMenu boots it. Everything else that
does not come from Omarchy is current practice, not a rule, and the direction
is to depend on less of it over time.

## Why

Every rule from another vendor is a place where Omarchy's own choices get
refused, wrapped or shimmed, and each of those is maintenance that grows with
every Omarchy release. ZFS and ZFSBootMenu earn that cost: snapshots before
every update and a boot menu that can roll back to them are why this repo
exists. Most of the rest was taken on because CachyOS was the quickest way to
a ZFS install, not because it is wanted for itself.

## What this means for new work

- When Omarchy and another vendor both offer a thing, prefer Omarchy's, unless
  taking it would put the ZFS root or ZFSBootMenu at risk.
- A guard that refuses an Omarchy choice says which of the two rules it
  protects. One that protects neither is a candidate for removal.
- Moving off a non-Omarchy dependency is done one at a time, each with its own
  decision. This ADR does not schedule any of them.

## Current dependencies outside the two rules

Recorded so they are visible, not because they are permanent:

- CachyOS as the base: `/etc/os-release` must say `cachyos`, and `[cachyos]`
  sits above `[omarchy]` in `pacman.conf`.
- CachyOS's Qt and other builds, which is why stable Omarchy cannot take a full
  upgrade while CachyOS ships Qt 6.12 (ADR 0003, track-omarchy-dev-on-edge).
- `linux-cachyos-zfs` as the fallback kernel's ZFS module (ADR 0008). This one
  serves the ZFS rule directly: a module that needs no DKMS build. Another
  vendor's packaged module would serve it equally well.

## Considered

- **CachyOS as a third hard rule.** It would make every CachyOS-specific guard
  permanent by default, which is the opposite of the direction wanted.
- **No hard rules, everything negotiable.** ZFS and ZFSBootMenu are what the
  rollback story rests on; treating them as negotiable would mean
  re-arguing them every time an Omarchy release touches the boot path.
