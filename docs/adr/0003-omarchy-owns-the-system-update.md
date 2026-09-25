# Omarchy's update runs; monarchy brackets it

`omarchy-update` runs in full, as upstream wrote it. Monarchy goes before and
after it rather than instead of it, and `omarchy update` owns `pacman -Syu`.

## What this replaces

The overlay wrapped `omarchy-update` onto `monarchy-update` and stopped there,
so the entire command was gone: the free-space check, the cache prune, the
keyring refresh, the AUR pass, the mise pass, the orphan sweep, the log
analysis, `omarchy-update-restart`, and `omarchy-update-status` — which is the
only thing that tells the bar's system-update widget there is anything to
report. That widget had been silent for as long as the wrap existed.

Monarchy wanted three specific things from that flow — dotfiles applied before
it, the bootloader left alone, and the overlay rebuilt after it — and paid for
them by removing all of it. That is too heavy a departure for what is being
protected.

ADR 0001's rule for `~/.config/hypr` is the same shape, and this follows it:
be the thing that asserts and brackets, not the thing that replaces.

## The order, and why each part is where it is

1. **Guards.** A host this overlay must never touch is refused while nothing
   has changed. `--only` cannot skip them.
2. **ZFS pre-update snapshot.** Everything after it has a rollback point.
3. **Household refresh, chezmoi front-loaded.** A template that reads a
   package version should see the one the box is about to run, and a
   post-update hook Omarchy fires should find chezmoi already applied.
4. **Prepare the local packages.** See the hazard below. This is the step
   that cannot move.
5. **The real `omarchy-update`,** by absolute path out of the package tree.
   Its children still resolve through the overlay, which is how `bin.skip`
   and the ZFS `omarchy-snapshot` take effect.
6. **Classify, then apply.** The upgrade replaced `/usr/share/omarchy` and
   `hyprland.desktop`; without this the overlay and the session `NoDisplay`
   are gone.
7. **`omarchy-migrate`, then `omarchy-update-status`.** Held back from step 5;
   see `bin.skip`.

## The hazard that fixes step 4 in place

`omarchy` depends on `omarchy-settings=<exact>`. Our replacement,
`omarchy-settings-monarchy`, provides that name at the version it was built
for. When upstream releases 4.0.5 and we still provide 4.0.4, a
`pacman -Syu --noconfirm` resolves the new dependency by pulling upstream's
`omarchy-settings`, which conflicts with ours, which `--noconfirm` answers by
replacing it — and upstream's `post_install` does `rm -f /etc/os-release` and
overwrites `nsswitch.conf`. That is a box nobody logs in to, arrived at by
answering yes to a question nobody was asked.

Building ours to the new version *first* is what makes the upgrade resolve
without reaching for upstream's. `monarchy_ensure_settings_pkg` already did
exactly this and then stopped, telling the operator to run a full upgrade and
come back. In this flow that upgrade is the next step, so
`MONARCHY_EXPECT_FULL_UPGRADE=1` turns that stop into a note and carries on.
The same flag covers `monarchy_ensure_omarchy_pkg`, which hands off for the
same reason.

## bin.skip

A third answer next to deny and wrap. `bin.deny` is "nothing should ever call
this, and if something does, say so" — it exits 2. `bin.wrap` is "this has to
behave differently here". `bin.skip` is "upstream is right to call this, and
here it has nothing to do" — it exits 0 and says nothing.

The category exists because `omarchy-update` runs under `set -e`: a name in
its ordinary flow that refuses loudly takes the whole system update with it.
Three rows, each with its reason in the file. Two matter:

- **`omarchy-migrate`** runs directly after the upgrade that ships a
  migration, which is before monarchy has classified it against
  `migrations.deny` or written the marker that keeps a denied one out of
  `--pending`. Monarchy runs the real one itself, after classification.
- **`omarchy-update-restart`** would bring the shell back holding stock QML —
  no switch-user on the lock screen, an unpatched power panel — before the
  overlay has been rebuilt over it, and it would be restarted again moments
  later. `monarchy_restart_shell` does this once, at the end of apply.

## Consequences

**`cachy-update` no longer owns `-Syu`.** `lib/monarchy/pacman.sh` said so and
now says `omarchy update` instead. The practical loss is CachyOS's mirror
ranking and its pre/post update tasks; the practical gain is one update
command instead of two, which is what upstream intended. `cachy-update` still
works by hand and `monarchy_refuse_partial_upgrade` still names both.

**A menu-driven update passes `-y`.** The Omarchy menu wrap-execs with no
terminal and `omarchy-update-confirm` would wait on an answer nobody can give.
`-y` is upstream's own promise not to ask anything.

**`--no-omarchy-update` exists** for iterating on monarchy without a full
`-Syu` in the middle.

**The blast radius is larger than it was.** A run now performs a full system
upgrade where before it installed filtered leaves. The snapshot at step 2 is
what that is traded against, and it is taken before the household refresh
rather than after.
