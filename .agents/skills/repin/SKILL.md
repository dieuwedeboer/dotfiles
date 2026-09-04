---
name: repin
description: Re-pin the Omarchy overlay onto a newer berenddeboer/omarchy commit. Use when the pin is behind, when --repin-check reports rows to classify, or when a new Omarchy feature is wanted on these boxes.
---

# Re-pin the overlay

`monarchy/omarchy.lock` pins the exact commit every box checks out. Bumping it
is how new Omarchy work reaches the household. It stays a human-reviewed step
because `monarchy_check_migrations` and `monarchy_check_packages_deny` halt an
apply on anything unclassified, and there is no canary box to find out on.

Work through the steps in order. Stop at step 7 and hand back: the apply needs
a terminal for sudo.

## 1. Review

```bash
./install.sh --repin-check
```

Read-only. It reports position (including whether the fork rebased and
force-pushed away from the pin), both classification guards, the `bin/`
inventory diff, `packages.installed`, every new migration with its own summary
line, and added or deleted privileged drop-ins.

Done when you can name what changed in every section. `pin is current` ends the
task here.

## 2. Classify what the guards caught

Only rows the guards named need a decision. Judgement is in **Classifying**
below. Edit `monarchy/packages.deny` or leave the row to be picked up by
`packages.installed` in step 4.

Done when `--repin-check` reports both guards passing.

## 3. Read the new migrations

The guards only grep for limine and `pacman.conf`. Read each new migration for
what it does to a box that boots rEFInd into ZFSBootMenu and snapshots with
sanoid. A migration that rewrites the bootloader, the dataset layout, or the
greeter goes into `monarchy/migrations.deny`.

Report anything that reverses a decision this repo made on purpose — `install.sh`
enabling `sshd`, for one — rather than silently accepting it.

Done when every new migration is either understood or denied.

## 4. Regenerate

Get the candidate checkout, then write both inventories from it:

```bash
tmp=$(mktemp -d)
git clone --quiet --filter=blob:none --branch quattro-on-zfs \
  https://github.com/berenddeboer/omarchy.git "$tmp/clone"
git -C "$tmp/clone" checkout --quiet --detach <new-commit>

python3 lib/monarchy/generate-inventories.py "$tmp/clone"

bash -c 'export MONARCHY_SRC='"$tmp/clone"'
  source lib/monarchy.sh; monarchy_load_inventories
  monarchy_filtered_packages' > monarchy/packages.installed
```

Done when `git diff` on `monarchy/` matches what step 1 predicted.

## 5. Bump the lock and the pin line

Set `commit=` in `monarchy/omarchy.lock`. Update the `Pin:` line at the top of
`docs/monarchy-clashes.md` with the new commit and the counts the generator
printed.

Done when both name the same commit.

## 6. Test

```bash
MONARCHY_SRC=$tmp/clone bash tests/run.sh
```

Green against the candidate checkout is the bar.

`bash tests/run.sh` without that variable fails `test-overlay.sh` with
`inventory has N names, clone bin/ has M`. That is correct: the tree now
describes a commit this box has not fetched. It clears when the box updates.
Leave it.

## 7. Commit and hand back

Commit `monarchy/omarchy.lock`, the three `bin.*` lists, `packages.installed`,
and `docs/monarchy-clashes.md`. Say in the message what the gap contained, what
moved bucket, and anything from step 3 the operator has to act on themselves.

Then tell the operator to run `monarchy-update`. That is what fetches the new
commit onto the box and applies it.

## Classifying

**A new `bin/` name** is allow unless it bricks CachyOS+ZFS+KDE. The bricking
set is the one already in `generate-inventories.py`: replacing `pacman.conf`,
touching Limine, renaming the dataset, or running the ISO provisioner. Anything
else is a real binary, including `omarchy-install-*` and `omarchy-pkg-*`. A
command that merely fails on these boxes is still allow — a deny stub is for
damage, not for disappointment.

**A new package row** goes in `packages.installed` unless it is a brick, in
which case it goes in `monarchy/packages.deny`.

**A removed package row** stays installed on the box. Find whether a migration
removes it; if none does, say so in the commit message.

**A deleted privileged drop-in** — anything under `etc/sudoers.d/`,
`etc/systemd/system/`, `etc/udev/` — is the finding that matters most. Apply
installs files and never reconciles them, so a rule upstream deleted for
security stays on the box until a person removes it. Report the path and the
grant it carried.
