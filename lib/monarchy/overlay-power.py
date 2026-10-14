#!/usr/bin/env python3
"""Patch the Omarchy power panel so "Holding" requires a charge limit to exist.

`chargeThresholdActive()` treats UPower's pending-charge as a hold at a charge
threshold, unconditionally. UPower reports pending-charge for any kernel
`status` of "Not charging", and an EC that pulse-charges reports that at any
charge level: an HP ZBook 14u G6 alternates Charging / Not charging every ~12s
with a sawtooth current, so the panel relabels its rows to "Charge limit" and
"Battery state: Holding" while the pack is filling at 27%. There is no
charge_control_* anywhere on that machine, so the limit row renders "-" and
`batteryFlowIdle` suppresses the time to full.

The gate is the panel's own data: omarchy-battery-status prints a `threshold`
field only when the kernel exposes charge_control_start/end_threshold. No
field, no limit, and "holding at a limit" cannot be what is happening.
Undefined until the first status read, which leaves stock behaviour rather
than guessing from an empty batteryInfo -- the bar icon reads this before the
panel has ever been opened.

Which is why the second patch exists. Stock reads the battery status only
while the panel is open, so on a machine nobody has clicked the battery on,
the gate stays undefined for the life of the shell and the bar glyph goes on
flickering with the pulse. A small timer seeds that one read and stops itself
once it lands.

Machines that do have a charge threshold are unaffected: the field is present,
the gate passes, and every branch decides as it does upstream.

Fails if the packaged files no longer contain the expected anchors.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

THRESHOLD_OLD = """function chargeThresholdActive(device, onBattery, states) {
  var d = device || {}
  var s = states || {}
  if (!(d && d.isPresent && !onBattery)) return false
"""

THRESHOLD_NEW = """function chargeThresholdActive(device, onBattery, states, hasChargeLimit) {
  var d = device || {}
  var s = states || {}
  // Monarchy: holding is a claim about a charge limit, so it takes one to be
  // true. false turns the branch off; undefined is "not known yet" and keeps
  // the stock answer.
  if (hasChargeLimit === false) return false
  if (!(d && d.isPresent && !onBattery)) return false
"""

ICON_OLD = """function batteryIcon(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""
"""

ICON_NEW = """function batteryIcon(device, onBattery, states, hasChargeLimit) {
  var d = device || {}
  if (!d.isPresent) return ""
"""

ICON_CALL_OLD = "  var threshold = chargeThresholdActive(d, onBattery, states)\n"
ICON_CALL_NEW = (
    "  var threshold = chargeThresholdActive(d, onBattery, states, hasChargeLimit)\n"
)

# modeLabel takes upstream's translator as its fourth argument on edge, and
# no translator on stable releases before it (ADR 0009); hasChargeLimit goes
# last either way. Model.js and Panel.qml come from one package, so the
# signature found in Model.js picks the call patched in Panel.qml. Each
# anchor is one line: whole function bodies broke on every upstream edit.
MODE_VARIANTS = (
    (
        "function modeLabel(device, onBattery, states, tr) {\n",
        "function modeLabel(device, onBattery, states, tr, hasChargeLimit) {\n",
        "Model.modeLabel(device, root.discharging, upowerStates(), Commons.I18n.t)",
        "Model.modeLabel(device, root.discharging, upowerStates(), Commons.I18n.t, root.hasChargeLimit)",
    ),
    (
        "function modeLabel(device, onBattery, states) {\n",
        "function modeLabel(device, onBattery, states, hasChargeLimit) {\n",
        "Model.modeLabel(device, root.discharging, upowerStates())",
        "Model.modeLabel(device, root.discharging, upowerStates(), root.hasChargeLimit)",
    ),
)

MODE_CALL_OLD = "  if (chargeThresholdActive(d, onBattery, states)) return "
MODE_CALL_NEW = "  if (chargeThresholdActive(d, onBattery, states, hasChargeLimit)) return "

PANEL_GATE_ANCHOR = "  function batteryIcon() {\n"

PANEL_GATE_NEW = """  // Monarchy: whether this machine has a charge limit at all. The panel is
  // the only place that knows -- omarchy-battery-status prints `threshold`
  // only when the kernel exposes charge_control_*. undefined before the first
  // status read, so the bar icon keeps stock behaviour instead of reading an
  // empty batteryInfo as "no limit".
  readonly property var hasChargeLimit: {
    if (root.batteryInfo.percentage === undefined) return undefined
    return !!root.batteryInfo.threshold
  }

  function batteryIcon() {
"""

PANEL_ICON_OLD = "Model.batteryIcon(device, root.discharging, upowerStates())"
PANEL_ICON_NEW = "Model.batteryIcon(device, root.discharging, upowerStates(), root.hasChargeLimit)"

PANEL_ACTIVE_OLD = """  readonly property bool chargeThresholdActive: {
    var device = UPower.displayDevice
    return Model.chargeThresholdActive(device, root.discharging, upowerStates())
  }
"""

PANEL_ACTIVE_NEW = """  readonly property bool chargeThresholdActive: {
    var device = UPower.displayDevice
    return Model.chargeThresholdActive(device, root.discharging, upowerStates(), root.hasChargeLimit)
  }
"""


PANEL_SEED_OLD = """  Process {
    id: batteryProc
    command: ["omarchy-battery-status", "--shell"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "battery") }
  }
"""

PANEL_SEED_NEW = """  Process {
    id: batteryProc
    command: ["omarchy-battery-status", "--shell"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "battery") }
  }

  // Monarchy: seed the one status read the gate needs.
  //
  // batteryInfo is stock's, and stock only fills it while the panel is open
  // -- onOpenedChanged calls refresh(), and the 5s timer below runs on
  // `root.opened`. So before the panel has ever been opened batteryInfo is
  // {}, hasChargeLimit is undefined, and the bar icon takes the stock answer:
  // on an EC that pulse-charges, the glyph flips between the charging and
  // plain sets every few seconds for as long as nobody clicks it. The panel
  // looked fixed because opening it is what fixed it.
  //
  // Self-limiting by construction: `running` goes false the moment
  // batteryInfo lands, so a machine whose first read answers pays for exactly
  // one process. The repeat is for a UPower that is not up yet at launch, and
  // a machine with no battery never starts the timer at all.
  Timer {
    interval: 2000
    running: root.batteryPresent && root.hasChargeLimit === undefined
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!batteryProc.running) batteryProc.running = true
  }
"""


def must_replace(content: str, old: str, new: str, label: str) -> str:
    if old not in content:
        raise SystemExit(f"overlay-power: {label} missing from packaged file")
    if content.count(old) != 1:
        raise SystemExit(f"overlay-power: {label} matched {content.count(old)} times")
    return content.replace(old, new, 1)


def mode_variant(model: str) -> tuple[str, str, str, str]:
    for variant in MODE_VARIANTS:
        if variant[0] in model:
            return variant
    raise SystemExit("overlay-power: modeLabel signature missing from packaged file")


def patch_model(content: str, variant: tuple[str, str, str, str]) -> str:
    content = must_replace(content, THRESHOLD_OLD, THRESHOLD_NEW, "chargeThresholdActive")
    content = must_replace(content, ICON_OLD, ICON_NEW, "batteryIcon signature")
    content = must_replace(content, ICON_CALL_OLD, ICON_CALL_NEW, "batteryIcon threshold call")
    content = must_replace(content, variant[0], variant[1], "modeLabel signature")
    content = must_replace(content, MODE_CALL_OLD, MODE_CALL_NEW, "modeLabel threshold call")
    return content


def patch_panel(content: str, variant: tuple[str, str, str, str]) -> str:
    content = must_replace(content, PANEL_GATE_ANCHOR, PANEL_GATE_NEW, "batteryIcon function")
    content = must_replace(content, PANEL_ICON_OLD, PANEL_ICON_NEW, "batteryIcon call")
    content = must_replace(content, variant[2], variant[3], "modeLabel call")
    content = must_replace(content, PANEL_ACTIVE_OLD, PANEL_ACTIVE_NEW, "chargeThresholdActive property")
    content = must_replace(content, PANEL_SEED_OLD, PANEL_SEED_NEW, "battery status seed")
    return content


def cmd_power(power_dir: Path, apply: bool) -> None:
    model = power_dir / "Model.js"
    panel = power_dir / "Panel.qml"
    if not model.is_file() or not panel.is_file():
        raise SystemExit(f"overlay-power: missing Model.js or Panel.qml in {power_dir}")
    model_in = model.read_text()
    variant = mode_variant(model_in)
    model_out = patch_model(model_in, variant)
    panel_out = patch_panel(panel.read_text(), variant)
    if apply:
        model.write_text(model_out)
        panel.write_text(panel_out)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("mode", choices=("check", "apply"))
    p.add_argument("path")
    args = p.parse_args()
    cmd_power(Path(args.path), args.mode == "apply")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception as e:
        print(f"overlay-power: {e}", file=sys.stderr)
        raise SystemExit(1)
