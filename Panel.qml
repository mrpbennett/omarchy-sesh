import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "mrpbennett.sesh"
  ipcTarget: "mrpbennett.sesh"
  manageIpc: false

  property int selectedIndex: 0
  property bool cursorActive: false
  property bool showingSessions: false
  // Name, not index: the list reloads underneath the confirmation.
  property string pendingDeleteName: ""

  readonly property bool confirmingDelete: pendingDeleteName !== ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color inverse: Color.background
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool active: service.mode === "active"
  readonly property bool modeKnown: service.modeKnown
  readonly property string sessionLabel: !root.modeKnown
    ? "unavailable"
    : root.active
    ? "auto"
    : (service.sessionName !== "" ? service.sessionName : "manual")
  readonly property var options: [
    { title: "Active", detail: "Enable automatic session snapshots", icon: "󰐊" },
    { title: "Manual", detail: "Disable autosave and save now", icon: "󰆓" },
    { title: "Restore", detail: "Choose a saved session to restore", icon: "󰑓" }
  ]

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function choose(index) {
    if (!service.installed || service.busy) return
    selectedIndex = index
    if (index === 0) service.activate()
    else if (index === 1) service.saveManual()
    else showSessions()
  }

  function showSessions() {
    showingSessions = true
    selectedIndex = 0
    cursorActive = false
    pendingDeleteName = ""
    service.listSessions()
  }

  function showOptions() {
    showingSessions = false
    cursorActive = false
    selectedIndex = 2
    pendingDeleteName = ""
  }

  function chooseSession(index) {
    if (!service.installed || service.busy || index < 0 || index >= service.sessions.length) return
    selectedIndex = index
    service.restoreNamed(service.sessions[index].name)
  }

  // Deleting is irreversible, so the row action only asks; deleteConfirmed()
  // is the one path that reaches the database.
  function requestDelete(index) {
    if (!service.installed || service.busy || index < 0 || index >= service.sessions.length) return
    selectedIndex = index
    deleteConfirm.selectedIndex = 0
    pendingDeleteName = service.sessions[index].name
  }

  function deleteCanceled() {
    pendingDeleteName = ""
  }

  function deleteConfirmed() {
    var name = pendingDeleteName
    pendingDeleteName = ""
    if (name !== "") service.deleteSession(name)
  }

  onOpenedChanged: if (opened) {
    selectedIndex = active ? 0 : 1
    cursorActive = false
    showingSessions = false
    pendingDeleteName = ""
    service.ensureInstalled(true)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onActiveChanged: if (opened && !cursorActive) selectedIndex = active ? 0 : 1

  Service { id: service }

  // Deleting a session shortens the list under the cursor.
  Connections {
    target: service
    function onSessionsChanged() {
      if (!root.showingSessions) return
      var count = service.sessions.length
      root.selectedIndex = count === 0 ? 0 : Math.min(root.selectedIndex, count - 1)
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function active(): string { return service.activate() ? "ok" : "unavailable" }
    function manual(): string { return service.saveManual() ? "ok" : "unavailable" }
    function restore(): string { return service.restore() ? "ok" : "unavailable" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        SessionIcon {
          anchors.centerIn: parent
          iconSize: Style.space(13)
          primary: root.barForeground
          inverse: Color.background
          active: root.active
          opacity: root.modeKnown ? 1.0 : 0.55
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) service.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    // Follow the face that is currently turned toward the viewer so the card
    // resizes at the midpoint of the flip rather than before it starts.
    contentHeight: panel.fittedContentHeight(flipable.faceHeight, Style.space(460))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: false
      // While the confirmation is up it owns every key. Enter reaches both
      // returnRequested and activateRequested, so only the latter answers the
      // dialog — otherwise the first handler would close it and the second
      // would fall through and restore the row underneath.
      onMoveRequested: function(dx, dy) {
        if (root.confirmingDelete) {
          if (dx !== 0) deleteConfirm.selectedIndex = deleteConfirm.selectedIndex === 0 ? 1 : 0
          return
        }
        if (!root.cursorActive) root.cursorActive = true
        else if (dy !== 0) {
          var count = root.showingSessions ? service.sessions.length : root.options.length
          if (count > 0) root.selectedIndex = (root.selectedIndex + dy + count) % count
        }
      }
      onActivateRequested: {
        if (root.confirmingDelete) {
          if (deleteConfirm.selectedIndex === 0) root.deleteCanceled()
          else root.deleteConfirmed()
        } else if (root.cursorActive) {
          if (root.showingSessions) root.chooseSession(root.selectedIndex)
          else root.choose(root.selectedIndex)
        }
      }
      onReturnRequested: if (root.cursorActive && !root.confirmingDelete) {
        if (root.showingSessions) root.chooseSession(root.selectedIndex)
        else root.choose(root.selectedIndex)
      }
      onDeleteRequested: if (root.showingSessions && root.cursorActive && !root.confirmingDelete) {
        root.requestDelete(root.selectedIndex)
      }
      onCloseRequested: {
        if (root.confirmingDelete) root.deleteCanceled()
        else if (root.showingSessions) root.showOptions()
        else root.close()
      }
      onTabRequested: function(direction) {
        if (root.confirmingDelete) {
          deleteConfirm.selectedIndex = deleteConfirm.selectedIndex === 0 ? 1 : 0
          return
        }
        root.switchPanel(direction)
      }

      Flipable {
        id: flipable
        anchors.fill: parent

        // The rotation is what decides which face the viewer sees, so the
        // panel height tracks the animated angle, not `showingSessions`.
        readonly property bool showingBack: flipRotation.angle > 90
        readonly property real faceHeight: showingBack ? sessionColumn.implicitHeight : optionColumn.implicitHeight

        front: Item {
          width: flipable.width
          height: flipable.height
          // Only the face turned toward the viewer takes pointer input.
          enabled: !flipable.showingBack

          ColumnLayout {
            id: optionColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Style.space(12)

            PanelHero {
              Layout.fillWidth: true
              title: "Omarchy Sesh"
              detail: service.busy ? "Working..." : root.sessionLabel
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: service.installed ? 1.0 : 0.6
              iconComponent: Component {
                SessionIcon {
                  iconSize: Style.font.display
                  primary: root.foreground
                  inverse: root.inverse
                  active: root.active
                }
              }
            }

            Text {
              visible: service.status !== "" || service.error !== ""
              Layout.fillWidth: true
              text: service.error !== "" ? service.error : service.status
              color: service.error !== "" ? Color.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            PanelSeparator {
              Layout.fillWidth: true
              foreground: root.foreground
            }

            Repeater {
              model: root.options

              CursorSurface {
                required property var modelData
                required property int index

                Layout.fillWidth: true
                implicitHeight: optionRow.implicitHeight + Style.spacing.rowPaddingX
                foreground: root.foreground
                hasCursor: root.cursorActive && !root.showingSessions && root.selectedIndex === index
                current: root.modeKnown && ((index === 0 && root.active) || (index === 1 && !root.active))

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: service.installed && !service.busy
                  cursorShape: Qt.PointingHandCursor
                  onEntered: { root.cursorActive = true; root.selectedIndex = index }
                  onClicked: root.choose(index)
                }

                RowLayout {
                  id: optionRow
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(10)

                  Text {
                    text: modelData.icon
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.icon
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(1)

                    Text {
                      Layout.fillWidth: true
                      text: modelData.title
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }

                    Text {
                      Layout.fillWidth: true
                      text: modelData.detail
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }
          }
        }

        back: Item {
          width: flipable.width
          height: flipable.height
          enabled: flipable.showingBack

          ColumnLayout {
            id: sessionColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Style.space(12)

            PanelHero {
              Layout.fillWidth: true
              title: "Restore Session"
              detail: service.sessionsLoading ? "Loading..." : (service.busy ? "Working..." : "Saved")
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: service.installed ? 1.0 : 0.6
              iconComponent: Component {
                SessionIcon {
                  iconSize: Style.font.display
                  primary: root.foreground
                  inverse: root.inverse
                  active: root.active
                }
              }
              trailingControl: Component {
                PanelActionButton {
                  iconText: "󰌍"
                  tooltipText: "Back"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.showOptions()
                }
              }
            }

            Text {
              visible: service.status !== "" || service.error !== ""
              Layout.fillWidth: true
              text: service.error !== "" ? service.error : service.status
              color: service.error !== "" ? Color.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            PanelSeparator {
              Layout.fillWidth: true
              foreground: root.foreground
            }

            Text {
              visible: !service.sessionsLoading && service.sessions.length === 0 && service.error === ""
              Layout.fillWidth: true
              text: "Named sessions are created with omarchy-sesh save --name NAME."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: service.sessions

              CursorSurface {
                required property var modelData
                required property int index

                Layout.fillWidth: true
                implicitHeight: sessionRow.implicitHeight + Style.spacing.rowPaddingX
                foreground: root.foreground
                hasCursor: root.cursorActive && root.showingSessions && root.selectedIndex === index

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: service.installed && !service.busy
                  cursorShape: Qt.PointingHandCursor
                  onEntered: { root.cursorActive = true; root.selectedIndex = index }
                  onClicked: root.chooseSession(index)
                }

                RowLayout {
                  id: sessionRow
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(10)

                  PanelActionButton {
                    iconText: "󰐊"
                    tooltipText: "Restore session"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    enabled: service.installed && !service.busy
                    onClicked: root.chooseSession(index)
                    onHovered: function(isHovered) {
                      if (!isHovered) return
                      root.cursorActive = true
                      root.selectedIndex = index
                    }
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(1)

                    Text {
                      Layout.fillWidth: true
                      text: modelData.name
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                    }

                    Text {
                      Layout.fillWidth: true
                      text: modelData.created_at + " | " + modelData.windows + (modelData.windows === 1 ? " window" : " windows")
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  PanelActionButton {
                    iconText: "󰩹"
                    tooltipText: "Delete session"
                    foreground: root.foreground
                    hoverColor: Color.urgent
                    fontFamily: root.fontFamily
                    enabled: service.installed && !service.busy
                    onClicked: root.requestDelete(index)
                    onHovered: function(isHovered) {
                      if (!isHovered) return
                      root.cursorActive = true
                      root.selectedIndex = index
                    }
                  }
                }
              }
            }
          }
        }

        transform: Rotation {
          id: flipRotation
          origin.x: flipable.width / 2
          origin.y: flipable.height / 2
          axis { x: 0; y: 1; z: 0 }
          angle: root.showingSessions ? 180 : 0

          Behavior on angle {
            NumberAnimation { duration: 280; easing.type: Easing.InOutQuad }
          }
        }
      }

      // Sibling of the Flipable, so the half-turn never applies to it.
      ConfirmDialog {
        id: deleteConfirm
        anchors.fill: parent
        z: 10
        opened: root.confirmingDelete
        message: "Delete saved session \"" + root.pendingDeleteName + "\"? This cannot be undone."
        confirmText: "Delete"
        background: Color.popups.background
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: root.deleteCanceled()
        onConfirmed: root.deleteConfirmed()
      }
    }
  }
}
