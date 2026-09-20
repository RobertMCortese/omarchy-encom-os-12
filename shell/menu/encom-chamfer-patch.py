#!/usr/bin/env python3
"""Give the Omarchy menu card the ENCOM chamfered frame.

<user>.menu is a clone of the built-in omarchy.menu (made by the installer), so Omarchy updates to the
menu do not reach it. To pick them up: remove this clone, re-run
`omarchy plugin clone omarchy.menu`, copy this script back into the new clone
and run it. It edits the card block, the appLibrary binding and the apps
provider; each edit is applied once, so running it again is safe and also
brings an older patched clone up to date.

The card keeps its BorderSurface for layout, with the stock fill and gradient
border switched off, and a Canvas behind the content draws the chamfered
frame instead. The stock border width is added back as padding so the content
insets, and therefore the whole layout, stay exactly where they were.
"""
import os
import sys

path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Menu.qml")
src = open(path).read()
changed = []


def apply(marker, edits, what):
    """Apply (old, new) edits unless marker shows they are already in."""
    global src
    if marker in src:
        return
    for a, b in edits:
        if a not in src:
            sys.exit(what + " not found — the upstream menu changed; patch by hand")
        src = src.replace(a, b, 1)
    changed.append(what)


old = """    BorderSurface {
      id: card
      width: root.cardWidth
      height: Math.min(root.cardHeight, panel.height - Style.gapsOut - panel.effectiveCardTop)
      radius: root.cornerRadius
      anchors.horizontalCenter: parent.horizontalCenter
      y: panel.effectiveCardTop
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin
"""

new = """    BorderSurface {
      id: card
      width: root.cardWidth
      height: Math.min(root.cardHeight, panel.height - Style.gapsOut - panel.effectiveCardTop)
      radius: 0
      anchors.horizontalCenter: parent.horizontalCenter
      y: panel.effectiveCardTop
      // ENCOM chamfer: the frame below replaces the stock fill and border.
      color: "transparent"
      borderSpec: Border.none()
      padding: root.contentMargin + Border.top(root.borderSpec)

      Canvas {
        id: encomFrame
        anchors.fill: parent
        z: -1

        readonly property int chamfer: 16

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
          target: root
          function onBackgroundChanged() { encomFrame.requestPaint() }
        }
        Connections {
          target: Color
          function onAccentChanged() { encomFrame.requestPaint() }
        }

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var c = chamfer
          // Half-pixel inset keeps the 1px stroke crisp.
          var x0 = 0.5, y0 = 0.5, x1 = width - 0.5, y1 = height - 0.5

          // Top-right and bottom-left cut, matching the HUD panels.
          ctx.beginPath()
          ctx.moveTo(x0, y0)
          ctx.lineTo(x1 - c, y0)
          ctx.lineTo(x1, y0 + c)
          ctx.lineTo(x1, y1)
          ctx.lineTo(x0 + c, y1)
          ctx.lineTo(x0, y1 - c)
          ctx.closePath()

          ctx.fillStyle = root.background
          ctx.fill()

          ctx.strokeStyle = Color.accent
          ctx.globalAlpha = 0.75
          ctx.lineWidth = 1
          ctx.stroke()

          // Bright tab along the top edge.
          ctx.globalAlpha = 1.0
          ctx.lineWidth = 2
          ctx.beginPath()
          ctx.moveTo(x0 + 10, y0 + 1)
          ctx.lineTo(x0 + 10 + Math.min(60, width * 0.18), y0 + 1)
          ctx.stroke()

          // Mirrored short tab on the bottom edge, right of the cut.
          ctx.globalAlpha = 0.6
          ctx.beginPath()
          ctx.moveTo(x1 - 10 - Math.min(36, width * 0.1), y1 - 1)
          ctx.lineTo(x1 - 10, y1 - 1)
          ctx.stroke()
        }
      }
"""

apply("// ENCOM chamfer", [(old, new)], "card block")

# ── App-library fallback ─────────────────────────────────────────────────
# On Omarchy 4.0.4 a cloned menu is handed a shell API whose appLibrary is
# null (it is null from the moment the handle arrives), so the Apps list is
# empty. Fall back to a private AppLibrary built from the same shell service
# the built-in uses, and re-merge the app rows whenever the library appears,
# because the apps provider only runs once per shell.
IMPORT_OLD = 'import "MenuModel.js" as MenuModel\n'
IMPORT_NEW = ('import "MenuModel.js" as MenuModel\n'
              'import "file:///usr/share/omarchy/shell/services" as OmarchyServices\n')

LIB_OLD = "  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null\n"
LIB_NEW = """  // ENCOM app-library fallback: prefer the shell's, else use a private one.
  readonly property var appLibrary: root.shell && root.shell.appLibrary
    ? root.shell.appLibrary : (encomAppLibraryLoader.item || null)
  onAppLibraryChanged: if (root.appLibrary && root.providersLoaded["apps"]) root.mergeAppRows()

  Loader {
    id: encomAppLibraryLoader
    // Only built when the shell gave us nothing, so a working Omarchy costs
    // no second icon scan. The shell handle itself can miss (clone panels
    // are injected on the Loader's onLoaded, which is racy across restarts),
    // so gate on the effective appLibrary, not on `shell`.
    active: !(root.shell && root.shell.appLibrary)
    sourceComponent: Component { OmarchyServices.AppLibrary { } }
  }
"""

apply("// ENCOM app-library fallback", [(IMPORT_OLD, IMPORT_NEW), (LIB_OLD, LIB_NEW)],
      "appLibrary property")

# ── Apps list refresh ────────────────────────────────────────────────────
# The stock apps provider fills the list once per shell. If that first fill
# lands before the library has read the desktop entries, the Apps list stays
# "Nothing here yet" until the shell restarts. Rebuild it on every visit
# (it is a quick in-memory sort), and while it comes back empty, try again
# shortly.
LOAD_OLD = """  function loadProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return
"""
LOAD_NEW = """  function loadProviderForMenu(id) {
    var entry = root.item(id)
    // ENCOM apps refresh: rebuild the app rows on every visit.
    if (entry && entry.provider === "apps") {
      root.providersLoaded[id] = true
      root.mergeAppRows()
      return
    }
    if (!entry || !entry.provider || root.providersLoaded[id]) return
"""
MERGE_OLD = """    var rows = root.appLibrary.sortedEntries("")
"""
MERGE_NEW = """    var rows = root.appLibrary.sortedEntries("")
    if (rows.length === 0 && encomAppRetry.tries < 20) encomAppRetry.restart()
    else encomAppRetry.tries = 0
"""
RETRY_OLD = """  Connections {
    target: root.appLibrary
"""
RETRY_NEW = """  Timer {
    id: encomAppRetry
    property int tries: 0
    interval: 500
    onTriggered: { tries++; root.mergeAppRows() }
  }

  Connections {
    target: root.appLibrary
"""
apply("// ENCOM apps refresh",
      [(LOAD_OLD, LOAD_NEW), (MERGE_OLD, MERGE_NEW), (RETRY_OLD, RETRY_NEW)], "apps provider")

if changed:
    open(path, "w").write(src)
    print("patched:", ", ".join(changed))
else:
    print("already patched")
