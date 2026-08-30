# shellcheck shell=bash
# Load the Monarchy library. Sourced from install.sh.

_monarchy_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/monarchy" && pwd)
# shellcheck source=monarchy/common.sh
source "$_monarchy_dir/common.sh"
# shellcheck source=monarchy/denylist.sh
source "$_monarchy_dir/denylist.sh"
# shellcheck source=monarchy/clone.sh
source "$_monarchy_dir/clone.sh"
# shellcheck source=monarchy/overlay.sh
source "$_monarchy_dir/overlay.sh"
# shellcheck source=monarchy/pacman.sh
source "$_monarchy_dir/pacman.sh"
# shellcheck source=monarchy/update.sh
source "$_monarchy_dir/update.sh"
# shellcheck source=monarchy/packages.sh
source "$_monarchy_dir/packages.sh"
# shellcheck source=monarchy/sessions.sh
source "$_monarchy_dir/sessions.sh"
# shellcheck source=monarchy/portals.sh
source "$_monarchy_dir/portals.sh"
# shellcheck source=monarchy/settings.sh
source "$_monarchy_dir/settings.sh"
# shellcheck source=monarchy/plugins.sh
source "$_monarchy_dir/plugins.sh"
# shellcheck source=monarchy/user.sh
source "$_monarchy_dir/user.sh"
# shellcheck source=monarchy/sddm.sh
source "$_monarchy_dir/sddm.sh"
# shellcheck source=monarchy/splash.sh
source "$_monarchy_dir/splash.sh"
unset _monarchy_dir
