# Games are shared and never snapshotted

Steam's game files live in `<pool>/games`, mounted at `/games`, and are
shared by every player on the machine. No snapshot of that dataset is ever
kept. `lib/games.sh` sets it up on every apply.

## Why

On 14 October 2026 the pool on the main machine was 83% full. 373 GB of
`/home` was Steam games, and 200 GB more was `/home` snapshots. Snapshots keep
every block they reference, so each game update left its old files on disk for
as long as sanoid kept a snapshot taken before it: up to two months under
`monthly = 2`. Deleting the four oldest snapshots would have freed 150 GB.

Game files can be downloaded again. Snapshotting them protects nothing and
costs more space than anything else on the pool. Every player installing their
own copy of the same game costs the same again.

## No snapshots

- The dataset is a sibling of `ROOT`, not a child of `ROOT/cos` or of `home`.
  The pacman pre-update hook snapshots `ROOT/cos` recursively, and a dataset
  under it would be included. A snapshot of `home` never includes a separate
  dataset, even one mounted inside `/home`; only a recursive snapshot of a
  parent does.
- `sanoid.conf` does not list it.
- `com.sun:auto-snapshot=false` is set for any other tool that honours it.
- Any snapshot found on it, for example from a recursive snapshot of the
  whole pool, is destroyed on the next apply.

## Sharing

- Players are the king, queen and kids in `users.conf`. Membership of the
  `games` group is exactly that set; a kid moved to serf loses it.
- `/games` is group `games`, setgid, with a default ACL of group `rwx`, so
  files any player's Steam creates stay group-writable whatever its umask.
  Each apply repairs paths that have dropped out, such as games moved in by
  hand.
- Only `steamapps/common` is shared, as `/games/steam/common`, bind-mounted
  over each player's own `steamapps/common`. A bind mount rather than a
  symlink, so Steam and its runtime container see an ordinary directory.
- Each player's `steamapps/downloading` is bind-mounted from their own
  `/games/steam/downloading/<user>`, so no `/home` snapshot holds a staged
  download. One per player, because two clients staging the same game in one
  directory would clash.
- Manifests, temp files, shader caches and Proton prefixes stay in each
  player's home. Each Steam client keeps its own state, each player has
  their own saves, and Wine never meets a prefix owned by another user. This
  replaces a per-user Proton compatibility tool that sharing all of
  `steamapps` would have needed.
- `/games` is laid out so more of `steamapps`, or another launcher's library,
  can move in later.

## Consequences

- A second player's Steam shows a shared game as not installed until they
  install it, which finds the files and downloads only what differs.
- One player uninstalling a game removes it for everyone.
- Each Steam client updates games on its own. When one player's Steam has
  updated a game, the next player's Steam sees an update too and checks the
  files. Two clients updating the same game at once, in two logged-in
  sessions, is not prevented.
- `downloading` and `common` are two bind mounts, and Linux will not
  `rename()` across mount points even on one filesystem. If Steam moves
  finished files into `common` by renaming, it has to fall back to copying.
  Whether it does is untested; disk write errors on update would be the sign
  that it does not, and the fix would be to drop the `downloading` mount.
- Files Steam `chmod`s itself can lose group write until the next apply.
- A game already in a player's `common` is never mounted over: the hidden
  files would still use their space. The apply warns, and the player moves
  them into `/games/steam/common` once.
