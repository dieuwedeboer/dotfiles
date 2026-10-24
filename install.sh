#!/usr/bin/env bash
# One entry point. Bare ./install.sh on a fresh box is household bootstrap
# plus Monarchy apply. After /etc/omarchy.conf exists, bare ./install.sh is
# the same as --update: household refresh (packages, dotfiles, hardware, ZFS)
# then snapshot, rebuild packages, classify, apply. PATH has monarchy-update
# (this file, --update).
set -e
VERBOSE=0
MODE=full
OMARCHY_UPDATE_ARGS=()
for arg in "$@"; do
    case "$arg" in
        -v|-r|--verbose) VERBOSE=1 ;;
        --check) MODE=check ;;
        --update) MODE=update ;;
        --no-packages)
            # read by monarchy_install_packages and monarchy_keep_sddm
            # shellcheck disable=SC2034
            MONARCHY_NO_PACKAGES=1
            if [ "$MODE" = full ]; then
                MODE=apply
            fi
            ;;
        --splash-only) MODE=splash ;;
        -y|--yes)
            OMARCHY_UPDATE_ARGS+=(-y)
            # read by monarchy_update_plugins: -y means do not ask, and a
            # plugin update that is not asked about is not made
            # shellcheck disable=SC2034
            MONARCHY_ASSUME_YES=1
            # The fingerprint is pinned and checked before this is consulted;
            # -y only drops the question. Read by monarchy_confirm_omarchy_key.
            # shellcheck disable=SC2034
            MONARCHY_TRUST_OMARCHY_KEY=1
            ;;
        --no-omarchy-update)
            # read below
            # shellcheck disable=SC2034
            MONARCHY_NO_OMARCHY_UPDATE=1
            ;;
        --only=*)
            MONARCHY_ONLY=${arg#--only=}
            export MONARCHY_ONLY
            ;;
        -h|--help)
            cat <<'EOF'
usage: install.sh [--check] [--update] [--no-packages] [--splash-only] [-v]
       monarchy-update [same flags]

  (none)          Household refresh, then Monarchy. On a fresh box: packages,
                  dotfiles, rEFInd glow, services, hardware, ZFS, then apply.
                  Once /etc/omarchy.conf exists, the same as --update.
  --check         Monarchy dry-run. Writes nothing under /etc or /usr/local.
  --update        Guards and a ZFS snapshot, household refresh (dotfiles
                  front-loaded), then Omarchy's own `omarchy-update` in full,
                  then rebuild packages, classify and apply over the top.
                  After the first install this is the command; monarchy-update
                  is this file with --update, and the overlay's omarchy-update
                  is a wrapper onto it.
  --no-packages   Monarchy apply without pacman leaf packages. Still links
                  the dotfiles.
  --splash-only   Omarchy Plymouth theme, plymouth around zfs, retain-splash.
  --only=<unit>   Run one unit only. Combines with --check and --update.
                  Skips the household refresh and Omarchy's own update.
                  Units: guards pacman packaging prefix overlay leaves
                  settings sddm session logind portals user splash
  -y              Do not ask anything: passed to `omarchy update`, trusts
                  the pinned packaging key, prints reboot advice instead of
                  prompting. Plugin updates still wait for a run without -y.
                  The password is asked once at the start; Omarchy's own
                  update asks once more, and AUR builds ask per command at
                  the very end, after monarchy has been applied.
  --no-omarchy-update
                  Monarchy only. Household refresh, snapshot, classify,
                  apply -- without running Omarchy's own update in the
                  middle. For iterating on monarchy without a full -Syu.

  omarchy-update (Omarchy menu) wraps monarchy-update. That path has no
  terminal, so nothing on it asks: omarchy update gets -y.

  Every run ends with a summary: what changed, what was left alone, what
  warned. Left alone is a decision, not a failure -- apply seeds, and never
  switches back on what was switched off on this box. -v restores the
  timestamped log lines; NO_COLOR drops the escapes.

  MONARCHY_TRUST_OMARCHY_KEY=1 skips the packaging-key prompt.
