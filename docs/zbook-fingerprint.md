# ZBook 14u G6 fingerprint reader

- **Author:** Dieuwe
- **Date:** 2026-08-29
- **Status:** plan. Not scheduled. Not a Monarchy feature.
- **Audience:** anyone about to wire `fprintd` or Omarchy fingerprint setup on zbook
- **Machines in scope:** HP ZBook 14u G6 only (Whiskey Lake i7-8665U, board 8549, AMD Radeon Pro WX 3200). First bring-up host. Verified on hostname `zbook`.

This class uses a palm-rest Validity/Synaptics reader, USB ID `06cb:00b7`. ArchWiki lists that ID as **No**. Later ZBooks (Firefly, Ultra, Fury) have different sensors and are out of scope. kingfisher and bonw9 have no reader. `scripts/setup-zbook.sh` is DMI-gated for every HP ZBook; this plan is not. Do not put any of this into that script.

---

## Verdict

Leave it. Stock `libfprint` cannot drive this chip. Omarchy's fingerprint wizard installs that stock stack. Plasma lock PAM is already ready and still has nothing to talk to. Tonight the USB device is not even enumerating.

The only Linux path that has ever claimed `06cb:00b7` is `python-validity` plus `open-fprintd`. Community reverse-engineering, AUR, HP SoftPaq firmware blob, unmerged forks, mixed verify rates. It conflicts with the `fprintd` package Omarchy wants.

FIDO2 is the Omarchy hardware-auth path that actually works. Use that if the goal is "unlock without typing."

---

## Current state (zbook, 2026-08-29)

| Check | Result |
| --- | --- |
| DMI | `HP ZBook 14u G6` / `103C_5336AN HP ZBook` |
| `lsusb` | Quanta `0408:5343` camera, Intel `8087:0029` AX200. No `06cb:00b7`, no `138a:*` |
| `omarchy-hw-fingerprint` | exit 1. Omarchy menu item is hidden (`when: omarchy-hw-fingerprint`) |
| `fprintd` / `libfprint` | not installed |
| `/etc/pam.d/omarchy-lock-fingerprint` | absent |
| `/usr/lib/pam.d/kde-fingerprint` | present. Optional `pam_fprintd.so`. Plasma lock is already wired |
| `/etc/pam.d/sddm` | password only. Monarchy greeter has no fingerprint UI |
| `fwupdmgr` | no Prometheus / fingerprint device |
| EFI | `FingerPrintReset-fb3b9ece-…` exists, payload `00`. Firmware expects a reader |
| I2C `SYNA3091` `06CB:82F5` | touchpad, not the reader |
| SPI `spi0.0` | `spi-nor` flash, not the reader |
| dmesg / journal | no Validity, Synaptics fingerprint, or `06cb:00b7` |

linux-hardware.org probes of this model with the same WX 3200 GPU show `06cb:00b7` on USB as "Fingerprint reader [HP G6]", driver failed. This SKU class has the part. Ours is not enumerating.

Likely cause is BIOS: Computer Setup, Advanced / Built-in Device Options, Fingerprint Device. Until `lsusb` shows `06cb:00b7`, there is nothing to hook up.

---

## Why stock paths fail

### Linux / libfprint

libfprint's supported-devices list has Synaptics IDs from `06cb:00bd` upward (newer Match-on-Chip). `06cb:00b7` is the older Validity firmware protocol. No kernel driver. Userspace owns the chip, and stock userspace does not speak this dialect.

libfprint MR !626 registers `06cb:00b7` as VCSFW, untested, not shipped.

### Plasma

`kscreenlocker` already uses a separate PAM service, `/usr/lib/pam.d/kde-fingerprint`, with `-auth required pam_fprintd.so` (the dash means ignore if the module is missing). System Settings > Users can enroll once a working `fprintd` exists. No Monarchy work for Plasma lock PAM.

SDDM login is a different stack. ArchWiki would add `pam_fprintd` to `/etc/pam.d/sddm`. The Monarchy greeter is custom QML around password `sddm.login()`. Greeter fingerprint is out of scope even if the driver existed. Unlock-from-lock is the only realistic Plasma target.

### Omarchy

First-class, and the wrong driver for this laptop.

`omarchy-setup-security-fingerprint` (Super+Space > Setup > Security > Fingerprint):

