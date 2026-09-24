# AGENTS.md

Monarchy — repeatable system setup for Arch Linux (CachyOS with ZFS) running
Omarchy. See `README.md` for installation and `docs/monarchy.md` for how the
Omarchy overlay is put together.

## No names

Do not add a person's username or name to this repo. Not in `lib/`, not in
`monarchy/`, not in `docs/`, not in comments, not in examples.

Account identity is a fact about a machine, not about this repo. Roles live in
`/etc/monarchy/users.conf` on each box; the repo holds only what each role gets.
See `CONTEXT.md` for the roles.

This keeps usernames free to change without breaking anything, lets someone fork
the repo without inheriting a stranger's household, and keeps personal
information out of a public repository. Names already in git history are a
separate matter and are not in scope.

Use `king`, `queen`, `kid`, `serf` in examples and placeholders.

## Coding standards

`CODING_STANDARDS.md` at the repo root. It governs what is worth a test — the
bar is "could this leave someone stranded, or is it irreversible?" — and
forbids tests that grep a source file or assert that a string is absent.

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues, via the `gh` CLI.
See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles, each label string equal to its name.
See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repo root.
See `docs/agents/domain.md`.

### Moving to a new Omarchy release

Monarchy tracks the official `omarchy` package from the `[omarchy]` repository,
channel stable — not a fork, not a clone, not a git commit. `monarchy/omarchy.lock`
records which package and channel. There is no pin to bump. `monarchy-update` rebuilds the two local packages in
`pkgbuilds/`, installs the current `omarchy` from `[omarchy]` stable, and halts
if a new binary or migration touches Limine, snapper or `pacman.conf` without
being classified into `monarchy/bin.deny`, `monarchy/bin.wrap` or
`monarchy/migrations.deny`. Classifying it is a human call.

A row in `migrations.deny` is then enforced, not just recorded: the `user` unit
marks it complete under `~/.local/state/omarchy/migrations/` so `omarchy-migrate`
stops offering it. Only names the package still ships are marked, so a row that
has gone stale stays visible to the classification guard.
