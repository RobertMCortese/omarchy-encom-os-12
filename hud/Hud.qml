import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// ENCOM OS-12 desktop HUD.
//
// A click-through layer that sits above the wallpaper and below windows, so
// it reads as etched into the desktop rather than floating over the work.
// Everything here is drawn once and repainted only when a sample changes:
// this runs on a Broadwell iGPU, and a continuously animating HUD would show
// up as fan noise and battery drain long before it looked cool.
Item {
  id: root

  property var shell
  property var manifest

  // ── Theme palette ───────────────────────────────────────────────────────
  // The current Omarchy theme's encom.json, so a theme switch recolours the
  // ENCOM pieces together. Missing or unreadable, the Tron: Legacy colours
  // below stand in.
  property var encom: ({})
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/encom.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.encom = JSON.parse(text()) } catch (e) { root.encom = ({}) } }
    onLoadFailed: root.encom = ({})
  }

  readonly property color cyan:    encom.accent || "#6fc3df"
  readonly property color cyanHi:  encom.accentHi || "#a8ecff"
  readonly property color cyanDim: encom.accentDim || "#1b4d5e"
  readonly property color orange:  encom.contrast || "#ff8c21"
  // Alerts are ENCOM teal, as in the Boardroom; orange stays for load warnings.
  readonly property color alert:   encom.alert || "#a8ecff"

  readonly property string mono: "JetBrainsMono Nerd Font"

  // ── Live sample ─────────────────────────────────────────────────────────
  property int cpu: 0
  property int mem: 0
  property int memUsed: 0
  property int temp: 0
  property int bat: -1
  property string bstat: "none"
  property real rx: 0
  property real tx: 0

  // ── Static identity, refreshed rarely ───────────────────────────────────
  property string hostName: ""
  property string kernel: ""
  property string uptime: ""

  // ── Boot cascade ────────────────────────────────────────────────────────
  // OS-12 comes up with a system check that types itself out and settles.
  // It runs once per shell start, then never costs anything again.
  property bool booting: true
  property int bootStep: 0
  readonly property var bootLines: [
    "ENCOM SYSTEM BOOT",
    "SYS CHECK .......... OK",
    "MEM CHECK .......... OK",
    "GRID LINK .......... OK",
    "I/O TOWER .......... OK",
    "USER AUTHENTICATED"
  ]

  function pad2(n) { return n < 10 ? "0" + n : String(n) }

  function humanRate(b) {
    if (b < 1024) return "0 K"
    if (b < 1048576) return Math.round(b / 1024) + " K"
    if (b < 1073741824) return (b / 1048576).toFixed(1) + " M"
    return (b / 1073741824).toFixed(1) + " G"
  }

  function statusWord() {
    if (alerts.length) return "ALERT \u00d7" + alerts.length
    if (temp >= 90 || mem >= 92) return "THROTTLED"
    if (cpu >= 85 || mem >= 85) return "LOAD HIGH"
    return "NOMINAL"
  }

  function statusColor() {
    if (alerts.length) return alert
    return statusWord() === "NOMINAL" ? cyan : orange
  }

  Process {
    id: probe
    command: ["bash", "-lc", "$HOME/.config/omarchy/bar/scripts/encom-telemetry"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!text) return
        try {
          var d = JSON.parse(text)
          root.cpu = d.cpu; root.mem = d.mem; root.memUsed = d.memused
          root.temp = d.temp; root.bat = d.bat; root.bstat = d.bstat
          root.rx = d.rx; root.tx = d.tx
        } catch (e) {}
      }
    }
  }

  Process {
    id: identProbe
    command: ["bash", "-lc",
      "printf '%s\\n%s\\n%s\\n' \"$(hostnamectl hostname 2>/dev/null || hostname)\" \"$(uname -r)\" \"$(uptime -p 2>/dev/null | sed 's/^up //')\""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text).split("\n")
        root.hostName = (lines[0] || "").toUpperCase()
        root.kernel = lines[1] || ""
        root.uptime = lines[2] || ""
      }
    }
  }

  // ── Alerts ──────────────────────────────────────────────────────────────
  // The same checks the Boardroom uses (~/.local/share/encom-boardroom/
  // checks.py): disk, memory and swap, failed services, sustained heat,
  // low battery, and crashes or OOM kills in the last five minutes.
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

  // The HUD is ambient, so it samples half as often as the bar gauge.
  Timer {
    interval: 6000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: probe.running = true
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: identProbe.running = true
  }

  // Step through the boot lines, then hand the screen over to the HUD.
  Timer {
    id: bootTimer
    interval: 320
    running: root.booting
    repeat: true
    onTriggered: {
      if (root.bootStep < root.bootLines.length) {
        root.bootStep++
      } else {
        root.booting = false
        running = false
      }
    }
  }

  // ── Boardroom wallpaper ─────────────────────────────────────────────────
  // While the live Boardroom is the desktop background (encom-wallpaper),
  // it already shows this machine's state, and it shares this layer, so the
  // HUD steps aside. The wallpaper's service creates this flag file while it
  // runs and removes it when it stops, crashed or not.
  property bool wallpaperActive: false

  FileView {
    id: wallpaperFlag
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/encom-wallpaper.active"
    printErrors: false
    onLoaded: root.wallpaperActive = true
    onLoadFailed: root.wallpaperActive = false
  }
  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: wallpaperFlag.reload()
  }

  // ── Screensaver ─────────────────────────────────────────────────────────
  // Omarchy's ttfx screensaver is switched off (omarchy toggle screensaver)
  // and this opens the ENCOM one instead (Light Cycles or the Boardroom), at
  // the same idle timeout and honouring the same inhibitors. Its window
  // carries the org.omarchy.screensaver class, so Omarchy's idle service
  // tracks it as its own screensaver: the lock still fires on schedule, and
  // closing it counts as activity. The launcher checks stay-awake, lock
  // state and its own encom-screensaver-off toggle.
  property int screensaverSeconds: 150

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    onFileChanged: reload()
    // Without the file, still run the screensaver at the default timeout.
    onLoadFailed: root.screensaverTimeoutKnown = true
    onLoaded: {
      try {
        var idle = JSON.parse(text()).idle || {}
        var s = Number(idle.screensaver)
        if (isFinite(s) && s > 0) root.screensaverSeconds = s
        root.screensaverTimeoutKnown = true
        console.log("encom.hud: screensaver timeout " + root.screensaverSeconds + "s")
      } catch (e) {
        console.warn("encom.hud: could not read idle timeout: " + e)
      }
    }
  }

  // IdleMonitor registers its timeout with the compositor when it is created
  // and does not re-register when the property changes later, so it is only
  // built once shell.json has been read, and rebuilt when the value changes.
  property bool screensaverTimeoutKnown: false
  onScreensaverSecondsChanged: {
    if (!screensaverTimeoutKnown) return
    idleMonitorLoader.active = false
    idleMonitorLoader.active = true
  }

  Loader {
    id: idleMonitorLoader
    active: root.screensaverTimeoutKnown
    sourceComponent: Component {
      IdleMonitor {
        enabled: true
        timeout: root.screensaverSeconds
        respectInhibitors: true
        onIsIdleChanged: {
          console.log("encom.hud: idle=" + isIdle + " after " + root.screensaverSeconds + "s")
          if (isIdle)
            Quickshell.execDetached(["bash", "-lc", "exec \"$HOME/.local/bin/encom-screensaver\""])
        }
      }
    }
  }

  // ── Reusable pieces ─────────────────────────────────────────────────────

  component Meter: Item {
    id: m
    property string label: ""
    property int value: 0
    property string suffix: "%"
    property int warnAt: 85

    readonly property color lit: value >= warnAt ? root.orange : root.cyan

    implicitWidth: 172
    implicitHeight: 15

    Text {
      id: name
      anchors.verticalCenter: parent.verticalCenter
      text: m.label
      color: root.cyan
      opacity: 0.75
      font.family: root.mono
      font.pixelSize: 9
      font.letterSpacing: 1.2
      width: 36
    }

    Row {
      id: cells
      anchors.left: name.right
      anchors.leftMargin: 4
      anchors.verticalCenter: parent.verticalCenter
      spacing: 2
      Repeater {
        model: 20
        Rectangle {
          required property int index
          width: 4
          height: 8
          color: (index * 5) < m.value ? m.lit : root.cyanDim
          opacity: (index * 5) < m.value ? 0.95 : 0.4
        }
      }
    }

    Text {
      anchors.left: cells.right
      anchors.leftMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      text: root.pad2(m.value) + m.suffix
      color: m.lit
      font.family: root.mono
      font.pixelSize: 9
    }
  }

  component Readout: Row {
    property string k: ""
    property string v: ""
    property color vColor: root.cyanHi
    spacing: 8
    Text {
      text: parent.k
      color: root.cyan
      opacity: 0.6
      font.family: root.mono
      font.pixelSize: 9
      font.letterSpacing: 1.0
      width: 32
    }
    Text {
      text: parent.v
      color: parent.vColor
      font.family: root.mono
      font.pixelSize: 9
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: hud
      required property var modelData

      screen: modelData
      visible: !root.wallpaperActive
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }

      WlrLayershell.namespace: "encom-hud"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}

      readonly property int inset: 18
      readonly property int topInset: 34
      // Notifications land top-right and are about 80px tall, so the ident
      // panel starts below that band rather than underneath them. A burst of
      // stacked notifications can still reach it, but those are transient.
      readonly property int notifyBand: 82

      // ── Corner brackets ───────────────────────────────────────────────
      Canvas {
        anchors.fill: parent
        opacity: root.booting ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 500 } }

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.strokeStyle = root.cyan
          ctx.lineWidth = 1
          ctx.globalAlpha = 0.5

          var i = hud.inset, t = hud.topInset, arm = 26
          var w = width, h = height

          ctx.beginPath(); ctx.moveTo(i, t + arm); ctx.lineTo(i, t); ctx.lineTo(i + arm, t); ctx.stroke()
          ctx.beginPath(); ctx.moveTo(w - i - arm, t); ctx.lineTo(w - i, t); ctx.lineTo(w - i, t + arm); ctx.stroke()
          ctx.beginPath(); ctx.moveTo(i, h - i - arm); ctx.lineTo(i, h - i); ctx.lineTo(i + arm, h - i); ctx.stroke()
          ctx.beginPath(); ctx.moveTo(w - i - arm, h - i); ctx.lineTo(w - i, h - i); ctx.lineTo(w - i, h - i - arm); ctx.stroke()

          ctx.globalAlpha = 0.13
          ctx.beginPath()
          ctx.moveTo(i, t + arm + 10); ctx.lineTo(i, h - i - arm - 10)
          ctx.moveTo(w - i, t + arm + 10); ctx.lineTo(w - i, h - i - arm - 10)
          ctx.stroke()
        }
      }

      // ── Boot cascade ──────────────────────────────────────────────────
      Column {
        x: hud.inset + 32
        y: hud.topInset + 30
        spacing: 5
        visible: root.booting
        opacity: root.booting ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 420 } }

        Repeater {
          model: root.bootLines.length
          Text {
            required property int index
            visible: index < root.bootStep
            text: root.bootLines[index]
            color: index === 0 ? root.cyanHi : root.cyan
            font.family: root.mono
            font.pixelSize: index === 0 ? 15 : 11
            font.bold: index === 0
            font.letterSpacing: index === 0 ? 4 : 1.6
          }
        }
      }

      // ── Top-right: system ident ───────────────────────────────────────
      // Sits right so a terminal's top-left corner is not competing with it
      // through the translucent background.
      ChamferPanel {
        id: identPanel
        x: parent.width - hud.inset - 14 - width
        y: hud.topInset + 14 + hud.notifyBand
        opacity: root.booting ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 600 } }

        stroke: root.cyan
        tabStroke: root.cyanHi
        headerRule: true
        headerHeight: 38
        padding: 13
        chamfer: 13

        Column {
          spacing: 3

          Row {
            spacing: 8
            bottomPadding: 14
            // The current theme's wordmark, traced to SVG and kept at
            // logo/mark.svg in every theme. Rendered at 2x for crisp edges.
            Image {
              anchors.verticalCenter: parent.verticalCenter
              source: "file://" + Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/logo/mark.svg"
              height: 18
              width: 77
              fillMode: Image.PreserveAspectFit
              sourceSize: Qt.size(154, 36)
              smooth: true
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              // "OS-12" for ENCOM; a branded theme says who it belongs to.
              text: (root.encom.brand || "ENCOM OS-12").replace(/^ENCOM /, "")
              color: root.cyan
              opacity: 0.7
              font.family: root.mono
              font.pixelSize: 15
              font.letterSpacing: 3
            }
          }

          Readout { k: "NODE"; v: root.hostName }
          Readout { k: "KRNL"; v: root.kernel }
          Readout { k: "CYCL"; v: root.uptime }
          Readout { k: "STAT"; v: root.statusWord(); vColor: root.statusColor() }
        }
      }

      // ── Alerts, stacked under the ident panel ─────────────────────────
      ChamferPanel {
        visible: root.alerts.length > 0
        x: parent.width - hud.inset - 14 - width
        y: identPanel.y + identPanel.height + 10
        opacity: root.booting ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 600 } }

        stroke: root.alert
        tabStroke: "#ffffff"
        strokeAlpha: 0.9
        padding: 11
        chamfer: 11
        chamferTopRight: false
        chamferBottomLeft: false
        chamferTopLeft: true
        chamferBottomRight: true

        Column {
          spacing: 3

          Text {
            text: "SYSTEM ALERT"
            color: root.alert
            font.family: root.mono
            font.pixelSize: 11
            font.bold: true
            font.letterSpacing: 3
            bottomPadding: 3
          }

          Repeater {
            // Room for four; the Boardroom's box shows the full list.
            model: root.alerts.slice(0, 4)
            Row {
              required property var modelData
              spacing: 7
              Text {
                text: modelData.level
                color: modelData.level === "CRIT" ? "#ffffff" : root.cyan
                font.family: root.mono
                font.pixelSize: 9
                width: 30
              }
              Text {
                text: String(modelData.who).toUpperCase() + "  " + modelData.title
                color: "#cfefff"
                font.family: root.mono
                font.pixelSize: 9
                width: 210
                elide: Text.ElideRight
              }
            }
          }

          Text {
            visible: root.alerts.length > 4
            text: "+" + (root.alerts.length - 4) + " MORE"
            color: root.cyan
            opacity: 0.7
            font.family: root.mono
            font.pixelSize: 9
          }
        }
      }

      // ── Bottom-right: telemetry ───────────────────────────────────────
      ChamferPanel {
        x: parent.width - hud.inset - 14 - width
        y: parent.height - hud.inset - 14 - height
        opacity: root.booting ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 600 } }

        stroke: root.cyan
        tabStroke: root.cyanHi
        padding: 13
        chamfer: 13
        // Mirror the ident panel so the pair reads as one system.
        chamferTopRight: false
        chamferBottomLeft: false
        chamferTopLeft: true
        chamferBottomRight: true

        Column {
          spacing: 2

          Meter { label: "CPU"; value: root.cpu }
          Meter { label: "MEM"; value: root.mem }
          Meter { label: "THRM"; value: root.temp; suffix: "°"; warnAt: 85 }
          // Battery is inverted: low is the alarming end, so it never warns
          // the way a high CPU load does.
          Meter { label: "PWR"; value: root.bat < 0 ? 100 : root.bat; warnAt: 101 }

          Item { width: 1; height: 5 }

          Row {
            spacing: 12
            Item { width: 36; height: 1 }
            Text {
              text: "▲ " + root.humanRate(root.tx)
              color: root.cyan
              opacity: root.tx > 8192 ? 0.95 : 0.4
              font.family: root.mono
              font.pixelSize: 9
            }
            Text {
              text: "▼ " + root.humanRate(root.rx)
              color: root.cyanHi
              opacity: root.rx > 8192 ? 0.95 : 0.4
              font.family: root.mono
              font.pixelSize: 9
            }
          }
        }
      }

      // ── Bottom-left: identity disc ────────────────────────────────────
      Canvas {
        id: discCanvas
        width: 84
        height: 84
        x: hud.inset + 14
        y: parent.height - hud.inset - 14 - height
        opacity: root.booting ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 700 } }

        Connections {
          target: root
          function onCpuChanged() { discCanvas.requestPaint() }
        }

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var cx = width / 2, cy = height / 2, r = width / 2 - 3

          ctx.globalAlpha = 0.85
          ctx.strokeStyle = root.cyanHi
          ctx.lineWidth = 1
          ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.stroke()

          ctx.globalAlpha = 0.45
          ctx.strokeStyle = root.cyan
          ctx.beginPath(); ctx.arc(cx, cy, r * 0.62, 0, Math.PI * 2); ctx.stroke()

          ctx.globalAlpha = 0.4
          for (var i = 0; i < 36; i++) {
            var a = i * Math.PI / 18
            var r0 = r * 0.80, r1 = r * 0.92
            ctx.beginPath()
            ctx.moveTo(cx + r0 * Math.cos(a), cy + r0 * Math.sin(a))
            ctx.lineTo(cx + r1 * Math.cos(a), cy + r1 * Math.sin(a))
            ctx.stroke()
          }

          var frac = Math.max(0, Math.min(100, root.cpu)) / 100
          if (frac > 0.005) {
            ctx.globalAlpha = 0.95
            ctx.strokeStyle = root.cpu >= 85 ? root.orange : root.cyanHi
            ctx.lineWidth = 3
            ctx.beginPath()
            ctx.arc(cx, cy, r * 0.62, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * frac)
            ctx.stroke()
          }

          ctx.globalAlpha = 0.9
          ctx.fillStyle = root.cyanHi
          ctx.beginPath(); ctx.arc(cx, cy, 3, 0, Math.PI * 2); ctx.fill()
        }
      }
    }
  }
}
