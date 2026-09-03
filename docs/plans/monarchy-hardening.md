# Plan: Monarchy hardening

- **Status:** plan. Agreed 2026-09-03, not started. Uncommitted by request.
- **Audience:** whoever works the sequence below, in order.
- **Constraint:** no canary box and no snapshot headroom. `KEEP=3` and a
  15-minute dedup window in `zfs-snapshot-pre-update` stay as they are, so
  iterating by running apply burns the rollback. Verification happens in
  `tests/` and `--check`, which write nothing.

Seven findings from an architectural review, resequenced so nothing on the
bricking surface moves before the tests that cover it exist. `brick` is defined
in `CONTEXT.md` and is the sole criterion for whether behaviour is tested.

## Sequence

| # | Work | Risk | Covered by |
| --- | --- | --- | --- |
| 0 | Dead code, docs name scrub | None | — |
| 1 | Revive tests into `tests/` | None | — |
| 2 | Inventory guards in `monarchy_apply` | Low | `test-overlay.sh` |
| 3 | Collapse privilege dispatch in `overlay.sh` | Bricking | `test-overlay.sh` |
| 4 | Marker blocks for seeders | Low | `test-user.sh` |
| 5 | chezmoi owns `~/.config/hypr` | Low, every box | `test-user.sh` |
| 6 | Roles and `users.conf` | Bricking | `test-sddm.sh`, no-names |
| 7 | Unit list with check/apply verbs | Highest | whole suite |

### 0. Dead code and docs scrub

Delete `monarchy_migration_denied` (`lib/monarchy/update.sh:3`). It is never
called — `monarchy_check_migrations` reimplements it inline — and its logic is
wrong: the outer condition matches `/etc/os-release` or `nvidia-dkms`, but the
only route to a "denied" return is a second match on limine/pacman, so an
os-release-clobbering migration falls through to allowed.

Delete the `set -a` / `set +a` pair and its orphaned `# shellcheck disable=SC1090`
at `lib/monarchy/common.sh:49-51`. Nothing sits between them; it is left over
from when the lock was sourced rather than parsed.

Remove personal names from prose. Known sites: `docs/monarchy-install.md:94`,
`docs/monarchy.md:233`, `docs/monarchy.md:247`, plus the author references
throughout `docs/plans/themes.md` and `docs/plans/zbook-fingerprint.md`. Since
nothing is grandfathered in step 6, every one of these must go or the no-names
test fails. Rewrite them by role — "the king", "the machine's king" — not by
name. Code sites wait for step 6.

### 1. Revive the tests

Fourteen test files, 1,588 lines, were deleted as collateral in `8fcaa34`, the
`scripts/` to `lib/` restructure. Recover each with
`git show 8fcaa34^:scripts/lib/<path>`.

They are not unit tests. They run the real functions against temp prefixes
through seams that still exist — `MONARCHY_SRC`, `MONARCHY_PATH`,
`MONARCHY_INSTALL_SUDO_STUBS=0`, `MONARCHY_LOG`, `ZBOOK_DMI`. Every header says
"No sudo". `MONARCHY_INSTALL_SUDO_STUBS` still sits at `lib/monarchy/overlay.sh:76`
as a seam with nothing using it.

```text
tests/
├── run.sh                  # every tests/**/test-*.sh, then shellcheck
├── monarchy/test-*.sh
├── zbm/test-boot.sh
└── hardware/test-detect.sh
```

Plain bash, no bats. Fixtures are built inline with `mktemp -d`, so nothing
needs committing alongside. Fix the `scripts/lib/...` source paths and the
`setup-monarchy` to `monarchy-update` rename. Drop assertions about behaviour
that has genuinely changed; keep the rest.

Judge each test against the `brick` definition. `test-sddm.sh`,
`test-sddm-resume.sh`, `test-switch-user.sh`, `test-lock.sh`, `test-overlay.sh`
and `test-splash.sh` cover the bricking surface. `test-branding.sh` and
`test-version.sh` do not — a wrong version string is broken, not bricking.

`tests/run.sh` is the gate to run before any apply.

### 2. Inventory guards in apply

`monarchy_apply` never calls `monarchy_check_inventory_complete` or
`monarchy_check_clone_bin_classified`, and `monarchy_rebuild_overlay`
(`update.sh:156`) runs before `monarchy_add_omarchy_repo` (`:160`), so the
overlay is rebuilt from a possibly-unclassified clone before any guard fires.
Call both at the top of `monarchy_apply`, before `monarchy_sync_omarchy_clone`.

