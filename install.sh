#!/usr/bin/env bash
# One entry point. Bare ./install.sh on a fresh box is household bootstrap
# plus Monarchy apply. After /etc/omarchy.conf exists, bare ./install.sh is
# the same as --update: household refresh (packages, chezmoi, hardware, ZFS)
# then snapshot, rebuild packages, classify, apply. PATH has monarchy-update
# (this file, --update).
set -e
VERBOSE=0
MODE=full
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
  --update        Household refresh, then snapshot, rebuild packages,
                  classify, apply. After the first install this is the
                  command; monarchy-update is this file with --update.
  --no-packages   Monarchy apply without pacman leaf packages. Still refreshes
                  chezmoi-managed dotfiles.
  --splash-only   Omarchy Plymouth theme, plymouth around zfs, retain-splash.
  --only=<unit>   Run one unit only. Combines with --check and --update.
                  Skips the household refresh. Units: guards pacman packaging
                  prefix overlay leaves settings sddm session logind portals
                  user splash

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
        update)
            monarchy_update
            packages_strip_omarchy_owned
            packages_install_omarchy_aur
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
if [ -z "${MONARCHY_ONLY:-}" ]; then
    household_refresh
fi

case "$MODE" in
    update) monarchy_cli update ;;
    apply|full) monarchy_cli apply ;;
    *)
        echo "unknown monarchy mode: $MODE" >&2
        exit 2
        ;;
esac

monarchy_section "Done"
printf '  Reboot so SDDM is the greeter. Plasma stays the family default.\n'
printf '  The king'"'"'s user defaults to Omarchy. See docs/monarchy-install.md\n' 
