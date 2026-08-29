# shellcheck shell=bash
# Quiet ZBM and host kernel command lines. Sourced from setup-zfs.sh.

ZBM_CONFIG="${ZBM_CONFIG:-/etc/zfsbootmenu/config.yaml}"
ZBM_HOST_TOKENS=(
    rw quiet splash loglevel=0
    systemd.show_status=false
    rd.udev.log_level=0
    vt.global_cursor_default=0
)
ZBM_IMAGE_TOKENS=(
    ro quiet loglevel=0
    vt.global_cursor_default=0
    fbcon=logo-count:0
    rd.udev.log_level=0
)

zbm_merge_cmdline() {
    local current=$1
    shift
    # shellcheck disable=SC2086
    set -- $current "$@"
    local -a out=()
    local tok seen
    for tok in "$@"; do
        seen=0
        local have
        for have in "${out[@]+"${out[@]}"}"; do
            if [ "$have" = "$tok" ]; then
                seen=1
                break
            fi
        done
        [ "$seen" = 1 ] || out+=("$tok")
    done
    printf '%s\n' "${out[*]}"
}

zbm_pool_from_root() {
    local src fstype
    fstype=$(findmnt -n -o FSTYPE / 2>/dev/null || true)
    [ "$fstype" = zfs ] || return 1
    src=$(findmnt -n -o SOURCE / 2>/dev/null || true)
    [ -n "$src" ] || return 1
    printf '%s\n' "${src%%/*}"
}

zbm_yaml_cmdline() {
    local file=$1
    [ -f "$file" ] || return 1
    awk '
        /^[[:space:]]*CommandLine:[[:space:]]*/ {
            line = $0
            sub(/^[[:space:]]*CommandLine:[[:space:]]*/, "", line)
            gsub(/^["'\'']|["'\'']$/, "", line)
            print line
            found = 1
            exit
        }
        END { exit found ? 0 : 1 }
    ' "$file"
}

zbm_yaml_set_cmdline() {
    local file=$1
    local value=$2
    local tmp
    tmp=$(mktemp)
    if grep -qE '^[[:space:]]*CommandLine:' "$file"; then
        awk -v v="$value" '
            /^[[:space:]]*CommandLine:[[:space:]]*/ {
                print "  CommandLine: " v
                next
            }
            { print }
        ' "$file" >"$tmp"
    elif grep -qE '^Kernel:' "$file"; then
        awk -v v="$value" '
            /^Kernel:/ { print; print "  CommandLine: " v; next }
            { print }
        ' "$file" >"$tmp"
    else
        cat "$file" >"$tmp"
        printf '\nKernel:\n  CommandLine: %s\n' "$value" >>"$tmp"
    fi
    cat "$tmp" >"$file"
    rm -f "$tmp"
}

zbm_apply_host_cmdline() {
    local pool current merged
    command -v zfs >/dev/null 2>&1 || return 0
    pool=$(zbm_pool_from_root) || return 0
    current=$(zfs get -H -o value org.zfsbootmenu:commandline "$pool" 2>/dev/null || true)
    [ "$current" = "-" ] && current=""
    merged=$(zbm_merge_cmdline "$current" "${ZBM_HOST_TOKENS[@]}")
    if [ "$merged" = "$current" ]; then
        echo "  org.zfsbootmenu:commandline already quiet on $pool"
        return 0
    fi
    echo "  set org.zfsbootmenu:commandline on $pool"
    sudo zfs set "org.zfsbootmenu:commandline=$merged" "$pool"
}

zbm_apply_image_cmdline() {
    local file=$ZBM_CONFIG
    local current merged
    [ -f "$file" ] || {
        echo "  $file missing; skip ZBM image cmdline"
        return 0
    }
    current=$(zbm_yaml_cmdline "$file" || true)
    merged=$(zbm_merge_cmdline "$current" "${ZBM_IMAGE_TOKENS[@]}")
    if [ "$merged" = "$current" ]; then
        echo "  $file Kernel.CommandLine already quiet"
        return 0
    fi
    echo "  update Kernel.CommandLine in $file"
    local tmp
    tmp=$(mktemp)
    cp -a "$file" "$tmp"
    zbm_yaml_set_cmdline "$tmp" "$merged"
    sudo cp "$tmp" "$file"
    rm -f "$tmp"
    if ! command -v generate-zbm >/dev/null 2>&1; then
        echo "  generate-zbm not installed; yaml updated, image not rebuilt"
        return 0
    fi
    echo "  generate-zbm"
    sudo generate-zbm
}

zbm_apply_quiet_boot() {
    echo "=== Quiet ZFSBootMenu and host cmdline ==="
    zbm_apply_host_cmdline
    zbm_apply_image_cmdline
}
