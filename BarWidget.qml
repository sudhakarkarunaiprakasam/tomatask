import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar widget entry point for the Tomatask plugin: a tomato pill that shows
// the countdown and hosts the start/stop popup (Panel.qml).
BarWidget {
  id: root
  moduleName: "sudhakar.tomatask"

  property string sessionType: "focus" // "focus" | "rest"
  readonly property int focusDurationSeconds: Model.defaultDurationSeconds()
  readonly property int restDurationSeconds: Model.defaultRestSeconds()
  readonly property int durationSeconds: sessionType === "rest" ? restDurationSeconds : focusDurationSeconds
  property int remainingSeconds: durationSeconds
  property bool running: false
  readonly property string timeText: Model.formatTime(remainingSeconds)

  function notify(headline, execCommand) {
    if (!root.bar) return
    var command = "omarchy-notification-send " + Util.shellQuote(headline) + " --app-name Tomatask"
    if (execCommand) command += " --exec " + Util.shellQuote(execCommand)
    root.bar.run(command)
  }

  property string suggestion: ""

  function start() {
    if (remainingSeconds <= 0) remainingSeconds = durationSeconds
    running = true
    suggestion = ""
    notify(Model.sessionStartMessage(sessionType))
  }

  function stop() {
    running = false
  }

  function toggleRunning() {
    running ? stop() : start()
  }

  function reset() {
    running = false
    remainingSeconds = durationSeconds
  }

  function setSessionType(type) {
    if (type !== "focus" && type !== "rest") return
    suggestion = ""
    if (sessionType === type) return
    sessionType = type
    running = false
    remainingSeconds = durationSeconds
  }

  function toggleSessionType() {
    setSessionType(sessionType === "focus" ? "rest" : "focus")
  }

  // Preloads the next session (rest <-> focus) and opens the panel with a
  // suggestion banner, triggered by clicking the session-end notification.
  function promptNextSession() {
    var endedType = sessionType
    setSessionType(Model.nextSessionType(endedType))
    suggestion = Model.transitionMessage(endedType)
    open()
  }

  readonly property int maxRemainingSeconds: 180 * 60

  function adjustMinutes(deltaMinutes) {
    var next = remainingSeconds + deltaMinutes * 60
    remainingSeconds = Math.max(0, Math.min(maxRemainingSeconds, next))
    if (remainingSeconds <= 0) running = false
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  // Hints the bar's open-panel underline to the label's own width/height
  // instead of a generic fraction of the slot, so it fully covers the pill.
  readonly property real openPanelIndicatorWidth: label.implicitWidth
  readonly property real openPanelIndicatorHeight: label.implicitHeight

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = root
    if ("hostWidget" in target) target.hostWidget = root
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  implicitWidth: label.implicitWidth + Style.spacing.controlPaddingX * 2
  implicitHeight: barSize

  Timer {
    interval: 1000
    running: root.running && root.remainingSeconds > 0
    repeat: true
    onTriggered: {
      root.remainingSeconds--
      if (root.remainingSeconds <= 0) {
        root.running = false
        root.notify(Model.sessionEndMessage(root.sessionType), "omarchy-shell sudhakar.tomatask promptNextSession")
      }
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "sudhakar.tomatask"

    function start(): void { root.start() }
    function stop(): void { root.stop() }
    function toggle(): void { root.toggleRunning() }
    function toggleSession(): void { root.toggleSessionType() }
    function promptNextSession(): void { root.promptNextSession() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function togglePanel(): void { root.togglePanel() }
  }

  Text {
    id: label
    anchors.centerIn: parent
    // Focused (monocle) face for focus, sleeping face for rest.
    text: (root.sessionType === "rest" ? "\uD83D\uDE34 " : "\uD83E\uDDD0 ") + root.timeText
    color: root.bar ? root.bar.barForeground : Color.foreground
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.togglePanel()
  }
}