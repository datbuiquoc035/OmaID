import QtQuick
import QtTest
import "../../plugin" as Plugin

// Headless coverage for the success mark. The lock screen only shows this for
// about a second, so a broken draw, a wrong stagger, or a stale progress value
// would otherwise only show up as a one-frame glitch on a real lock.
//
// Shapes are rasterised through a real scene graph, so this needs a working
// render backend. tests/run.sh sets QT_QPA_PLATFORM=offscreen and
// QT_QUICK_BACKEND=software for exactly this file.
Item {
  id: stage
  width: 320
  height: 320
  visible: true

  Rectangle {
    anchors.fill: parent
    color: "#000000"
  }

  Component {
    id: markComponent
    Plugin.SuccessMark {}
  }

  TestCase {
    id: testCase
    name: "SuccessMark"
    when: windowShown

    // Counts lit pixels in a grab. SuccessMark colours its stroke white, so a
    // threshold is enough to tell drawn geometry from the black plate.
    // grabImage renders on demand, so no waitForRendering here: on an item that
    // is already on screen it just burns its full timeout waiting for a frame
    // that will never be needed.
    function litPixels(item) {
      var grabbed = grabImage(item)
      var lit = 0
      for (var y = 0; y < grabbed.height; y += 1) {
        for (var x = 0; x < grabbed.width; x += 1) {
          var pixel = grabbed.pixel(x, y)
          if (pixel.r > 0.5 && pixel.g > 0.5 && pixel.b > 0.5) lit += 1
        }
      }
      return lit
    }

    function makeMark(properties) {
      var mark = createTemporaryObject(markComponent, stage)
      verify(mark !== null, "mark created")
      mark.width = 160
      mark.height = 160
      mark.markColor = "white"
      for (var key in properties) mark[key] = properties[key]
      return mark
    }

    function test_hidden_until_active() {
      var mark = makeMark({ active: false })
      compare(mark.visible, false, "mark stays hidden until it is activated")
      compare(litPixels(mark), 0, "an inactive mark paints nothing")
    }

    function test_draws_from_empty_to_full() {
      var mark = makeMark({ active: true })
      compare(litPixels(mark), 0, "nothing is drawn on the first frame")

      wait(200)
      var midFlight = litPixels(mark)
      wait(mark.totalDuration + 150)
      var complete = litPixels(mark)

      verify(midFlight > 0, "the mark is part-drawn mid-flight, saw " + midFlight)
      verify(complete > midFlight, "the mark is fully drawn at the end, saw " + complete)
    }

    function test_every_path_finishes_within_total_duration() {
      var mark = makeMark({ active: true })
      wait(mark.totalDuration + 150)
      compare(mark.outerProgress, 1, "outer frame finished")
      compare(mark.topNotchProgress, 1, "top notch finished")
      compare(mark.innerProgress, 1, "inner frame finished")
      compare(mark.bottomStubProgress, 1, "bottom stub finished")
      compare(mark.leftStubProgress, 1, "left stub finished")
    }

    function test_staggered_paths_are_not_simultaneous() {
      // The inner frame starts at 360ms, well after the outer frame is already
      // moving. If the stagger were lost they would both be past halfway here.
      var mark = makeMark({ active: true })
      wait(430)
      verify(mark.outerProgress > mark.innerProgress,
        "outer frame leads the inner frame, " + mark.outerProgress + " vs " + mark.innerProgress)
    }

    function test_static_when_motion_disabled() {
      var mark = makeMark({ active: true, motionEnabled: false })
      var lit = litPixels(mark)
      verify(lit > 500, "the mark renders in full without animating, saw " + lit)
    }

    // The two stubs are the only paths omarchy.org draws with mark-draw-back:
    // they grow from their far end rather than their start. Drawing them the
    // normal way still produces a complete mark, so only the trim values give
    // the direction away.
    function test_reverse_paths_move_trim_start_not_trim_end() {
      var mark = makeMark({ active: true })
      wait(mark.totalDuration + 150)

      // Deactivating stops the animation and rewinds the drivers, so the
      // progress values set below are not overwritten.
      mark.active = false
      wait(20)

      var outerFrame = findChild(mark, "outerFrame")
      var bottomStub = findChild(mark, "bottomStub")
      var leftStub = findChild(mark, "leftStub")
      verify(outerFrame !== null, "outer frame path found")
      verify(bottomStub !== null, "bottom stub path found")
      verify(leftStub !== null, "left stub path found")

      mark.outerProgress = 0.5
      mark.bottomStubProgress = 0.25
      mark.leftStubProgress = 0.75
      wait(20)

      compare(outerFrame.trim.start, 0, "a forward path holds trim.start at 0")
      compare(outerFrame.trim.end, 0.5, "a forward path grows trim.end")

      compare(bottomStub.trim.start, 0.75, "the bottom stub trims from its far end")
      compare(bottomStub.trim.end, 1, "the bottom stub holds trim.end at 1")

      compare(leftStub.trim.start, 0.25, "the left stub trims from its far end")
      compare(leftStub.trim.end, 1, "the left stub holds trim.end at 1")
    }

    function test_static_path_shows_the_reverse_paths_whole() {
      var mark = makeMark({ active: true, motionEnabled: false })
      wait(20)

      var bottomStub = findChild(mark, "bottomStub")
      var leftStub = findChild(mark, "leftStub")
      verify(bottomStub !== null, "bottom stub path found")
      verify(leftStub !== null, "left stub path found")

      // With motion off the drivers stay at zero, so the static branch has to
      // pin the reverse paths open itself or they would render as nothing.
      compare(bottomStub.trim.start, 0, "the static mark shows the whole bottom stub")
      compare(bottomStub.trim.end, 1, "the static mark shows the whole bottom stub")
      compare(leftStub.trim.start, 0, "the static mark shows the whole left stub")
      compare(leftStub.trim.end, 1, "the static mark shows the whole left stub")
    }

    function test_reactivation_replays_the_draw() {
      var mark = makeMark({ active: true })
      wait(mark.totalDuration + 150)
      verify(litPixels(mark) > 500, "fully drawn after the first run")

      mark.active = false
      wait(20)
      compare(mark.outerProgress, 0, "deactivating rewinds the drivers")
      compare(mark.leftStubProgress, 0, "deactivating rewinds the staggered drivers too")

      mark.active = true
      wait(20)
      verify(mark.outerProgress < 0.5, "reactivating restarts the draw rather than resuming it")

      wait(mark.totalDuration + 150)
      verify(litPixels(mark) > 500, "fully drawn again after the replay")
    }
  }
}
