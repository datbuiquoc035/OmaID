import QtQuick
import qs.Commons

Item {
  id: root

  property string faceState: "idle"
  property string assetSource: ""
  property string successAssetSource: ""
  property string successStyle: "mark"
  property bool motionEnabled: true
  property bool compact: false

  readonly property int badgeSize: compact ? 72 : 104
  readonly property int imageSize: compact ? 42 : 58
  readonly property int radius: compact ? 20 : 28
  // "mark" draws the animated Omarchy geometry, "image" falls back to the
  // bundled raster. The raster is only the fallback, so the two never overlap.
  readonly property bool useSuccessMark: faceState === "success" && successStyle === "mark"
  readonly property bool showSuccessAsset: faceState === "success" && !useSuccessMark && successAssetSource.length > 0
  readonly property color stateColor: faceState === "success"
    ? "#5fd18b"
    : faceState === "failed" || faceState === "error"
      ? "#e06c75"
      : faceState === "scanning"
        ? Color.lock.borderActive
        : Color.lock.placeholder

  implicitWidth: badgeSize
  implicitHeight: badgeSize

  Rectangle {
    id: surface
    anchors.fill: parent
    radius: root.radius
    color: Qt.rgba(0.05, 0.07, 0.09, root.compact ? 0.88 : 0.78)
    border.width: root.compact ? 2 : 3
    border.color: Qt.rgba(root.stateColor.r, root.stateColor.g, root.stateColor.b, root.faceState === "idle" ? 0.42 : 0.92)
    scale: root.faceState === "scanning" ? 1.0 : 0.98

    Behavior on border.color {
      ColorAnimation { duration: 180 }
    }

    Behavior on scale {
      NumberAnimation { duration: 180; easing.type: Easing.OutBack }
    }

    Image {
      id: faceImage
      objectName: "faceImage"
      anchors.centerIn: parent
      width: root.imageSize
      height: root.imageSize
      source: root.assetSource
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      visible: !root.showSuccessAsset && status === Image.Ready
    }

    Image {
      id: successImage
      objectName: "successImage"
      anchors.centerIn: parent
      width: root.imageSize
      height: root.imageSize
      source: root.successAssetSource
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      cache: false
      visible: root.showSuccessAsset && status === Image.Ready
    }

    SuccessMark {
      objectName: "successMark"
      anchors.centerIn: parent
      width: root.imageSize
      height: root.imageSize
      markColor: root.stateColor
      motionEnabled: root.motionEnabled
      active: root.useSuccessMark
    }

    Text {
      anchors.centerIn: parent
      visible: root.useSuccessMark
        ? false
        : root.showSuccessAsset
          ? successImage.status !== Image.Ready
          : faceImage.status !== Image.Ready
      text: "☺"
      color: root.stateColor
      font.family: Style.font.family
      font.pixelSize: Math.round(root.imageSize * 0.72)
    }

    Rectangle {
      id: scanRing
      anchors.centerIn: parent
      width: parent.width - 10
      height: parent.height - 10
      radius: parent.radius - 5
      color: "transparent"
      border.width: 2
      border.color: Qt.rgba(root.stateColor.r, root.stateColor.g, root.stateColor.b, 0.72)
      opacity: 0
      visible: root.faceState === "scanning"

      SequentialAnimation on scale {
        running: root.faceState === "scanning"
        loops: Animation.Infinite
        NumberAnimation {
          from: 0.82
          to: 1.04
          duration: 850
          easing.type: Easing.OutCubic
        }
        NumberAnimation {
          from: 1.04
          to: 0.82
          duration: 850
          easing.type: Easing.InCubic
        }
      }

      SequentialAnimation on opacity {
        running: root.faceState === "scanning"
        loops: Animation.Infinite
        NumberAnimation { from: 0.85; to: 0.12; duration: 850 }
        NumberAnimation { from: 0.12; to: 0.85; duration: 850 }
      }
    }
  }
}
