# Track omarchy-dev on the edge channel until a stable release has the Qt 6.12 fix

Monarchy tracked `omarchy` on `[omarchy]` stable. On 9 October 2026 a full
upgrade brought Qt 6.12 from CachyOS, and the shell lost most of its theme
colours: menus, tooltips and the bar drew black. Qt 6.12 adds a QtQuick
`Color` singleton, and a bare `Color.tooltip` in Omarchy's QML now reads Qt's
object, which has no such member. Upstream's fix qualifies every use as
`Commons.Color`. On 10 October 2026 that fix was in `omarchy-dev` on edge and
in no stable release.

`monarchy/omarchy.lock` now names `package=omarchy-dev` and `channel=edge`.
The lock used to be recorded and not read. It now drives three things: the
`[omarchy]` server path, the upstream settings package that
`omarchy-settings-monarchy` is built from, and which Omarchy package the
packaging unit installs. Moving back
is a lock edit: `package=omarchy`, `channel=stable`, then
`./install.sh --only=pacman`, `cachy-update`, `monarchy-update`.

## Considered

- **Roll back `cos/root` and hold upgrades.** Restores a matching set, but
  the next `pacman -Syu` brings Qt 6.12 back, so it only buys time.
- **Patch the 54 shell files locally.** Every `omarchy` upgrade overwrites
  them, so it needs a pacman hook and leaves `pacman -Qkk` permanently dirty,
  for a fix upstream has already made.
- **Take Arch packages from `stable-mirror.omarchy.org`.** That mirror still
  carries Qt 6.11.2, the set stable Omarchy is tested on, and is the right
  long-term direction. But the CachyOS repos sit above `core` and `extra` and
  carry their own Qt 6.12 builds, so it means dropping or overriding CachyOS
  repos, which is the kernel and ZFS question parked separately.

## Consequences

- Edge is upstream's development branch. It carries more migrations and new
  binaries per update, and each still has to pass the classification guards.
  The switch classified 43 new migrations and 14 new package rows; see
  `docs/monarchy-clashes.md`.
- Migrations change the home directory and do not reverse. Moving back to
  stable later does not undo what edge migrations did.
- The migration guard now also stops on `/etc/pacman.conf` and
  `omarchy-update-system-pkgs`, after `1791403252.sh` was found moving
  `[omarchy]` above every other repository and running a full upgrade, which
  the old pattern did not catch.
- Third-party shell plugins that use bare `Color` stay broken under Qt 6.12
  whatever Omarchy ships, until each author qualifies it.
- Revisit when an `omarchy` stable release includes the `Commons.Color` fix.
