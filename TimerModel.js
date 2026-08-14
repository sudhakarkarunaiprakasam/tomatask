// Timer state helpers shared by QML and tests.

var StateVersion = 1
var StatusStopped = "stopped"
var StatusRunning = "running"
var StatusPaused = "paused"

var PhaseWork = "work"
var PhaseShortBreak = "shortBreak"
var PhaseLongBreak = "longBreak"

function finiteNumber(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : fallback
}

function boundedInteger(value, fallback, min, max) {
  var n = Math.round(finiteNumber(value, fallback))
  return Math.max(min, Math.min(max, n))
}

function normalizeConfig(settings) {
  var raw = settings || {}
  return {
    workMinutes: boundedInteger(raw.workMinutes, 25, 1, 120),
    shortBreakMinutes: boundedInteger(raw.shortBreakMinutes, 5, 1, 60),
    longBreakMinutes: boundedInteger(raw.longBreakMinutes, 15, 1, 120),
    workPhasesPerLongBreak: boundedInteger(raw.workPhasesPerLongBreak, 4, 1, 12)
  }
}

function isStatus(value) {
  return value === StatusStopped || value === StatusRunning || value === StatusPaused
}

function isPhase(value) {
  return value === PhaseWork || value === PhaseShortBreak || value === PhaseLongBreak
}

function phaseLabel(phase) {
  if (phase === PhaseShortBreak) return "Short break"
  if (phase === PhaseLongBreak) return "Long break"
  return "Work"
}

function durationSeconds(phase, config) {
  var c = normalizeConfig(config)
  if (phase === PhaseShortBreak) return c.shortBreakMinutes * 60
  if (phase === PhaseLongBreak) return c.longBreakMinutes * 60
  return c.workMinutes * 60
}

function stoppedState(config, nowMs) {
  var now = finiteNumber(nowMs, 0)
  var duration = durationSeconds(PhaseWork, config)
  return {
    version: StateVersion,
    status: StatusStopped,
    phase: PhaseWork,
    completedWorkPhases: 0,
    phaseDurationSec: duration,
    remainingSec: duration,
    startedAtMs: 0,
    deadlineMs: 0,
    updatedAtMs: now,
    taskId: ""
  }
}

function runningPhase(phase, completedWorkPhases, durationSec, nowMs, taskId) {
  var now = finiteNumber(nowMs, 0)
  var duration = Math.max(1, finiteNumber(durationSec, 1))
  return {
    version: StateVersion,
    status: StatusRunning,
    phase: isPhase(phase) ? phase : PhaseWork,
    completedWorkPhases: Math.max(0, Math.round(finiteNumber(completedWorkPhases, 0))),
    phaseDurationSec: duration,
    remainingSec: duration,
    startedAtMs: now,
    deadlineMs: now + duration * 1000,
    updatedAtMs: now,
    taskId: String(taskId || "")
  }
}

function startNewCycle(config, nowMs, taskId) {
  return runningPhase(PhaseWork, 0, durationSeconds(PhaseWork, config), nowMs, taskId)
}

function remainingMilliseconds(state, nowMs) {
  if (!state) return 0
  if (state.status === StatusRunning) {
    return Math.max(0, finiteNumber(state.deadlineMs, 0) - finiteNumber(nowMs, 0))
  }
  return Math.max(0, finiteNumber(state.remainingSec, 0) * 1000)
}

function remainingSeconds(state, nowMs) {
  return Math.ceil(remainingMilliseconds(state, nowMs) / 1000)
}

function elapsedProgress(state, nowMs) {
  if (!state) return 0
  var totalMs = Math.max(1000, finiteNumber(state.phaseDurationSec, 1) * 1000)
  var elapsed = totalMs - remainingMilliseconds(state, nowMs)
  return Math.max(0, Math.min(1, elapsed / totalMs))
}

function pause(state, nowMs) {
  if (!state || state.status !== StatusRunning) return state
  var now = finiteNumber(nowMs, 0)
  var next = cloneState(state)
  next.status = StatusPaused
  next.remainingSec = Math.max(0, remainingMilliseconds(state, now) / 1000)
  next.deadlineMs = 0
  next.updatedAtMs = now
  return next
}

