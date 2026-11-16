#!/usr/bin/env bash
# A leaf that replaces a package CachyOS installed fails the whole leaves
# transaction under --noconfirm, and every run stops there. Such a leaf has to
# be told apart from one that only provides a name, which pacman installs
# alongside without asking.
#
# No sudo, no network. pacman is answered by stubbed functions.
# shellcheck disable=SC2329  # the stubs are called from packages.sh
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers.sh
source "$TEST_DIR/../helpers.sh"
# shellcheck source=../../lib/monarchy/common.sh
source "$LIB/common.sh"
# shellcheck source=../../lib/monarchy/packages.sh
source "$LIB/packages.sh"

pacman() {
    case "$1 $2" in
        "-Si omarchy-power-profiles-daemon")
            printf 'Repository      : omarchy\nName            : omarchy-power-profiles-daemon\nProvides        : power-profiles-daemon\nConflicts With  : power-profiles-daemon\n'
            ;;
        "-Si neovim")
            printf 'Repository      : extra\nName            : neovim\nProvides        : vi  vim-plugin-runtime\nConflicts With  : None\n'
            ;;
        "-Si tlp-pd")
            printf 'Repository      : extra\nName            : tlp-pd\nProvides        : power-profiles-daemon=0.30\nConflicts With  : power-profiles-daemon\n'
            ;;
        "-Qq power-profiles-daemon")
            [ "${PPD:-1}" = 1 ] && echo power-profiles-daemon
            ;;
        *) return 1 ;;
    esac
}

monarchy_replaces_installed omarchy-power-profiles-daemon \
    || fail "omarchy-power-profiles-daemon over CachyOS's power-profiles-daemon is not taken as a swap"
monarchy_replaces_installed tlp-pd \
    || fail "a versioned Provides is not matched against Conflicts"
if monarchy_replaces_installed neovim; then
    fail "neovim, which conflicts with nothing, was taken as a swap"
fi
if PPD=0 monarchy_replaces_installed omarchy-power-profiles-daemon; then
    fail "taken as a swap with nothing installed for it to replace"
fi

echo "leaves swap tests passed"
