# chezmoi owns ~/.config/hypr; Monarchy asserts and never applies it

`~/.config/hypr/*.lua` was written by two subsystems: chezmoi, from
`chezmoi/dot_config/hypr/`, and `monarchy_setup_user`, which appended binds and
detected prior state by grepping for an exact literal. That converged only
because the two literals matched character-for-character across two files, and
it had already cost one bespoke `awk` migration to retrofit `locked = true`
onto an earlier seed that did not match.

chezmoi now owns the personal override files outright — `bindings.lua`,
`looknfeel.lua`, `input.lua`, `autostart.lua`. Monarchy detects drift with
`chezmoi status ~/.config/hypr` and dies with the command to run. It never
writes them and never invokes `chezmoi apply` on the user's behalf.

Two files in that directory stay Monarchy's, because they are overlay assets
rather than personal config: `hyprland.lua`, seeded from the pinned Omarchy
clone, and `boot-color.lua`, copied from `monarchy/hypr/`. Monarchy still adds
the `boot-color` require to `hyprland.lua` as a marked block.

## Why not have Monarchy run `chezmoi apply` itself

Because `chezmoi apply` prompts. From `chezmoi apply --help`: "If a target has
been modified since chezmoi last wrote it then the user will be prompted if
they want to overwrite the file." `omarchy-update` is wired into the Omarchy
menu, which wrapped-execs `monarchy-update`, so a prompt in that path blocks a
GUI-invoked update with no terminal to answer it. `--force` avoids the prompt
by silently destroying deliberate local edits, which is worse than failing.

The new-box case needs no special handling: `install.sh` installs chezmoi in
`packages_install`, runs `chezmoi apply`, and only then runs Monarchy apply. By
the time Monarchy asserts, chezmoi has already run. The only path lacking a
chezmoi step is `monarchy-update`, and a box reaching that path is provisioned
by definition.

## Consequences

A missing file and a drifted file fail the same way, with the same message.
Seeding an absent file was considered and rejected: it would keep Monarchy a
writer of that path, which is the property being removed.

Boxes an earlier apply wrote to carry Monarchy's marked blocks in those files.
`monarchy_release_user_config` removes them, which is what the markers were
added for. After that the file matches what chezmoi carries.

The first apply after this change fails on any box whose `~/.config/hypr` has
not been brought up to the current chezmoi state. That is the intended
behaviour: the fix is one command, and the alternative is silent divergence.
