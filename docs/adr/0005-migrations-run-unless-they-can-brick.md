# Omarchy migrations run unless they can brick this host

Every Omarchy migration runs here. One is held back only when it cannot run
without a risk of bricking this ZFS host, and then a human decides, once, in
`monarchy/migrations.deny` or `monarchy/migrations.allow`. Omarchy commands
that belong to tools this host replaces are mapped onto what it uses instead,
through `monarchy/bin.alias`.

## What this replaces

`migrations.deny` held eleven rows with no reasons, and the guard in
`update.sh` halted on any migration mentioning `limine-mkinitcpio` or
`pacman.conf`. On 14 October 2026, 61 migrations were pending. Three
things had piled them up:

- `omarchy-migrate` was in `bin.skip`, so the notification's "click to run"
  did nothing at all.
- 1788163635 calls `omarchy-sudo-passwordless __migrate`. The wrap refused
  it, and `omarchy-migrate` stops at the first failure.
- 1791769486 mentions `limine-mkinitcpio` in a branch this host cannot
  reach, which would have stopped the next update.

Reading the denied rows showed that most of them were never a risk. Upstream's
Limine migrations check for Limine before they act
(`omarchy-cmd-present limine-mkinitcpio`, the drop-in files, the hardware),
and none of that exists here, so they exit 0.

## The rule

A migration is held back when it matches a brick path in
`lib/monarchy/migrate.sh`:

- boot loader and initramfs config
- Omarchy's kernel packages
- ZFS
- package sources
- PAM, sudoers and SDDM
- USB authorisation
- a call to a name monarchy denies or wraps
- installing a `packages.deny` package

`brick` means what `CONTEXT.md` says it means.

The check is keywords, not judgement. That keeps it fast enough to run on every
click, and every hold comes with the reason it matched. Classifying the hold is
reading one script, done once and recorded in git with its reason.

Two migrations are denied today: the `linux-omarchy` kernel install, and
moving `[omarchy]` above CachyOS. Each row says why.

## Shims, not stubs

`limine-mkinitcpio` and `limine-update` run `mkinitcpio -P`, which is what
every kernel upgrade already does here. `limine-snapper-sync` does nothing,
because ZFSBootMenu lists snapshots itself. Each one says so on stderr, the
way the overlay's `yay` says it is running `paru`. They live in
`/usr/local/bin` as well as the overlay, because upstream calls them under
`sudo`, whose `secure_path` reaches `/usr/local/bin`. If a later case needs
more than that, a general way to shim sudo commands is the extension.

Two are left missing on purpose. `limine-entry-tool` edits ESP boot entries
and has no counterpart. `snapper` is checked with `command -v`, and a shim
would make Omarchy go on to set snapper up. Snapshot creation already goes to
ZFS through the `omarchy-snapshot` wrap.

## Kernel command line

Omarchy's two Plymouth fixes, `initramfs_async=0` and
`systemd.tty.term.console=dumb`, arrive as Limine drop-ins that `settings.skip`
removes. They are wanted here too, so `lib/zbm/boot.sh` merges them into
`org.zfsbootmenu:commandline`.

## Considered

- **Keep denying on Limine keywords.** It holds back migrations that are
  already safe here and gives no reason when it does.
- **An agent reviewing every pending migration at click time.** Slow, and a
  judgement that is not written down anywhere. The keyword check leaves an
  agent the occasional hold to read, not the whole backlog.
- **Shim snapper onto ZFS.** Snapper's snapshot numbers have no ZFS
  counterpart, and `snapper delete <n>` mapped onto `zfs destroy` is not a
  risk worth taking.

## Consequences

- `bin.skip` no longer holds `omarchy-migrate`. It is a wrap. Inside the real
  `omarchy-update` it does nothing (`MONARCHY_IN_OMARCHY_UPDATE`), which keeps
  the reason ADR 0003 gave for skipping it.
- `monarchy-migrate` refuses to run anything while a hold is unclassified,
  rather than running the migrations before it. Upstream also stops at the
  first problem, and holds should be rare.
- The guard and the wrap use one function, so there is one set of criteria.
  The rules reach other accounts through `/var/lib/monarchy/migration-rules`,
  written at apply.
- `usbguard` follows Omarchy, which dropped it. Monarchy does not uninstall
  packages (ADR 0002), so on a box that has it and where Omarchy never granted
  it, it is removed by hand.
