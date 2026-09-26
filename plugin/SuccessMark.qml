import QtQuick
import QtQuick.Shapes

// The Omarchy mark, drawn with the same stroke-dash choreography as the
// omarchy.org header logo. The site sets pathLength="1" on every path and then
// animates stroke-dashoffset from 1 to 0, so the dash maths is normalised to
// path length rather than to pixels. ShapePath.trim is the native equivalent:
// trim.start and trim.end are path-length fractions too, so the same keyframes
// port over without recomputing a single path length.
//
// The five paths are the site's own "d" strings, verbatim. Two of them
// (mark-draw-back on the site) grow from their end point instead of their
// start, which is why their trim.start moves while trim.end stays pinned at 1.
Item {
  id: root

  // The mark geometry is authored on a 1200x1200 grid with an 80 unit stroke,
  // exactly like the site, so it is rendered at that size and scaled down to
  // this item's box. A Shape clips to its own width and height, so the unscaled
  // 1200 unit box is what has to be measured here.
  readonly property real units: 1200
  readonly property real strokeUnits: 80

  property color markColor: "white"
  property bool motionEnabled: true
  property bool active: false

  readonly property bool drawing: active && motionEnabled

  // The mark is not done when the last path in the source list is done: the
  // inner frame starts late enough to outlive it. This is the largest
  // delay + duration across all five, which callers holding a success state
  // open need to exceed.
  readonly property int totalDuration: 830

  property real outerProgress: 0
  property real topNotchProgress: 0
  property real innerProgress: 0
  property real bottomStubProgress: 0
  property real leftStubProgress: 0

  implicitWidth: 58
  implicitHeight: 58
  visible: active

  // A stopped ParallelAnimation leaves its targets wherever they stopped, so
  // deactivate by hand to guarantee the next activation starts from nothing.
  onActiveChanged: {
    if (active) return
    outerProgress = 0
    topNotchProgress = 0
    innerProgress = 0
    bottomStubProgress = 0
    leftStubProgress = 0
  }

  // The stagger only means something inside a group: a bare NumberAnimation has
  // no delay property at all, so every driver whose start is offset gets a
  // PauseAnimation in front of it. Restating an explicit "from" makes a
  // reactivation replay the draw instead of resuming a half-finished one.
  ParallelAnimation {
    running: root.drawing

    NumberAnimation {
      target: root
      property: "outerProgress"
      from: 0
      to: 1
      duration: 650
      easing.type: Easing.InOutQuad
    }

    SequentialAnimation {
      PauseAnimation { duration: 250 }
      NumberAnimation {
        target: root
        property: "topNotchProgress"
        from: 0
        to: 1
        duration: 110
        easing.type: Easing.OutQuad
      }
    }

    SequentialAnimation {
      PauseAnimation { duration: 360 }
      NumberAnimation {
        target: root
        property: "innerProgress"
        from: 0
        to: 1
        duration: 470
        easing.type: Easing.InOutQuad
      }
    }

    SequentialAnimation {
      PauseAnimation { duration: 540 }
      NumberAnimation {
        target: root
        property: "bottomStubProgress"
        from: 0
        to: 1
        duration: 70
        easing.type: Easing.InOutQuad
      }
    }

    SequentialAnimation {
      PauseAnimation { duration: 600 }
      NumberAnimation {
        target: root
        property: "leftStubProgress"
        from: 0
        to: 1
        duration: 70
        easing.type: Easing.InOutQuad
      }
    }
  }

  Shape {
    anchors.centerIn: parent
    width: root.units
    height: root.units
    scale: root.width / root.units
    transformOrigin: Item.Center
    antialiasing: true

    ShapePath {
      objectName: "outerFrame"
      strokeColor: root.markColor
      strokeWidth: root.strokeUnits
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      joinStyle: ShapePath.MiterJoin
      pathHints: ShapePath.PathLinear
      trim.start: 0
      trim.end: root.motionEnabled ? root.outerProgress : 1
      PathSvg { path: "M640 1160H40V40H1160V1160H720" }
    }

    ShapePath {
      objectName: "topNotch"
      strokeColor: root.markColor
      strokeWidth: root.strokeUnits
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      joinStyle: ShapePath.MiterJoin
      pathHints: ShapePath.PathLinear
      trim.start: 0
      trim.end: root.motionEnabled ? root.topNotchProgress : 1
      PathSvg { path: "M600 40V200" }
    }

    ShapePath {
      objectName: "innerFrame"
      strokeColor: root.markColor
      strokeWidth: root.strokeUnits
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      joinStyle: ShapePath.MiterJoin
      pathHints: ShapePath.PathLinear
      trim.start: 0
      trim.end: root.motionEnabled ? root.innerProgress : 1
      PathSvg { path: "M640 200H200V1000H1000V200H880" }
    }

    ShapePath {
      objectName: "bottomStub"
      strokeColor: root.markColor
      strokeWidth: root.strokeUnits
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      joinStyle: ShapePath.MiterJoin
      pathHints: ShapePath.PathLinear
      trim.start: root.motionEnabled ? 1 - root.bottomStubProgress : 0
      trim.end: 1
      PathSvg { path: "M600 1160V1040" }
    }

    ShapePath {
      objectName: "leftStub"
      strokeColor: root.markColor
      strokeWidth: root.strokeUnits
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      joinStyle: ShapePath.MiterJoin
      pathHints: ShapePath.PathLinear
      trim.start: root.motionEnabled ? 1 - root.leftStubProgress : 0
      trim.end: 1
      PathSvg { path: "M40 600H200" }
    }
  }
}
