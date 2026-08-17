import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "espi.lofi-radio"

  property string playbackState: "stopped"
  property string stationName: "Lofi Hip Hop"
  property var spectrum: [0, 0, 0, 0, 0, 0, 0, 0]

  readonly property string controlPath: Qt.resolvedUrl("control.sh").toString().replace("file://", "")
  readonly property string visualizerPath: Qt.resolvedUrl("visualizer.sh").toString().replace("file://", "")
  readonly property int visualizerFps: {
    var configured = Number(setting("visualizerFps", 60))
    if (isNaN(configured) || configured === 0) return 60
    return Math.max(15, Math.min(120, Math.round(configured)))
  }
  readonly property bool visualizerOpen: playbackState === "playing" && button.tooltipHovered
  readonly property string stateIcon: playbackState === "playing" ? "󰝚"
    : playbackState === "paused" ? "󰐊"
    : playbackState === "error" ? "󰀪"
    : "󰝚"
  readonly property string stateLabel: playbackState.charAt(0).toUpperCase() + playbackState.slice(1)

  function refresh() {
    if (!statusProcess.running) statusProcess.running = true
  }

  function runAction(action) {
    if (!root.bar) return
    root.bar.run(controlPath + " " + action)
    refreshDelay.restart()
  }

  function updateSpectrum(line) {
    var fields = String(line).trim().split(";")
    var next = []
    for (var i = 0; i < 8; i++) {
      var value = i < fields.length ? Number(fields[i]) : 0
      next.push(isNaN(value) ? 0 : Math.max(0, Math.min(100, value)))
    }
    spectrum = next
  }

  function bandColor(index, count) {
    var start = Color.accent
    var end = root.bar ? root.bar.urgent : Color.urgent
    var amount = count > 1 ? index / (count - 1) : 0
    return Qt.rgba(
      start.r + (end.r - start.r) * amount,
      start.g + (end.g - start.g) * amount,
      start.b + (end.b - start.b) * amount,
      1
    )
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: statusProcess
    command: [root.controlPath, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var label = text.trim()
        if (label !== "") root.stationName = label
      }
    }
    onExited: function(exitCode) {
      root.playbackState = exitCode === 0 ? "playing"
        : exitCode === 3 ? "paused"
        : exitCode === 4 ? "stopped"
        : "error"
    }
  }

  Process {
    id: cavaProcess
    command: [root.visualizerPath, String(root.visualizerFps)]
    running: root.playbackState === "playing"
    stdout: SplitParser {
      onRead: function(line) { root.updateSpectrum(line) }
    }
    onExited: root.spectrum = [0, 0, 0, 0, 0, 0, 0, 0]
  }

  Timer {
    id: refreshDelay
    interval: 350
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.playbackState === "playing" ? Style.space(64) : Style.bar.statusSlot
    tooltipText: root.visualizerOpen ? "" : root.stationName + " · " + root.stateLabel + "\nLeft: play/pause · Middle: switch station · Right: stop"

    Text {
      anchors.centerIn: parent
      visible: root.playbackState !== "playing"
      text: root.stateIcon
      color: button.foreground
      font.family: button.fontFamily
      font.pixelSize: Style.bar.iconFont
    }

    Item {
      anchors.centerIn: parent
      visible: root.playbackState === "playing"
      width: Style.space(52)
      height: Style.space(14)

      Repeater {
        model: 8

        Rectangle {
          required property int index
          readonly property real level: root.spectrum[index]
          x: index * parent.width / 8 + parent.width / 32
          width: parent.width / 16
          height: Math.max(2, parent.height * level / 100)
          anchors.bottom: parent.bottom
          radius: width / 2
          color: root.bandColor(index, 8)

          Behavior on height {
            NumberAnimation { duration: 55; easing.type: Easing.OutQuad }
          }
        }
      }
    }

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.runAction("stop")
      else if (mouseButton === Qt.MiddleButton) root.runAction("switch")
      else if (mouseButton === Qt.LeftButton) root.runAction("toggle")
    }
  }

  PopupCard {
    id: visualizer
    anchorItem: button
    bar: root.bar
    // Keep the shell's open-panel marker off this passive hover preview.
    owner: button
    triggerMode: "hover"
    open: root.visualizerOpen
    contentWidth: visualizer.fittedContentWidth(Style.space(280))
    contentHeight: visualizer.fittedContentHeight(content.implicitHeight)

    Column {
      id: content
      anchors.fill: parent
      spacing: Style.space(8)

      Text {
        width: parent.width
        text: root.stationName
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
      }

      Row {
        id: controls
        width: parent.width
        height: Style.space(24)
        spacing: 0

        Repeater {
          model: [
            { click: "left", action: "Play/Pause" },
            { click: "middle", action: "Station" },
            { click: "right", action: "Stop" }
          ]

          Item {
            required property var modelData
            required property int index
            width: (controls.width - controls.spacing * 2) / 3
            height: controls.height

            Row {
              anchors.centerIn: parent
              spacing: Style.space(5)

              Item {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(12)
                height: Style.space(16)

                Rectangle {
                  anchors.fill: parent
                  radius: width / 2
                  color: "transparent"
                  border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.5)
                  border.width: 1
                }

                Rectangle {
                  visible: modelData.click === "left" || modelData.click === "right"
                  x: modelData.click === "left" ? 1.5 : parent.width / 2 + 0.5
                  y: 1.5
                  width: parent.width / 2 - 2
                  height: Style.space(5)
                  radius: Style.space(1.5)
                  color: Color.accent
                }

                Rectangle {
                  visible: modelData.click === "middle"
                  anchors.horizontalCenter: parent.horizontalCenter
                  y: 2
                  width: Style.space(2)
                  height: Style.space(5)
                  radius: width / 2
                  color: Color.accent
                }

                Rectangle {
                  anchors.horizontalCenter: parent.horizontalCenter
                  y: 1
                  width: 1
                  height: Style.space(7)
                  color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.28)
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.action
                color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.72)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }

      Item {
        width: parent.width
        height: Style.space(54)

        Row {
          anchors.fill: parent
          spacing: Style.space(4)

          Repeater {
            model: 8

            Rectangle {
              required property int index
              width: (parent.width - parent.spacing * 7) / 8
              height: Math.max(Style.space(3), parent.height * root.spectrum[index] / 100)
              anchors.bottom: parent.bottom
              radius: Math.min(width / 2, Style.space(2))
              color: root.bandColor(index, 8)

              Behavior on height {
                NumberAnimation { duration: 55; easing.type: Easing.OutQuad }
              }
            }
          }
        }
      }
    }
  }
}