1. Bails unless `omarchy-hw-fingerprint` sees a USB vendor in `27c6 138a 06cb 08ff 1c7a 147e` or a product string that says fingerprint.
2. Installs **stock** `libfprint` + `fprintd` (migration `1785090473` already threw out `libfprint-git`).
3. Runs `fprintd-enroll`. PAM is written only after enroll and verify succeed.
4. Then patches `/etc/pam.d/sudo` and `polkit-1` (`pam_fprintd` plus `omarchy-hw-laptop-closed` so a shut lid skips the sensor) and writes `/etc/pam.d/omarchy-lock-fingerprint`.

If the USB ID appeared, step 1 would pass (`06cb` is in the vendor list, and this chip has no kernel driver bound). Step 3 would fail: "No devices available." Do not run that wizard on this hardware.

Omarchy lock already has a separate fingerprint PAM flow (`shell/plugins/lock/Service.qml`, config `omarchy-lock-fingerprint`). Dropping that file in by hand would light up the lock icon once a real `fprintd` backend exists. The wizard is not required for that file. The wizard is the problem, because it installs stock libfprint.

---

## If Dieuwe still wants it

Gate every later step on the USB ID. Wrong ID means stop; that is a different chip and a different plan.

1. **BIOS.** Computer Setup. Enable Fingerprint Device under Built-in Device Options. Optional: Security > reset fingerprint data on next boot. Reboot.
2. **Confirm.** `lsusb` must show `06cb:00b7 Synaptics, Inc. Fingerprint reader [HP G6]`. Anything else, including still-missing, ends the work.
3. **Do not** run `omarchy-setup-security-fingerprint`. It will install stock `fprintd` and fail enroll.
4. **Driver.** AUR `python-validity` + `open-fprintd` + `fprintd-clients`. Extract the HP SoftPaq firmware blob (`validity-sensors-firmware`). `06cb:00b7` support is still in unmerged PRs and forks (`uunicorn/python-validity` #256 / #270, SimpleX-T fork). Two silicon variants exist on G6 machines, `0xd51` and `0x969`. A ZBook 17 G6 report enrolled but verified about 1 in 5 presses.
5. **Enroll** with `fprintd-enroll` against open-fprintd. Verify with `fprintd-verify`.
6. **Plasma.** Nothing to write. `kde-fingerprint` already calls `pam_fprintd`. Test kscreenlocker unlock.
7. **Omarchy lock.** Write `/etc/pam.d/omarchy-lock-fingerprint` by hand (same contents `omarchy-apply-lock` would). Do not let the setup script replace open-fprintd with stock `fprintd`.
8. **sudo / polkit.** Optional and shared across both sessions. Omarchy's lid-closed `pam_exec` gate is the right shape if fingerprint is `sufficient` on those stacks. Fingerprint-only sudo is a hijack risk (CVE-2024-37408); keep password as fallback.

`open-fprintd` Provides the fprintd D-Bus API and **conflicts** with the `fprintd` package. Omarchy remove/setup will fight it on every run that touches fingerprint packages. That fight is why this stays out of `setup-zbook.sh` and out of Monarchy apply.

---

## Out of scope

- Later ZBooks. Different USB IDs. Some of those *are* in stock libfprint. Re-probe on that machine; do not reuse this plan.
- kingfisher, bonw9.
- SDDM greeter fingerprint UI.
- Shipping python-validity from this repo.
- Teaching `omarchy-hw-fingerprint` to treat a missing USB ID as present.

---

## References

- Live zbook, 2026-08-29: `lsusb`, `omarchy-hw-fingerprint`, `/usr/lib/pam.d/kde-fingerprint`, EFI `FingerPrintReset`
- https://wiki.archlinux.org/title/HP_ZBook_14u_G6 (`06cb:00b7`, Working? No)
- https://fprint.freedesktop.org/supported-devices.html (no `06cb:00b7`; Synaptics starts at `06cb:00bd`)
- https://linux-hardware.org/?probe=9ab0bfb583 (14u G6 + WX 3200, `06cb:00b7` failed)
- Clone `/usr/local/src/monarchy/omarchy/bin/omarchy-setup-security-fingerprint`, `omarchy-hw-fingerprint`, `omarchy-apply-lock`, `manual/37-hardware-authentication.md`
- https://github.com/uunicorn/python-validity/pull/256 (sensor type `0xd51`, `06cb:00b7` by symmetry)
- https://github.com/uunicorn/python-validity/issues/225 (`06cb:00b7` init failures on stock python-validity)
- https://wiki.archlinux.org/title/Fprint (Plasma `kde-fingerprint` already configured; SDDM is a separate page)
