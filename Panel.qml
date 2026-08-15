import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Tomatask popup: shows the countdown and start/stop/reset controls.
// BarWidget.qml owns the timer state; this panel just drives it.
Panel {
  id: root
  moduleName: "sudhakar.tomatask"
  ipcTarget: "sudhakar.tomatask"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property bool running: hostWidget ? hostWidget.running === true : false
  readonly property string timeText: hostWidget ? hostWidget.timeText : Model.formatTime(Model.defaultDurationSeconds())
  readonly property string sessionType: hostWidget ? hostWidget.sessionType : "focus"
  readonly property string suggestion: hostWidget ? hostWidget.suggestion : ""

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  // PopupCard is the actual layer-shell surface; the base Panel only tracks
  // open/close state, so nothing renders on screen without this.
  PopupCard {
    id: card
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root.hostWidget || root
    open: root.opened
    centerOnBar: true
    contentWidth: card.fittedContentWidth(Style.space(260))
    contentHeight: card.fittedContentHeight(content.implicitHeight)

    ColumnLayout {
      id: content
      anchors.centerIn: parent
      width: card.contentWidth
      spacing: Style.space(12)

      Text {
        visible: root.suggestion !== ""
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignHCenter
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.suggestion
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.bodySmall
      }

      RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Style.space(8)

        Button {
          text: "-"
          bordered: true
          onClicked: if (root.hostWidget) root.hostWidget.adjustMinutes(-1)
        }

        Text {
          text: root.timeText
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.h1
        }

        Button {
          text: "+"
          bordered: true
          onClicked: if (root.hostWidget) root.hostWidget.adjustMinutes(1)
        }
      }

      RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Style.space(4)

        Button {
          text: "Focus"
          bordered: true
          selected: root.sessionType === "focus"
          onClicked: if (root.hostWidget) root.hostWidget.setSessionType("focus")
        }

        Button {
          text: "Rest"
          bordered: true
          selected: root.sessionType === "rest"
          onClicked: if (root.hostWidget) root.hostWidget.setSessionType("rest")
        }
      }

      RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Style.space(8)

        Button {
          text: root.running ? "Stop" : "Start"
          bordered: true
          onClicked: {
            if (!root.hostWidget) return
            root.running ? root.hostWidget.stop() : root.hostWidget.start()
          }
        }

        Button {
          text: "Reset"
          bordered: true
          onClicked: if (root.hostWidget) root.hostWidget.reset()
        }
      }
    }
  }
}

