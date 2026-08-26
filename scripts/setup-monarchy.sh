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
        --packages) MONARCHY_INSTALL_PACKAGES=1 ;;
        --splash-only) MODE=splash ;;
        -h|--help)
            cat <<'EOF'
usage: setup-monarchy.sh [--check] [--update] [--no-packages] [--splash-only] [-v]

  --check         Snapshot-free dry-run. Safe on kingfisher.
  --update        Snapshot, fetch, check, then apply.
  (none)          Snapshot-first apply. Refuses kingfisher/bonw9 unless
                  MONARCHY_ALLOW_HOST=1.
  --no-packages   Overlay/repo only (default until PR 4a).
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

case "$MODE" in
    check) monarchy_check ;;
    apply) monarchy_apply ;;
    update) monarchy_update ;;
    splash) monarchy_die "splash is PR 5; not implemented yet" ;;
esac