The review originally claimed apply also omits `monarchy_refuse_archzfs`,
`monarchy_refuse_omarchy_zfs_repo`, `monarchy_preserve_pacman_conf` and
`monarchy_refuse_partial_upgrade`. That was wrong. All four are reached
indirectly — the first three inside `monarchy_add_omarchy_repo`
(`pacman.sh:160-161`), the fourth inside `monarchy_install_packages`
(`packages.sh:57`). Only the two inventory guards are genuinely absent.

`test-overlay.sh` already called both, so this defect is downstream of the test
deletion in step 1.

### 3. Privilege dispatch

`monarchy_rebuild_overlay` writes its deny/allow/wrap loop twice, once plain and
once behind `monarchy_sudo`. `monarchy_explode_symlink_dir`,
`monarchy_overlay_replace_dir` and `monarchy_overlay_replace_file` repeat the
same if/else. Roughly 50 lines of parallel logic that can drift.

```bash
# Run a command, elevating only if the destination's parent is not writable.
monarchy_write_to() {
    local dir=$1; shift
    if [ -w "$dir" ]; then "$@"; else monarchy_sudo "$@"; fi
}
```

### 4. Marker blocks

Every `monarchy_seed_*` in `lib/monarchy/user.sh` appends to a user file and
detects prior state by grepping for an exact literal. `pacman.sh:155` already
has the right pattern — a `# BEGIN monarchy-omarchy` / `# END` block replaced in
place. Wrap the seeders in the same shape. This lands before step 5 so the
seeders are removable without leaving orphaned appends in files already on disk.

### 5. chezmoi owns the hypr config

See `docs/adr/0001-chezmoi-owns-user-config.md`. Remove the seeders from
`monarchy_setup_user`; replace with a `chezmoi status ~/.config/hypr` check that
dies naming the command to run. Missing and drifted fail identically.

### 6. Roles and users.conf

Four roles, defined in `CONTEXT.md`: king (one), queen (one), kid (many), serf
(many). Membership lives in `/etc/monarchy/users.conf`, two columns,
`username role`, never committed. The repo ships `monarchy/users.conf.example`
with placeholder usernames. An account absent from the file is a serf; that is a
valid state, not an error, and nothing is done to serfs beyond the defaults.

Session preference is a separate field from role. Default is Omarchy; queen and
kid are overridden to Plasma; king and serf take the default.

UIDs were considered and rejected. They are allocated sequentially in account
creation order from `UID_MIN` 1000, so a repo-committed UID map would misassign
roles on any machine built in a different order — a child account silently
holding adult rules. Usernames on a machine are harmless;
only usernames in the repo are the problem. Groups were also considered and
deferred: the `family` group is for shared directories, a different problem from
session and rule policy, and does not exist on this box yet.

`monarchy/sddm/Main.qml:134` hardcodes two names in `prefersPlasma()`. QML cannot
read `getent`, so apply enumerates `users.conf` and generates the override list
the greeter reads. **Unverified:** what the SDDM theme can read at greeter
privilege. Establish that before fixing the file format.

Write the no-names test first in this step, watch it fail, then make it pass.
It reads the usernames from `/etc/monarchy/users.conf` and greps `lib/`,
`monarchy/` and `tests/` for each. The test itself contains no names, so it works
in a fork without knowing who lives there. Nothing is grandfathered.

### 7. Unit list

Replace the two hand-maintained linear lists in `monarchy_check` and
`monarchy_apply` with one ordered array and per-unit `check` / `apply` verbs.

```bash
MONARCHY_UNITS=(guards pacman clone overlay settings sddm session logind portals user splash)
```

Check can no longer fall behind apply, the ordering constraint becomes readable
rather than tacit, and `--only=<unit>` shrinks the blast radius of an iteration
from twenty subsystems to one — which is what makes it worth doing at all, given
there is no canary box and no snapshot headroom. It goes last because it
rewrites the two functions whose failure modes are worst, and it should happen
with the suite green on both sides.

## Not doing

- Raising `KEEP` or adding a held snapshot. Declined; the helper stays as is.
- Rewriting git history to remove names already published. Scrubbing `HEAD`
  limits future exposure and does not undo past exposure. A separate decision.
- bats, or any test framework.
- Grandfathering any existing name in the no-names test.
