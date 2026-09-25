import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property var shell: null
  property string omarchyPath: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"
  readonly property string faceAssetSource: Qt.resolvedUrl("assets/face-id/face.svg")
  readonly property string faceSuccessAssetSource: Qt.resolvedUrl("assets/omarchy-logo-hackerman.png")

  property bool lockRequested: false
  property bool pendingSessionLock: false
  property bool authenticatingPassword: false
  property bool fingerprintAuthenticating: false
  property bool faceAuthenticating: false
  property bool passwordPamConfigured: false
  property bool fingerprintConfigured: false
  property bool facePamConfigured: false
  property bool faceBridgeConfigured: false
  property bool faceConfigured: false
  property string faceState: "unavailable"
  property int faceAttempts: 0
  property int faceRequestCounter: 0
  property string faceRequestId: ""
  property bool sudoScanVisible: false
  property string sudoScanState: "idle"
  property string sudoScanRequest: ""
  property bool previewVisible: false
  property string enteredPassword: ""
  property string pendingPassword: ""
  property string failureMessage: ""
  property int failedAttempts: 0
  property string backgroundPath: ""
  property int backgroundVersion: 0
  property string lastEvent: "init"
  property string lastEventAt: ""
  property bool strandedLock: false
  property bool strandedLockResolved: false

  readonly property bool locked: lockRequested || sessionLock.locked || sessionLock.secure
  readonly property bool authenticating: authenticatingPassword || fingerprintAuthenticating || faceAuthenticating

  function realScreenCount() {
    var screens = Quickshell.screens || []
    var count = 0

    for (var i = 0; i < screens.length; i++) {
      var screen = screens[i]
      if (screen && screen.name && screen.width > 0 && screen.height > 0) count += 1
    }

    return count
  }

  function hasRealScreen() {
    return realScreenCount() > 0
  }

  function queueSessionLock() {
    pendingSessionLock = true
    if (!sessionLockStabilizeTimer.running) logEvent("lock-pending: screen-stabilizing")
    sessionLockStabilizeTimer.restart()
    if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
  }

  function requestSessionLock() {
    if (!lockRequested || sessionLock.locked || sessionLock.secure) return
    if (sessionLockStabilizeTimer.running) return

    if (!hasRealScreen()) {
      if (!pendingSessionLock || lastEvent !== "lock-pending: no-real-screen") logEvent("lock-pending: no-real-screen")
      pendingSessionLock = true
      if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
      return
    }

    pendingSessionLock = false
    pendingSessionLockTimer.stop()
    sessionLock.locked = true
  }

  // ext-session-lock outlives its client, and a restart carries no lock over, so
  // a session locked this early is an orphan behind Hyprland's failsafe. Outputs
  // are often still absent here, so ask until the answer means something.
  function checkStrandedLock() {
    if (strandedLockResolved || strandedLockCheckProc.running) return

    // A lock this shell took is nobody's orphan.
    if (locked || lockRequested) {
      strandedLockResolved = true
      return
    }

    strandedLockCheckProc.running = true
  }

  function recoverStrandedLock() {
    if (!strandedLock || locked || !passwordPamConfigured) return

    strandedLock = false
    logEvent("lock-stranded: recovering")
    beginLock()
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function refreshFingerprintStatus() {
    if (!fingerprintCheckProc.running) fingerprintCheckProc.running = true
  }

  function refreshFaceStatus() {
    if (!faceCheckProc.running) faceCheckProc.running = true
  }

  function refreshFaceBridgeStatus() {
    if (!faceBridgeCheckProc.running) faceBridgeCheckProc.running = true
  }

  function logEvent(event) {
    lastEvent = event
    lastEventAt = new Date().toISOString()
    console.log("omarchy lock " + lastEventAt + " " + event)
  }

  function resetAuthenticationState() {
    enteredPassword = ""
    pendingPassword = ""
    failureMessage = ""
    failedAttempts = 0
    authenticatingPassword = false
    fingerprintAuthenticating = false
    faceAuthenticating = false
    faceAttempts = 0
    faceState = faceConfigured ? "idle" : "unavailable"
    fingerprintRetryTimer.stop()
    faceRetryTimer.stop()
    faceSuccessTimer.stop()
    faceBridge.cancel()
    faceRequestId = ""
    if (passwordPam.active) passwordPam.abort()
    if (fingerprintPam.active) fingerprintPam.abort()
  }

  function beginLock() {
    if (!passwordPamConfigured) {
      logEvent("lock-denied: missing-pam")
      return false
    }

    resetAuthenticationState()
    lockRequested = true
    armBlankTimer()
    logEvent("lock-requested")
    queueSessionLock()

    Qt.callLater(function() {
      root.refreshBackground()
      root.refreshFingerprintStatus()
      root.refreshFaceStatus()
      root.refreshFaceBridgeStatus()
    })

    return true
  }

  function finishUnlock() {
    if (!root.locked && !lockRequested) return

    lockRequested = false
    pendingSessionLock = false
    sessionLockStabilizeTimer.stop()
    pendingSessionLockTimer.stop()
    resetAuthenticationState()
    idleBlankTimer.stop()
    sessionLock.locked = false
    logEvent("unlocked")
    runWake()
  }

  function armBlankTimer() {
    idleBlankTimer.armedAt = Date.now()
    idleBlankTimer.restart()
  }

  function runWake() {
    if (!wakeProcess.running) wakeProcess.running = true
    if (lockRequested) armBlankTimer()
  }

  function runBlank() {
    if (!blankProcess.running) blankProcess.running = true
  }

  function cancelFaceScan() {
    faceRetryTimer.stop()
    faceBridge.cancel()
    faceRequestId = ""
    faceAuthenticating = false
    if (faceState === "scanning") faceState = faceConfigured ? "idle" : "unavailable"
  }

  function handlePasswordEdited(password) {
    if (String(password || "").length > 0) cancelFaceScan()
  }

  function submitPassword(value) {
    var password = String(value || "")
    if (!lockRequested || authenticatingPassword || password.length === 0) return

    cancelFaceScan()
    runWake()
    pendingPassword = password
    failureMessage = ""
    authenticatingPassword = true

    if (!passwordPam.start()) {
      handlePasswordFailure()
      return
    }

    Qt.callLater(respondToPasswordPrompt)
  }

  function respondToPasswordPrompt() {
    if (!authenticatingPassword || !passwordPam.active || !passwordPam.responseRequired) return
    passwordPam.respond(pendingPassword)
  }

  function handlePasswordFailure() {
    if (!lockRequested) return

    authenticatingPassword = false
    enteredPassword = ""
    pendingPassword = ""
    failedAttempts += 1
    failureMessage = "Authentication failed (" + failedAttempts + ")"
    runWake()
  }

  function startFingerprint() {
    if (!lockRequested || !sessionLock.secure || !fingerprintConfigured) return
    if (fingerprintPam.active || fingerprintAuthenticating) return

    fingerprintAuthenticating = true
    if (!fingerprintPam.start()) {
      fingerprintAuthenticating = false
    }
  }

  function handleFingerprintFinished(result) {
    fingerprintAuthenticating = false

    if (!lockRequested) return
    if (result === PamResult.Success) {
      finishUnlock()
    } else {
      if (fingerprintConfigured) fingerprintRetryTimer.restart()
      if (!fingerprintConfigured) scheduleFaceStart()
    }
  }

  function scheduleFaceStart() {
    if (!lockRequested || !sessionLock.secure || fingerprintConfigured) return
    if (!faceBridgeConfigured || !faceConfigured || faceAuthenticating) return
    if (enteredPassword.length > 0 || faceAttempts >= 2) return

    startFace()
  }

  function startFace() {
    if (!lockRequested || !sessionLock.secure || !faceBridgeConfigured || !faceConfigured) return
    if (fingerprintConfigured || faceAuthenticating || enteredPassword.length > 0) return
    if (faceAttempts >= 2) return

    faceAttempts += 1
    faceState = "scanning"
    faceAuthenticating = true
    faceRequestCounter += 1
    faceRequestId = String(Date.now()) + "-" + String(faceRequestCounter)
    logEvent("face-scan-start")

    if (!faceBridge.request(faceRequestId)) {
      faceAuthenticating = false
      faceRequestId = ""
      faceState = "failed"
      faceRetryTimer.restart()
    }
  }

  function handleFaceBridgeFinished(id, success) {
    if (id !== faceRequestId) return
    faceRequestId = ""
    handleFaceFinished(success ? PamResult.Success : PamResult.Failed)
  }

  function handleFaceFinished(result) {
    faceAuthenticating = false
    faceRetryTimer.stop()

    if (!lockRequested) return
    if (result === PamResult.Success) {
      faceState = "success"
      faceSuccessTimer.restart()
      return
    }

    faceState = "failed"
    if (enteredPassword.length === 0 && faceAttempts < 2) faceRetryTimer.restart()
  }

  function handleSudoAuthEvent(rawMessage) {
    var event = null
    try {
      event = JSON.parse(String(rawMessage || ""))
    } catch (error) {
      logEvent("sudo-notify:invalid-json")
      return
    }

    if (!event || event.service !== "sudo" || event.user !== root.userName) return
    if (!event.request) return

    if (event.event === "begin") {
      sudoSuccessTimer.stop()
      sudoScanRequest = String(event.request)
      sudoScanState = "scanning"
      sudoScanVisible = true
      sudoScanTimeout.restart()
      return
    }

    if (event.request !== sudoScanRequest) return

    if (event.event === "fallback") {
      sudoSuccessTimer.stop()
      sudoScanState = "failed"
      sudoScanVisible = false
      sudoScanTimeout.stop()
    } else if (event.event === "end") {
      sudoScanTimeout.stop()
      if (sudoScanState !== "failed") {
        sudoScanState = "success"
        sudoScanVisible = true
        sudoSuccessTimer.restart()
      }
      sudoScanRequest = ""
    }
  }

  WlSessionLock {
    id: sessionLock

    locked: false

    onSecureStateChanged: {
      root.logEvent("secure=" + secure)
      if (secure) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.startFingerprint()
        if (!fingerprintConfigured) root.scheduleFaceStart()
      }
    }

    onLockStateChanged: {
      root.logEvent("session-locked=" + locked)

      if (locked) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
      }

      if (!locked && root.lockRequested) {
        root.lockRequested = false
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.resetAuthenticationState()
        root.runWake()
      }
    }

    WlSessionLockSurface {
      id: lockSurface
      color: Color.background

      LockView {
        id: lockView
        anchors.fill: parent
        backgroundPath: root.backgroundPath
        backgroundVersion: root.backgroundVersion
        fingerprintConfigured: root.fingerprintConfigured
        faceConfigured: root.faceConfigured
        faceState: root.faceState
        faceAssetSource: root.faceAssetSource
        faceSuccessAssetSource: root.faceSuccessAssetSource
        authenticatingPassword: root.authenticatingPassword
        failureMessage: root.failureMessage
        failedAttempts: root.failedAttempts
        inputEnabled: root.lockRequested
        loadBackground: root.locked
        passwordText: root.enteredPassword
        onPasswordTextEdited: function(password) {
          root.enteredPassword = password
          root.handlePasswordEdited(password)
        }
        onSubmitPassword: function(password) { root.submitPassword(password) }
        onClearFailureRequested: root.failureMessage = ""
        onWakeRequested: root.runWake()
      }

    }
  }

  PanelWindow {
    id: previewWindow
    visible: root.previewVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-lock-preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    LockView {
      anchors.fill: parent
      backgroundPath: root.backgroundPath
      backgroundVersion: root.backgroundVersion
      fingerprintConfigured: root.fingerprintConfigured
      faceConfigured: root.faceConfigured
      faceState: root.faceState
      faceAssetSource: root.faceAssetSource
      faceSuccessAssetSource: root.faceSuccessAssetSource
      authenticatingPassword: false
      failureMessage: ""
      failedAttempts: 0
      inputEnabled: false
      loadBackground: root.previewVisible
      passwordText: ""
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: root.previewVisible = false
    }
  }

  FaceAuthClient {
    id: faceBridge
    socketPath: "/run/omaid/face-auth.sock"
    onCompleted: function(id, success) { root.handleFaceBridgeFinished(id, success) }
    onFailed: function(id) { root.handleFaceBridgeFinished(id, false) }
  }

  FaceAuthSocket {
    id: faceAuthSocket
    socketPath: root.runtimeDir.length > 0 ? root.runtimeDir + "/omaid-face-auth.sock" : ""
    onMessageReceived: function(message) { root.handleSudoAuthEvent(message) }
  }

  PanelWindow {
    id: sudoScanWindow
    visible: root.sudoScanVisible
    anchors.top: true
    margins { top: 16 }
    implicitWidth: 72
    implicitHeight: 72
    color: "transparent"
    WlrLayershell.namespace: "omaid-sudo-scan"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    SudoScanPill {
      anchors.centerIn: parent
      scanState: root.sudoScanState
      assetSource: root.faceAssetSource
      successAssetSource: root.faceSuccessAssetSource
    }
  }

  PamContext {
    id: passwordPam
    config: "omarchy-lock-password"
    user: root.userName

    onResponseRequiredChanged: root.respondToPasswordPrompt()
    onPamMessage: root.respondToPasswordPrompt()

    onCompleted: function(result) {
      root.authenticatingPassword = false
      root.pendingPassword = ""

      if (!root.lockRequested) return
      if (result === PamResult.Success) root.finishUnlock()
      else root.handlePasswordFailure()
    }

    onError: function(error) {
      root.handlePasswordFailure()
    }
  }

  PamContext {
    id: fingerprintPam
    config: "omarchy-lock-fingerprint"
    user: root.userName

    onCompleted: function(result) {
      root.handleFingerprintFinished(result)
    }

    onError: function(error) {
      root.fingerprintAuthenticating = false
      if (root.lockRequested && root.fingerprintConfigured) fingerprintRetryTimer.restart()
    }
  }

  Timer {
    id: fingerprintRetryTimer
    interval: 250
    repeat: false
    onTriggered: root.startFingerprint()
  }

  Timer {
    id: faceRetryTimer
    interval: 1800
    repeat: false
    onTriggered: root.startFace()
  }

  Timer {
    id: faceSuccessTimer
    interval: 350
    repeat: false
    onTriggered: root.finishUnlock()
  }

  Timer {
    id: sudoSuccessTimer
    interval: 1000
    repeat: false
    onTriggered: root.sudoScanVisible = false
  }

  Timer {
    id: sudoScanTimeout
    interval: 12000
    repeat: false
    onTriggered: {
      root.sudoScanVisible = false
      root.sudoScanState = "failed"
      root.sudoScanRequest = ""
    }
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = String(text || "").trim()
        if (next !== root.backgroundPath) {
          root.backgroundPath = next
          root.backgroundVersion += 1
        }
      }
    }
  }

  Process {
    id: fingerprintCheckProc
    command: ["bash", "-c", "if [[ -f /etc/pam.d/omarchy-lock-fingerprint ]] && command -v fprintd-list >/dev/null 2>&1 && fprintd-list \"$USER\" 2>/dev/null | grep -qi finger; then echo yes; else echo no; fi"]
    stdout: StdioCollector { id: fingerprintCheckStdout; waitForEnd: true }
    onExited: {
      root.fingerprintConfigured = String(fingerprintCheckStdout.text || "").trim() === "yes"
      if (root.lockRequested && sessionLock.secure) root.startFingerprint()
      else if (!root.fingerprintConfigured && fingerprintPam.active) fingerprintPam.abort()
    }
  }

  Process {
    id: faceCheckProc
    command: ["bash", "-c", "if [[ -r /usr/lib/security/pam_facelock.so ]] && /usr/bin/facelock is-enrolled --quiet >/dev/null 2>&1; then printf yes; else printf no; fi"]
    stdout: StdioCollector { id: faceCheckStdout; waitForEnd: true }
    onExited: {
      root.faceConfigured = String(faceCheckStdout.text || "").trim() === "yes"
      if (root.lockRequested && sessionLock.secure) root.scheduleFaceStart()
    }
  }

  Process {
    id: faceBridgeCheckProc
    command: ["bash", "-c", "if [[ -S /run/omaid/face-auth.sock ]]; then printf yes; else printf no; fi"]
    stdout: StdioCollector { id: faceBridgeCheckStdout; waitForEnd: true }
    onExited: {
      root.faceBridgeConfigured = String(faceBridgeCheckStdout.text || "").trim() === "yes"
      if (root.lockRequested && sessionLock.secure) root.scheduleFaceStart()
    }
  }

  Process {
    id: strandedLockCheckProc
    command: ["bash", "-c", "omarchy-hyprland-session-locked"]
    onExited: function(exitCode) {
      // No output to read the lock off yet.
      if (exitCode === 2) return

      root.strandedLockResolved = true

      // A lock taken while this was in flight is this shell's own.
      root.strandedLock = exitCode === 0 && !root.locked && !root.lockRequested
      root.recoverStrandedLock()
    }
  }

  Process {
    id: wakeProcess
    command: ["bash", "-c", "omarchy-system-wake"]
  }

  Process {
    id: blankProcess
    command: ["bash", "-c", "omarchy-brightness-keyboard off; omarchy-brightness-display off"]
  }

  Timer {
    id: idleBlankTimer
    interval: 5000
    repeat: false
    property double armedAt: 0
    onTriggered: {
      // A countdown frozen by suspend fires right after resume, which would
      // blank the freshly woken unlock screen under the user. Wall-clock time
      // exposes the gap: take a fresh run-up instead of blanking.
      if (Date.now() - armedAt > interval + 2000) {
        root.armBlankTimer()
        return
      }
      // Only a password check in flight should hold the display up. The
      // fingerprint PAM stays armed for the whole lock, so gating on
      // `authenticating` here would keep the panel lit until unlock.
      if (root.lockRequested && !root.authenticatingPassword) root.runBlank()
    }
  }

  Timer {
    id: sessionLockStabilizeTimer
    interval: 500
    repeat: false
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: pendingSessionLockTimer
    interval: 100
    repeat: true
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: strandedLockRetryTimer
    interval: 500
    repeat: true
    // Covers the compositor settling; screens coming back re-arm it.
    readonly property int budget: 20
    property int remaining: 20
    running: !root.strandedLockResolved && remaining > 0

    function rearm() {
      if (!root.strandedLockResolved) remaining = budget
    }

    onTriggered: {
      remaining -= 1
      root.checkStrandedLock()
    }
  }

  Connections {
    target: Quickshell
    function onScreensChanged() {
      root.requestSessionLock()

      // A monitor still coming up has no workspace, so cannot answer yet.
      strandedLockRetryTimer.rearm()
      root.checkStrandedLock()
    }
  }

  onAuthenticatingPasswordChanged: {
    if (!lockRequested) return
    if (authenticatingPassword) idleBlankTimer.stop()
    else armBlankTimer()
  }

  FileView {
    path: "/etc/pam.d/omarchy-lock-password"
    watchChanges: true
    printErrors: false
    onLoaded: root.passwordPamConfigured = true
    onLoadFailed: root.passwordPamConfigured = false
    onFileChanged: reload()
  }

  FileView {
    path: "/etc/pam.d/omarchy-lock-face"
    watchChanges: true
    printErrors: false
    onLoaded: {
       root.facePamConfigured = true
       root.refreshFaceStatus()
       root.refreshFaceBridgeStatus()
       if (root.lockRequested && sessionLock.secure) root.scheduleFaceStart()
    }
    onLoadFailed: {
      root.facePamConfigured = false
    }
    onFileChanged: reload()
  }

  // No lock before PAM is known good. An answer from before then may be stale --
  // the failsafe can be cleared from a TTY -- so re-ask rather than act on it.
  onPasswordPamConfiguredChanged: {
    if (!passwordPamConfigured) return

    strandedLock = false
    strandedLockResolved = false
    strandedLockRetryTimer.rearm()
    checkStrandedLock()
  }

  Component.onCompleted: {
    refreshBackground()
    refreshFingerprintStatus()
    refreshFaceStatus()
    refreshFaceBridgeStatus()
    checkStrandedLock()
  }

  IpcHandler {
    target: "lock"

    function lock(): string {
      if (!root.passwordPamConfigured) return "missing-pam"
      if (!root.locked && !root.beginLock()) return "failed"
      return "ok"
    }

    function isLocked(): string {
      return root.locked ? "true" : "false"
    }

    function status(): string {
      return JSON.stringify({
        locked: root.locked,
        requested: root.lockRequested,
        pending: root.pendingSessionLock,
        sessionLocked: sessionLock.locked,
        secure: sessionLock.secure,
        realScreens: root.realScreenCount(),
        passwordPam: root.passwordPamConfigured,
        fingerprint: root.fingerprintConfigured,
         facePam: root.facePamConfigured,
         faceBridge: root.faceBridgeConfigured,
         faceConfigured: root.faceConfigured,
         faceState: root.faceState,
        faceAuthenticating: root.faceAuthenticating,
        sudoScanVisible: root.sudoScanVisible,
        sudoScanState: root.sudoScanState,
        authenticating: root.authenticating,
        lastEvent: root.lastEvent,
        lastEventAt: root.lastEventAt
      })
    }

    function preview(): string {
      root.refreshBackground()
      root.refreshFingerprintStatus()
      root.previewVisible = true
      return "ok"
    }

    function hidePreview(): string {
      root.previewVisible = false
      return "ok"
    }
  }
}
