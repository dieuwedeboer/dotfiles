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
