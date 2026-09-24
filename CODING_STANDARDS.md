# Coding standards

How code in this repo is written and, more to the point, what is worth
testing. `CONTEXT.md` is the glossary; this is the practice.

## Tests

### One bar: could this leave someone stranded?

A test earns its place only if the failure it catches is one of these:

1. **A machine nobody can reach a desktop on.** This is `brick` in
   `CONTEXT.md`, and it is the criterion, not a paraphrase of it: after an
   apply that reported success, at least one person cannot get to a usable
   desktop without a ZFSBootMenu rollback, a TTY, or the machine's king.
2. **Something irreversible.** A real person's name committed to a public
   repository cannot be taken back out of git history. A greeter that hands
   one account's live session to whoever is standing at it cannot be undone
   afterwards either.

Everything else is uncovered on purpose. Wrong wallpaper, stale branding, a
bar widget in the wrong place, a missing webapp, a battery estimate that reads
20 minutes short, a log line that did not land — all broken, none of them
worth a test. The person can see them and the fix is one command.

This is not a target for coverage to grow towards later. A suite that tests
everything is a suite nobody reads the failures of.

### Test what the code does, never what it says

Run the function. Assert on what it produced — the file on disk, the exit
status, the value returned.

Never grep a source file for a literal. `grep -q 'monarchy_seed_hyprland_config'
"$LIB/user.sh"` does not test that Hyprland config gets seeded; it tests that
a line of code has not been reworded. It passes when the function is called
and broken, fails when the function is renamed and correct, and quietly stops
meaning anything the day someone moves the call. The same goes for parsing a
function body out with `awk` to check the order of two lines in it, and for
static "does apply reach this function" walks over the library.

If a behaviour is worth protecting, it is worth calling the function against
a temp directory and looking at the result.

### Never assert that something is absent

`grep -q X && fail` pins the non-existence of a string. It is a worse trade
than it looks:

- It fails the day the string legitimately returns under a new design.
- It passes for ever once the code it was guarding is deleted, so the suite
  gets greener as it protects less.
- It says what the past was, not what the present must be. Nobody reading it
  can tell whether the thing it forbids is still a hazard.

Where absence genuinely matters, assert the positive. Not "`plasma-login-manager`
must not appear in the filtered list" but "the filtered list is exactly this".
Not "the theme dir has no `Main.qml`" but "the theme dir contains exactly the
assets the overlay copies". An expected value that happens to be empty is a
positive assertion; a grep for something you hope is missing is not.

### No test may need the network, sudo, or a real box

Temp directories, stubbed commands, fixture trees. `tests/run.sh` is the gate
before any apply, and it has to be runnable at any moment without consequence.

### A test that skips must say so

A silent skip reads as a pass. `require_omarchy_tree` fails loudly rather than
letting a missing package tree turn a check into a no-op.

## Shell

- bash, `set -e`, idempotent. Sudo only where the destination demands it —
  `monarchy_sudo` and `monarchy_write_to` decide that, not the call site.
- `shellcheck -x` is part of `tests/run.sh`. It is not optional and it is not
  advisory: a finding at any level fails the suite. Install it; a skipped lint
  arm reads as a pass, which is how four real findings sat unnoticed.
- One voice for output. `monarchy_step`, `monarchy_log`, `monarchy_changed`,
  `monarchy_left_alone`, `monarchy_warn` — never a bare `echo` for progress.
- Comments explain **why**, especially why an obvious simpler thing is wrong.
  A comment restating the line below it is noise.

## Apply

- Apply seeds. It may turn on a thing that has never been on; it may not turn
  back on a thing that was on and is now off. See
  `docs/adr/0002-apply-seeds-it-does-not-reverse.md`.
- A decision not to act is an outcome, reported through `monarchy_left_alone`,
  not silence.
- A unit's check is a postcondition. Preconditions live in `guards`.

## Language

- New Zealand English: organise, colour, programme, licence (noun) /
  license (verb).
- Dates as 27 July 2026 or 2026-07-27. Never month-first.
- No personal names anywhere in the repo. See the No names rule in
  `AGENTS.md`; `tests/monarchy/test-no-names.sh` enforces it.
