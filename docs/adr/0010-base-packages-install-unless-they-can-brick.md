# Omarchy's base packages install unless they can brick this host

Every row of Omarchy's `install/omarchy-base.packages` is installed unless
`monarchy/packages.deny` names it. A row is held back for a human only when
its name sits on a brick path, and then it is classified once, into
`packages.deny` or `packages.allow`, with its reason. This is ADR 0005's rule
for migrations, applied to packages. `monarchy/packages.installed` is gone.

## What this replaces

`packages.installed` was apply's record of the filtered base list, written
back into the repo. Any base row not in it, or in `packages.deny`, stopped the
next update until someone added it. That made every upstream addition a
manual step, even though nearly all of them are wanted, and with boxes on
different channels (ADR 0009) a stable box and an edge box rewrote each
other's copy.

## Why a deny list alone is not enough

A dependency on a denied package does not stop a new row: `monarchy-boot-stub`
provides `limine` and `snapper`, so anything depending on them resolves. The
rows that could do harm are the ones that need nothing denied: a second
display manager, a kernel, a power daemon that fights CachyOS's, a ZFS package
from another vendor.

## The rule

`monarchy_package_hazard` in `lib/monarchy/migrate.sh` names the brick paths:

- kernels (`linux`, `linux-*`, not firmware or API headers)
- boot loaders and initramfs generators
- snapshot tools
- ZFS packages
- display managers
- Omarchy's own package and settings variants
- power daemons

It is names, not judgement, so it runs on every update, and every hold says
which path it matched. Migrations use the same function for the packages
they install, so there is one set of names.

Plymouth is not on the list: the splash unit owns it.

## Consequences

- `packages.allow` holds rows that match a brick path and are wanted. Today
  that is `sddm`, Monarchy's greeter.
- A plain conflict between a new base row and a CachyOS package is not caught
  by name. It stops that apply in pacman instead, which is visible and fixed
  the same way: a `packages.deny` row.
- `/var/lib/monarchy/packages.installed` stays: it is this box's own record
  of what apply installed.
