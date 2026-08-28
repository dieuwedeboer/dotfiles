#!/usr/bin/env bash
# Sliding-window watt math against recorded 14u G6 charge_now steps. No sudo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RATE=$SCRIPT_DIR/battery-rate
fail() {
    echo "test-battery-rate: $*" >&2
    exit 1
}

[ -x "$RATE" ] || fail "battery-rate is not executable"

# Live sample from this G6: 3000 uAh drop, ~11.55 V, 15.7 s -> ~8 W.
got=$("$RATE" --compute <<'EOF'
0.00  2651000  11579000
15.70 2648000  11522000
EOF
)
# 3000 uAh / 15.7 s * 3600 * 11.5505 V / 1e6 uW-per-W ~= 7.96e6 uW
if [ "$got" -lt 7000000 ] || [ "$got" -gt 9000000 ]; then
    fail "expected ~8W in uW, got $got"
fi

# Window too short -> no print, exit 1
if "$RATE" --compute <<'EOF' >/dev/null; then
0 2651000 11500000
2 2648000 11500000
EOF
    fail "short window should fail"
fi

# No charge movement -> no print
if "$RATE" --compute <<'EOF' >/dev/null; then
0  2651000 11500000
20 2651000 11500000
EOF
    fail "unchanged charge should fail"
fi

# Charging (charge_now rises) still reports a positive rate
got=$("$RATE" --compute <<'EOF'
0  2000000 12000000
20 2100000 12100000
EOF
)
if [ "$got" -le 0 ]; then
    fail "charging rate should be positive, got $got"
fi

echo "zbook battery-rate tests passed"
