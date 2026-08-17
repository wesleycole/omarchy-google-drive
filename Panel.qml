import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.wesleycole.google-drive"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property string focusSection: "setup"
  property int fileIndex: 0
  property bool cursorActive: false
  property int phraseIndex: 0
  property string fileQuery: ""

  readonly property var barIdentity: hostWidget || root
  readonly property bool searchMode: fileQuery.trim().length >= 2
  readonly property var fileResults: searchMode ? drive.searchResults : drive.files
  readonly property bool driveActive: drive.active
  readonly property string driveStatus: drive.statusText
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: drive.authenticated && drive.active ? foreground : dim
  readonly property color barIconColor: drive.authenticated && drive.active ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property string toggleHint: drive.active ? "Unmount Google Drive" : "Mount Google Drive"
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && drive.authenticated
  readonly property string displayMountPath: Model.shortHomePath(drive.accountPath, Quickshell.env("HOME"))
  readonly property var activePhrases: [
    "Clouds connected",
    "Files within reach",
    "Folders flowing",
    "Drive mounted",
    "Bytes on standby",
    "Workspace in the cloud"
  ]
  readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]

  function refresh() {
    drive.refresh()
  }

  function setup() {
    drive.setup()
  }

  function toggleMount() {
    if (drive.installed && drive.authenticated && !drive.busy) drive.toggleRunning()
  }

  function open() {
    drive.refresh()
    root.controller.show()
    Qt.callLater(function() {
      root.cursorActive = false
      if (panelFlick) panelFlick.contentY = 0
      keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    root.controller.hide()
  }

  function focusFileSearch() {
    if (!drive.active) return
    searchField.forceActiveFocus()
    searchField.selectAll()
  }

  function clearFileSearch() {
    fileQuery = ""
    searchField.text = ""
    drive.clearSearch()
    fileIndex = 0
    focusSection = "header"
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function ensureCursor() {
    if (!drive.authenticated) {
      focusSection = "setup"
      fileIndex = 0
      return
    }
    if (root.fileResults.length === 0) {
      focusSection = "header"
      fileIndex = 0
      return
    }
    if (focusSection !== "files" && focusSection !== "header") focusSection = "files"
    if (fileIndex >= root.fileResults.length) fileIndex = Math.max(0, root.fileResults.length - 1)
    if (fileIndex < 0) fileIndex = 0
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return
    if (focusSection === "header") {
      if (dy > 0 && root.fileResults.length > 0) {
        focusSection = "files"
        fileIndex = 0
        scrollCursorIntoView()
      }
      return
    }
    if (focusSection === "files") {
      if (dy < 0 && fileIndex === 0) {
        setHeaderCursor()
        return
      }
      fileIndex = Math.max(0, Math.min(root.fileResults.length - 1, fileIndex + dy))
      scrollCursorIntoView()
    }
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
    if (panelFlick) panelFlick.contentY = 0
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "setup") drive.setup()
    else if (focusSection === "header") toggleMount()
    else if (focusSection === "files") drive.openFile(selectedFile())
  }

  function selectedFile() {
    if (root.fileResults.length === 0) return null
    return root.fileResults[Math.max(0, Math.min(fileIndex, root.fileResults.length - 1))]
  }

  function setFileCursor(index) {
    cursorActive = true
    focusSection = "files"
    fileIndex = index
    scrollCursorIntoView()
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin)
        panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (focusSection === "files" && fileColumn && fileIndex >= 0 && fileIndex < fileColumn.children.length)
      scrollItemIntoView(fileColumn.children[fileIndex])
  }

  onFileIndexChanged: scrollCursorIntoView()

  Service {
    id: drive
    settings: root.settings
  }

  Connections {
    target: drive
    function onAuthenticatedChanged() { root.ensureCursor() }
    function onFilesChanged() { root.ensureCursor() }
    function onSearchResultsChanged() { root.ensureCursor() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") drive.refresh()
        else if (t === "l" || t === "L") drive.setup()
        else if (t === "p" || t === "P") root.toggleMount()
        else if (t === "o" || t === "O") drive.openDrive()
        else if (t === "/") root.focusFileSearch()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            visible: drive.authenticated
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.setHeaderCursor() }

            PanelHero {
              id: hero
              width: parent.width
              title: "Google Drive"
              meta: drive.active ? root.heroPhraseText : "Drive is unmounted"
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: drive.active ? 1.0 : 0.5
              iconComponent: Component {
                GoogleDriveIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                }
              }
              trailingControl: Component {
                ToggleSwitch {
                  id: mountSwitch
                  visible: drive.installed && drive.authenticated
                  checked: drive.active
                  busy: drive.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: root.toggleMount()

                  PanelToolTip {
                    visible: mountSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            visible: drive.actionStatus !== "" || drive.lastError !== "" || drive.warning !== ""
            width: parent.width
            text: drive.actionStatus !== "" ? drive.actionStatus
              : (drive.lastError !== "" ? drive.lastError : drive.warning)
            color: drive.lastError !== "" && drive.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          SetupButton {
            visible: !drive.authenticated
            width: parent.width
          }

          Column {
            visible: drive.authenticated
            width: parent.width
            spacing: Style.spacing.labelGap

            InfoPair {
              label: "Stored"
              value: Model.usageText(drive.usedBytes, drive.quotaBytes, drive.quotaKnown)
            }
            InfoPair {
              label: "Location"
              value: root.displayMountPath
            }
            InfoPair {
              label: "Remote"
              value: drive.remoteName + ":"
            }
          }

          PanelSeparator {
            visible: drive.authenticated
            foreground: root.foreground
          }

          RowLayout {
            visible: drive.authenticated
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: searchField
              Layout.fillWidth: true
              enabled: drive.active
              foreground: root.foreground
              font.family: root.fontFamily
              placeholderText: drive.active ? "Search all files…" : "Mount Drive to search"
              onTextChanged: {
                root.fileQuery = text
                root.fileIndex = 0
                if (text.trim().length >= 2) searchDebounce.restart()
                else {
                  searchDebounce.stop()
                  drive.clearSearch()
                }
              }
              onAccepted: {
                searchDebounce.stop()
                drive.search(text)
              }
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  if (text !== "") root.clearFileSearch()
                  else keyCatcher.forceActiveFocus()
                  event.accepted = true
                } else if (event.key === Qt.Key_Down && root.fileResults.length > 0) {
                  root.cursorActive = true
                  root.focusSection = "files"
                  root.fileIndex = 0
                  keyCatcher.forceActiveFocus()
                  root.scrollCursorIntoView()
                  event.accepted = true
                }
              }
            }

            PanelActionButton {
              visible: searchField.text !== ""
              iconText: "󰅖"
              tooltipText: "Clear search"
              foreground: root.foreground
              fontFamily: root.fontFamily
              Layout.alignment: Qt.AlignVCenter
              onClicked: root.clearFileSearch()
            }
          }

          Column {
            visible: drive.authenticated
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: root.searchMode ? "SEARCH RESULTS" : "RECENT FILES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: root.searchMode && drive.searching
              width: parent.width
              text: "Searching Google Drive…"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              visible: !drive.active || (!drive.searching && root.fileResults.length === 0)
              width: parent.width
              text: !drive.active
                ? "Mount Google Drive to browse files."
                : (root.searchMode
                  ? (drive.searchError !== "" ? drive.searchError : "No files match “" + root.fileQuery.trim() + "”.")
                  : "No recent files found in the mounted folders.")
              color: drive.searchError !== "" ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            Text {
              visible: root.searchMode && drive.searchTruncated
              width: parent.width
              text: "Showing the first 50 matches. Refine your search for more specific results."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            Column {
              id: fileColumn
              visible: drive.active && root.fileResults.length > 0
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.fileResults
                FileRow {
                  required property var modelData
                  required property int index
                  width: fileColumn.width
                  file: modelData
                  rowIndex: index
                }
              }
            }
          }
        }
      }
    }
  }

  Timer {
    id: searchDebounce
    interval: 350
    repeat: false
    onTriggered: drive.search(root.fileQuery)
  }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && drive.authenticated && drive.active
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero
      property: "metaOpacity"
      to: 0.0
      duration: 180
      easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }
    PropertyAnimation {
      target: hero
      property: "metaOpacity"
      to: 1.0
      duration: 260
      easing.type: Easing.InQuad
    }
  }

  component SetupButton: CursorSurface {
    id: setupButton

    hasCursor: root.cursorActive && root.focusSection === "setup"
    foreground: root.foreground
    implicitHeight: setupRow.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: drive.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
      enabled: !drive.busy
      onEntered: {
        root.cursorActive = true
        root.focusSection = "setup"
      }
      onClicked: drive.setup()
    }

    RowLayout {
      id: setupRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Item {
        Layout.preferredWidth: Style.space(24)
        Layout.preferredHeight: Style.space(24)
        Layout.alignment: Qt.AlignVCenter

        GoogleDriveIcon {
          anchors.centerIn: parent
          iconSize: Style.space(20)
          color: root.foreground
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: drive.installed
            ? "Configure the " + drive.remoteName + ": remote"
            : "rclone is required"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: drive.installed
            ? "Run rclone config, then refresh this panel"
            : "Install rclone and FUSE before using this plugin"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: "󰏌"
        tooltipText: "Open prerequisite instructions"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: !drive.busy
        Layout.alignment: Qt.AlignVCenter
        onClicked: drive.setup()
      }
    }
  }

  component FileRow: CursorSurface {
    id: fileRow
    property var file: null
    property int rowIndex: 0
    readonly property string fileName: file ? String(file.name || "Untitled") : "Untitled"

    hasCursor: root.cursorActive && root.focusSection === "files" && root.fileIndex === rowIndex
    foreground: root.foreground
    implicitHeight: fileContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setFileCursor(fileRow.rowIndex)
      onClicked: drive.openFile(fileRow.file)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: Model.fileGlyph(fileRow.fileName)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        Layout.preferredWidth: Style.space(22)
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: fileContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: fileRow.fileName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: Model.fileMeta(fileRow.file)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item {
      width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2)
      height: 1
    }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }
}
