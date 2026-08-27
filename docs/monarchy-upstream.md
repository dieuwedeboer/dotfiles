# Upstream: quattro-on-zfs coexistence

`berenddeboer/omarchy` has issues disabled. The ZFS-specific package repo does not (`berenddeboer/omarchy-zfs-pkgs`). The issue below was filed there, asking whether the fork will treat non-`zroot` pools and non-Limine boot paths as in-scope.

This is not a request that they support CachyOS, multi-user SDDM, or `linux-cachyos`. Those stay in Monarchy's bridge. If they generalize discovery of the live root dataset and skip Limine when ZFSBootMenu is already the boot path, the bridge shrinks.

Filed: https://github.com/berenddeboer/omarchy-zfs-pkgs/issues/1

`berenddeboer/omarchy` has issues disabled, so this went on the ZFS package repo. A PR against `quattro-on-zfs` is offered in the issue if that is easier for Berend.

## What we asked for

1. Do not hardcode `zroot/ROOT/default`. `install/config/zfs.sh` already takes the pool from `findmnt SOURCE /`. `omarchy-snapshot create` is already layout-agnostic. `omarchy-upgrade-to-quattro-zfs-check` and the upgrade snapshot are not.
2. Do not require Limine when ZFSBootMenu (often behind rEFInd) is already booting the box. `omarchy-refresh-limine` already skips Snapper on non-Btrfs. The same "command missing? skip" pattern would cover `limine-update` / `limine-mkinitcpio`.

## What we did not ask them to take

- CachyOS repos or `linux-cachyos` / `linux-cachyos-zfs`
- Multi-user SDDM greeter overlay (stock Omarchy theme is last-user only)
- Sanoid vs Snapper
- Not replacing `/etc/pacman.conf`

## Follow-ons if they say yes

PAM homes at `$pool/data/home`, plymouth-before-zfs mkinitcpio rewrite, and the archzfs requirement. Mentioned in the issue as related, not the ask.
