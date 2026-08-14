import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "sudhakar.tomatask"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var timerService: null
  readonly property var barIdentity: hostWidget || root

  property string draftTaskName: ""
  property int selectedAction: 0

  readonly property color foreground: Color.popups.text
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    selectedAction = 0
    controller.show()
  }

  function close() {
    controller.hide()
  }

  function toggle() {
    if (opened) close()
    else open()
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function activatePrimary() {
    if (!timerService || !timerService.initialized) return
    if (timerService.stopped) timerService.startOrStop()
    else timerService.togglePause()
  }

  function addTaskFromDraft() {
    if (!timerService) return
    if (timerService.addTask(draftTaskName)) draftTaskName = ""
  }

  function phaseGlyph() {
    if (!timerService) return "󱎫"
    if (timerService.phase === "work") return "󱎫"
    if (timerService.phase === "shortBreak") return "󰅶"
    return "󰤄"
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight + Style.space(22))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onActivateRequested: root.activatePrimary()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      onTextKey: function(t) {
        var x = String(t || "").toLowerCase()
        if (x === "s" && root.timerService && !root.timerService.stopped) root.timerService.skipPhase()
        else if (x === "r" && root.timerService && !root.timerService.stopped) root.timerService.resetPhase()
        else if (x === "n") root.addTaskFromDraft()
      }

      Column {
        id: contentColumn
        width: parent.width - Style.space(24)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(12)

        Rectangle {
          width: parent.width
          height: Style.space(26)
          radius: Math.round(height / 2)
          color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14)

          Row {
            anchors.centerIn: parent
            spacing: Style.space(6)

            Text {
              text: root.phaseGlyph()
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              text: root.timerService
                ? root.timerService.phaseLabel + " · " + root.timerService.remainingText
                : "Work · 25:00"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
          }
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: root.timerService ? root.timerService.activeTaskName : "Inbox"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Rectangle {
          width: parent.width
          height: 6
          radius: 3
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)

          Rectangle {
            width: parent.width * (root.timerService ? root.timerService.progress : 0)
            height: parent.height
            radius: parent.radius
            color: root.accent

            Behavior on width {
              NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
          }
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(10)

          PanelActionButton {
            iconText: root.timerService && root.timerService.running ? "" : ""
            tooltipText: root.timerService && root.timerService.running ? "Pause" : "Start"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: {
              if (!root.timerService) return
              if (root.timerService.stopped) root.timerService.startOrStop()
              else root.timerService.togglePause()
            }
          }

          PanelActionButton {
            iconText: ""
            tooltipText: "Stop"
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: !!root.timerService && !root.timerService.stopped
            opacity: enabled ? 1 : 0.45
            onClicked: if (root.timerService) root.timerService.startOrStop()
          }

          PanelActionButton {
            iconText: ""
            tooltipText: "Skip (S)"
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: !!root.timerService && !root.timerService.stopped
            opacity: enabled ? 1 : 0.45
            onClicked: if (root.timerService) root.timerService.skipPhase()
          }

          PanelActionButton {
            iconText: "󰕌"
            tooltipText: "Reset (R)"
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: !!root.timerService && !root.timerService.stopped
            opacity: enabled ? 1 : 0.45
            onClicked: if (root.timerService) root.timerService.resetPhase()
          }

          Item { Layout.fillWidth: true }
        }

        Rectangle {
          width: parent.width
          radius: Style.space(6)
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

          Column {
            width: parent.width - Style.space(14)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Style.space(8)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(8)
            spacing: Style.space(8)

            Text {
              width: parent.width
              text: "Tasks"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              Rectangle {
                Layout.fillWidth: true
                height: Style.space(24)
                radius: Style.space(4)
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                border.width: 1
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)

                TextInput {
                  id: taskInput
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  verticalAlignment: Text.AlignVCenter
                  clip: true
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  text: root.draftTaskName
                  onTextChanged: root.draftTaskName = text
                  onAccepted: root.addTaskFromDraft()
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  text: "New task name"
                  visible: taskInput.text.length === 0
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }

              Rectangle {
                width: Style.space(36)
                height: Style.space(24)
                radius: Style.space(4)
                color: String(root.draftTaskName).trim() !== ""
                  ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.25)
                  : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

                Text {
                  anchors.centerIn: parent
                  text: "Add"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  anchors.fill: parent
                  enabled: String(root.draftTaskName).trim() !== ""
                  onClicked: root.addTaskFromDraft()
                }
              }
            }

            Repeater {
              model: root.timerService ? root.timerService.tasks : []

              Rectangle {
                width: parent.width
                height: Style.space(28)
                radius: Style.space(4)
                color: modelData.id === (root.timerService ? root.timerService.activeTaskId : "")
                  ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
                  : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

                Row {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(8)

                  Text {
                    width: parent.width - Style.space(120)
                    elide: Text.ElideRight
                    text: modelData.name
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    text: String(modelData.sessions) + " sessions"
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.75)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: if (root.timerService) root.timerService.selectTask(modelData.id)
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "Space start/pause · S skip · R reset · N add task"
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
