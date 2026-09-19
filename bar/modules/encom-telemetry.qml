import QtQuick
import Quickshell.Io

// ENCOM OS-12 telemetry cluster: CPU / MEM arc gauges plus net throughput,
// driven by one probe on one timer. Three separate widgets would mean three
// bash forks per tick; on a Broadwell iGPU that is worth avoiding.
Item {
  id: root

  property var bar
  property string moduleName: "encom.telemetry"
  property var settings: ({})

  // Probe cadence in seconds. 3s is responsive enough to watch a build spike
  // without waking the CPU more than necessary.
  readonly property int pollSeconds: Math.max(1, Number((settings && settings.interval) || 3))

  property int cpu: 0
  property int mem: 0
  property int memUsed: 0
  property real rx: 0
  property real tx: 0
  property int temp: 0

  readonly property color cyan:     "#6fc3df"
  readonly property color cyanHi:   "#a8ecff"
  readonly property color cyanDim:  "#14414f"
  readonly property color orange:   "#ff8c21"

  readonly property bool vertical: bar ? bar.vertical === true : false
  readonly property string fontFamily: bar ? bar.fontFamily : "monospace"

  // A gauge runs cyan until the subsystem is under real pressure, then goes
  // Clu-orange. 85 is the point where this machine starts swapping.
  function gaugeColor(pct) { return pct >= 85 ? orange : cyan }

  // Pad without relying on String.prototype.padStart being present in the
  // QML JS engine.
  function pad2(n) { return n < 10 ? "0" + n : String(n) }

  function humanRate(bytesPerSec) {
    var b = bytesPerSec
    if (b < 1024) return "0k"
    if (b < 1024 * 1024) return Math.round(b / 1024) + "k"
    if (b < 1024 * 1024 * 1024) return (b / (1024 * 1024)).toFixed(b < 10485760 ? 1 : 0) + "M"
    return (b / (1024 * 1024 * 1024)).toFixed(1) + "G"
  }

  implicitWidth: vertical ? (bar ? bar.barSize : 28) : row.implicitWidth + 10
  implicitHeight: vertical ? col.implicitHeight : (bar ? bar.barSize : 26)

  Process {
    id: probe
    command: ["bash", "-lc", "$HOME/.config/omarchy/bar/scripts/encom-telemetry"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!text) return
        try {
          var d = JSON.parse(text)
          root.cpu = d.cpu
          root.mem = d.mem
          root.memUsed = d.memused
          root.rx = d.rx
          root.tx = d.tx
          root.temp = d.temp
        } catch (e) {
          // A partial read just means we keep the previous sample.
        }
      }
    }
  }

  // ── Alerts ──────────────────────────────────────────────────────────────
  // Same checks as the HUD and the Boardroom (checks.py). The bar is the one
  // ENCOM surface that stays visible over windows, so this is where an alert
  // is seen while working.
  property var alerts: []

  Process {
    id: alertProbe
    command: ["bash", "-lc", "exec python3 \"$HOME/.local/share/encom-boardroom/checks.py\" --json --journal"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var list = JSON.parse(text)
          if (Array.isArray(list)) root.alerts = list
        } catch (e) {}
      }
    }
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: alertProbe.running = true
  }

  function alertText() {
    var lines = []
    for (var i = 0; i < root.alerts.length; i++) {
      var a = root.alerts[i]
      lines.push(a.level + "  " + String(a.who).toUpperCase() + "  " + a.title)
    }
    return lines.join("\n")
  }

  Timer {
    interval: root.pollSeconds * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: probe.running = true
  }

  // ── Arc gauge ────────────────────────────────────────────────────────────
  component Gauge: Item {
    id: g
    property int value: 0
    property string label: ""
    property color arcColor: root.cyan

    readonly property int dim: 17
    implicitWidth: dim + valueText.implicitWidth + 3
    implicitHeight: dim

    Canvas {
      id: face
      width: g.dim
      height: g.dim
      anchors.verticalCenter: parent.verticalCenter

      // Repaint only when the sample actually moves.
      Connections {
        target: g
        function onValueChanged() { face.requestPaint() }
        function onArcColorChanged() { face.requestPaint() }
      }

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var cx = width / 2, cy = height / 2, r = width / 2 - 1.6
        // 270° sweep opening at the bottom, like a disc with a gap.
        var start = Math.PI * 0.75
        var sweep = Math.PI * 1.5

        ctx.lineWidth = 2
        ctx.lineCap = "butt"

        ctx.beginPath()
        ctx.arc(cx, cy, r, start, start + sweep)
        ctx.strokeStyle = root.cyanDim
        ctx.stroke()

        var frac = Math.max(0, Math.min(100, g.value)) / 100
        if (frac > 0.001) {
          ctx.beginPath()
          ctx.arc(cx, cy, r, start, start + sweep * frac)
          ctx.strokeStyle = g.arcColor
          ctx.stroke()
        }

        // Centre pip — the disc core.
        ctx.beginPath()
        ctx.arc(cx, cy, 1.5, 0, Math.PI * 2)
        ctx.fillStyle = g.arcColor
        ctx.globalAlpha = 0.85
        ctx.fill()
      }
    }

    Text {
      id: valueText
      anchors.left: face.right
      anchors.leftMargin: 3
      anchors.verticalCenter: parent.verticalCenter
      text: root.pad2(g.value)
      color: g.arcColor
      font.family: root.fontFamily
      font.pixelSize: 10
      font.letterSpacing: 0.4
    }
  }

  Row {
    id: row
    visible: !root.vertical
    anchors.centerIn: parent
    spacing: 9

    // Alert marker: only present while something is wrong.
    Text {
      visible: root.alerts.length > 0
      anchors.verticalCenter: parent.verticalCenter
      text: "!" + (root.alerts.length > 1 ? root.alerts.length : "")
      color: root.cyanHi                                  // alerts are ENCOM teal
      font.family: root.fontFamily
      font.pixelSize: 11
      font.bold: true
    }

    Gauge {
      id: cpuGauge
      anchors.verticalCenter: parent.verticalCenter
      value: root.cpu
      arcColor: root.gaugeColor(root.cpu)
    }

    Gauge {
      anchors.verticalCenter: parent.verticalCenter
      value: root.mem
      arcColor: root.gaugeColor(root.mem)
    }

    // Net throughput, stacked up over down to stay inside the bar height.
    Column {
      anchors.verticalCenter: parent.verticalCenter
      spacing: -1
      Text {
        text: "▲ " + root.humanRate(root.tx)
        color: root.cyan
        opacity: root.tx > 8192 ? 1.0 : 0.45
        font.family: root.fontFamily
        font.pixelSize: 8
      }
      Text {
        text: "▼ " + root.humanRate(root.rx)
        color: root.cyanHi
        opacity: root.rx > 8192 ? 1.0 : 0.45
        font.family: root.fontFamily
        font.pixelSize: 8
      }
    }
  }

  Column {
    id: col
    visible: root.vertical
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: 4
    Text {
      text: root.pad2(root.cpu)
      color: root.gaugeColor(root.cpu)
      font.family: root.fontFamily
      font.pixelSize: 10
    }
    Text {
      text: root.pad2(root.mem)
      color: root.gaugeColor(root.mem)
      font.family: root.fontFamily
      font.pixelSize: 10
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    onEntered: if (root.bar) root.bar.showTooltip(root,
      (root.alerts.length ? "SYSTEM ALERT\n" + root.alertText() + "\n\n" : "")
      + "CPU " + root.cpu + "%  ·  MEM "
      + root.mem + "% (" + root.memUsed + " MB)  ·  CORE " + root.temp + "°C\n"
      + "▲ " + root.humanRate(root.tx) + "/s   ▼ " + root.humanRate(root.rx) + "/s")
    onExited: if (root.bar) root.bar.hideTooltip(root)
    onClicked: function(mouse) {
      if (!root.bar) return
      if (mouse.button === Qt.RightButton) root.bar.run("omarchy-launch-or-focus-tui btop")
      else root.bar.run("omarchy-launch-or-focus-tui btop")
    }
  }
}
