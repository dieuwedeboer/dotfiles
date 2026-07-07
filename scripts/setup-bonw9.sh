#!/usr/bin/env bash
set -e
[ "${VERBOSE:-0}" = 1 ] && set -x

# =========================================================================
# bonw9 = System76 Bonobo WS (Clevo P170SM-A barebone)
# Haswell i7-4810MQ + NVIDIA GTX 970M (Maxwell GM204). No iGPU fallback:
# the internal LVDS panel is wired straight to the dGPU, so runtime D3 is
# impossible and the dGPU stays in D0 across S3.
# =========================================================================
# Scope of THIS script (2026-07-08 rewrite):
#   - Install + enable Tuxedo Control Center (tccd) for the EC fan curve.
#   - Patch TCC persistence quirks (profile + keyboard backlight).
# What this script deliberately does NOT do (see Lessons learned below):
#   - Touch the kernel cmdline.
#   - Touch nvidia-suspend/resume/hibernate services.
#   - Touch NVreg_PreserveVideoMemoryAllocations.
#   - Touch the Clevo EC directly.
#   - Touch the systemd-sleep hooks.
# =========================================================================
# TCC persistence quirks (the reason the edit-tccd-config block exists):
#   1. SetTempProfileById (TCC GUI dbus call) is temporary — it updates
#      tccd's in-memory stateMap but not /etc/tcc/settings. On reboot
#      tccd reads the persisted stateMap, sees the old profile, and
#      activates that instead. We directly edit the custom profile's
#      fanProfile in /etc/tcc/profiles to "Quiet" so the persisted
#      profile uses the Quiet fan curve.
#   2. Keyboard backlight colour changes made via the TCC GUI update
#      tccd's in-memory settings but are only flushed to disk on clean
#      exit. If tccd is killed abruptly, the changes are lost. We sync
#      the live sysfs state (rgb:kbd_backlight) into the persisted
#      settings file.
# Both edits are done with tccd stopped to prevent it overwriting our
# changes on exit. tccd is restarted afterwards.
# =========================================================================
#
# =========================================================================
# Lessons learned (dead ends) — DO NOT REDO, see leads at the bottom of
# each block before touching this box again.
# =========================================================================
#
# (A) Raw EC writes for fan duty / fan mode.
#     What we tried: clevo-ec 0xB8 0x01 (manual mode) + 0xB0 0x00 /
#     0xB1 0x00 (CPU/GPU fan off) and the inverse to restore. EC reads
#     return consistent values; writes succeed (no timeout); fan RPM
#     does not change.
#     Why it failed: register addresses 0xB0/0xB1/0xB8 are the
#     canonical Clevo ITE-EC layout from tuxedo-cc / clevo-xsm-wmi,
#     but the EC firmware on bonw9 (Clevo P170SM-A) appears to use a
#     different layout. The original clevo-ec.c header flagged this
#     as unverified; the experiment on real hardware confirmed it.
#     Leads for next time:
#       - tuxedo-cc's `tuxedo-io` kernel driver IS the path that
#         actually drives the fan on this board (it's what TCC uses
#         to apply its profile). The kernel-driver layer works; only
#         the bare-metal register addresses are unknown. So if fan
#         control ever breaks, debug tccd / tuxedo-io first, not EC
#         registers.
#       - If raw EC access ever becomes necessary, dump all 256 EC
#         registers while the fan is at a known duty and again at a
#         different duty. Registers that change in a way correlated
#         with fan duty are the real control registers. The original
#         `clevo-ec dump` was the right tool for this — re-derive it
#         from tuxedo-cc's clevo-xsm-wmi source if needed.
#
# (B) Pre-suspend EC write to silence the fan during S3.
#     What we tried: systemd system-sleep hook that flips manual mode
#     + fan-off before systemd-suspend, restores auto on resume. See
#     (A): the EC writes succeed (no timeout) but the fan behaviour
#     during S3 is unchanged.
#     Why it failed: depends on (A) being correct, so it's doubly
#     broken. Independently of the address issue, the EC firmware's
#     S3 fan behaviour may not be reachable via runtime EC writes at
#     all — the EC may switch into a different S3 mode regardless.
#     Leads for next time:
#       - Investigate whether tccd exposes a dbus method to apply a
#         different profile during S3. If tccd's profile persists
#         into suspend, the EC's own S3 fan logic might pick it up.
#       - Look at the EC firmware's documented S3 mode (if Clevo ever
#         published a spec for P170SM-A's EC). The `S3` fan mode may
#         be set by a completely different register than runtime
#         duty.
#       - The original symptom ("fan blasts at 100% during S3, often
#         forever") is also reported on similar Clevo barebones on
#         Linux; the canonical fix on those is usually BIOS/EC
#         firmware update. Check whether System76 published an EC
#         update for bonw9 that addresses it.
#
# (C) Disable nvidia-suspend / nvidia-resume / nvidia-hibernate
#     systemd services + modprobe.d override of
#     NVreg_PreserveVideoMemoryAllocations=0.
#     What we tried: `systemctl disable nvidia-suspend nvidia-resume
#     nvidia-hibernate` and an /etc/modprobe.d/nvidia-suspend-fix.conf
#     containing `options nvidia
#     NVreg_PreserveVideoMemoryAllocations=0`. Both applied to the
#     live machine.
#     Why it failed: does not prevent the suspend hang. Symptom is
#     unchanged: systemd-suspend.service hangs, fans blast at 100%
#     (EC failsafe), screen stays black, hard reset required.
#     The original hypothesis (nvidia_uvm crashes in uvm_suspend()
#     during the procfs suspend write — driver 580.159.04 bug on
#     kernel 6.18+) may be wrong, or the driver has another suspend
#     path that still triggers the crash even with the procfs path
#     bypassed.
#     Leads for next time:
#       - CAPTURE the actual hang before doing anything else. After
#         a hung suspend and a hard reset, boot and immediately run
#         `journalctl -b -1` (the previous boot) and look for the
#         last task to log before silence. Also `dmesg` for any
#         nvidia backtrace near the suspend timestamp.
#       - The hang may not be nvidia-related at all. Check whether
#         any other driver logs errors during the suspend sequence.
#         Haswell-era boards with NVIDIA dGPU also have known issues
#         with the i915 driver being loaded-but-unused; check
#         `lsmod | grep -E 'i915|nvidia'` and consider blacklisting
#         i915 if it loads but no device is present.
#       - The most reliable diagnostic is to bisect: try suspend
#         with `nvidia_uvm` rmmod'd manually first (do this from a
#         TTY, not SSH, since you'll lose the dGPU). If that fixes
#         it, nvidia_uvm is the culprit; if not, the driver layer
#         to suspect is the main `nvidia` module's PCI PM path, not
#         UVM.
#       - If nvidia_uvm IS the culprit, the proper fix is upstream
#         (driver update), not disabling services. Track the nvidia
#         driver changelog; the 580.x series had a known UVM suspend
#         regression reported on multiple forums.
#       - PreserveVideoMemoryAllocations=0 is the right setting for
#         this hardware if nvidia-suspend.service is enabled. Do not
#         re-enable both — they're independent bugs that interact
#         badly.
#
# (D) Screen brightness — NOT SOFTWARE-CONTROLLABLE on bonw9.
#     The Clevo EC firmware drives the LVDS backlight PWM pin directly
#     via a hardware path that no software interface can reach.
#     What we tried / verified dead:
#       - ACPI _BCM (SSDT2:378): both branches are dead code. ECBL
#         is initialised to Zero and never set to non-zero in any
#         table, so the EC.OEM2 write is never taken. The GPU PWM
#         branch checks PBCC (PCI config 0x03 = GPU device ID high
#         byte = 0x13, never 1), so it's dead too.
#       - EC register 0xC9 (OEM2): direct write tested — no effect.
#         EC RAM doesn't even change when Fn brightness keys work.
#       - GPU MMIO PWM registers: blocked by CONFIG_STRICT_DEVMEM=y
#         + CONFIG_IO_STRICT_DEVMEM=y. Even if accessible, the EC
#         likely owns the PWM pin directly.
#       - NVIDIA driver nvidia_0 "raw" backlight: registers but
#         doesn't reach the panel (EC owns the PWM).
#       - No ACPI events from Fn brightness keys — EC handles them
#         in firmware.
#     Why it failed: hardware, not software. The EC and the panel
#     are wired together with no kernel-visible control path.
#     Leads for next time (low probability of success):
#       - Physically probe the backlight PWM pin on the LVDS
#         connector to confirm EC ownership. If the EC drives the
#         pin directly, no kernel fix is possible.
#       - Clevo backlight control via SMM (System Management Mode)
#         has worked on some older Clevo barebones. Requires an SMM
#         handler hook in firmware — almost certainly not feasible
#         on a Haswell-era board without vendor cooperation.
#       - The 2026 driver landscape may have changed. Re-check
#         `ls /sys/class/backlight/` after a kernel update; a new
#         `nvidia_0` or `acpi_video0` interface showing up would be
#         a real change worth investigating.
#     Workaround (permanent): brightness is only changeable via the
#     Fn keys. Do NOT add `acpi_backlight=video` or
#     `acpi_backlight=native` to the kernel cmdline — both create
#     non-functional /sys/class/backlight devices that make KDE show
#     a useless brightness slider.
#
# (E) CD tray pops open on resume.
#     Symptom reported but unconfirmed. No `acpi_listen` log
#     captured, no reproducible steps.
#     Lead for next time: run `sudo acpi_listen` during a wake from
#     suspend. If a `cdrom` eject event appears, add a udev rule
#     under /etc/udev/rules.d/ to swallow the spurious event.
# =========================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== bonw9 (System76 Bonobo WS) setup ==="

