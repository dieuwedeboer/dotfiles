# Plan: replace chezmoi with mise dotfiles

- **Status:** done, 2026-10-23. The record is `docs/adr/0011-mise-links-user-config.md`; where this plan and the ADR differ, the ADR is what shipped. Corrections found while implementing on mise 2026.10.17: history is `[settings] history.enabled`, the hook is `[bootstrap.hooks] post-dotfiles`, `CLAUDE.md` and the opencode `AGENTS.md` are relative links in `home/` (a `~` source is missing on a fresh box, and mise checks every source before writing), fold-back walks `home/` itself (`status --json` names only the first file per group), stale chezmoi copies are recognised by their committed blob, and the font hooks use `sed -i --follow-symlinks`. The Plasma dotfiles were dropped.
- **Audience:** whoever implements the switch, and whoever reviews the ADR that supersedes ADR 0001
- **Scope:** full conversion. chezmoi, its source tree, its hook and every reference to it go.

Every dotfile is deployed by `mise dot`, as a symlink into this checkout. Live
edits land in the git working tree. Nothing commits them except the king, by
hand. Everything else stays at mise's defaults unless a line below says why
not.

## Decisions

- **Links, not copies.** mise's default for a group is `symlink-each`: one link
  per file. An app or an Omarchy migration that edits a dotfile edits the
  checkout, and `git status` shows it. Commit it, or `git checkout` it away.
  This replaces chezmoi's overwrite prompt, which could be answered the wrong
  way, and the `chezmoi-drift` hook, which existed because chezmoi silently
  reverted migration edits.
- **mise never commits.** No `track` entries, no history watcher service, no
  `mise dot origin`. History recording is switched off (`history.enabled =
  false`), so mise keeps no git repository of its own either. The only commits
  are the king's.
- **No prompts anywhere.** `mise dot apply --yes` never asks. The TTY gate
  ADR 0001 built around `chezmoi apply` goes away for dotfiles. A menu-driven
  `omarchy-update` applies them like any other run.
- **Same accounts as today.** Dotfiles are applied for whoever runs
  `install.sh` or `monarchy-update`, which is the king. Other roles are out of
  scope (see Multi-user).

## Repo layout

`chezmoi/` becomes `home/`, a plain mirror of `$HOME` with real names.

| chezmoi today | mise |
| --- | --- |
| `dot_config/…`, `dot_local/…`, `dot_agents/…` | `.config/…`, `.local/…`, `.agents/…` (`dot_prefix` stays at its default, off) |
| `executable_<name>` | `<name>` with the executable bit set in git. A link carries the source's mode. |
| `symlink_apply-font-size.tmpl` ×3 under `.config/omarchy/hooks/*.d/` | A relative symlink committed in git, `../apply-font-size`. Deployed as a link to a link; it resolves inside the checkout. |
| `symlink_CLAUDE.md.tmpl`, `symlink_skills.tmpl`, opencode `symlink_AGENTS.md.tmpl` | Explicit `[dotfiles]` entries, e.g. `"~/.claude/CLAUDE.md" = { source = "~/.agents/AGENTS.md" }`. A git symlink cannot spell `~`. Tested on 2026.9.12. |
| `modify_settings.json` + `.chezmoitemplates/claude-settings.json` | `home/.claude/settings.json` holding only the owned keys, excluded from the group, plus a `merge = true` entry. See Claude settings. |
| `run_after_herdr-claude-integration.sh` | A `post-dotfiles` hook running the same three lines. |
| `dot_config/omarchy/hooks/post-update.d/executable_chezmoi-drift` | Replaced by `dotfiles-drift`. See Monarchy changes. |

The mise config itself lives at `mise/dotfiles.toml`, outside `home/`:

```toml
[dotfile_groups.home]
root = "."
exclude = [".claude/settings.json"]

[dotfiles]
"~/.claude/CLAUDE.md" = { source = "~/.agents/AGENTS.md" }
"~/.claude/skills" = { source = "~/.agents/skills" }
"~/.config/opencode/AGENTS.md" = { source = "~/.agents/AGENTS.md" }
"~/.claude/settings.json/monarchy" = { merge = true }

[history]
enabled = false

[hooks]
post-dotfiles = "…herdr integration check…"
```

