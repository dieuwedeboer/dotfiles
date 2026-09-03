# Plan: Monarchy hardening

- **Status:** the seven steps are implemented, `605370e..d5d7209`, 2026-09-03.
  What remains is in [Still open](#still-open). Uncommitted by request.
- **Audience:** whoever picks up the open items.
- **Constraint, unchanged:** no canary box, and `zfs-snapshot-pre-update` keeps
  three snapshots with a 15-minute dedup window, so repeated applies burn the
  rollback. `./tests/run.sh` and `./install.sh --check` write nothing and are
  the cheap gates. `--only=<unit>` now shrinks a real apply to one subsystem.

Originating review: seven findings against `lib/monarchy/`. `brick` in
`CONTEXT.md` is the criterion for whether behaviour is tested. How the overlay
works now is `docs/monarchy.md`; this file is only the plan's own record.

## What shipped

| # | Work | Commits |
| --- | --- | --- |
| 0 | Dead code, docs name scrub | `605370e` |
| 1 | shellcheck-clean, then 9 tests revived into `tests/` | `068ad3d` `c733e69` |
| 2 | Inventory guards reach `monarchy_apply` | `3bc5192` |
| 3 | Privilege dispatch collapsed, −58 lines | `ff4c097` |
| 4 | Marked, replaceable seed blocks | `5cb3ad8` |
| 5 | chezmoi owns `~/.config/hypr`; monarchy asserts | `f975725` |
| 6 | Roles in `/etc/monarchy/users.conf`; no names in code | `6cde27f` |
| 7 | One ordered unit list, `--only=<unit>` | `3e0bbfc` |

Fixes to the above, found by review or by testing rather than by reading:
`bac43b6` (the ordering test failed without saying why), `6243a9b` (the test
revival reintroduced names into a public repo), `3dbe817` (two clone-dependent
tests passed while asserting nothing), `b208a96` (`seed_block` tightened file
modes to 600 and its unanchored patterns ate user lines), `1cda2f3` (the assert
read an unmanaged chezmoi as clean, and the release path deleted user content
past a truncated marker), `e7dc8c2` (apply verified before it acted, which
aborted both a fresh box and a converting box), `d5d7209` (`--only` skipped
every host guard; a quote in a username would have produced an unparseable
greeter; a CRLF `users.conf` silently moved the whole household to Omarchy; and
those warnings went to stdout, which both callers read as data).

## Where this deviated from the plan as written

**Step 2 placement.** The plan said put the inventory guards "at the top of
`monarchy_apply`, before `monarchy_sync_omarchy_clone`". Both read
`$MONARCHY_SRC/bin`, which does not exist until the clone is synced, so that
would abort every first install. They sit immediately after the sync and before
anything is built from the clone. Confirmed independently in review.

**Step 6 greeter mechanism.** The plan left open "what the SDDM theme can read
at greeter privilege". It reads nothing: the theme's only file references are
image sources. Rather than add a runtime read on the login path, apply
generates the list into the deployed `Main.qml`, the way `overlay-lock.py`
already patches the lock QML. The repo copy ships an empty list. That closes
the question without needing a live greeter to test.

**Step 1 scope.** Nine of the fourteen recovered tests were kept. Branding,
version, settings, logind and battery-rate are not bricking by the `CONTEXT.md`
definition and stay in `8fcaa34^`. An unplanned commit, `068ad3d`, came first:
shellcheck found three real defects in `lib/`, so the tree had to be clean
before shellcheck could join the gate.

**Step 5, and then the reverse.** The plan and ADR 0001 said monarchy must
never invoke `chezmoi apply`, because it prompts and `omarchy-update` reaches
the code from the Omarchy menu with no terminal. That was too broad: an
interactive `./install.sh` has a terminal, and printing a command for the
operator to paste back was busywork. `916037f` gates on `monarchy_can_prompt`
instead — fix it when someone can answer, report and stop when nobody can. The
same gate offers `monarchy-user-setup` when `/etc/monarchy/users.conf` is
missing.

**Steps 4 and 5, the release path.** Step 4's stated purpose was to make the
appends removable in step 5. They were removable, and then the removal itself
was deleted: `chezmoi apply` overwrites the file and drops the blocks anyway, so
a monarchy that edits the file to tidy up is still a monarchy that writes there.
The markers earned their place on idempotence alone.

**Step 5 scope.** chezmoi owns four files, not the whole directory.
`hyprland.lua` and `boot-color.lua` stay monarchy's: they are overlay assets
from the pinned clone, not personal config.

**Step 7 ordering.** Apply runs each unit's apply and *then* its check. A
unit's check is a postcondition. Checking first aborted every fresh box
(`monarchy_check_hidden_hyprland_sessions` needs the `NoDisplay` that
`monarchy_install_omarchy_session` writes) and every converting box
(`monarchy_assert_sddm_runtime` refuses the `plasma-login-manager` that
`monarchy_keep_sddm` removes).

## Still open

### 1. No apply and no greeter round-trip yet

The two provisioning steps are done on this box, observed 2026-09-03:
`/etc/monarchy/users.conf` exists with a king, a queen and a kid, and
`chezmoi status ~/.config/hypr` is clean, so `monarchy_assert_chezmoi_hypr`
passes and `monarchy_plasma_users` resolves the queen and the kid. The
no-names test now runs against real names and reports clean.

Since `916037f` an interactive run repairs both by itself: a drifted
`~/.config/hypr` gets `chezmoi apply`, and a missing `users.conf` gets
`monarchy-user-setup`. A menu-driven `omarchy-update` still reports and stops.

What has not happened is an apply. The suite drives the real functions against
temp prefixes; a fixture is not a login screen, and steps 5, 6 and 7 all
changed the login path.

```bash
./tests/run.sh                  # must be green first
./install.sh --check            # dry run; --only=<unit> narrows it
./install.sh --only=sddm        # smallest real change to the greeter
```

Then log out and back in: pick a user with Tab, a session with Up/Down, confirm
the queen and the kid land on Plasma and the king on Omarchy, and confirm
Super+Ctrl+U reaches the greeter from a locked session. That last one is the
path that has hard-crashed a host before.

### 2. The gate depends on a tool the repo does not install

`tests/run.sh` runs shellcheck and skips that arm when it is absent, so the
gate silently weakens on a box without it. It was installed here with
`mise use -g shellcheck`, which writes `~/.config/mise/config.toml` — not
chezmoi-managed, so that is machine-local state the repo does not capture.

Decide one: add `shellcheck` to `PACMAN_PACKAGES` in `lib/packages.sh`; or put
mise's global config under chezmoi; or make `run.sh` fail rather than skip.

### 3. No CI

Q3 settled on shellcheck-in-CI, and what shipped was shellcheck-in-`run.sh`.
There is still no `.github/`. Measured rather than assumed: with
`MONARCHY_SRC=/nonexistent`, seven tests produce byte-identical output and so
assert exactly as much without a clone — `test-user`, `test-splash`,
`test-units`, `test-sddm-resume`, `test-no-names`, `hardware/test-detect`,
`zbm/test-boot`. Those seven plus shellcheck are safe on a plain runner.

`test-sddm` also exits 0 without a clone but skips its whole
`monarchy_refresh_sddm` block, so in CI it would pass while testing less than
it appears to. Either give it the same `require_clone` treatment as
`test-lock`, `test-overlay` and `test-switch-user`, or split the clone-dependent
half out. The remaining three already hard-require a clone and would fail
honestly.

`test-no-names` is a special case: it is a no-op without `/etc/monarchy/users.conf`,
which a CI runner will not have. It cannot enforce the rule in CI, only locally.

### 4. The lock carries two keys nothing reads

`monarchy_load_lock` parses `hyprland` and `quickshell` from
`monarchy/omarchy.lock`, both empty, and no code consumes either. `068ad3d`
marked them rather than deleting them, because whether the lock format should
still offer those keys is a decision about the format, not a lint fix. Either
drop the parsing and the keys, or record what is supposed to read them.

### 5. A per-account keyboard preference has nowhere to go

The old `monarchy_seed_capslock` left a `kb_options` the user had customised
alone. chezmoi's `input.lua` now sets `caps:capslock` unconditionally for
everyone it is applied to. Noted in the ADR. If a queen or a kid ever wants a
different keyboard layout, that needs a per-account answer.

### 6. Five tests were dropped on a judgement call

Branding, version, settings, logind and battery-rate. All in `8fcaa34^`. If the
`brick` definition in `CONTEXT.md` changes, revisit.

## Not doing

- Raising `KEEP` or holding a snapshot. Declined; the helper stays as is.
- Rewriting git history to remove names already published. Scrubbing `HEAD`
  limits future exposure and does not undo past exposure. A separate decision.
- bats, or any test framework.
- Grandfathering any existing name in the no-names test.
