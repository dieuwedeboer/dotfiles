# A file moving into settings is handed over in one transaction

When upstream moves a file from the Omarchy package into the settings
package, `omarchy-settings-monarchy` is installed in the same `pacman -U` as
the new Omarchy package, downloaded ahead of `omarchy update`. This is a
partial upgrade of one package, and an exception to ADR 0003, where
`omarchy update` owns `pacman -Syu`.

## What forced it

On 14 October 2026, `omarchy-dev` r6975 moved five paths into
`omarchy-settings-dev`: `omarchy-security-functions`,
`omarchy-sudo-passwordless`, the two copies of them under
`/usr/share/omarchy/bin/`, and `05-omarchy-passwordless-revoke.hook`.
ADR 0003 step 4 installs settings first, on its own, so that the upgrade
resolves against ours. The installed `omarchy-dev` r6860 still owned those
files, pacman refused with "exists in filesystem", and `monarchy-update`
stopped before the upgrade.

pacman hands a file from one package to another only when both change in the
same transaction. Settings has to go before `omarchy update` (ADR 0003), and
the Omarchy package cannot go before settings, so the only transaction that
holds both is one monarchy runs itself.

## Considered

- **`--overwrite` the paths owned by the Omarchy package.** Keeps the separate
  transaction. The file is then listed under both packages, and when the
  upgrade removes the old Omarchy version, which owns it and whose new
  version does not ship it, pacman is expected to delete it. That would leave
  the passwordless-sudo helper and its revoke hook missing with no error.
  This was not tested in libalpm; it was not worth finding out on the box.
- **Add the moved paths to `settings.skip`.** The new Omarchy package does not
  ship them either, so they would vanish.
- **Serve the built packages from a local repository** so the full upgrade
  takes them with everything else. The clean answer, and a larger change to
  `pacman.conf` than this case justifies today.

## Consequences

- It applies only when `monarchy_plan_overwrites` finds a path in the built
  settings package owned by the installed Omarchy package. On an ordinary
  release, nothing changes.
- The Omarchy package is fetched with `pacman -Sddw`, so pacman checks the
  signature. Its dependencies are resolved by the `-U` itself and can pull
  packages from the sync repos. For `omarchy-dev`, a script package with no
  versioned dependencies, that is a small set. Revisit this if one release
  brings a soname bump.
- For stable `omarchy`, the same transaction also satisfies the exact
  `omarchy-settings=` pin, so the `--assume-installed` handoff is not used.
- `omarchy update` still runs straight after and finds the Omarchy package
  already current.

## Amendment, 2 November 2026: every release, not only a handover

Settings and the Omarchy package are now always upgraded in one transaction,
whenever [omarchy] has a newer Omarchy package than the one installed. The
handover above is one reason for that, no longer the only one.

### What forced it

`omarchy-update` sources `omarchy-security-functions`, which settings has
shipped since r6975. The two are written against each other at the same
upstream commit. On 2 November 2026 upstream r7555 removed
`omarchy_security_install_sudo_cleanup_traps` from the security functions and
removed the call to it from `omarchy-update`. `monarchy_ensure_settings_pkg`
installed settings r7555 on its own, as this ADR allowed when no file moved.
`omarchy-dev` pins no settings version, so nothing held it back. The installed
r7409 `omarchy-update` then ran against the r7555 library and exited 127
before reaching its own `pacman -Syu`. A run that has upgraded only one of
the two packages cannot repair itself through `omarchy update`.

Installing them in the same transaction is the only order that cannot leave
the two out of step. Settings first breaks the old `omarchy-update`. Leaving
settings behind breaks the new one the same way in reverse.

### Changes from the original decision

- `monarchy_ensure_settings_pkg` fetches the Omarchy package and installs it
  in the same `pacman -U` as the built settings package whenever the installed
  version is older than the sync DB's, as well as when a path moves.
- If settings is already current and the Omarchy package is not, which is
  what an interrupted earlier run leaves, `monarchy_catch_up_locked_pkg`
  installs the Omarchy package on its own.
- On stable `omarchy`, the same transaction satisfies the exact
  `omarchy-settings=` pin, so the stop telling the operator to run a full
  upgrade, and the `MONARCHY_EXPECT_FULL_UPGRADE` note that replaced it during
  `update-pre`, are gone. `--assume-installed` is still used when the
  *other* Omarchy package is installed and `monarchy_ensure_omarchy_pkg` is
  about to replace it.
- `omarchy update` finds the Omarchy package already current on every release
  bump, not only on a handover. The partial upgrade is still one package
  ahead of `-Syu`, with the dependency risk described above, and now happens
  every release. The local repository considered above remains the clean way
  out.
