import QtQuick
import qs.Commons

Item {
  id: root

  property string scanState: "scanning"
  property string assetSource: ""
  property string successAssetSource: ""
  property string successStyle: "mark"
  property bool motionEnabled: true

  implicitWidth: 72
  implicitHeight: 72

  FaceIdBadge {
    anchors.fill: parent
    faceState: root.scanState
    assetSource: root.assetSource
    successAssetSource: root.successAssetSource
    successStyle: root.successStyle
    motionEnabled: root.motionEnabled
    compact: true
  }
}
