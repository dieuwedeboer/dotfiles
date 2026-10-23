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
2. **ZFS pre-update snapshot.** Everything that writes has a rollback point.
   The guards above it only read — they refuse by dying, having changed
   nothing — so the order between those two is a matter of failing fast, not
   of recoverability.
3. **Household refresh, dotfiles front-loaded.** A post-update hook Omarchy
   fires should find the dotfiles already linked (ADR 0011).
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
without reaching for upstream's — and it has to read a **refreshed** sync DB
to do it. Every version check in that step is a plain `pacman -Si`, and the
first `-Sy` in the flow is inside `omarchy-update-keyring`, which runs after.
Against a stale DB the check sees the release it already tracks, builds
nothing, and the upgrade then hits exactly the conflict this step exists to
prevent. `cachy-update` used to keep the DB fresh as a side effect of owning
`-Syu`; this decision took that away, so `update-pre` runs `pacman -Sy` of its
own first. `monarchy_ensure_settings_pkg` already did
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
- **`omarchy-update-restart`** is held back, not dropped: it runs from
  `monarchy_after_omarchy_update` once the overlay is rebuilt. Where upstream
  puts it, its reboot prompt offers to reboot into a tree monarchy has not
  re-applied to — the session `Exec=` and the greeter would still be the old
  one — and its shell restart would land on stock QML and be repeated. It
  carries the kernel-updated, reboot-required and Hyprland-updated prompts
  and the `restart-*-required` sweep, none of which monarchy has an
  equivalent for, and which matter more now that this decision makes kernel
  upgrades part of the flow.

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

**A failure in Omarchy's update does not skip the re-apply.** Six fallible
steps sit between the upgrade and the end of that command — the AUR pass,
mise, the orphan sweep. Letting any of them end the run leaves the worst
state this flow can produce: a new package tree with monarchy's overlay, the
session `NoDisplay` and the greeter still belonging to the old one. The
status is captured and reported; the re-apply runs either way.

**`update-pre` prepares only when the upgrade will actually follow.**
`--only` and `--no-omarchy-update` still take the guards and the snapshot,
but not the package build: building against a release bump with no upgrade
behind it leaves `omarchy` with an unsatisfied `omarchy-settings` pin, and
`MONARCHY_EXPECT_FULL_UPGRADE` would have turned the guard that says so into
a note.

**The blast radius is larger than it was.** A run now performs a full system
upgrade where before it installed filtered leaves. The snapshot at step 2 is
what that is traded against, and it is taken before the household refresh
rather than after.

## Amendment, 14 October 2026: the source-root check

From r6975, `omarchy-update`, `omarchy-update-stay-awake` and
`omarchy-channel-set` refuse to run unless the command really is
`$OMARCHY_PATH/bin/<name>`, and `omarchy-update` sets `PATH` to
`$OMARCHY_PATH/bin` first. The overlay's mirrored symlinks fail that check,
and the overlay's `omarchy-update` is the wrap that leads here.

The decision stands; how it is reached changes. The overlay copies, rather
than links, every command that makes the check, found by grep at each
rebuild. Step 5 runs `omarchy-update` from `/usr/local/share/omarchy-update`,
rebuilt each run: links into the working prefix, plus a copy of the overlay
`bin/` holding a real `omarchy-update`. With `OMARCHY_PATH` pointing there,
the check passes and its children still resolve through `bin.skip` and the
wraps. This works around upstream's hardening rather than with it. The files
are root-owned, so it does not open what the check guards against: an
environment variable pointing Omarchy at other code. If upstream tightens the
check further, revisit running stock `omarchy-update` with
`OMARCHY_PATH=/usr/share/omarchy`.
