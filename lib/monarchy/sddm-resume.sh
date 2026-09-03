#!/usr/bin/env bash
# Activate an existing Wayland session for a user. Used by the SDDM greeter
# so Enter does not call sddm.login() (that starts a second compositor and
# has crashed this machine).
set -euo pipefail

LOGINCTL=${MONARCHY_LOGINCTL:-loginctl}

if [ "${1:-}" = --httpd ]; then
    port=${MONARCHY_SDDM_RESUME_PORT:-17621}
    bin=${MONARCHY_SDDM_RESUME_BIN:-/usr/local/bin/monarchy-sddm-resume}
    export MONARCHY_SDDM_RESUME_PORT=$port
    export MONARCHY_SDDM_RESUME_BIN=$bin
    exec python3 - <<'PY'
import os, subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

PORT = int(os.environ["MONARCHY_SDDM_RESUME_PORT"])
BIN = os.environ["MONARCHY_SDDM_RESUME_BIN"]
PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489"
    "0000000a49444154789c63000100000500010d0a2db40000000049454e44ae426082"
)

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        u = urlparse(self.path)
        if u.path != "/resume":
            self.send_error(404)
            return
        user = (parse_qs(u.query).get("user") or [""])[0]
        r = subprocess.run([BIN, user], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if r.returncode == 0:
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(PNG)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(PNG)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *_args):
        pass

HTTPServer(("127.0.0.1", PORT), H).serve_forever()
PY
fi

user=${1:-}
[[ "$user" =~ ^[a-z_][a-z0-9_-]*$ ]] || exit 1

best=
best_ts=

while read -r sid _ name _; do
    [ -n "$sid" ] || continue
    [ "$name" = "$user" ] || continue
    dump=$($LOGINCTL show-session "$sid" 2>/dev/null) || continue
    class='' type='' seat='' state='' ts=''
    while IFS= read -r line; do
        case "$line" in
            Class=*) class=${line#Class=} ;;
            Type=*) type=${line#Type=} ;;
            Seat=*) seat=${line#Seat=} ;;
            State=*) state=${line#State=} ;;
            TimestampMonotonic=*) ts=${line#TimestampMonotonic=} ;;
        esac
    done <<<"$dump"
    [ "$class" = user ] || continue
    [ "$type" = wayland ] || continue
    [ "$seat" = seat0 ] || continue
    case "$state" in
        active|online) ;;
        *) continue ;;
    esac
    if [ -z "$best" ] || [ "${ts:-0}" -lt "${best_ts:-0}" ]; then
        best=$sid
        best_ts=${ts:-0}
    fi
done < <($LOGINCTL list-sessions --no-legend 2>/dev/null)

[ -n "$best" ] || exit 1
$LOGINCTL activate "$best"
exit 0
