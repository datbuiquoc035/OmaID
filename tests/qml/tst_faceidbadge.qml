import QtQuick
import QtTest
import "../../plugin" as Plugin

// Headless coverage for the badge's success rendering. The mark itself is
// covered by tst_successmark.qml; this checks that the badge picks it, keeps
// the raster fallback out of the way, and stays off it in every other state.
//
// FaceIdBadge imports qs.Commons, which only resolves inside a running
// Quickshell, so tests/run.sh points -import at tests/qml/stubs.
Item {
  id: stage
  width: 140
  height: 140
  visible: true

  Rectangle {
    anchors.fill: parent
    color: "#000000"
  }

  Component {
    id: badgeComponent
    Plugin.FaceIdBadge {}
  }

  Component {
    id: pillComponent
    Plugin.SudoScanPill {}
  }

  TestCase {
    name: "FaceIdBadge"
    when: windowShown

    // Success renders in the state colour, which is a desaturated green, so a
    // green-dominant filter separates it from the badge plate.
    function litPixels(item) {
      var grabbed = grabImage(item)
      var lit = 0
      for (var y = 0; y < grabbed.height; y += 1) {
        for (var x = 0; x < grabbed.width; x += 1) {
          var pixel = grabbed.pixel(x, y)
          if (pixel.g > 0.35 && pixel.g > pixel.b && pixel.g > pixel.r) lit += 1
        }
      }
      return lit
    }

    function makeBadge(properties) {
      var badge = createTemporaryObject(badgeComponent, stage)
      verify(badge !== null, "badge created")
      badge.width = 104
      badge.height = 104
      for (var key in properties) badge[key] = properties[key]
      return badge
    }

    function test_success_draws_the_mark_and_not_the_raster() {
      // Give the badge a real raster source on purpose. Both visuals are then
      // eligible for the success state, and only the style guard keeps the
      // filled raster from painting on top of the drawn mark.
      var badge = makeBadge({
        faceState: "success",
        successAssetSource: Qt.resolvedUrl("../../assets/omarchy-logo-hackerman.png")
      })
      wait(1100)

      var mark = findChild(badge, "successMark")
      var raster = findChild(badge, "successImage")
      verify(mark !== null, "the mark is in the tree")
      verify(raster !== null, "the raster is still in the tree")

      compare(mark.visible, true, "the mark is shown on success")
      compare(raster.visible, false, "the raster fallback stays hidden")

      var lit = litPixels(badge)
      verify(lit > 100, "the badge paints the mark, saw " + lit)
    }

    function test_image_style_uses_the_raster_instead() {
      var badge = makeBadge({
        faceState: "success",
        successStyle: "image",
        successAssetSource: Qt.resolvedUrl("../../assets/omarchy-logo-hackerman.png")
      })
      wait(80)

      var mark = findChild(badge, "successMark")
      var raster = findChild(badge, "successImage")
      compare(mark.visible, false, "the mark is not used in image mode")
      compare(raster.visible, true, "the raster is used in image mode")
    }

    function test_no_other_state_shows_the_mark() {
      var states = ["idle", "scanning", "failed", "error", "unavailable"]
      for (var i = 0; i < states.length; i += 1) {
        var badge = makeBadge({ faceState: states[i] })
        wait(20)
        var mark = findChild(badge, "successMark")
        verify(mark !== null, "mark is in the tree for " + states[i])
        compare(mark.visible, false, "no mark for state " + states[i])
      }
    }

    function test_compact_pill_draws_the_mark_at_pill_size() {
      var pill = createTemporaryObject(pillComponent, stage)
      verify(pill !== null, "pill created")
      pill.width = 72
      pill.height = 72
      pill.scanState = "success"
      wait(1100)

      var mark = findChild(pill, "successMark")
      verify(mark !== null, "pill contains the mark")
      compare(mark.visible, true, "the pill shows the mark on success")
      compare(mark.width, 42, "the pill uses the compact mark box")
    }
  }
}