Monarchy links it in as `~/.config/mise/conf.d/20-dotfiles.toml`. A global
config file needs no `mise trust`, and a repo-root `mise.toml` would make the
whole checkout a mise project for no gain.

Two departures from defaults, both forced:

- **`dotfiles.root`.** The default is `~/.dotfiles`; the checkout is wherever
  `install.sh` lives. Where the checkout sits is a fact about the box, so
  Monarchy writes it once with `mise settings set dotfiles.root
  "$DOTFILES_DIR/home"`. That goes into the king's `~/.config/mise/config.toml`,
  never the repo.
- **No relative `source` in `mise/dotfiles.toml`.** Tested on 2026.9.12: a
  relative source in a symlinked `conf.d` file resolves against the link's
  directory (`~/.config/mise/conf.d/../…`), not the repo. Group roots resolve
  against `dotfiles.root` and a merge entry without `source` reads
  `<dotfiles.root>/<target path>`, so neither needs one. Every other source is
  a `~` path.

## Claude settings

`home/.claude/settings.json` holds the five keys owned today: `attribution`,
`enabledPlugins`, `model`, `permissions`, `theme`. The `merge = true` entry
sets those keys in `~/.claude/settings.json` on every apply and leaves the rest
alone. That covers the herdr `SessionStart` hook and anything Claude Code adds
later. The file stays a regular file Claude Code can write, so nothing it
writes reaches the working tree. That matters because herdr's hook path names
the account.

- `/model` and `/config` changes to an owned key are reset on the next apply,
  exactly as today. To keep one, edit `home/.claude/settings.json` and commit.
- mise merges nested objects key by key and replaces arrays; chezmoi replaced
  each top-level key whole. A key Claude Code adds inside `permissions` now
  survives an apply. Nothing owned today depends on the old behaviour.
- A `settings.json` that does not parse is reported and never overwritten.
- `mise dot status` reports drift only in owned keys, so the drift hook's
  ignore list for this file goes away.

## Monarchy changes

`lib/household.sh`: `household_chezmoi` becomes `household_dotfiles`.

1. Require mise 2026.10.4 or later. Older: warn, skip dotfiles, carry on. Not
   a die; the live files from the last apply are still there.
2. Link `~/.config/mise/conf.d/20-dotfiles.toml` to `mise/dotfiles.toml` if it
   is not already that link. Set `dotfiles.root` if it differs.
3. **Fold back.** For each target `mise dot status --json` reports as
   `differs` because a regular file sits where the link should go, copy the
   live file over its source in `home/`. Tools that save by rename (`sed -i`,
   most editors, KConfig) replace a link with a regular file. Without this
   step, `--force` would throw their edit away. Fold-back writes to the
   working tree only and never commits. If that source already has
   uncommitted changes, stop and name both files rather than pick one.
4. `mise dot apply --yes --force`. Every conflict was folded back in step 3,
   so `--force` only replaces copies that are already in the working tree.
5. `mise dot status --missing`. Non-zero is a warning naming `mise dot status`.
6. If `git status --short home/` is not empty, list the files under `left
   alone`, so the run summary says there is something to commit or discard.

`lib/monarchy/user.sh`: `monarchy_assert_chezmoi_hypr` becomes an assert that
the four hypr files are links resolving into `home/.config/hypr/`. Missing or
not a link: run `household_dotfiles`, re-check, die naming `mise dot status`.
`monarchy_strip_marked_blocks` and the block-drift filtering go. The screens
plugin's `-- BEGIN im0001gt.screens` block is already committed in
`bindings.lua`, so a plugin rewrite shows up as an ordinary diff.
`MONARCHY_CHEZMOI_HYPR` is renamed and keeps its four names for
`monarchy_seed_hyprland_config`.

`monarchy_can_prompt` stays: `omarchy-update -y` and the `users.conf` path still
use it. Its comment loses the chezmoi rationale.

`dotfiles-drift` replaces `chezmoi-drift` in `post-update.d`. It runs straight
after `omarchy-migrate`, as now. It resolves its own path with `readlink -f` to
find the checkout, which a deployed copy could not do. It reports two things:
links a migration replaced with a file, and `git status --short home/`. It
keeps the critical notification, never repairs and never commits. The next
`household_dotfiles` folds the files back.

Paths and names:

