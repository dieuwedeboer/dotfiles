#!/usr/bin/env bash
# monarchy-migrate: omarchy-migrate, once the pending migrations have been
# checked against the few things that can brick this host. ADR 0005.
#
# Every Omarchy migration runs by default. One that matches a brick path
# below, and has no row in migrations.deny or migrations.allow, stops the run
# before anything executes, so a human classifies it. The update guard in
# lib/monarchy/update.sh sources this file for the same check.
#
# Installed to /usr/local/bin/monarchy-migrate by the overlay unit, with its
# rules in /var/lib/monarchy/migration-rules, because the omarchy-migrate wrap
# runs in every account and the repo is not readable from all of them.

MONARCHY_MIGRATION_RULES=${MONARCHY_MIGRATION_RULES:-/var/lib/monarchy/migration-rules}

# label<TAB>regex, matched against the script with comment lines removed.
# Limine and snapper are not here: Omarchy's migrations check for them before
# acting, and bin.alias maps the Limine rebuild onto mkinitcpio.
MONARCHY_MIGRATION_BRICK_RULES=(
    $'initramfs or boot loader\tmkinitcpio\\.conf|/etc/mkinitcpio|efibootmgr|/boot/efi|refind|zfsbootmenu|generate-zbm|/etc/kernel/cmdline'
    $'kernel\tlinux-(omarchy|t2|ptl|mainline)'
    $'ZFS\t(^|[^[:alnum:]_-])(zfs|zpool)([^[:alnum:]_-]|$)'
    $'package sources\tpacman\\.conf|omarchy-refresh-pacman|use_omarchy_pacman_config|omarchy-update-system-pkgs|pacman +-S|pacman +-U'
    $'login\t/etc/pam\\.d|sudoers|(^|[^[:alnum:]_-])sddm([^[:alnum:]_-]|$)'
    $'input devices\tusbguard|authorized_default'
)

# Arrays the caller fills: binaries monarchy denies or wraps, and packages.deny.
MONARCHY_MIGRATION_BINARIES=()
MONARCHY_MIGRATION_PKG_DENY=()

# Prints one line per hazard found in a migration. No output means none.
monarchy_migration_hazards() {
    local file=$1 body rule label re name pkg
    body=$(grep -vE '^[[:space:]]*#' "$file")

    for rule in "${MONARCHY_MIGRATION_BRICK_RULES[@]}"; do
        label=${rule%%$'\t'*}
        re=${rule#*$'\t'}
        grep -qE -- "$re" <<<"$body" && printf '%s: %s\n' "$label" "$(grep -oE -- "$re" <<<"$body" | sort -u | paste -sd' ' -)"
    done

    for name in "${MONARCHY_MIGRATION_BINARIES[@]}"; do
        # A migration that names omarchy-migrate is not reaching this wrap.
        [ "$name" = omarchy-migrate ] && continue
        grep -qE -- "(^|[^[:alnum:]_-])${name}([^[:alnum:]_-]|$)" <<<"$body" \
            && printf 'calls %s, which monarchy denies or wraps\n' "$name"
    done

    while read -r pkg; do
        case "$pkg" in
            ''|-*|\$*|\"*) continue ;;
            linux-firmware*|linux-api-headers) ;;
            linux|linux-*) printf 'installs kernel %s\n' "$pkg"; continue ;;
        esac
        for name in "${MONARCHY_MIGRATION_PKG_DENY[@]}"; do
            [ "$pkg" = "$name" ] && printf 'installs %s, which is in packages.deny\n' "$pkg"
        done
    done < <(grep -oP 'omarchy-pkg-add\s+\K[^|;&#]+' <<<"$body" | tr ' ' '\n')
    return 0
}

# Pending migrations that match a brick path and have no row. stdin: names.
# stdout: "<name>: <hazard>" lines. Callers fill the two row arrays.
MONARCHY_MIGRATION_DENIED=()
MONARCHY_MIGRATION_ALLOWED=()
monarchy_unclassified_hazards() {
    local dir=$1 name row hazard skip
    while read -r name; do
        [ -n "$name" ] && [ -f "$dir/$name" ] || continue
        skip=0
        for row in "${MONARCHY_MIGRATION_DENIED[@]}" "${MONARCHY_MIGRATION_ALLOWED[@]}"; do
            [ "$row" = "$name" ] && skip=1
        done
        [ "$skip" = 0 ] || continue
        while IFS= read -r hazard; do
            [ -n "$hazard" ] && printf '%s: %s\n' "$name" "$hazard"
        done < <(monarchy_migration_hazards "$dir/$name")
    done
}

monarchy_migrate_main() {
    local real=${MONARCHY_REAL_MIGRATE:-/usr/share/omarchy/bin/omarchy-migrate}
    local dir=${MONARCHY_MIGRATIONS_DIR:-/usr/share/omarchy/migrations}
    local kind value found

    # Anything but a plain run (--pending, --help) only reads.
    if [ $# -gt 0 ]; then
        exec "$real" "$@"
    fi

    [ -r "$MONARCHY_MIGRATION_RULES" ] || {
        echo "monarchy-migrate: $MONARCHY_MIGRATION_RULES is missing; run monarchy-update first" >&2
        exit 1
    }
    while read -r kind value; do
        case "$kind" in
            deny) MONARCHY_MIGRATION_DENIED+=("$value") ;;
            allow) MONARCHY_MIGRATION_ALLOWED+=("$value") ;;
            binary) MONARCHY_MIGRATION_BINARIES+=("$value") ;;
            pkg-deny) MONARCHY_MIGRATION_PKG_DENY+=("$value") ;;
        esac
    done <"$MONARCHY_MIGRATION_RULES"

    # --pending exits 1 when nothing is pending.
    found=$( { "$real" --pending 2>/dev/null || true; } | monarchy_unclassified_hazards "$dir")
    if [ -n "$found" ]; then
        echo "These pending migrations touch something that can brick this machine:" >&2
        printf '  %s\n' "${found//$'\n'/$'\n'  }" >&2
        echo "Nothing has run. Add each to monarchy/migrations.allow or migrations.deny, run monarchy-update, then run this again." >&2
        exit 1
    fi
    exec "$real"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -euo pipefail
    monarchy_migrate_main "$@"
fi
