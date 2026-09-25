#!/usr/bin/env bash
# One entry point. Bare ./install.sh on a fresh box is household bootstrap
# plus Monarchy apply. After /etc/omarchy.conf exists, bare ./install.sh is
# the same as --update: household refresh (packages, chezmoi, hardware, ZFS)
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
                  chezmoi, rEFInd glow, services, hardware, ZFS, then apply.
                  Once /etc/omarchy.conf exists, the same as --update.
  --check         Monarchy dry-run. Writes nothing under /etc or /usr/local.
  --update        Guards and a ZFS snapshot, household refresh (chezmoi
                  front-loaded), then Omarchy's own `omarchy-update` in full,
                  then rebuild packages, classify and apply over the top.
                  After the first install this is the command; monarchy-update
                  is this file with --update, and the overlay's omarchy-update
                  is a wrapper onto it.
  --no-packages   Monarchy apply without pacman leaf packages. Still refreshes
                  chezmoi-managed dotfiles.
  --splash-only   Omarchy Plymouth theme, plymouth around zfs, retain-splash.
  --only=<unit>   Run one unit only. Combines with --check and --update.
                  Skips the household refresh and Omarchy's own update.
                  Units: guards pacman packaging prefix overlay leaves
                  settings sddm session logind portals user splash
  -y              Passed to `omarchy update`: do not ask anything.
  --no-omarchy-update
                  Monarchy only. Household refresh, snapshot, classify,
                  apply -- without running Omarchy's own update in the
                  middle. For iterating on monarchy without a full -Syu.

  omarchy-update (Omarchy menu) wraps monarchy-update. That path has no
  terminal, so chezmoi apply is skipped rather than hanging on a prompt.

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
trap monarchy_summary EXIT

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
            monarchy_load_lock
            monarchy_load_inventories
            monarchy_guards_check
            monarchy_snapshot_first
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

# Guards and the ZFS snapshot run before anything is touched, the household
# refresh included: a host this overlay must never touch is refused while
# nothing has changed yet, and everything after has a rollback point.
if [ "$MODE" = update ]; then
    monarchy_cli update-pre
fi

if [ -z "${MONARCHY_ONLY:-}" ]; then
    household_refresh
fi

case "$MODE" in
    update)
        # Household first, then Omarchy's own update, then monarchy over the
        # top. Dotfiles are front-loaded on purpose: a template that reads a
        # package version should see the one the box is about to run, and a
        # post-update hook Omarchy fires should find chezmoi already applied.
        if [ -z "${MONARCHY_ONLY:-}" ] && [ "${MONARCHY_NO_OMARCHY_UPDATE:-0}" != 1 ]; then
            # -y is upstream's promise not to ask anything. The Omarchy menu
            # wrap-execs this with no terminal, and omarchy-update-confirm
            # would sit there waiting on an answer nobody can give.
            if ! monarchy_can_prompt; then
                OMARCHY_UPDATE_ARGS=(-y)
            fi
            monarchy_real_omarchy_update "${OMARCHY_UPDATE_ARGS[@]}"
        fi
        monarchy_cli update-post
        ;;
    apply|full) monarchy_cli apply ;;
    *)
        echo "unknown monarchy mode: $MODE" >&2
        exit 2
        ;;
esac

monarchy_section "Done"
printf '  Reboot so SDDM is the greeter. Plasma stays the family default.\n'
printf '  The king'"'"'s user defaults to Omarchy. See docs/monarchy-install.md\n' 
