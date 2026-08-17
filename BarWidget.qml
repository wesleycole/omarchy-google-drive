import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.wesleycole.google-drive"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false
  readonly property color iconColor: panelLoader.item
    ? panelLoader.item.barIconColor
    : (bar ? bar.barForeground : Color.foreground)
  readonly property bool driveActive: panelLoader.item ? panelLoader.item.driveActive === true : false
  readonly property string driveStatus: panelLoader.item ? panelLoader.item.driveStatus : "Checking…"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function setup() {
    if (panelLoader.item && panelLoader.item.setup) panelLoader.item.setup()
  }

  function toggleMount() {
    if (panelLoader.item && panelLoader.item.toggleMount) panelLoader.item.toggleMount()
  }

  function open() {
    if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item && panelLoader.item.closeForPopoutSwitch)
      panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: root.moduleName
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.broadcast("refresh"); return "ok" }
    function setup(): string { root.setup(); return "ok" }
    function toggleMount(): string { root.toggleMount(); return "ok" }
    function status(): string { return root.driveStatus }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: "Google Drive · " + root.driveStatus
    iconComponent: Component {
      Item {
        GoogleDriveIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.iconColor
          opacity: root.driveActive ? 1.0 : 0.6
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh()
      else if (buttonCode === Qt.MiddleButton) root.setup()
      else root.toggle()
    }
  }
}
