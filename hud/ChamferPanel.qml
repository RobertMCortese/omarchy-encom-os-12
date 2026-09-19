import QtQuick

// The signature ENCOM panel: a thin-outlined rectangle with one or more
// corners cut at 45 degrees, a brighter "tab" segment on one edge, and an
// optional ticked rule under the header.
//
// Drawn in a single Canvas pass and repainted only when its geometry or
// colours change — the frame is chrome, so it must cost nothing at rest.
Item {
  id: panel

  default property alias content: inner.data

  property color stroke: "#6fc3df"
  // The backing is deliberately NOT the stroke colour: filling with cyan
  // lightens the panel and a busy wallpaper then shows straight through it.
  // A dark backing is what makes these read as smoked glass over the grid.
  property color fill: "#03070b"
  property color tabStroke: "#a8ecff"
  property real strokeAlpha: 0.55
  property real fillAlpha: 0.72
  property int chamfer: 12
  property int padding: 12

  // Which corners get cut. Top-right + bottom-left reads closest to the
  // film's console panels.
  property bool chamferTopLeft: false
  property bool chamferTopRight: true
  property bool chamferBottomRight: false
  property bool chamferBottomLeft: true

  // Header rule: a hairline with tick marks below the first child row.
  property bool headerRule: false
  property int headerHeight: 22

  implicitWidth: inner.childrenRect.width + padding * 2
  implicitHeight: inner.childrenRect.height + padding * 2

  Canvas {
    id: frame
    anchors.fill: parent

    Connections {
      target: panel
      function onWidthChanged() { frame.requestPaint() }
      function onHeightChanged() { frame.requestPaint() }
      function onStrokeChanged() { frame.requestPaint() }
    }

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()

      var c = panel.chamfer
      // Inset by half a pixel so a 1px stroke lands on the pixel grid
      // instead of straddling two rows and going grey.
      var x0 = 0.5, y0 = 0.5
      var x1 = width - 0.5, y1 = height - 0.5

      ctx.beginPath()
      ctx.moveTo(x0 + (panel.chamferTopLeft ? c : 0), y0)
      ctx.lineTo(x1 - (panel.chamferTopRight ? c : 0), y0)
      if (panel.chamferTopRight) ctx.lineTo(x1, y0 + c)
      ctx.lineTo(x1, y1 - (panel.chamferBottomRight ? c : 0))
      if (panel.chamferBottomRight) ctx.lineTo(x1 - c, y1)
      ctx.lineTo(x0 + (panel.chamferBottomLeft ? c : 0), y1)
      if (panel.chamferBottomLeft) ctx.lineTo(x0, y1 - c)
      ctx.lineTo(x0, y0 + (panel.chamferTopLeft ? c : 0))
      ctx.closePath()

      ctx.fillStyle = panel.fill
      ctx.globalAlpha = panel.fillAlpha
      ctx.fill()

      ctx.globalAlpha = panel.strokeAlpha
      ctx.strokeStyle = panel.stroke
      ctx.lineWidth = 1
      ctx.stroke()

      // Tab: a short bright run along the top edge, left of any chamfer.
      // This is what stops the frame reading as a plain box.
      ctx.globalAlpha = 0.95
      ctx.strokeStyle = panel.tabStroke
      ctx.lineWidth = 2
      ctx.beginPath()
      var tabStart = x0 + (panel.chamferTopLeft ? c : 0) + 6
      ctx.moveTo(tabStart, y0 + 1)
      ctx.lineTo(tabStart + Math.min(34, width * 0.3), y0 + 1)
      ctx.stroke()

      if (!panel.headerRule) return

      // Header rule with ticks, sitting under the panel's first row.
      var ry = y0 + panel.headerHeight
      ctx.globalAlpha = 0.4
      ctx.strokeStyle = panel.stroke
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(x0 + 8, ry)
      ctx.lineTo(x1 - 8, ry)
      ctx.stroke()

      ctx.globalAlpha = 0.55
      ctx.beginPath()
      for (var tx = x0 + 12; tx < x1 - 10; tx += 9) {
        ctx.moveTo(tx, ry)
        ctx.lineTo(tx, ry + 3)
      }
      ctx.stroke()
    }
  }

  Item {
    id: inner
    x: panel.padding
    y: panel.padding
  }
}
