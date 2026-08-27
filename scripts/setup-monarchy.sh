#!/usr/bin/env bash
set -e
VERBOSE=0
MODE=apply
for arg in "$@"; do
    case "$arg" in
        -v|-r|--verbose) VERBOSE=1 ;;
        --check) MODE=check ;;
        --update) MODE=update ;;
        --no-packages) MONARCHY_NO_PACKAGES=1 ;;
        --splash-only) MODE=splash ;;
        -h|--help)
            cat <<'EOF'
usage: setup-monarchy.sh [--check] [--update] [--no-packages] [--splash-only] [-v]

  --check         Snapshot-free dry-run. Safe on kingfisher.
  --update        Snapshot, fetch, check, then apply.
  (none)          Snapshot-first apply: clone, overlay, trust Omarchy
                  packaging key (prompts once), [omarchy] repo, filtered
                  packages, greeter session, UWSM env, user Hyprland
                  config. Refuses kingfisher/bonw9 unless MONARCHY_ALLOW_HOST=1.
                  MONARCHY_TRUST_OMARCHY_KEY=1 skips the key prompt.
  --no-packages   Skip pacman leaf packages (still does overlay, repo, session).
  --splash-only   Branding + Plymouth HOOKS (PR 5; not implemented yet).

First apply is an older laptop, not kingfisher. Build and review may run
--check here.
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/monarchy/common.sh
source "$SCRIPT_DIR/lib/monarchy/common.sh"
# shellcheck source=lib/monarchy/denylist.sh
source "$SCRIPT_DIR/lib/monarchy/denylist.sh"
# shellcheck source=lib/monarchy/clone.sh
source "$SCRIPT_DIR/lib/monarchy/clone.sh"
# shellcheck source=lib/monarchy/overlay.sh
source "$SCRIPT_DIR/lib/monarchy/overlay.sh"
# shellcheck source=lib/monarchy/pacman.sh
source "$SCRIPT_DIR/lib/monarchy/pacman.sh"
# shellcheck source=lib/monarchy/update.sh
source "$SCRIPT_DIR/lib/monarchy/update.sh"
# shellcheck source=lib/monarchy/packages.sh
source "$SCRIPT_DIR/lib/monarchy/packages.sh"
# shellcheck source=lib/monarchy/sessions.sh
source "$SCRIPT_DIR/lib/monarchy/sessions.sh"
# shellcheck source=lib/monarchy/portals.sh
source "$SCRIPT_DIR/lib/monarchy/portals.sh"
# shellcheck source=lib/monarchy/user.sh
source "$SCRIPT_DIR/lib/monarchy/user.sh"

case "$MODE" in
    check) monarchy_check ;;
    apply) monarchy_apply ;;
    update) monarchy_update ;;
    splash) monarchy_die "splash is PR 5; not implemented yet" ;;
esac
