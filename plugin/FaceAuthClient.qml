import QtQuick
import Quickshell.Io

Socket {
  id: client

  property string socketPath: ""
  property bool requestPending: false
  property string requestId: ""
  property bool available: false

  path: socketPath

  signal completed(string id, bool success)
  signal failed(string id)

  function request(id): bool {
    if (requestPending || socketPath.length === 0) return false
    requestId = String(id)
    requestPending = true
    connected = true
    return true
  }

  function cancel() {
    requestPending = false
    requestId = ""
    connected = false
  }

  function sendRequest() {
    if (!requestPending || !connected) return
    write("AUTH " + requestId + "\n")
    flush()
  }

  function failPending() {
    if (!requestPending) return
    var id = requestId
    requestPending = false
    requestId = ""
    available = false
    connected = false
    failed(id)
  }

  function handleLine(rawLine: string) {
    if (!requestPending) return

    var fields = String(rawLine || "").trim().split(/\s+/)
    if (fields.length !== 2 || fields[1] !== requestId) return

    var id = requestId
    var success = fields[0] === "SUCCESS"
    requestPending = false
    requestId = ""
    available = true
    connected = false
    completed(id, success)
  }

  parser: SplitParser {
    splitMarker: "\n"
    onRead: function(line) { client.handleLine(String(line)) }
  }

  onConnectionStateChanged: {
    if (connected) {
      available = true
      sendRequest()
    } else {
      available = false
      if (requestPending) failPending()
    }
  }

  onError: {
    available = false
    if (requestPending) failPending()
  }
}
