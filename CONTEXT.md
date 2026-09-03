# Context

Glossary for this repo. Terms only — no implementation detail. How the Omarchy
overlay is built is `docs/monarchy.md`; this file is what the words mean.

## Brick

A change **bricks** a machine if, after an apply that reported success, at least
one user cannot reach a usable desktop without intervention that a
non-technical household member cannot perform — a ZFSBootMenu rollback, a TTY,
or the machine's king.

Bricking is about *reachability of a desktop*, not about correctness. An apply
that leaves the wrong wallpaper, stale branding, a wrong version string, or a
missing webapp is broken but not bricking. An apply that leaves the greeter
unable to start, the session `Exec=` pointing at nothing, the lock screen
unable to authenticate, or a needed command replaced by a deny stub is
bricking, because the person in front of the machine has no way forward.

The distinction is load-bearing: it is the sole criterion for whether a
behaviour is covered by a test. The test suite protects the bricking surface
and deliberately leaves everything else uncovered.

## Roles

Every account on a household box holds exactly one role. Roles govern policy;
they do not describe relationships, and they are never recorded in this repo —
only in `/etc/monarchy/users.conf` on each machine.

- **King** — administers the box. One per machine.
- **Queen** — co-adult, unrestricted, does not administer. One per machine.
- **Kid** — supervised. Many per machine. Future restrictions hang off this role.
- **Serf** — anyone else, including guests and any account not yet classified.
  Many per machine.

An account absent from `users.conf` is a serf. Nothing is done to serfs beyond
the defaults; absence is a valid state, not an error.

## Session preference

Which desktop an account gets at the greeter. Separate from role, because it is
a preference rather than a policy.

The default is Omarchy. Queen and kid are overridden to Plasma. King and serf
take the default. Long term the Plasma overrides are expected to disappear, but
that is measured in years, not releases.
