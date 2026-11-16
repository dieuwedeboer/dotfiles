# Stable is the channel master keeps working

`master` must always work on `omarchy` from the `stable` channel. `omarchy-dev`,
`rc` and `edge` stay supported in the code (ADR 0009 still holds: the channel
is read from the box), but they are best effort. A change that is right for
stable goes in even if it breaks a box on another channel, and that box adapts
itself or moves back to stable.

## Why

Omarchy 4.5.0, with the Qt 6.12 fix that took a box to edge (ADR 0003,
track-omarchy-dev-on-edge), reached stable on 16 November 2026. Holding every
change to "works on all channels" cost a day of the 4.5.0 upgrade on skew
between rc and the release, and the same three breaks were fixed twice, once
per channel.

## Considered

- **Strip `omarchy-dev` and channel handling out of master.** About 20 files.
  It removes a working way back to edge for no gain on stable, so it stays.

## Consequences

- An overlay anchor, a `monarchy/` list row or a guard is tested against the
  current stable package. Matching other channels' forms as well (ADR 0009,
  One repo, several channels) is welcome but not required.
- Work that needs an unreleased Omarchy goes on a branch until the release
  reaches stable.
