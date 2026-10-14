# The Omarchy package and channel are a fact about the box

`monarchy/omarchy.lock` is gone. Which Omarchy package a box runs (`omarchy`
or `omarchy-dev`) and which `[omarchy]` channel it takes it from (`stable`,
`rc`, `edge`) are read from the box: the package from what is installed, the
channel from the `Server` line of `[omarchy]` in `pacman.conf`. A fresh box
gets `omarchy` on `stable`. This replaces the lock half of ADR 0003
(track-omarchy-dev-on-edge); the reason for tracking edge on the box that
needed the Qt 6.12 fix still stands for that box.

## Why

The lock was repo-wide, so one box moving to edge moved every box. A box
still on stable that pulled the repo would, on its next update, build
`omarchy-settings-monarchy` from the stale `omarchy-dev` that the stable
channel also carries, try to swap `omarchy` for it, and then stop at the
channel check with the overlay half applied. The Monarchy changes themselves,
ZFS, packages, overlays, were never channel-specific; only the lock was.

Account identity is already treated this way (`AGENTS.md`, No names): a fact
about a machine, kept on the machine.

## Moving a box

Nothing moves a box by itself. Name the target in the environment once:

    MONARCHY_OMARCHY_PACKAGE=omarchy-dev MONARCHY_OMARCHY_CHANNEL=edge ./install.sh --only=pacman
    MONARCHY_OMARCHY_PACKAGE=omarchy-dev monarchy-update

The first rewrites the `[omarchy]` block; the second swaps the package. After
that both are read back from the box. Moving back is the same with
`omarchy` and `stable`. Migrations an edge build ran do not reverse (ADR 0003).

## One repo, several channels

The lists in `monarchy/` serve every channel at once, and a tagged release is
usually behind `omarchy-dev`:

- A `bin.deny`, `bin.wrap` or `bin.skip` row naming a binary the installed
  package does not ship stops the run only on `omarchy-dev`, which is
  upstream's leading edge. On a tagged release it is noted and kept.
- `migrations.deny` already marked only names the package ships.
- `packages.installed` in the repo is the union of what every channel has
  classified; `/var/lib/monarchy/packages.installed` is the box's own set.
- An overlay whose anchor differs between channels matches both forms, picked
  by what the package contains, not by a version number. The lock and power
  panel overlays do this today. A version gate is added only where content
  cannot tell the difference, and only when a real failure asks for it.

## Considered

- **Keep the lock, one per host in the repo.** A hostname in the repo is the
  kind of machine fact `AGENTS.md` keeps out, and it would still need editing
  in two places to move a box.
- **Keep the lock in `/etc/monarchy/`.** A second record of something
  `pacman.conf` and the package database already say, free to disagree with
  them.
- **Version gates on every overlay.** Most anchors are the same on both
  channels; gating them all is maintenance with nothing to show for it.

## Consequences

- `/etc/omarchy.lock` is removed at apply. Nothing read it.
- `omarchy-dev` on a channel other than edge warns: every channel carries one,
  but only edge keeps it current.
- A stale row can now sit unnoticed on a stable box. It is still caught on
  the first edge box that applies.