function resume(state, nowMs) {
  if (!state || state.status !== StatusPaused) return state
  var now = finiteNumber(nowMs, 0)
  var remaining = Math.max(1, finiteNumber(state.remainingSec, 1))
  var total = Math.max(remaining, finiteNumber(state.phaseDurationSec, remaining))
  var next = cloneState(state)
  next.status = StatusRunning
  next.phaseDurationSec = total
  next.remainingSec = remaining
  next.startedAtMs = now - (total - remaining) * 1000
  next.deadlineMs = now + remaining * 1000
  next.updatedAtMs = now
  return next
}

function nextPhaseInfo(state, config) {
  var c = normalizeConfig(config)
  var completed = Math.max(0, Math.round(finiteNumber(state && state.completedWorkPhases, 0)))
  var phase = state && isPhase(state.phase) ? state.phase : PhaseWork

  if (phase === PhaseWork) {
    completed++
    if (completed >= c.workPhasesPerLongBreak) {
      return { phase: PhaseLongBreak, completedWorkPhases: completed }
    }
    return { phase: PhaseShortBreak, completedWorkPhases: completed }
  }

  if (phase === PhaseLongBreak) completed = 0
  return { phase: PhaseWork, completedWorkPhases: completed }
}

function advance(state, config, nowMs, nextTaskId) {
  var next = nextPhaseInfo(state, config)
  var taskId = next.phase === PhaseWork ? String(nextTaskId || "") : ""
  return runningPhase(next.phase, next.completedWorkPhases, durationSeconds(next.phase, config), nowMs, taskId)
}

function recoverInterrupted(state, config, nowMs) {
  var now = finiteNumber(nowMs, 0)
  var clean = sanitizeState(state, config, now)

  if (clean.status === StatusStopped)
    return { state: stoppedState(config, now), notifyPhase: "" }

  if (clean.status === StatusPaused)
    return { state: clean, notifyPhase: "" }

  if (clean.phase === PhaseWork)
    return { state: startNewCycle(config, now, clean.taskId), notifyPhase: PhaseWork }

  if (finiteNumber(clean.deadlineMs, 0) > now) {
    clean.remainingSec = remainingMilliseconds(clean, now) / 1000
    clean.updatedAtMs = now
    return { state: clean, notifyPhase: "" }
  }

  return { state: advance(clean, config, now, clean.taskId), notifyPhase: PhaseWork }
}

function sanitizeState(raw, config, nowMs) {
  var now = finiteNumber(nowMs, 0)
  if (!raw || Number(raw.version) !== StateVersion || !isStatus(raw.status) || !isPhase(raw.phase)) {
    return stoppedState(config, now)
  }

  var fallbackDuration = durationSeconds(raw.phase, config)
  var duration = Math.max(1, finiteNumber(raw.phaseDurationSec, fallbackDuration))
  var remaining = Math.max(0, Math.min(duration, finiteNumber(raw.remainingSec, duration)))
  var status = raw.status

  if (status === StatusPaused && remaining <= 0) remaining = 1

  return {
    version: StateVersion,
    status: status,
    phase: raw.phase,
    completedWorkPhases: Math.max(0, Math.round(finiteNumber(raw.completedWorkPhases, 0))),
    phaseDurationSec: duration,
    remainingSec: status === StatusRunning ? Math.max(0, finiteNumber(raw.remainingSec, duration)) : remaining,
    startedAtMs: Math.max(0, finiteNumber(raw.startedAtMs, 0)),
    deadlineMs: status === StatusRunning ? Math.max(0, finiteNumber(raw.deadlineMs, 0)) : 0,
    updatedAtMs: Math.max(0, finiteNumber(raw.updatedAtMs, now)),
    taskId: String(raw.taskId || "")
  }
}

function serializableState(state, nowMs) {
  var now = finiteNumber(nowMs, 0)
  var next = cloneState(state)
  if (next.status === StatusRunning) {
    next.remainingSec = remainingMilliseconds(next, now) / 1000
  }
  next.updatedAtMs = now
  return next
}

function formatRemaining(seconds) {
  var value = Math.max(0, Math.ceil(finiteNumber(seconds, 0)))
  var minutes = Math.floor(value / 60)
  var rest = value % 60
  return String(minutes).padStart(2, "0") + ":" + String(rest).padStart(2, "0")
}

function cloneState(state) {
  var copy = {}
  for (var key in state) copy[key] = state[key]
  return copy
}
