# mise links every dotfile into the checkout; nothing commits but the king

Supersedes ADR 0001.

Every file in `home/` is deployed by `mise dot` as a symlink into this
checkout. `mise/dotfiles.toml` declares one group over `home/`, linked in as
`~/.config/mise/conf.d/20-dotfiles.toml`; `dotfiles.root` points at the
checkout's `home/` and is written into the king's own mise config, because
where the checkout sits is a fact about the box. `household_dotfiles` in
`lib/household.sh` is the one place that applies them, on every install and
every update.

A live edit is therefore an edit to the working tree. `git status` shows it,
and the king commits it or `git checkout`s it away. mise's history is off and
it never commits; there is no origin and no sync.

## What this replaces

chezmoi copied files. A copy edited in place — by an app, by an Omarchy
migration, by a hook — was silently reverted by the next `chezmoi apply`;
that is how foot dropped from 12pt back to 9pt, and how a migration left
`alacritty.toml` unparseable for days. `chezmoi-drift` existed only to notice
that before it happened. And `chezmoi apply` prompts on a modified target, so
ADR 0001 built a TTY gate around it: apply with a terminal, report and die
without one. A menu-driven `omarchy-update` could not refresh dotfiles at all.

## The rules

- **No prompt anywhere.** `mise dot apply --yes --force`. The menu path
  applies dotfiles like any other run, so `monarchy_can_prompt` no longer
  guards them.
- **Fold back before forcing.** A tool that saves by rename (`sed -i`, most
  editors) swaps a link for a regular file. `--force` would discard it, so
  `household_dotfiles` first copies any live file that differs from its
  source over that source. Content the repo has committed before is a stale
  copy, not an edit, and is linked over without folding: that is every
  chezmoi copy on a box whose checkout has been pulled since its last apply.
  When the live file and its source both have uncommitted changes, nothing
  is picked: the step warns, names the file and applies nothing.
- **Hooks edit through the link.** The `font-size.d` and `alpha.d` hooks use
  `sed -i --follow-symlinks`, because they run on every boot and would
  otherwise break three links each time.
- **`~/.claude/settings.json` is merged, not linked.** Claude Code rewrites it
  and herdr's hook path names the account; linked, every one of those writes
  would be one `git commit -a` from a public repository. A `merge = true`
  entry sets the five owned keys from `home/.claude/settings.json` and leaves
  the rest.
- **mise is checked before the config is linked.** An older mise rejects
  `[bootstrap.hooks] post-dotfiles`, and an unknown key in a `conf.d` file
  stops every mise command from parsing, the coding agents' shims included.
  Below 2026.10.4 the step warns and leaves the last apply in place.

## The hypr assert

`bindings.lua`, `looknfeel.lua`, `input.lua` and `autostart.lua` stay the
checkout's, as under ADR 0001, and Monarchy still never writes them.
`monarchy_assert_dotfiles_hypr` checks that each is a link resolving into
`home/.config/hypr/`. If one is not, it runs `household_dotfiles` once and
re-checks, then dies naming `mise dot status`. A plugin's marked block in
`bindings.lua` is now an ordinary diff in the checkout rather than drift to
be filtered, so `monarchy_strip_marked_blocks` is gone.

## Consequences

- Every app write to a linked dotfile lands in the working tree of a public
  repository. `dotfiles-drift` (Omarchy's `post-update.d`) and the run
  summary list the files; review is `git diff home/`.
- chezmoi is retired on every box by the same step: its source link, its
  drift hook and its state go, and the package is removed with the unwanted
  packages. Rollback is `mise dot unapply`, reinstalling chezmoi and
  `chezmoi apply` from the last commit before the switch, or the pre-update
  ZFS snapshot.
- Dotfiles are applied for the king only, as before. Per-role dotfiles would
  be one group per role, selected per account in its own mise config, with a
  checkout every account can read.
- The Plasma dotfiles were dropped rather than carried over: the household is
  leaving Plasma. Their last copies stay on disk, unmanaged.
