import QtQuick 2.0
import SddmComponents 2.0

// Omarchy greeter with a household overlay: cycle users and sessions.
// Color literals #1a1b26 and #ffffff are tokens for omarchy-plymouth-set.

Rectangle {
  id: root
  width: 640
  height: 480
  color: "#1a1b26"

  property int userIndex: 0
  property int sessionIndex: 0
  property bool loginFailed: false
  property bool resumePending: false
  property string pendingPassword: ""
  property int pendingSession: 0
  property string currentUser: userNameAt(userIndex)
  property string sessionLabel: sessionLabelAt(sessionIndex)

  // Greeter Image GET: 200 png means the user already has a Wayland session
  // and we switched to it. 404/error falls through to sddm.login().
  Image {
    id: resumeImg
    visible: false
    cache: false
    asynchronous: true
    onStatusChanged: {
      if (!root.resumePending)
        return
      if (status === Image.Loading)
        return
      resumeTimer.stop()
      root.resumePending = false
      if (status === Image.Ready)
        return
      sddm.login(root.currentUser, root.pendingPassword, root.pendingSession)
    }
  }

  Timer {
    id: resumeTimer
    interval: 800
    repeat: false
    onTriggered: {
      if (!root.resumePending)
        return
      root.resumePending = false
      sddm.login(root.currentUser, root.pendingPassword, root.pendingSession)
    }
  }

  function attemptEnter() {
    root.pendingPassword = password.text
    root.pendingSession = root.sessionIndex
    root.resumePending = true
    resumeTimer.restart()
    resumeImg.source = ""
    resumeImg.source = "http://127.0.0.1:17621/resume?user=" + encodeURIComponent(root.currentUser) + "&t=" + Date.now()
  }

  // Optional overlay: drop background.jpg next to this QML in monarchy/sddm/.
  Image {
    id: background
    anchors.fill: parent
    source: "background.jpg"
    fillMode: Image.PreserveAspectCrop
    visible: status === Image.Ready
  }

  Rectangle {
    anchors.fill: parent
    color: "#1a1b26"
    opacity: background.visible ? 0.55 : 0
  }

  function userCount() {
    if (typeof userModel.count === "number")
      return userModel.count
    return userModel.rowCount()
  }

  function userNameAt(i) {
    return (userModel.data(userModel.index(i, 0), Qt.UserRole + 1) || "").toString()
  }

  function sessionBlob(i) {
    var idx = sessionModel.index(i, 0)
    var file = (sessionModel.data(idx, Qt.UserRole + 1) || "").toString()
    var name = (sessionModel.data(idx, Qt.UserRole + 2) || "").toString()
    var display = (sessionModel.data(idx, Qt.DisplayRole) || "").toString()
    return (file + " " + name + " " + display).toLowerCase()
  }

  function sessionLabelAt(i) {
    var idx = sessionModel.index(i, 0)
    var name = (sessionModel.data(idx, Qt.UserRole + 2) || "").toString()
    var display = (sessionModel.data(idx, Qt.DisplayRole) || "").toString()
    var file = (sessionModel.data(idx, Qt.UserRole + 1) || "").toString()
    return name || display || file
  }

  function isOmarchySession(i) {
    return sessionBlob(i).indexOf("omarchy") !== -1
  }

  function isPlasmaSession(i) {
    var blob = sessionBlob(i)
    return blob.indexOf("plasma") !== -1 && blob.indexOf("omarchy") === -1
  }

  function findSession(kind) {
    var n = sessionModel.rowCount()
    var i
    for (i = 0; i < n; i++) {
      if (kind === "omarchy" && isOmarchySession(i))
        return i
      if (kind === "plasma" && isPlasmaSession(i))
        return i
    }
    return Math.max(0, sessionModel.lastIndex)
  }

  // Filename only. Omarchy's Name is "Omarchy (Hyprland uwsm)".
  function isStockHyprlandSession(i) {
    var file = (sessionModel.data(sessionModel.index(i, 0), Qt.UserRole + 1) || "").toString().toLowerCase()
    var parts = file.split("/")
    var base = parts[parts.length - 1]
    return base === "hyprland.desktop" || base === "hyprland-uwsm.desktop"
  }

  // Generated at apply time from /etc/monarchy/users.conf. The repo never
  // holds a username. Empty here means every account takes the default
  // session, which is Omarchy.
  property var plasmaUsers: []

  function prefersPlasma(user) {
    for (var i = 0; i < plasmaUsers.length; i++) {
      if (plasmaUsers[i] === user)
        return true
    }
    return false
  }

  function defaultSessionFor(user) {
    return findSession(prefersPlasma(user) ? "plasma" : "omarchy")
  }

  function indexOfUser(name) {
    var n = userCount()
    var i
    for (i = 0; i < n; i++) {
      if (userNameAt(i) === name)
        return i
    }
    return Math.max(0, userModel.lastIndex)
  }

  function cycleUser(delta) {
    var n = userCount()
    if (n <= 0)
      return
    userIndex = (userIndex + delta + n) % n
    sessionIndex = defaultSessionFor(currentUser)
  }

  function cycleSession(delta) {
    var n = sessionModel.rowCount()
    if (n <= 0)
      return
    var i = sessionIndex
    var steps = 0
    do {
      i = (i + delta + n) % n
      steps++
    } while (isStockHyprlandSession(i) && steps < n)
    sessionIndex = i
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      root.loginFailed = true
      password.text = ""
      password.focus = true
    }
    function onLoginSucceeded() {
      root.loginFailed = false
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: 24

    Image {
      id: logo
      source: "logo.png"
      width: Math.min(sourceSize.width, root.width * 0.8)
      height: sourceSize.width > 0 ? Math.round(width * sourceSize.height / sourceSize.width) : 0
      fillMode: Image.PreserveAspectFit
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Text {
      text: root.currentUser
      color: "#ffffff"
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: 20
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Text {
      text: root.sessionLabel
      color: "#ffffff"
      opacity: 0.7
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: 14
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 15

      Image {
        source: root.loginFailed ? "lock-failed.png" : "lock.png"
        width: 34
        height: 38
        fillMode: Image.PreserveAspectFit
        anchors.verticalCenter: parent.verticalCenter
      }

      Item {
        width: entry.width
        height: entry.height

        Image {
          id: entry
          source: root.loginFailed ? "entry-failed.png" : "entry.png"
          anchors.centerIn: parent
        }

        Row {
          anchors.left: parent.left
          anchors.leftMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          spacing: 5

          Repeater {
            model: Math.min(password.text.length, 21)

            Image {
              source: "bullet.png"
              width: 7
              height: 7
            }
          }
        }

        TextInput {
          id: password
          anchors.fill: parent
          anchors.leftMargin: 20
          anchors.rightMargin: 20
          verticalAlignment: TextInput.AlignVCenter
          echoMode: TextInput.Password
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 24
          font.letterSpacing: 5
          passwordCharacter: "\u2022"
          color: "transparent"
          selectionColor: "transparent"
          selectedTextColor: "transparent"
          cursorDelegate: Item {}
          focus: true

          onTextChanged: root.loginFailed = false

          Keys.onPressed: {
            if (event.key === Qt.Key_Tab) {
              root.cycleUser(event.modifiers & Qt.ShiftModifier ? -1 : 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Backtab) {
              root.cycleUser(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              root.cycleSession(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Down) {
              root.cycleSession(1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.attemptEnter()
              event.accepted = true
            }
          }
        }
      }
    }

    Text {
      text: "Tab user  ·  Up/Down session  ·  Enter resumes an open session"
      color: "#ffffff"
      opacity: 0.45
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: 12
      anchors.horizontalCenter: parent.horizontalCenter
    }
  }

  Component.onCompleted: {
    var idx = 0
    if (userModel.lastUser)
      idx = indexOfUser(userModel.lastUser)
    else if (userModel.lastIndex >= 0)
      idx = userModel.lastIndex
    userIndex = idx
    sessionIndex = defaultSessionFor(userNameAt(userIndex))
    password.forceActiveFocus()
  }
}
