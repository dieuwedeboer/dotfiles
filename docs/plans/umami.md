# Plan: what to take from umami

- **Status:** plan. Not scheduled. Notes from reading umami on 2026-11-20, to revisit.
- **Audience:** anyone changing how the overlay patches Omarchy's tree, or deciding whether to adopt umami
- **Source:** <https://github.com/OldJobobo/umami>, read at `825b0a8` (2026-11-19). Its `README.md`, `docs/design.md` and `docs/future-machine-setups.md` are the primary reference; the claims about umami below come from those and from `umami/compose.py`, not from running it.

umami ("Umami Flavors") is an unofficial add-on that customises stock Omarchy without a fork. A **flavor** is a TOML recipe of **transforms** (a Hyprland setting, a key chord, an anchored patch, a `git diff`, a wrapped command, a removed shell plugin). On every Omarchy package change a pacman hook copies `/usr/share/omarchy`, applies the recipe, and swaps the result into `/var/lib/umami/tree`, which `/etc/omarchy.conf` points at. A transform whose target moved is reported **stale** and skipped; the rest still applies and the update never stops.

It is a prototype. Its own README says it was verified in a VM on 4.5.0 stable and across a stable→edge switch, and has not been tested across a stable release bump.

## Same problem, same answer

umami and Monarchy reached the same core design independently:

| Concern | umami | Monarchy |
| --- | --- | --- |
| Where Omarchy comes from | Official package, no fork, no clone | Same (ADR 0009) |
| How the desktop is redirected | `/etc/omarchy.conf` sets `OMARCHY_PATH` to a tree it owns | Same, `/usr/local/share/omarchy` |
| `sudo` reaching the overlay | sudoers `secure_path` points at the tree's `bin/` | `/usr/local/bin` precedes `/usr/bin` in `secure_path` |
| `omarchy_security_require_source_root` | Real files in the tree, never symlinks | Those commands are copied, not linked |
| Version/channel read `dev` off a non-stock path | Seven built-in one-line patches to its copy | `omarchy-version*` wrapped, `omarchy-channel-set` denied, `omarchy-update-dev` in `bin.skip` |

That agreement is useful on its own: two people reading the same code hit the same five snags. It is weak evidence that the snag list is complete.

## Where it differs

### Scope

umami is a desktop layer only. It does not touch `pacman.conf`, the bootloader, ZFS, the greeter, packages beyond a recipe's `[[package]]`, or accounts. Monarchy is the whole box: CachyOS stays the OS, and most of our code exists to stop Omarchy reaching Limine, snapper and `pacman.conf`. umami's `future-machine-setups.md` positions flavors as the environment layer *under* a machine provisioner. Monarchy is that provisioner.

### How the tree is built

| | umami | Monarchy |
| --- | --- | --- |
| Tree | Full real copy, `cp -rL --reflink=auto`, staged then swapped atomically | Symlink farm into `/usr/share/omarchy`; `bin/` mirrored with `cp -srT`; `shell/` and `default/` exploded only where patched |
| Patches | One generic compositor, ~660 lines of Python, driven by the recipe | Bespoke code per patch: `overlay-lock.py` (228 lines), `overlay-power.py` (222), launcher hides, agent marks, in `overlay.sh` |
| Hyprland | Generated `default/hypr/flavor.lua` in the tree, loaded after Omarchy's defaults and before the theme and `~/.config/hypr` | `monarchy/hypr/*.lua` copied into the king's `~/.config/hypr` and required from a `BEGIN monarchy` block |

The full copy costs disk unless reflink shares blocks (whether it does on our pools is an open question below), but it removes a class of bug we have paid for: the shell fingerprint has to be measured across two overlay steps, and `PluginRegistry` does not follow directory symlinks, so `shell/plugins` had to be copied whole anyway.

### When it runs

umami recomposes in a `PostTransaction` ALPM hook on `omarchy`, `omarchy-dev`, `omarchy-settings` and `omarchy-settings-dev`, inside the same transaction, so `omarchy-migrate` already runs from the composed tree.

Monarchy brackets `omarchy-update` from `monarchy-update` and applies afterwards. That works when the update goes through `monarchy-update`. **To check:** when `omarchy` is upgraded any other way (`cachy-update`, a bare `pacman -Syu`), our exploded copies under `shell/` and `default/` keep the old version's QML until the next `monarchy-update`, while `bin/` symlinks already point at the new one. We have no hook that closes that gap. Whether it has bitten anyone is not known.

Note that umami's hook targets package names, not `provides`, so `omarchy-settings-monarchy` would not trigger it. Unverified; matters only if we ever run umami.

### Failure policy

| | umami | Monarchy |
| --- | --- | --- |
| Target moved | Transform marked stale, skipped, reported; rest applies | Patch scripts `monarchy_die`, apply stops |
| Must-have change fails | `required = true` → next boot runs stock Omarchy | n/a |
| New upstream binary or migration | Not its concern | Classification guards halt the update for a human call |

Our strictness is right for brick paths (Limine, snapper, `pacman.conf`), and nothing in umami argues against that. It is not obviously right for cosmetic patches: a lock-screen hint that no longer applies should not stop a household's update.