# -------------------------------------------------------------------------
# AUR packages: Tuxedo Control Center for the EC fan curve.
# -------------------------------------------------------------------------
AUR_PACKAGES=(
    tuxedo-control-center-bin
)

if command -v paru &> /dev/null; then
    for pkg in "${AUR_PACKAGES[@]}"; do
        if paru -Q "$pkg" &> /dev/null; then
            echo "  $pkg already installed"
        else
            echo "  Installing $pkg..."
            paru -S --noconfirm "$pkg"
        fi
    done
else
    echo "  paru not found — install paru first (run scripts/setup-packages.sh)"
    exit 1
fi

echo "Enabling tccd (Tuxedo Control Center daemon) for EC fan curves..."
if ! systemctl is-enabled tccd &> /dev/null; then
    sudo systemctl enable --now tccd
else
    echo "  tccd already enabled"
fi

# -------------------------------------------------------------------------
# TCC profile + keyboard backlight persistence (see header for why these
# edits are done manually instead of via the TCC GUI dbus API).
# -------------------------------------------------------------------------
TCC_SETTINGS=/etc/tcc/settings
TCC_PROFILES=/etc/tcc/profiles

echo "Configuring TCC profile + keyboard backlight persistence..."

# Stop tccd before editing config files so it doesn't overwrite our
# changes on exit.
echo "  Stopping tccd to edit config files..."
sudo systemctl stop tccd

