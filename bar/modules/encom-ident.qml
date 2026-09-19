import QtQuick
import Quickshell.Io
import Quickshell

// ENCOM OS-12 system ident: the identity-disc sigil plus the wordmark.
// Deliberately static — it is chrome, not telemetry, so it must not cost a
// single repaint once drawn. The only motion is a hover response.
Item {
  id: root

  property var bar
  property string moduleName: "encom.ident"
  property var settings: ({})

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

  readonly property color cyan:   encom.accent || "#6fc3df"
  readonly property color cyanHi: encom.accentHi || "#a8ecff"

  readonly property bool vertical: bar ? bar.vertical === true : false
  readonly property string fontFamily: bar ? bar.fontFamily : "monospace"
  readonly property string wordmark: String((settings && settings.text) || "ENCOM")

  property bool hovered: false

  implicitWidth: vertical ? (bar ? bar.barSize : 28) : content.implicitWidth + 12
  implicitHeight: vertical ? sigil.height + 6 : (bar ? bar.barSize : 26)

  Row {
    id: content
    anchors.centerIn: parent
    spacing: 6

    // The ENCOM International mark on a horizontal bar; the disc sigil stays
    // for vertical bars, which are too narrow for the wide logo.
    Image {
      visible: !root.vertical
      anchors.verticalCenter: parent.verticalCenter
      source: "file://" + Quickshell.env("HOME") + "/.config/omarchy/themes/encom-os-12/logo/encom-mark.svg"
      height: 12
      width: 52
      fillMode: Image.PreserveAspectFit
      sourceSize: Qt.size(104, 24)
      smooth: true
      opacity: root.hovered ? 1.0 : 0.88
      Behavior on opacity { NumberAnimation { duration: 140 } }
    }

    Canvas {
      id: sigil
      visible: root.vertical
      width: 15
      height: 15
      anchors.verticalCenter: parent.verticalCenter
      opacity: root.hovered ? 1.0 : 0.88
      Behavior on opacity { NumberAnimation { duration: 140 } }

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var cx = width / 2, cy = height / 2
        ctx.strokeStyle = root.cyanHi
        ctx.lineWidth = 1.2

        // Outer ring, broken at the top like a disc seated in its dock.
        ctx.beginPath()
        ctx.arc(cx, cy, cx - 1, -Math.PI * 0.35, Math.PI * 1.2)
        ctx.stroke()

        // Inner ring.
        ctx.beginPath()
        ctx.arc(cx, cy, (cx - 1) * 0.52, 0, Math.PI * 2)
        ctx.strokeStyle = root.cyan
        ctx.lineWidth = 1.6
        ctx.stroke()

        // Core.
        ctx.beginPath()
        ctx.arc(cx, cy, 1.3, 0, Math.PI * 2)
        ctx.fillStyle = root.cyanHi
        ctx.fill()
      }
    }

    Text {
      visible: false   // superseded by the logo mark above
      anchors.verticalCenter: parent.verticalCenter
      text: root.wordmark
      color: root.hovered ? root.cyanHi : root.cyan
      font.family: root.fontFamily
      font.pixelSize: 10
      font.letterSpacing: 2.2
      font.bold: true
      Behavior on color { ColorAnimation { duration: 140 } }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onEntered: {
      root.hovered = true
      if (root.bar) root.bar.showTooltip(root, "ENCOM OS-12  ·  Omarchy")
    }
    onExited: {
      root.hovered = false
      if (root.bar) root.bar.hideTooltip(root)
    }
    onClicked: function(mouse) {
      if (!root.bar) return
      if (mouse.button === Qt.RightButton) root.bar.run("omarchy-launch-terminal")
      else root.bar.run("omarchy-menu")
    }
  }
}
