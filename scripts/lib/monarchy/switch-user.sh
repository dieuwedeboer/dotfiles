#!/usr/bin/env bash
# Lock the Omarchy session if needed, then SwitchToGreeter.
# Super+Ctrl+U from the menu, Hyprland, or the lock screen.
set -euo pipefail

DM=org.freedesktop.DisplayManager
SEAT_PATH=/org/freedesktop/DisplayManager/Seat0
SEAT_IFACE=org.freedesktop.DisplayManager.Seat
LOCK_TRIES=${MONARCHY_SWITCH_USER_LOCK_TRIES:-50}
LOCK_SLEEP=${MONARCHY_SWITCH_USER_LOCK_SLEEP:-0.1}

die() {
    echo "monarchy-switch-user: $*" >&2
    exit 1
}

lock_state() {
    local st out
    # isLocked is true as soon as lockRequested is set, before ext-session-lock
    # is held. Wait for the compositor lock so SwitchToGreeter cannot leave a
    # live desktop on the old VT.
    st=$(omarchy-shell lock status 2>/dev/null || true)
    if [ -n "$st" ]; then
        case "$st" in
            *'"secure":true'*|*'"sessionLocked":true'*) return 0 ;;
        esac
        return 1
    fi
    out=$(omarchy-shell lock isLocked 2>/dev/null || true)
    out=${out//$'\n'/}
    [ "$out" = true ]
}

can=$(busctl --system get-property "$DM" "$SEAT_PATH" "$SEAT_IFACE" CanSwitch 2>/dev/null || true)
case "$can" in
    *true*) ;;
    *) die "plasma-login-manager CanSwitch is not true ($can)" ;;
esac

if lock_state; then
    busctl --system call "$DM" "$SEAT_PATH" "$SEAT_IFACE" SwitchToGreeter
    exit 0
fi

command -v omarchy-system-lock >/dev/null 2>&1 || die "omarchy-system-lock is missing"
command -v omarchy-shell >/dev/null 2>&1 || die "omarchy-shell is missing"

got=$(omarchy-shell lock lock 2>/dev/null || true)
got=${got//$'\n'/}
[ "$got" = ok ] || die "could not lock ($got); not switching"
omarchy-system-lock

i=0
while [ "$i" -lt "$LOCK_TRIES" ]; do
    if lock_state; then
        busctl --system call "$DM" "$SEAT_PATH" "$SEAT_IFACE" SwitchToGreeter
        exit 0
    fi
    sleep "$LOCK_SLEEP"
    i=$((i + 1))
done

die "session did not lock; not switching"