### Plugins

| | umami | Monarchy |
| --- | --- | --- |
| Pin | Full commit in the recipe | Unpinned `git clone` of the default branch |
| Vetting | `omarchy-git-url-check`, then `omarchy-plugin-validate`, refuses if the checker is missing | `monarchy_validate_plugin_dir` (plugin validate) |
| Consent | Per user, at login, Omarchy's own warning, a No is remembered | King's apply; updates shown as a diff and confirmed |
| Removal | Plugins the old flavor installed offered for removal once | Drop the row, then `omarchy plugin remove` by hand |

Both refuse to put third-party plugins in the root-owned tree, for the same reason: built-ins get every capability their manifest asks for.

### Defaults and locks

umami has two strengths for anything it sets. A **default** is applied once per user, tracked per entry in `~/.local/state/umami/defaults.json`, and re-applied only when the flavor changes that value; this is our seed ledger and ADR 0002 under another name. A **lock** comes back every login: `locked = true` Hyprland settings and binds go in `flavor-locked.lua`, loaded at the end of `toggles.lua`, which `hyprland.lua` requires *after* the user's own files, so the flavor wins. `shell.plugins.remove` takes a widget out of the tree so there is nothing to enable.

That is the shape `CONTEXT.md` reserves for the **kid** role ("future restrictions hang off this role"). umami's locks are machine-wide; ours would need to be per role. Kid currently defaults to Plasma, so there is no demand yet.

### Reporting

`umami plan` composes into a scratch directory and prints what applies, what is stale, and `--files`/`--diff` against stock. `status` says where Omarchy runs from this session and from next boot. `--json` on all three, exit 2 for a failed required change, 1 for can't-do, 0 otherwise. Our `--check` is a dry run and our summary is a changed/left-alone/warned ledger, but nothing lists every file in the working prefix that differs from the package.

## Ideas, in rough order of value

1. **Back the `OMARCHY_PATH_TYPE` upstream PR.** umami plans to propose an `OMARCHY_PATH_TYPE=package|dev|flavor` line in `/etc/omarchy.conf` so scripts stop guessing from the path. It would let us retire the `omarchy-version*` wraps and the `omarchy-update-dev` skip, and possibly un-deny `omarchy-channel-set` (that one also rewrites `pacman.conf`, so check). Cheapest win here, and not our code to maintain. Watch for the PR; comment with our case as a second, non-umami user.
2. **Close the plain-`pacman` gap.** Confirm the staleness above on a box, then decide: an ALPM `PostTransaction` hook on `omarchy`/`omarchy-dev` that re-runs only the overlay unit, or a guard that refuses to start the session on a version mismatch. Contradicts nothing in ADR 0003; it keeps `omarchy update` owning `pacman -Syu`.
3. **Split patches into must-apply and may-skip.** Brick-path guards keep halting. Cosmetic patches (lock Super+Ctrl+U hint, power panel "Holding", agent marks) report stale and skip, and the summary's "warned" list names them. This is umami's `required` flag, inverted for our default.
4. **One anchored-patch helper.** Replace the per-file Python with a small table-driven helper: file, anchor that must occur exactly once, replacement. umami's `patch` and `diff` (with fallback `sources`, the first that applies wins) are the model. The `diff` form would have let us carry the Qt 6.12 `Color` fix as a patch instead of moving a box to edge (ADR 0003-track-omarchy-dev-on-edge rejected patching because it dirtied `pacman -Qkk`; a patched *copy* does not).
5. **Pin plugin commits.** Add an optional commit column to `monarchy/plugins` and run `omarchy-git-url-check` before cloning. Updates move the pin, not the branch.
6. **A `--diff` against stock.** List every file under `$OMARCHY_PATH` that is not a symlink to, or byte-identical with, `/usr/share/omarchy`. Makes "what does this box change" one command.
7. **Generated Hyprland module in the tree** instead of `BEGIN` blocks in the king's home directory. Only worth it if more than one role runs Omarchy, or if kid locks arrive.
8. **Per-role locks for kid**, using the `toggles.lua` load order. Wait for a real restriction to ask for it.

## Not recommended: running umami itself

- It takes `OMARCHY_PATH` and `/etc/omarchy.conf`, which our prefix already owns. Two owners of one slot.
- It copies `bin/` from the package, so our deny stubs and wraps would have to become `command.replace` transforms, and its README says privileged commands cannot be wrapped.
- It has no answer for Limine, snapper or `pacman.conf`, because on a stock Omarchy box those are correct.
- It is a prototype, not yet tested across a stable release bump, and ADR 0013 asks master to keep stable working.

Revisit if umami reaches a package repository and its tree can sit *under* our `bin/` overlay, at which point items 3, 4, 6 and 7 could become a recipe instead of our code.

## Open questions

- Does the plain-`pacman` staleness actually happen, and what does it break? (Idea 2.)
- Does `cp --reflink=auto` share blocks on our ZFS datasets, or would a full copy cost real space?
- Is `omarchy-channel-set` denied only for the path guess, or also for its `pacman.conf` write? (Idea 1.)

Any of these that turns into a decision belongs in an ADR, not here.
