import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "sudhakar.tomatask"

  readonly property var timerService: bar && bar.shell
    ? bar.shell.serviceFor(moduleName)
    : null

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false

  function syncService() {
    if (timerService && typeof timerService.configure === "function")
      timerService.configure(settings)
    injectPanel()
  }

  function injectPanel() {
    var panel = panelLoader.item
    if (!panel) return
    if ("bar" in panel) panel.bar = root.bar
    if ("settings" in panel) panel.settings = root.settings
    if ("anchorItem" in panel) panel.anchorItem = button
    if ("hostWidget" in panel) panel.hostWidget = root
    if ("timerService" in panel) panel.timerService = root.timerService
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: Qt.callLater(syncService)
  onSettingsChanged: Qt.callLater(syncService)
  onTimerServiceChanged: Qt.callLater(syncService)
  Component.onCompleted: Qt.callLater(syncService)

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.syncService)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: {
      if (!root.timerService) return "Tomatask"
      return root.timerService.phaseLabel + " · "
        + root.timerService.remainingText + " · "
        + root.timerService.activeTaskName
    }

    iconComponent: Component {
      Item {
        anchors.fill: parent

        Rectangle {
          anchors.centerIn: parent
          width: parent.width * 0.88
          height: parent.height * 0.88
          radius: Math.round(width / 2)
          color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
        }

        Canvas {
          id: progressRing
          anchors.fill: parent
          antialiasing: true

          onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            var progress = root.timerService ? root.timerService.progress : 0
            progress = Math.max(0, Math.min(1, Number(progress) || 0))

            var line = Math.max(2, Math.floor(width * 0.08))
            var radius = Math.max(0, (Math.min(width, height) - line) / 2)
            var cx = width / 2
            var cy = height / 2

            ctx.lineWidth = line
            ctx.lineCap = "round"

            ctx.beginPath()
            ctx.strokeStyle = "rgba(255,255,255,0.18)"
            ctx.arc(cx, cy, radius, 0, Math.PI * 2, false)
            ctx.stroke()

            if (progress > 0) {
              ctx.beginPath()
              ctx.strokeStyle = Color.accent
              ctx.arc(cx, cy, radius, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * progress, false)
              ctx.stroke()
            }
          }

          Connections {
            target: root.timerService
            function onProgressChanged() { progressRing.requestPaint() }
          }

          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
        }
      }
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }
}
