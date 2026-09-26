pragma Singleton
import QtQuick

// Stand-in for the shell singleton, which only exists inside a running
// Quickshell. Only the colours FaceIdBadge actually reads are here; reaching for
// anything else fails the test rather than silently rendering something wrong.
QtObject {
  readonly property QtObject lock: QtObject {
    readonly property color borderActive: "#7aa2f7"
    readonly property color placeholder: "#565f89"
  }
}
