import QtQuick
import Quickshell
import Quickshell.Io
import "TimerModel.js" as TimerModel

Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || ""
  property bool soundEnabled: true

  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME")
    || ((Quickshell.env("HOME") || "") + "/.local/state")
  readonly property string stateDir: stateHome + "/omarchy"
  readonly property string statePath: stateDir + "/tomatask.json"
  readonly property string notificationExecutable: omarchyPath !== ""
    ? omarchyPath + "/bin/omarchy-notification-send"
    : "omarchy-notification-send"

  property var config: TimerModel.normalizeConfig({})
  property var timerState: TimerModel.stoppedState(config, Date.now())
  property var tasks: []
  property string activeTaskId: ""

  property double nowMs: Date.now()
  property double lastTickMs: 0
  property bool initialized: false
  property bool configReady: false
  property bool stateFileLoaded: false
  property bool stateDirReady: false
  property bool savePending: false
  property string loadedStateText: ""

  readonly property string status: timerState.status
  readonly property string phase: timerState.phase
  readonly property string phaseLabel: TimerModel.phaseLabel(phase)
  readonly property int remainingSeconds: TimerModel.remainingSeconds(timerState, nowMs)
  readonly property string remainingText: TimerModel.formatRemaining(remainingSeconds)
  readonly property real progress: TimerModel.elapsedProgress(timerState, nowMs)
  readonly property bool stopped: status === TimerModel.StatusStopped
  readonly property bool running: status === TimerModel.StatusRunning
  readonly property bool paused: status === TimerModel.StatusPaused
  readonly property string activeTaskName: taskNameFor(activeTaskId)

  function finiteNumber(value, fallback) {
    var n = Number(value)
    return isFinite(n) ? n : fallback
  }

  function makeTask(name) {
    var cleaned = String(name || "").trim()
    if (cleaned === "") return null
    return {
      id: "task-" + Date.now() + "-" + Math.floor(Math.random() * 1000000),
      name: cleaned,
      sessions: 0,
      totalFocusSeconds: 0,
      updatedAtMs: Date.now()
    }
  }

  function cloneTasks(list) {
    var out = []
    var input = Array.isArray(list) ? list : []
    for (var i = 0; i < input.length; i++) {
      var task = input[i] || {}
      var name = String(task.name || "").trim()
      var id = String(task.id || "")
      if (id === "" || name === "") continue
      out.push({
        id: id,
        name: name,
        sessions: Math.max(0, Math.round(finiteNumber(task.sessions, 0))),
        totalFocusSeconds: Math.max(0, Math.round(finiteNumber(task.totalFocusSeconds, 0))),
        updatedAtMs: Math.max(0, Math.round(finiteNumber(task.updatedAtMs, Date.now())))
      })
    }
    return out
  }

  function ensureTaskSelection() {
    if (!Array.isArray(tasks) || tasks.length === 0) {
      tasks = [makeTask("Inbox")]
    }
    var exists = false
    for (var i = 0; i < tasks.length; i++) {
      if (tasks[i].id === activeTaskId) {
        exists = true
        break
      }
    }
    if (!exists) activeTaskId = tasks[0].id
  }

  function taskNameFor(taskId) {
    var id = String(taskId || "")
    for (var i = 0; i < tasks.length; i++) {
      if (tasks[i].id === id) return tasks[i].name
    }
    return "No task"
  }

  function configure(settings) {
    var next = TimerModel.normalizeConfig(settings || {})
    var sound = !!((settings || {}).sound)
    soundEnabled = sound
    if (JSON.stringify(next) !== JSON.stringify(config)) {
      config = next
      if (initialized && stopped) {
        timerState = TimerModel.stoppedState(config, Date.now())
        scheduleSave()
      }
    }
    configReady = true
    initializeIfReady()
  }

  function initializeIfReady() {
    if (initialized || !configReady || !stateFileLoaded) return

    var restored = null
    if (String(loadedStateText || "").trim() !== "") {
      try {
        restored = JSON.parse(loadedStateText)
      } catch (error) {
        console.warn("Tomatask: ignoring invalid persisted state", error)
      }
    }

    tasks = cloneTasks(restored ? restored.tasks : [])
    activeTaskId = String(restored && restored.activeTaskId ? restored.activeTaskId : "")
    ensureTaskSelection()

    var recovered = TimerModel.recoverInterrupted(restored ? restored.timerState : null, config, Date.now())
    timerState = recovered.state

    if (timerState.phase === TimerModel.PhaseWork && timerState.taskId === "") {
      timerState.taskId = activeTaskId
    }

    initialized = true
    lastTickMs = Date.now()
    nowMs = Date.now()

    if (recovered.notifyPhase !== "") notifyPhaseStarted(recovered.notifyPhase)
    scheduleSave()
  }

  function setState(next, persist) {
    timerState = next
    nowMs = Date.now()
    if (persist) scheduleSave()
  }

  function startOrStop() {
    if (!initialized) return
    var now = Date.now()
    ensureTaskSelection()
    if (stopped) {
      setState(TimerModel.startNewCycle(config, now, activeTaskId), true)
    } else {
      setState(TimerModel.stoppedState(config, now), true)
    }
    lastTickMs = now
  }

  function togglePause() {
    if (!initialized || stopped) return
    var now = Date.now()
    if (running) setState(TimerModel.pause(timerState, now), true)
    else setState(TimerModel.resume(timerState, now), true)
    lastTickMs = now
  }

  function resetPhase() {
    if (!initialized || stopped) return
    var now = Date.now()
    var next = TimerModel.cloneState(timerState)
    next.phaseDurationSec = TimerModel.durationSeconds(next.phase, config)
    next.remainingSec = next.phaseDurationSec
    if (next.status === TimerModel.StatusRunning) {
      next.startedAtMs = now
      next.deadlineMs = now + next.phaseDurationSec * 1000
    }
    next.updatedAtMs = now
    setState(next, true)
  }

  function skipPhase() {
    if (!initialized || stopped) return
    var now = Date.now()
    setState(TimerModel.advance(timerState, config, now, activeTaskId), true)
    notifyPhaseStarted(timerState.phase)
    lastTickMs = now
  }

  function tick() {
    if (!initialized) return

    var now = Date.now()
    nowMs = now

    if (!running) {
      lastTickMs = now
      return
    }

    if (lastTickMs > 0 && now - lastTickMs > 5000) {
      var recovered = TimerModel.recoverInterrupted(timerState, config, now)
      timerState = recovered.state
      if (recovered.notifyPhase !== "") notifyPhaseStarted(recovered.notifyPhase)
      lastTickMs = now
      scheduleSave()
      return
    }

    if (now >= Number(timerState.deadlineMs || 0)) {
      var old = timerState
      if (old.phase === TimerModel.PhaseWork) {
        recordCompletedWork(old.taskId, old.phaseDurationSec)
      }
      var next = TimerModel.advance(old, config, now, activeTaskId)
      setState(next, true)
      notifyPhaseStarted(next.phase)
    }

    lastTickMs = now
  }

  function notifyPhaseStarted(phaseName) {
    var title = TimerModel.phaseLabel(phaseName) + " started"
    var minutes = Math.round(TimerModel.durationSeconds(phaseName, config) / 60)
    var body = phaseName === TimerModel.PhaseWork
      ? "Focus on " + activeTaskName + " for " + minutes + " minutes."
      : "Take a " + minutes + " minute break."

    Quickshell.execDetached([
      notificationExecutable,
      "--app-name", "tomatask",
      "-g", "󱎫",
      "-u", "normal",
      title,
      body
    ])

    if (!soundEnabled) return
    if (phaseName === TimerModel.PhaseWork) {
      Quickshell.execDetached(["/usr/bin/pw-play", "/usr/share/sounds/freedesktop/stereo/complete.oga"])
    } else {
      Quickshell.execDetached(["/usr/bin/pw-play", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"])
    }
  }

  function recordCompletedWork(taskId, durationSec) {
    var id = String(taskId || "")
    if (id === "") return

    var next = cloneTasks(tasks)
    for (var i = 0; i < next.length; i++) {
      if (next[i].id !== id) continue
      next[i].sessions += 1
      next[i].totalFocusSeconds += Math.max(0, Math.round(finiteNumber(durationSec, 0)))
      next[i].updatedAtMs = Date.now()
      tasks = next
      scheduleSave()
      return
    }
  }

  function addTask(name) {
    var task = makeTask(name)
    if (!task) return false

    var next = cloneTasks(tasks)
    for (var i = 0; i < next.length; i++) {
      if (next[i].name.toLowerCase() === task.name.toLowerCase()) {
        activeTaskId = next[i].id
        scheduleSave()
        return true
      }
    }

    next.push(task)
    tasks = next
    activeTaskId = task.id
    if (stopped) {
      timerState = TimerModel.stoppedState(config, Date.now())
    }
    scheduleSave()
    return true
  }

  function selectTask(taskId) {
    var id = String(taskId || "")
    for (var i = 0; i < tasks.length; i++) {
      if (tasks[i].id !== id) continue
      activeTaskId = id
      if (stopped) timerState = TimerModel.stoppedState(config, Date.now())
      scheduleSave()
      return true
    }
    return false
  }

  function removeTask(taskId) {
    var id = String(taskId || "")
    if (tasks.length <= 1) return false

    var next = []
    var removed = false
    for (var i = 0; i < tasks.length; i++) {
      var task = tasks[i]
      if (task.id === id) {
        removed = true
        continue
      }
      next.push(task)
    }

    if (!removed || next.length === 0) return false

    tasks = next
    if (activeTaskId === id) activeTaskId = tasks[0].id
    if (timerState.taskId === id && stopped) {
      timerState = TimerModel.stoppedState(config, Date.now())
    }
    scheduleSave()
    return true
  }

  function serializableState() {
    return {
      version: 1,
      timerState: TimerModel.serializableState(timerState, Date.now()),
      tasks: cloneTasks(tasks),
      activeTaskId: activeTaskId
    }
  }

  function scheduleSave() {
    if (!initialized) return
    savePending = true
    saveTimer.restart()
  }

  function flushState() {
    if (!savePending || !stateDirReady) return
    savePending = false
    stateFile.setText(JSON.stringify(serializableState(), null, 2) + "\n")
  }

  Component.onCompleted: stateDirProcess.running = true

  Timer {
    interval: 250
    repeat: true
    running: root.initialized
    onTriggered: root.tick()
  }

  Timer {
    id: saveTimer
    interval: 120
    repeat: false
    onTriggered: root.flushState()
  }

  Process {
    id: stateDirProcess
    command: ["mkdir", "-p", root.stateDir]
    onExited: function(exitCode) {
      root.stateDirReady = exitCode === 0
      if (!root.stateDirReady) {
        console.warn("Tomatask: could not create state dir")
        return
      }
      root.flushState()
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false

    onLoaded: {
      root.loadedStateText = text()
      root.stateFileLoaded = true
      root.initializeIfReady()
    }

    onLoadFailed: {
      root.loadedStateText = ""
      root.stateFileLoaded = true
      root.initializeIfReady()
    }
  }
}