EOF
            exit 0
            ;;
        *)
            echo "unknown argument: $arg" >&2
            exit 2
            ;;
    esac
done
[ "$VERBOSE" = 1 ] && set -x
export VERBOSE

DOTFILES_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
LIB_DIR="$DOTFILES_DIR/lib"

# Overlay installs this file as /usr/local/bin/monarchy-update.
if [ "$(basename -- "$0")" = monarchy-update ] && [ "$MODE" = full ]; then
    MODE=update
fi

# Captured before anything writes it: the closing notes are for the run that
# provisions the box, not for every update after it.
MONARCHY_PROVISIONING=1
[ ! -f /etc/omarchy.conf ] || MONARCHY_PROVISIONING=0

# A provisioned box: bare ./install.sh is the same as --update.
if [ "$MODE" = full ] && [ -z "${MONARCHY_ONLY:-}" ] && [ -f /etc/omarchy.conf ]; then
    MODE=update
fi

# shellcheck source=lib/monarchy.sh
source "$LIB_DIR/monarchy.sh"
# shellcheck source=lib/packages.sh
source "$LIB_DIR/packages.sh"
# shellcheck source=lib/household.sh
source "$LIB_DIR/household.sh"

# Printed from a trap, so a run that dies partway still says what it managed
# to change and what it deliberately left alone before it stopped. That is the
# half of the report that used to be missing entirely: silence read the same
# whether monarchy had looked at something and declined, or never looked.
# The keepalive is stopped first so nothing elevated outlives the run.
trap 'monarchy_sudo_release; monarchy_report_incomplete; monarchy_summary' EXIT

monarchy_cli() {
    case "$1" in
        check) monarchy_check ;;
        apply)
            monarchy_apply
            packages_strip_omarchy_owned
            packages_install_omarchy_aur
            ;;
        update-pre)
            # Guards and the snapshot first, so a host this overlay must never
            # touch is refused before Omarchy's own update gets near it, and
            # so there is something to roll back to if it goes wrong.
            monarchy_ensure_log
            monarchy_load_channel
            monarchy_load_inventories
            monarchy_guards_check
            monarchy_snapshot_first
            # Only when the upgrade it prepares for is actually going to run.
            # --only and --no-omarchy-update skip that upgrade, and building
            # against a release bump without it leaves omarchy installed with
            # an unsatisfied omarchy-settings pin -- and silently, because
            # MONARCHY_EXPECT_FULL_UPGRADE turns the guard that would have
            # said so into a note.
            [ "$MONARCHY_RUN_OMARCHY_UPDATE" = 1 ] || return 0
            # Refresh the sync DB first. Everything below reads `pacman -Si`,
            # and the first -Sy in this flow is inside omarchy-update-keyring,
            # which runs after. Against a stale DB the version check sees the
            # release it already tracks, builds nothing, and the upgrade then
            # resolves omarchy's new omarchy-settings pin by reaching for
            # upstream's package -- the exact case this step exists to stop.
            # cachy-update used to keep the DB fresh; ADR 0003 took that away.
            monarchy_sudo pacman -Sy >/dev/null \
                || monarchy_die "pacman -Sy failed; cannot prepare the local packages"
            # Before the upgrade, not after. omarchy 4.0.5 depends on
            # omarchy-settings=4.0.5; our replacement still provides 4.0.4,
            # so a --noconfirm -Syu would resolve that by pulling upstream's
            # omarchy-settings, which conflicts with ours, which --noconfirm
            # answers by replacing it -- and upstream's post_install is the
            # `rm -f /etc/os-release` this repo exists to keep off the box.
            # Building ours to the new version first is what makes the
            # upgrade resolve without reaching for upstream's.
            export MONARCHY_EXPECT_FULL_UPGRADE=1
            monarchy_build_packages
            unset MONARCHY_EXPECT_FULL_UPGRADE
            ;;
        update-post)
            # monarchy_update re-runs the guards and finds the snapshot
            # already taken; what it adds is the classification of whatever
            # the upgrade landed, and the overlay rebuilt over it.
            monarchy_update
            packages_strip_omarchy_owned
            packages_install_omarchy_aur
            monarchy_after_omarchy_update
            ;;
        splash) monarchy_splash_only ;;
        *)
            echo "unknown monarchy mode: $1" >&2
            exit 2
            ;;
    esac
}