- `lib/zfs.sh` and `monarchy_install_snapshot_helper` in
  `lib/monarchy/common.sh` read `home/.local/bin/zfs-snapshot-pre-update`.
- `lib/agents.sh` comments: "chezmoi" becomes "mise dotfiles".
- `lib/packages.sh`: drop `chezmoi` from `PACMAN_PACKAGES`. Remove the
  installed package once, in the unwanted-packages step.
- `install.sh` comments and `--help` text.

Tests:

- `tests/monarchy/test-entrypoints.sh`: `household_chezmoi` →
  `household_dotfiles`.
- `tests/monarchy/test-no-names.sh`: its comment names `chezmoi/` as the
  out-of-scope tree. It becomes `home/`; the scan list does not change.
- No new tests. A dotfile is not on the brick path: the hypr assert dies before
  Monarchy writes anything, as it does today.

## Cutover on a box

1. Update mise to 2026.10.4 or later.
2. Pull the branch.
3. `./install.sh --update` from a terminal. The pre-update ZFS snapshot is
   taken first, as on every update. The first `household_dotfiles` finds
   chezmoi's regular-file copies at every target and folds each one back.
4. `git diff home/`. Anything here is a live file that had drifted from the
   repo under chezmoi. Commit what is wanted, `git checkout` the rest, run
   `mise dot apply --yes --force` once more.
5. Remove `~/.local/share/chezmoi` (the symlink) and `~/.config/chezmoi/`
   (chezmoi's state). The package goes with the next update.

Rollback: `mise dot unapply`, reinstall chezmoi, `chezmoi apply` from the last
commit before the switch. Or roll the root dataset back to the pre-update
snapshot.

## Public-repo and multi-user safeguards

- Every app write to a linked dotfile is now one `git commit -a` from public.
  The run summary and `dotfiles-drift` list the files, and review is a `git
  diff`. `.claude/settings.json` is not linked for exactly this reason.
- `test-no-names.sh` does not scan `home/`, as it does not scan `chezmoi/`
  today. Whether it should is a separate question.
- `mise dot origin` and `mise dot sync` stay unused. With history off there is
  nothing for them to push.
- `dotfiles.root` points into the king's home, which other accounts cannot
  read. That matches today: chezmoi runs only for the king. A later per-role
  setup fits mise's groups: one `[dotfile_groups.<role>]` per role, each
  account selecting its groups in its own `~/.config/mise/config.local.toml`
  (`[bootstrap] dotfile_groups`), written by Monarchy from `users.conf`. Roles
  stay off the repo, as `CONTEXT.md` requires. Shared content would then need
  a checkout every account can read, not the king's.

## Risks and open questions

- [ ] **Churny files.** Plasma rewrites `kdeglobals`, `plasmarc`, `kded5rc` and
  `kdedefaults/*`. If those diffs are noise, demote them to `mode = "copy"`
  group entries, which revert on every apply. Start with links and decide on
  evidence.
- [ ] **Syntax for `[history]` and `[hooks] post-dotfiles`.** Taken from the
  docs, not tested: 2026.9.12 rejects `post-dotfiles` and the whole config
  stops parsing. An unknown key in a `conf.d` file breaks every mise command,
  including the shims for the coding agents. Test on the target mise before
  linking the file.
- [ ] **A merge entry without `source`.** Check that it reads
  `<dotfiles.root>/.claude/settings.json` and not another path.
- [ ] **mise's pace.** About 30 releases since 2026-09-01, and dotfiles
  behaviour changed in most of them. Read the changelog before each Omarchy
  mise bump until it settles.
- [ ] **Partial applies.** A runtime error partway through leaves earlier
  entries applied (seen on 2026.9.12). Conflicts are checked before anything
  is written; other errors are not. Re-running is the fix.

## Records

- New ADR, `docs/adr/0011-mise-links-user-config.md`, superseding 0001: links
  instead of copies, no prompt, fold-back instead of a TTY gate. Mark 0001
  superseded.
- ADR 0003 point 3 ("chezmoi front-loaded"): reword to dotfiles, same ordering.
- `README.md`, `docs/monarchy.md`, `docs/monarchy-install.md`,
  `docs/monarchy-clashes.md`: replace every chezmoi reference.
- A GitHub issue tracking this plan.
