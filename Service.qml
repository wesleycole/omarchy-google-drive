import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property bool installed: false
  property bool running: false
  property bool authenticated: false

  // React immediately to a mount toggle while rclone and FUSE catch up.
  property int _desired: -1
  readonly property bool active: _desired === -1 ? running : (_desired === 1)
  property bool refreshing: false
  property string statusText: "Checking…"
  property string accountPath: ""
  property double usedBytes: 0
  property double quotaBytes: 0
  property double usagePercent: 0
  property bool quotaKnown: false
  property var files: []
  property string searchQuery: ""
  property var searchResults: []
  property bool searching: false
  property bool searchTruncated: false
  property string searchError: ""
  property string warning: ""
  property string actionStatus: ""
  property string lastError: ""

  property bool _autoMountAttempted: false
  property bool _pausedByUser: false
  property string _statusOutput: ""
  property string _statusError: ""
  property string _controlOutput: ""
  property string _controlError: ""
  property string _searchOutput: ""
  property string _searchErrorOutput: ""
  property string _searchProcessQuery: ""
  property string _queuedSearchQuery: ""

  readonly property string homePath: Quickshell.env("HOME") || ""
  readonly property string remoteName: String(setting("remoteName", "gdrive")).trim()
  readonly property string mountPath: expandHome(String(setting("mountPath", "~/Google Drive")))
  readonly property var autoMountSetting: setting("autoMount", true)
  readonly property bool autoMountEnabled: autoMountSetting === true
    || ["true", "on", "1", "yes"].indexOf(String(autoMountSetting).toLowerCase()) !== -1
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 60, 15, 3600)
  readonly property bool busy: statusProcess.running || controlProcess.running
  readonly property string setupUrl: "https://github.com/wesleycole/omarchy-google-drive#prerequisites"
  readonly property string helperPath: {
    var value = String(Qt.resolvedUrl("gdrive.py"))
    if (value.indexOf("file://") === 0) value = value.substring(7)
    return decodeURIComponent(value)
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function expandHome(path) {
    var value = String(path || "")
    if (value === "~") return homePath
    if (value.indexOf("~/") === 0) return homePath + value.substring(1)
    return value
  }

  function refresh() {
    if (statusProcess.running || helperPath === "") return
    _statusOutput = ""
    _statusError = ""
    refreshing = true
    statusProcess.command = [
      "python3", helperPath, "status",
      "--remote", remoteName,
      "--mount", mountPath,
      "--limit", "25"
    ]
    statusProcess.running = true
    statusWatchdog.restart()
  }

  function clearSearch() {
    searchQuery = ""
    searchResults = []
    searchError = ""
    searchTruncated = false
    _queuedSearchQuery = ""
  }

  function search(query) {
    var value = String(query || "").trim()
    searchQuery = value
    if (value.length < 2) {
      searchResults = []
      searchError = ""
      searchTruncated = false
      _queuedSearchQuery = ""
      return
    }
    if (searchProcess.running) {
      _queuedSearchQuery = value
      return
    }
    startSearch(value)
  }

  function startSearch(query) {
    if (!active || helperPath === "") {
      searchError = "Mount Google Drive before searching"
      return
    }
    _searchProcessQuery = query
    _queuedSearchQuery = ""
    _searchOutput = ""
    _searchErrorOutput = ""
    searchResults = []
    searchError = ""
    searchTruncated = false
    searching = true
    searchProcess.command = [
      "python3", helperPath, "search",
      "--mount", mountPath,
      "--query", query,
      "--limit", "50"
    ]
    searchProcess.running = true
    searchWatchdog.restart()
  }

  function applySearch(raw) {
    if (_searchProcessQuery !== searchQuery) return
    var parsed = Model.parseSearch(raw)
    if (!parsed.ok) {
      searchError = parsed.lastError || "Google Drive search failed"
      searchResults = []
      return
    }
    searchResults = parsed.files || []
    searchTruncated = parsed.truncated === true
    searchError = ""
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      lastError = parsed.lastError || "Failed to read Google Drive status"
      return
    }

    installed = parsed.installed === true
    running = parsed.running === true
    authenticated = parsed.authenticated === true
    if (_desired !== -1 && running === (_desired === 1)) _desired = -1
    statusText = String(parsed.statusText || (installed ? "Unavailable" : "Not installed"))
    accountPath = String(parsed.accountPath || mountPath)
    usedBytes = Number(parsed.usedBytes || 0)
    quotaBytes = Number(parsed.quotaBytes || 0)
    usagePercent = Number(parsed.usagePercent || 0)
    quotaKnown = parsed.quotaKnown === true
    files = parsed.files || []
    warning = String(parsed.warning || "")
    lastError = String(parsed.lastError || "")

    if (running) _autoMountAttempted = true
    if (authenticated) setupPoll.stop()
    if (autoMountEnabled && authenticated && !running && !_autoMountAttempted && !_pausedByUser) {
      _autoMountAttempted = true
      Qt.callLater(function() { root.mountDrive() })
    }
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 160 ? value.substring(0, 157) + "…" : value
  }

  function setup() {
    actionStatus = "Opening rclone prerequisites…"
    actionStatusTimer.restart()
    setupPoll.ticks = 0
    setupPoll.restart()
    Quickshell.execDetached(["omarchy-launch-browser", setupUrl])
  }

  function mountDrive() {
    if (!installed || !authenticated || controlProcess.running) return
    _pausedByUser = false
    runControl([
      "python3", helperPath, "mount",
      "--remote", remoteName,
      "--mount", mountPath
    ], 1)
  }

  function unmountDrive() {
    if (!installed || controlProcess.running) return
    _pausedByUser = true
    runControl([
      "python3", helperPath, "unmount",
      "--mount", mountPath
    ], 0)
  }

  function toggleRunning() {
    if (active) unmountDrive()
    else mountDrive()
  }

  function runControl(command, desired) {
    _desired = desired
    _controlOutput = ""
    _controlError = ""
    controlProcess.command = command
    controlProcess.running = true
    controlWatchdog.restart()
  }

  function openDrive() {
    if (active && accountPath !== "")
      Quickshell.execDetached(["uwsm-app", "--", "nautilus", fileUri(accountPath)])
    else
      Quickshell.execDetached(["omarchy-launch-browser", "https://drive.google.com/drive/my-drive"])
  }

  function openFile(file) {
    if (!active || !file || !file.path) return
    Quickshell.execDetached(["uwsm-app", "--", "nautilus", "--select", fileUri(String(file.path))])
  }

  function fileUri(path) {
    var parts = String(path || "").split("/")
    for (var i = 0; i < parts.length; i++) parts[i] = encodeURIComponent(parts[i])
    return "file://" + parts.join("/")
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: setupPoll
    property int ticks: 0
    interval: 3000
    repeat: true
    running: false
    onTriggered: {
      ticks += 1
      root.refresh()
      if (root.authenticated || ticks >= 100) stop()
    }
  }

  Timer {
    id: delayedRefresh
    interval: 800
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: settleTimer
    property int ticks: 0
    interval: 1500
    repeat: true
    running: false
    onTriggered: {
      ticks += 1
      root.refresh()
      if (ticks >= 5) {
        ticks = 0
        stop()
        root._desired = -1
      }
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 2600
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    id: statusWatchdog
    interval: 22000
    repeat: false
    onTriggered: {
      if (!statusProcess.running) return
      statusProcess.running = false
      root.refreshing = false
      root.lastError = "Google Drive status check timed out"
    }
  }

  Timer {
    id: searchWatchdog
    interval: 18000
    repeat: false
    onTriggered: {
      if (!searchProcess.running) return
      searchProcess.running = false
      root.searching = false
      root.searchError = "Google Drive search timed out"
    }
  }

  Timer {
    id: controlWatchdog
    interval: 40000
    repeat: false
    onTriggered: {
      if (!controlProcess.running) return
      controlProcess.running = false
      root._desired = -1
      root.lastError = "Google Drive mount command timed out"
      root.actionStatus = root.lastError
      actionStatusTimer.restart()
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: statusStdout
      waitForEnd: true
      onStreamFinished: root._statusOutput = text
    }
    stderr: StdioCollector {
      id: statusStderr
      waitForEnd: true
      onStreamFinished: root._statusError = text
    }
    onExited: function(exitCode) {
      statusWatchdog.stop()
      root.refreshing = false
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0) root.applyStatus(stdout)
      else root.lastError = root.elideStatus(stderr || stdout || "Could not read Google Drive status")
    }
  }

  Process {
    id: searchProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: searchStdout
      waitForEnd: true
      onStreamFinished: root._searchOutput = text
    }
    stderr: StdioCollector {
      id: searchStderr
      waitForEnd: true
      onStreamFinished: root._searchErrorOutput = text
    }
    onExited: function(exitCode) {
      searchWatchdog.stop()
      root.searching = false
      var stdout = String(searchStdout.text || root._searchOutput || "")
      var stderr = String(searchStderr.text || root._searchErrorOutput || "")
      if (root._searchProcessQuery === root.searchQuery) {
        if (exitCode === 0) root.applySearch(stdout)
        else root.searchError = root.elideStatus(stderr || stdout || "Google Drive search failed")
      }
      var queued = root._queuedSearchQuery
      root._queuedSearchQuery = ""
      if (queued.length >= 2 && queued !== root._searchProcessQuery && queued === root.searchQuery)
        Qt.callLater(function() { root.startSearch(queued) })
    }
  }

  Process {
    id: controlProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: controlStdout
      waitForEnd: true
      onStreamFinished: root._controlOutput = text
    }
    stderr: StdioCollector {
      id: controlStderr
      waitForEnd: true
      onStreamFinished: root._controlError = text
    }
    onExited: function(exitCode) {
      controlWatchdog.stop()
      var stdout = String(controlStdout.text || root._controlOutput || "")
      var stderr = String(controlStderr.text || root._controlError || "")
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = root.elideStatus(stderr || stdout || "Google Drive command failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      settleTimer.ticks = 0
      settleTimer.restart()
      delayedRefresh.restart()
    }
  }
}
