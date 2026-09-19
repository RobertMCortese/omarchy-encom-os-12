import QtQuick
import Quickshell.Io
import Quickshell
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// ENCOM OS-12 workspace nodes.
//
// Each workspace is a numbered node on a rail: dim when empty, lit when it
// holds windows, and bracketed with an underscored bar when focused. Drawn
// with plain rectangles rather than a Canvas so switching workspaces costs a
// property change, not a repaint.
BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

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

  readonly property color encomCyan: encom.accent || "#6fc3df"
  readonly property color encomCyanHi: encom.accentHi || "#a8ecff"

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : 1
    rowSpacing: root.vertical ? 2 : 0

    Repeater {
      model: root.workspaceIds()

      Item {
        id: node
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null
          && Hyprland.focusedWorkspace.id === modelData

        implicitWidth: root.vertical ? root.barSize : 20
        implicitHeight: root.barSize

        // Focus bracket: hairlines above and below the node, the way a
        // selected cell reads on an Encom console.
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          anchors.topMargin: 4
          width: 12
          height: 1
          color: root.encomCyanHi
          opacity: node.focused ? 0.9 : 0
          Behavior on opacity { NumberAnimation { duration: 110 } }
        }

        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 4
          width: 12
          height: 1
          color: root.encomCyanHi
          opacity: node.focused ? 0.9 : 0
          Behavior on opacity { NumberAnimation { duration: 110 } }
        }

        Text {
          id: label
          anchors.centerIn: parent
          text: node.modelData === 10 ? "0" : String(node.modelData)
          color: node.focused ? root.encomCyanHi : root.encomCyan
          font.family: root.bar ? root.bar.fontFamily : "monospace"
          font.pixelSize: 11
          font.bold: node.focused
          // Empty workspaces stay legible but recede; occupied ones sit
          // between the two so the eye can sort the rail at a glance.
          opacity: node.focused ? 1.0 : (node.occupied ? 0.78 : 0.3)
          Behavior on opacity { NumberAnimation { duration: 110 } }
          Behavior on color { ColorAnimation { duration: 110 } }
        }

        // Occupancy pip, hidden while focused since the brackets already
        // carry that state.
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 4
          width: 2
          height: 2
          radius: 1
          color: root.encomCyan
          visible: node.occupied && !node.focused
        }

        MouseArea {
          anchors.fill: parent
          onClicked: root.focusWorkspace(node.modelData)
        }
      }
    }
  }
}
