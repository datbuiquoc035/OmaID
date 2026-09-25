import QtQuick 2.0
import SddmComponents 2.0

Rectangle {
  id: root
  width: 640
  height: 480
  color: "#000000"

  property string currentUser: userModel.lastUser
  property bool authPending: false
  property string authState: "idle"
  property string authMessage: ""
  property bool loginFailed: false
  property int sessionIndex: {
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
      if (name.indexOf("uwsm") !== -1)
        return i
    }
    return sessionModel.lastIndex
  }

  function submitLogin() {
    if (authPending) return
    authPending = true
    authState = "scanning"
    authMessage = "Looking for face"
    sddm.login(currentUser, password.text, sessionIndex)
  }

  function setAuthState(state, message) {
    authState = state
    authMessage = message || ""
  }

  Connections {
    target: sddm

    function onInformationMessage(message) {
      var text = String(message || "")
      if (text.indexOf("Identifying face") !== -1) {
        root.setAuthState("scanning", "Looking for face")
      } else if (text.indexOf("Face recognized") !== -1) {
        root.setAuthState("success", "Face recognized")
      } else if (text.length > 0) {
        root.authMessage = text
      }
    }

    function onLoginFailed() {
      root.authPending = false
      root.authState = "failed"
      root.authMessage = "Face not recognized. Enter your password."
      root.loginFailed = true
      password.text = ""
      password.forceActiveFocus()
    }

    function onLoginSucceeded() {
      root.authPending = false
      root.authState = "success"
      root.authMessage = "Welcome"
      root.loginFailed = false
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: 28

    Image {
      id: logo
      source: "logo.png"
      width: Math.min(sourceSize.width, root.width * 0.8)
      height: sourceSize.width > 0 ? Math.round(width * sourceSize.height / sourceSize.width) : 0
      fillMode: Image.PreserveAspectFit
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Item {
      id: faceBadge
      width: 84
      height: 84
      anchors.horizontalCenter: parent.horizontalCenter

      Rectangle {
        anchors.fill: parent
        radius: 24
        color: "#141922"
        border.width: 2
        border.color: root.authState === "success"
          ? "#5fd18b"
          : root.authState === "failed"
            ? "#e06c75"
            : root.authPending
              ? "#81a1c1"
              : "#4c566a"

        Image {
          id: faceImage
          anchors.centerIn: parent
          width: 50
          height: 50
          source: "assets/face-id/face.svg"
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: false
          visible: status === Image.Ready
        }

        Text {
          anchors.centerIn: parent
          visible: faceImage.status !== Image.Ready
          text: "☺"
          color: "#d8dee9"
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 34
        }

        MouseArea {
          anchors.fill: parent
          onClicked: root.submitLogin()
        }
      }
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
          verticalAlignment: Text.AlignVCenter
          echoMode: TextInput.Password
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 24
          font.letterSpacing: 5
          passwordCharacter: "•"
          color: "transparent"
          selectionColor: "transparent"
          selectedTextColor: "transparent"
          cursorDelegate: Item {}
          focus: true

          onTextChanged: {
            root.loginFailed = false
            if (!root.authPending) root.setAuthState("idle", "")
          }

          Keys.onPressed: {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.submitLogin()
              event.accepted = true
            }
          }
        }
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.authPending
        ? root.authMessage
        : root.authState === "failed"
          ? root.authMessage
          : "Press Enter or click the face to scan"
      color: root.authState === "failed" ? "#e06c75" : "#9ea4b0"
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: 13
    }
  }

  Component.onCompleted: password.forceActiveFocus()
}
