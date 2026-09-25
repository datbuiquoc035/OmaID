import QtQuick
import Quickshell.Io

SocketServer {
  id: server

  property string socketPath: ""

  signal messageReceived(string message)

  active: socketPath.length > 0
  path: socketPath

  handler: Socket {
    parser: SplitParser {
      onRead: message => server.messageReceived(String(message))
    }
  }
}