# 1. Set custom profile fanProfile to "Quiet"
if [ -f "$TCC_PROFILES" ] && sudo jq empty "$TCC_PROFILES" 2>/dev/null; then
    CURRENT_FAN=$(sudo jq -r '.[0].fan.fanProfile // empty' "$TCC_PROFILES")
    if [ "$CURRENT_FAN" = "Quiet" ]; then
        echo "  Custom profile fanProfile already 'Quiet' — no change"
    else
        echo "  Updating custom profile fanProfile: '$CURRENT_FAN' → 'Quiet'"
        sudo jq '.[0].fan.fanProfile = "Quiet"' "$TCC_PROFILES" | sudo tee "${TCC_PROFILES}.tmp" > /dev/null && sudo mv "${TCC_PROFILES}.tmp" "$TCC_PROFILES"
    fi
else
    echo "  WARNING: $TCC_PROFILES missing or invalid — skipping profile fix"
fi

# 2. Sync live keyboard backlight states from sysfs to the TCC settings
# file. tccd is stopped, so its dbus interface is unavailable; the
# sysfs nodes under /sys/class/leds/rgb:kbd_backlight/ are the live
# source of truth for the current keyboard colour.
if [ -r /sys/class/leds/rgb:kbd_backlight/multi_intensity ]; then
    KBD_BRIGHTNESS=$(cat /sys/class/leds/rgb:kbd_backlight/brightness 2>/dev/null || echo 0)
    KBD_RED=$(cat /sys/class/leds/rgb:kbd_backlight/multi_intensity 2>/dev/null | awk '{print $1}' || echo 0)
    KBD_GREEN=$(cat /sys/class/leds/rgb:kbd_backlight/multi_intensity 2>/dev/null | awk '{print $2}' || echo 0)
    KBD_BLUE=$(cat /sys/class/leds/rgb:kbd_backlight/multi_intensity 2>/dev/null | awk '{print $3}' || echo 0)

    LIVE_KBD="[{\"mode\":0,\"brightness\":${KBD_BRIGHTNESS},\"red\":${KBD_RED},\"green\":${KBD_GREEN},\"blue\":${KBD_BLUE}},{\"mode\":0,\"brightness\":${KBD_BRIGHTNESS},\"red\":${KBD_RED},\"green\":${KBD_GREEN},\"blue\":${KBD_BLUE}},{\"mode\":0,\"brightness\":${KBD_BRIGHTNESS},\"red\":${KBD_RED},\"green\":${KBD_GREEN},\"blue\":${KBD_BLUE}}]"

    DISK_KBD=$(sudo jq -c '.keyboardBacklightStates // empty' "$TCC_SETTINGS" 2>/dev/null)
    if [ "$LIVE_KBD" != "$DISK_KBD" ]; then
        echo "  Syncing keyboard backlight states (sysfs → settings file)"
        echo "    sysfs: R=$KBD_RED G=$KBD_GREEN B=$KBD_BLUE brightness=$KBD_BRIGHTNESS"
        sudo jq '.keyboardBacklightStates = '"$LIVE_KBD" "$TCC_SETTINGS" | sudo tee "${TCC_SETTINGS}.tmp" > /dev/null && sudo mv "${TCC_SETTINGS}.tmp" "$TCC_SETTINGS"
    else
        echo "  Keyboard backlight states already in sync"
    fi
else
    echo "  rgb:kbd_backlight sysfs not present — skipping keyboard backlight sync"
fi

# Restart tccd to apply the updated config
echo "  Restarting tccd..."
sudo systemctl start tccd

echo "=== bonw9 setup complete ==="
echo "Reboot recommended for tccd to apply profile on next boot."
echo "After reboot, verify:"
echo "  systemctl status tccd"
echo "  journalctl -u tccd --no-pager | tail -40"
echo "  tuxedo-control-center  # GUI: confirm fans tracked on temp curve"
