import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  readonly property string binaryPath: Quickshell.env("HOME") + "/.local/bin/omarchy-sesh"
  readonly property string binarySourcePath: Qt.resolvedUrl("bin/omarchy-sesh").toString().replace(/^file:\/\//, "")
  readonly property string installPath: Qt.resolvedUrl("install.sh").toString().replace(/^file:\/\//, "")
  readonly property string manifestPath: Qt.resolvedUrl("manifest.json").toString().replace(/^file:\/\//, "")
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
  readonly property string unitDir: configHome + "/systemd/user"
  readonly property string installMarker: stateHome + "/omarchy/sesh-installed"

  property bool installed: false
  property string mode: "manual"
  property string sessionName: ""
  property bool modeKnown: false
  property bool busy: checkProcess.running || installProcess.running || modeProcess.running || actionProcess.running || listProcess.running || deleteProcess.running
  property string status: ""
  property string error: ""
  property var sessions: []
  property bool sessionsLoading: false
  property string pendingAction: ""
  property string listResultStatus: ""
  property bool startEnabledMode: false
  property bool installAfterCheck: false
  property bool preserveStatus: false

  Component.onCompleted: ensureInstalled(false)

  function ensureInstalled(installIfMissing) {
    if (installIfMissing === undefined) installIfMissing = true
    installAfterCheck = installAfterCheck || installIfMissing
    if (checkProcess.running) return
    checkProcess.command = [
      "bash", "-c",
      "version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[\"version\"])' \"$3\") && [[ $(cat \"$1\" 2>/dev/null) == \"$version\" ]] && cmp -s \"$5\" \"$2\" && [[ -x \"$2\" && -f \"$4/omarchy-sesh.service\" && -f \"$4/omarchy-sesh-autosave.service\" ]] && systemctl --user is-enabled omarchy-sesh.service >/dev/null && \"$2\" mode >/dev/null",
      "_", installMarker, binaryPath, manifestPath, unitDir, binarySourcePath
    ]
    checkProcess.running = true
  }

  function install() {
    if (installProcess.running) return
    status = "Installing session manager..."
    error = ""
    installProcess.command = ["bash", installPath]
    installProcess.running = true
  }

  function refresh(keepStatus) {
    if (!installed) return
    if (keepStatus === true) preserveStatus = true
    if (modeProcess.running) return
    if (keepStatus !== true) preserveStatus = false
    modeProcess.command = [binaryPath, "mode", "--json"]
    modeProcess.running = true
  }

  function activate() {
    return runMode("active")
  }

  function saveManual() {
    if (!installed || busy) return false
    pendingAction = "save"
    return runMode("manual")
  }

  function restore() {
    return runAction("restore")
  }

  // `resultStatus`, when given, survives the reload so a completed action
  // (for example a delete) keeps reporting its own outcome.
  function listSessions(resultStatus) {
    if (!installed || listProcess.running || actionProcess.running) return false
    sessions = []
    sessionsLoading = true
    listResultStatus = resultStatus === undefined ? "" : resultStatus
    status = listResultStatus !== "" ? listResultStatus : "Loading saved sessions..."
    error = ""
    listProcess.command = [binaryPath, "list", "--json"]
    listProcess.running = true
    return true
  }

  function restoreNamed(name) {
    return runAction("restore", name)
  }

  function deleteSession(name) {
    if (!installed || busy) return false
    status = "Deleting session..."
    error = ""
    deleteProcess.command = [binaryPath, "delete", "--name", name]
    deleteProcess.running = true
    return true
  }

  function runMode(nextMode) {
    if (!installed || busy) return false
    status = nextMode === "active" ? "Enabling autosave..." : "Saving session..."
    error = ""
    modeProcess.command = [binaryPath, "mode", nextMode, "--json"]
    modeProcess.running = true
    return true
  }

  function runAction(action, name) {
    if (!installed || busy) return false
    status = action === "restore" ? "Restoring session..." : "Saving session..."
    error = ""
    actionProcess.command = action === "restore"
      ? (name === undefined
          ? [binaryPath, "restore", "--timeout", "10"]
          : [binaryPath, "restore", "--name", name, "--timeout", "10"])
      : [binaryPath, "save", "--label", "manual"]
    actionProcess.running = true
    return true
  }

  Process {
    id: checkProcess
    command: []
    onExited: function(exitCode) {
      var shouldInstall = root.installAfterCheck
      root.installAfterCheck = false
      root.installed = exitCode === 0
      if (root.installed) root.refresh()
      else if (shouldInstall) root.install()
    }
  }

  Process {
    id: installProcess
    command: []
    stderr: StdioCollector { id: installError; waitForEnd: true }
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      root.status = exitCode === 0 ? "Session manager installed" : ""
      root.error = exitCode === 0 ? "" : (installError.text.trim() || "Installation failed")
      if (root.installed) {
        root.startEnabledMode = true
        root.refresh()
      }
    }
  }

  Process {
    id: modeProcess
    command: []
    stdout: StdioCollector { id: modeOutput; waitForEnd: true }
    stderr: StdioCollector { id: modeError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.modeKnown = false
        if (root.preserveStatus) {
          root.preserveStatus = false
          return
        }
        root.preserveStatus = false
        root.status = ""
        root.error = modeError.text.trim() || "Could not change autosave mode"
        root.pendingAction = ""
        return
      }
      var value = ""
      var name = ""
      try {
        var parsed = JSON.parse(modeOutput.text.trim())
        value = parsed.mode
        name = typeof parsed.name === "string" ? parsed.name : ""
      } catch (parseError) {
        value = ""
      }
      if (value !== "active" && value !== "manual") {
        root.modeKnown = false
        root.preserveStatus = false
        root.status = ""
        root.error = "Unexpected autosave mode response"
        root.pendingAction = ""
        return
      }
      root.mode = value
      root.sessionName = name
      root.modeKnown = true
      if (root.startEnabledMode) {
        root.startEnabledMode = false
        if (value === "active") {
          Qt.callLater(function() { root.runMode("active") })
          return
        }
      }
      if (root.pendingAction === "save") {
        root.pendingAction = ""
        Qt.callLater(function() { root.runAction("save") })
      } else if (!root.preserveStatus) {
        root.status = value === "active" ? "Autosave active" : "Manual mode"
      }
      root.preserveStatus = false
    }
  }

  Process {
    id: listProcess
    command: []
    stdout: StdioCollector { id: listOutput; waitForEnd: true }
    stderr: StdioCollector { id: listError; waitForEnd: true }
    onExited: function(exitCode) {
      root.sessionsLoading = false
      if (exitCode !== 0) {
        root.status = ""
        root.error = listError.text.trim() || "Could not load saved sessions"
        return
      }
      try {
        var sessions = JSON.parse(listOutput.text)
        if (!Array.isArray(sessions)) throw new Error("not an array")
        root.sessions = sessions
        root.status = root.listResultStatus !== ""
          ? root.listResultStatus
          : (sessions.length ? "Choose a saved session" : "No named sessions saved")
      } catch (error) {
        root.sessions = []
        root.status = ""
        root.error = "Could not read saved sessions"
      }
      root.listResultStatus = ""
    }
  }

  Process {
    id: deleteProcess
    command: []
    stdout: StdioCollector { id: deleteOutput; waitForEnd: true }
    stderr: StdioCollector { id: deleteError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.error = ""
        root.listSessions(deleteOutput.text.trim() || "Session deleted")
      } else {
        root.status = ""
        root.error = deleteError.text.trim() || deleteOutput.text.trim() || "Could not delete session"
      }
    }
  }

  Process {
    id: actionProcess
    command: []
    stdout: StdioCollector { id: actionOutput; waitForEnd: true }
    stderr: StdioCollector { id: actionError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.status = actionOutput.text.trim() || "Session action completed"
        root.error = ""
      } else {
        var message = actionError.text.trim() || actionOutput.text.trim() || "Session action failed"
        if (message.startsWith("restore incomplete:")) {
          root.status = message
          root.error = ""
        } else {
          root.status = ""
          root.error = message
        }
      }
      root.refresh(true)
    }
  }
}
