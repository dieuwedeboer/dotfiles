# Apply seeds; it does not switch back on what was switched off here

Monarchy apply may turn on a thing that has never been on. It may not turn
back on a thing that was on and is now off.

The repo declares what a role gets when it gets it. It does not declare what
the person at the keyboard must keep. Which bar widgets, which background
services and which optional applications this account wants are facts about
the account, in the same way that who is king is a fact about a machine and
lives in `/etc/monarchy/users.conf` rather than here. An apply that re-imposes
them is not enforcing a standard; it is overruling a decision it has no record
of, on a box it does not know the history of.

## What went wrong

`monarchy/plugins` carries `--enable` on six rows, and
`monarchy_install_plugins` ran the enable step on every apply rather than on
the apply that cloned the plugin. `omarchy plugin disable <id>` keeps no
"disabled" record — it removes the row from `shell.json`, and absence *is*
disabled — so the enable could not tell "never enabled" from "switched off on
purpose". Two widgets that had been turned off came back on every update, and
nobody noticed for three of them, because a re-placed widget is one log line
in a run that prints two hundred.

The same file already knew better about placement. `monarchy_shell_json_place_widget`
leaves a widget that is anywhere in the bar exactly where it is, settings
included, on the stated grounds that an apply must not undo a hand placement.
This decision extends that from where a widget sits to whether it is there at
all, and to the two other places with the same shape.

## The three call sites, and the marker each one uses

A seeding needs a marker: something on disk that says the seeding has already
happened, distinct from the thing being seeded. Where a natural marker exists,
it is used and no state is written.

| What | Marker |
| --- | --- |
| Shell plugins | the plugin directory under `~/.config/omarchy/plugins/<id>` |
| Hyprland config, branding | the destination file (`monarchy_copy_if_missing`) |
| systemd `--user` units | the seed ledger, for units this box already has |
| `omarchy-pkg-add` packages | the seed ledger, or the package being installed |

`systemctl --user is-enabled` answers `disabled` both for a unit the operator
turned off and for one that has never been on. An absent package was either
never installed or removed on purpose. Neither state on disk distinguishes the
two, so for those two the ledger is the marker:
`~/.local/state/monarchy/seeded/{units,pkg}/<name>`, alongside the migration
markers Omarchy keeps in `~/.local/state/omarchy/`.

## Consequences

**A gap is accepted.** Adding `--enable` to a row whose plugin is already
cloned has no effect, because the directory already says seeded. The
alternative is a fourth ledger for a case that arises about once a year, and
`omarchy plugin enable <id>` costs one command.

**A marker is written only once the thing it marks is true.** This is what
makes the gap above the only one. The plugin is enabled from its staging
directory and moved into place afterwards, so an enable that dies — a plugin
that replaces the whole bar, a jq failure, an interrupted run — leaves no
directory and the next apply tries again. The ledger bootstrap marks only
units this box actually has, so a unit a later Omarchy release ships still
gets its one seeding when it arrives.

**One thing cannot be verified, and the report says so.** An absent package
was either removed on purpose or is one whose install has been failing, and
pacman keeps no record of which. The ledger marks it either way, because not
marking it re-imposes the removal this decision exists to respect. So the
summary claims only that the package is not installed, and names the command
to add it — never that somebody removed it.

**Deleting a row from `monarchy/plugins` stops nothing already installed.**
The row still asserts that the plugin is cloned, so removal is two steps: drop
the row, then `omarchy plugin remove <id>`. This is the one thing the repo
does still enforce, and it is enforced because a plugin that is present but
switched off costs nothing, while a plugin that silently vanishes from a
household box is a support call.

**An established box is recorded as seeded without being acted on.**
`monarchy_seed_ledger_bootstrap` writes markers for everything the ledger
governs when the ledger is absent and Omarchy's `first-run-user` marker is
present. Without it, the first apply after this change would get one last
unwanted re-impose — the disabled unit switched back on, the removed package
reinstalled — and only then start behaving. A unit or package that is not in
`MONARCHY_SEEDED_UNITS` or `MONARCHY_SEEDED_PKGS` gets no bootstrap marker, so
one a later Omarchy release adds still gets its single seeding when it arrives.

**A decision not to act is now an outcome, not silence.** Each of these sites
reports through `monarchy_left_alone`, and the run ends with a summary that
lists what changed, what was left alone and what warned. This is the half of
the problem that was not about plugins at all: silence read identically
whether monarchy had looked at something and declined, or never looked.

**This does not extend to the bricking surface.** Guards, the overlay, the
session `Exec=`, the greeter and the lock PAM are re-imposed on every apply and
must stay that way. The rule here is about preferences — a widget, a
background service, an optional application — where the worst case of honouring
a local decision is that someone has to run one command. Where the worst case
is a machine nobody can log into, the repo wins. See `CONTEXT.md` on bricking.
