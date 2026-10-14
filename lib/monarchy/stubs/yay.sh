#!/usr/bin/env bash
# Overlay-only. Do not install into /usr/local/bin.
echo "monarchy: yay is denied; using paru" >&2
if ! command -v paru >/dev/null 2>&1; then
    echo "monarchy: paru is not installed" >&2
    exit 1
fi

# yay spells a boolean --sudoloop=false. paru reads anything after = as
# arguments for its sudo loop, so the same flag turns the loop on, and
# omarchy-update-aur-pkgs passes it right after revoking sudo.
args=()
for arg in "$@"; do
    case "$arg" in
        --sudoloop=false) args+=(--nosudoloop) ;;
        --sudoloop=true) args+=(--sudoloop) ;;
        *) args+=("$arg") ;;
    esac
done
exec paru "${args[@]}"
