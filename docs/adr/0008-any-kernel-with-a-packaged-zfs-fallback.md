# Run any kernel, Omarchy's included, while a packaged-ZFS fallback stays

This replaces the rule that the running kernel must be `linux-cachyos*`.
`linux-omarchy` is installed beside the CachyOS kernels and may be the one
that boots. What must always be true is that one installed kernel has a ZFS
module that comes from a package, not from a DKMS build. Today that is
`linux-cachyos` with `linux-cachyos-zfs`.

## Why the old rule existed

`linux-cachyos-zfs` is built by CachyOS against each kernel release and
depends on that exact kernel version, so the kernel and its ZFS module always
move together. Any other kernel takes its module from `zfs-dkms`, built on the
box after the upgrade. OpenZFS declares the newest kernel series it supports
(`Linux-Maximum` in the source's `META`). A kernel past that fails to build.
DKMS runs after the transaction, so pacman completes anyway, mkinitcpio writes
an initramfs without `zfs`, and that kernel cannot import the root pool.

## Why it can go

The failure is one kernel that cannot boot, not a box that cannot boot:

- ZFSBootMenu runs its own kernel from the ESP, so the menu survives a broken
  OS kernel and lists the others.
- The fallback kernel's module needed no build, so the same DKMS failure cannot
  reach it.
- Every transaction is snapshotted first.

Per `CONTEXT.md` a failed boot that needs someone to choose a kernel in
ZFSBootMenu is a brick for that boot. That risk is accepted, so Omarchy's
kernel can be tested here (ADR 0007), on the condition that a fallback is
always there. The hooks below make the failure rare and keep the fallback.

## What enforces it

`lib/zfs-kernel.sh`, installed as `/usr/local/lib/monarchy/zfs-kernel`, run by
three pacman hooks from `etc/pacman.d/hooks`:

- `zfs-kernel-guard.hook`, before the transaction, aborts it when an incoming
  kernel has no packaged ZFS module and is newer than the `Linux-Maximum` of
  the `zfs-dkms` that will be installed. It sorts before `zfs-snapshot.hook`,
  so a refused transaction takes no snapshot.
- `zfs-fallback-kernel.hook`, before a removal, aborts it when the removal
  would leave no kernel with a packaged ZFS module.
- `95-zfs-initramfs.hook`, after mkinitcpio, warns when any kernel's initramfs
  has no `zfs.ko`. That catches a DKMS build that fails inside a series
  OpenZFS claims to support. It cannot abort; it says to choose another kernel.

Monarchy's guards run `monarchy_require_fallback_kernel` in place of
`monarchy_refuse_kernel_swap`, for a box that lost its fallback some way the
hooks did not see.

`linux-omarchy`, `linux-omarchy-headers` and `zfs-dkms` are in
`PACMAN_PACKAGES`. Omarchy's own migration for the kernel, `1789325478.sh`,
stays in `migrations.deny`: it ends by checking a Limine entry with
`limine-entry-tool`, which this host does not have, so it could never complete.

## Considered

- **Keep `linux-cachyos` only.** Safe and simple, but it is a vendor rule that
  serves neither ZFS nor ZFSBootMenu directly (ADR 0007).
- **Pin ZFSBootMenu's default with `org.zfsbootmenu:kernel`.** Makes unattended
  boots predictable. Left unset for now, because Omarchy's kernel is what is
  being tested; it is the first thing to set on a box where nobody can be
  expected to choose a kernel.
- **Hold kernels with `IgnorePkg` until OpenZFS catches up.** A manual step on
  every new series; the guard does the same thing only when it is needed.

## Consequences

- A kernel upgrade can now be refused. The message names the kernel and the
  `Linux-Maximum` it exceeds; the fix is to wait for `zfs-dkms`, or hold the
  kernel with `IgnorePkg`.
- `linux-cachyos` and `linux-cachyos-zfs` cannot be removed while they are the
  only fallback. Moving the fallback to another vendor means installing that
  one first.
- The hooks land with `lib/zfs.sh` in the household refresh, after
  `packages_install`. On a fresh box the first `linux-omarchy` install is not
  checked; the fallback is already there.
