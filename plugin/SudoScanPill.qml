import QtQuick
import qs.Commons

Item {
  id: root

  property string scanState: "scanning"
  property string assetSource: ""
  property string successAssetSource: ""

  implicitWidth: 72
  implicitHeight: 72

  FaceIdBadge {
    anchors.fill: parent
    faceState: root.scanState
    assetSource: root.assetSource
    successAssetSource: root.successAssetSource
    compact: true
  }
}
