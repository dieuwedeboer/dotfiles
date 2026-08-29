#!/usr/bin/env python3
"""Patch Omarchy lock QML and the system menu so Super+Ctrl+U switches user.

Fails if the clone files no longer contain the expected anchors.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

KEYS_OLD = """        Keys.onPressed: function(event) {
          root.wakeRequested()
          if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
            root.passwordTextEdited("")
            event.accepted = true
          }
        }"""

KEYS_NEW = """        Keys.onPressed: function(event) {
          root.wakeRequested()
          var ctrl = event.modifiers & Qt.ControlModifier
          var meta = event.modifiers & Qt.MetaModifier
          if (root.inputEnabled && ctrl && meta && event.key === Qt.Key_U) {
            root.switchUserRequested()
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Escape || (ctrl && !meta && event.key === Qt.Key_U)) {
            root.passwordTextEdited("")
            event.accepted = true
          }
        }"""

SIGNAL_OLD = "  signal wakeRequested()\n"
SIGNAL_NEW = "  signal wakeRequested()\n  signal switchUserRequested()\n"

HINT_ANCHOR = """        objectName: "fingerprintIndicator"
        anchors.right: parent.right
        anchors.rightMargin: inputField.borderRight + 18
        anchors.verticalCenter: parent.verticalCenter
        visible: root.fingerprintConfigured
        text: "󰈷"
        color: Color.lock.placeholder
        font.family: Style.font.family
        font.pixelSize: Math.round(root.fieldFontSize * 1.1)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }"""

HINT_NEW = HINT_ANCHOR + """

    Shortcut {
      enabled: root.inputEnabled
      sequences: ["Ctrl+Meta+U", "Meta+Ctrl+U"]
      onActivated: root.switchUserRequested()
    }

    Text {
      id: switchUserHint
      objectName: "switchUserHint"
      anchors.horizontalCenter: inputField.horizontalCenter
      anchors.top: inputField.bottom
      anchors.topMargin: Math.round(root.fieldHeight * 0.35)
      visible: root.inputEnabled
      text: "Super+Ctrl+U to switch user"
      color: Color.lock.placeholder
      font.family: Style.font.family
      font.pixelSize: Math.round(root.fieldFontSize * 0.55)
      horizontalAlignment: Text.AlignHCenter
    }"""

WAKE_OLD = "        onWakeRequested: root.runWake()\n"
WAKE_NEW = (
    "        onWakeRequested: root.runWake()\n"
    "        onSwitchUserRequested: root.runSwitchUser()\n"
)

FINISH_OLD = """  function finishUnlock() {
    if (!root.locked && !lockRequested) return

    lockRequested = false
    pendingSessionLock = false
    sessionLockStabilizeTimer.stop()
    pendingSessionLockTimer.stop()
    resetAuthenticationState()
    idleBlankTimer.stop()
    sessionLock.locked = false
    logEvent("unlocked")
    runWake()
  }

  function armBlankTimer() {
"""

FINISH_NEW = """  function finishUnlock() {
    if (!root.locked && !lockRequested) return

    lockRequested = false
    pendingSessionLock = false
    sessionLockStabilizeTimer.stop()
    pendingSessionLockTimer.stop()
    resetAuthenticationState()
    idleBlankTimer.stop()
    sessionLock.locked = false
    logEvent("unlocked")
    runWake()
  }

  function runSwitchUser() {
    if (!root.lockRequested) return
    root.runWake()
    if (!switchUserProc.running) switchUserProc.running = true
  }

  function armBlankTimer() {
"""

BLANK_PROC = """  Process {
    id: blankProcess
    command: ["bash", "-c", "omarchy-brightness-keyboard off; omarchy-brightness-display off"]
  }
"""

SWITCH_PROC = """  Process {
    id: blankProcess
    command: ["bash", "-c", "omarchy-brightness-keyboard off; omarchy-brightness-display off"]
  }

  Process {
    id: switchUserProc
    command: ["/usr/local/bin/monarchy-switch-user", "--already-locked"]
  }
"""

LOCK_IPC = """    function lock(): string {
      if (!root.passwordPamConfigured) return "missing-pam"
      if (!root.locked && !root.beginLock()) return "failed"
      return "ok"
    }
"""

SWITCH_IPC = """    function lock(): string {
      if (!root.passwordPamConfigured) return "missing-pam"
      if (!root.locked && !root.beginLock()) return "failed"
      return "ok"
    }

    function switchUser(): string {
      if (!root.lockRequested) return "not-locked"
      root.runSwitchUser()
      return "ok"
    }
"""

MENU_LOCK = (
    '  "system.lock": {"icon":"","label":"Lock","action":"omarchy-system-lock"},\n'
)
MENU_SWITCH = (
    MENU_LOCK
    + '  "system.switch-user": {"icon":"󰡉","label":"Switch User","action":"monarchy-switch-user"},\n'
)


def must_replace(content: str, old: str, new: str, label: str) -> str:
    if old not in content:
        raise SystemExit(f"overlay-lock: {label} missing from clone file")
    if content.count(old) != 1:
        raise SystemExit(f"overlay-lock: {label} matched {content.count(old)} times")
    return content.replace(old, new, 1)


def patch_lock_view(content: str) -> str:
    content = must_replace(content, SIGNAL_OLD, SIGNAL_NEW, "signal wakeRequested")
    content = must_replace(content, KEYS_OLD, KEYS_NEW, "Keys.onPressed Ctrl+U")
    content = must_replace(content, HINT_ANCHOR, HINT_NEW, "fingerprintIndicator")
    return content


def patch_service(content: str) -> str:
    content = must_replace(content, FINISH_OLD, FINISH_NEW, "finishUnlock")
    content = must_replace(content, WAKE_OLD, WAKE_NEW, "onWakeRequested")
    content = must_replace(content, BLANK_PROC, SWITCH_PROC, "blankProcess")
    content = must_replace(content, LOCK_IPC, SWITCH_IPC, "IpcHandler lock()")
    return content


def patch_menu(content: str) -> str:
    if '"system.switch-user"' in content:
        return content
    return must_replace(content, MENU_LOCK, MENU_SWITCH, "system.lock menu row")


def write_if_apply(path: Path, content: str, apply: bool) -> None:
    if apply:
        path.write_text(content)


def cmd_lock(lock_dir: Path, apply: bool) -> None:
    view = lock_dir / "LockView.qml"
    service = lock_dir / "Service.qml"
    if not view.is_file() or not service.is_file():
        raise SystemExit(f"overlay-lock: missing LockView.qml or Service.qml in {lock_dir}")
    view_out = patch_lock_view(view.read_text())
    service_out = patch_service(service.read_text())
    write_if_apply(view, view_out, apply)
    write_if_apply(service, service_out, apply)


def cmd_menu(menu: Path, apply: bool) -> None:
    if not menu.is_file():
        raise SystemExit(f"overlay-lock: missing {menu}")
    out = patch_menu(menu.read_text())
    write_if_apply(menu, out, apply)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("mode", choices=("check", "apply"))
    p.add_argument("kind", choices=("lock", "menu"))
    p.add_argument("path")
    args = p.parse_args()
    apply = args.mode == "apply"
    path = Path(args.path)
    if args.kind == "lock":
        cmd_lock(path, apply)
    else:
        cmd_menu(path, apply)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception as e:
        print(f"overlay-lock: {e}", file=sys.stderr)
        raise SystemExit(1)
