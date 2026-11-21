# Minecraft is shared and snapshotted

XMCL's data root on every box is `/games/xmcl`, the dataset
`<pool>/games/xmcl`, shared by every player. Unlike the rest of `/games` it is
snapshotted. The Microsoft logins are shared per box as well. `lib/xmcl.sh`
sets it up on every apply.

## Why

The kids play LAN games across the household's machines, under whichever
account is free. On 21 November 2026 kingfisher had three XMCL instances on
three Minecraft versions and two mod loaders, all under one account, while the
other accounts and boxes had their own. A LAN game needs the same version and
mods on both ends, and a world made under one account could not be found from
another.

## One data root per box

- Every player's `~/.config/xmcl/root` names `/games/xmcl`, so every account on
  a box sees the same instances, versions, mods and worlds. A change one kid
  makes to an instance is the change every account sees.
- The data location is enforced, not seeded: the exception to ADR 0002, at
  the king's decision on 2026-11-21, so that a kid cannot split a box's
  Minecraft in two. Each player's `root` file is owned by root and immutable.
  XMCL changes the data location by moving the files and writing that file
  last; when the write fails it moves them back.
- A player whose data is somewhere else has it moved in by the apply, the
  exception to ADR 0004. Instances and worlds are moved one by one and never
  overwrite one another: a name already taken gets the account name added.
  Versions, libraries, assets and Java are merged without overwriting, since
  they can be downloaded again. Each moved instance's links and `instance.json`
  are pointed at the new root. What is left of the old root is kept aside as
  `*.before-monarchy` for the king to delete.
- Boxes are not kept in step with each other. The repo makes one place per box
  to look; keeping versions alike across boxes is still done by hand.

## Snapshotted, unlike its parent

ADR 0006 keeps `/games` out of every snapshot because game files can be
downloaded again and an update rewrites tens of gigabytes. Minecraft's worlds
cannot be downloaded again, and they are not in one place: XMCL keeps them in
the shared `saves` folder and inside each instance's own `saves`. No subtree
smaller than the whole root holds every world.

The whole root is a few gigabytes (8.8 GB on kingfisher, 5.4 GB of it worlds),
and the parts that can be downloaded again change only with a new Minecraft
version. Snapshotting all of it costs little, and also lets a mod or version
change a kid made be undone.

- A child of the games dataset, so it mounts at `/games/xmcl` by inheritance.
  The games dataset's snapshot sweep is one level deep and never reaches it.
- `recordsize=128K`, not the parent's 1M: region files are rewritten in small
  pieces.
- `sanoid.conf` lists it with the same template as `/home`.

## Shared logins

The household's Minecraft accounts are family accounts: any player on any box
may use any of them. XMCL keeps the Microsoft token cache in
`~/.config/xmcl/secret` and the account list in `~/.config/xmcl/user.json`.
Each player's are links into `/games/xmcl/accounts`, so one sign-in per account
per box serves every player, and a token refresh is written once instead of
leaving other copies stale.

XMCL encrypts the cache with the session's keyring, whose key no other account
has. It is started with `--password-store=basic` through a desktop entry in
`/usr/local/share/applications`, so it writes the cache with no per-user key,
and file permissions protect the tokens instead.

## Consequences

- `/games/xmcl` is mode `2770` with a default ACL that gives others nothing.
  Serfs get no Minecraft, and every king, queen and kid on the box can read the
  login tokens. That is the intent for family accounts, and the reason the
  rest of `/games` must not hold them.
- Login tokens are in the snapshots, readable only by the same group, for as
  long as sanoid keeps them.
- A player's own encrypted login is moved aside to `*.before-monarchy` on the
  first apply, and each account is signed in once more on each box.
- Two players running XMCL at once on one box share files with no locking. A
  launch from a second session while the first is open is not prevented.
- XMCL started some other way than its desktop entry uses the keyring, and a
  token it writes cannot be read by the other players.
- XMCL's rollback after a refused change of data location is its own, best
  effort. A player who renames `~/.config/xmcl` gets a fresh launcher asking
  for a data location until the next apply puts it back.
- Removing an account's home needs `chattr -i` on its XMCL `root` first.
- A test covers the move, because a world lost in it is lost for good.