case "$MODE" in
    check|splash)
        monarchy_cli "$MODE"
        exit 0
        ;;
esac

printf '%sWelcome back, commander.%s\n' "$MONARCHY_UI_BOLD" "$MONARCHY_UI_OFF"
monarchy_sudo_hold

# Whether Omarchy's own update runs this time. The pre phase prepares for it,
# so both have to agree; they used to be two separate conditions and the pre
# phase was the one that leaked.
MONARCHY_RUN_OMARCHY_UPDATE=0
if [ "$MODE" = update ] && [ -z "${MONARCHY_ONLY:-}" ] \
    && [ "${MONARCHY_NO_OMARCHY_UPDATE:-0}" != 1 ]; then
    MONARCHY_RUN_OMARCHY_UPDATE=1
fi

# Guards and the ZFS snapshot run before anything is touched, the household
# refresh included: a host this overlay must never touch is refused while
# nothing has changed yet, and everything after has a rollback point. The
# guards only read, so nothing has been written when they refuse.
if [ "$MODE" = update ]; then
    monarchy_cli update-pre
fi

if [ -z "${MONARCHY_ONLY:-}" ]; then
    household_refresh
fi

case "$MODE" in
    update)
        # Household first, then Omarchy's own update, then monarchy over the
        # top. Dotfiles are front-loaded on purpose: a post-update hook Omarchy
        # fires should find them already linked.
        if [ "$MONARCHY_RUN_OMARCHY_UPDATE" = 1 ]; then
            # -y is upstream's promise not to ask anything. The Omarchy menu
            # wrap-execs this with no terminal, and omarchy-update-confirm
            # would sit there waiting on an answer nobody can give.
            if ! monarchy_can_prompt; then
                OMARCHY_UPDATE_ARGS=(-y)
            fi
            # Its status is captured, not allowed to end the run. Six fallible
            # steps sit between the upgrade and the end of that command -- the
            # AUR pass, mise, the orphan sweep -- and any of them failing used
            # to skip everything below. That leaves the worst state this flow
            # can produce: a new package tree with monarchy's overlay, the
            # session NoDisplay and the greeter still belonging to the old
            # one. The re-apply is what closes that window, so it runs whether
            # or not Omarchy's update finished happily.
            omarchy_rc=0
            monarchy_mark_incomplete
            monarchy_real_omarchy_update "${OMARCHY_UPDATE_ARGS[@]}" || omarchy_rc=$?
            if [ "$omarchy_rc" -ne 0 ]; then
                monarchy_warn "omarchy-update exited $omarchy_rc; applying monarchy over the tree it left"
            fi
            # Upstream's closing step runs after the re-apply instead. See
            # monarchy_after_omarchy_update.
            export MONARCHY_DEFER_SHELL_RESTART=1
        fi
        monarchy_cli update-post
        ;;
    apply|full) monarchy_cli apply ;;
    *)
        echo "unknown monarchy mode: $MODE" >&2
        exit 2
        ;;
esac

# A single unit is not the whole overlay, so --only cannot vouch for it.
[ -n "${MONARCHY_ONLY:-}" ] || monarchy_clear_incomplete

if [ "$MONARCHY_PROVISIONING" = 1 ]; then
    monarchy_section "Done"
    printf '  Reboot so SDDM is the greeter. Plasma stays the family default.\n'
    printf '  The king'"'"'s user defaults to Omarchy. See docs/monarchy-install.md\n'
fi
