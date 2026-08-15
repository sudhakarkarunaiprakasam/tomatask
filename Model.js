.pragma library

// Default Pomodoro session length.
function defaultDurationSeconds() {
  return 25 * 60
}

// Default rest/break session length.
function defaultRestSeconds() {
  return 5 * 60
}

function sessionLabel(sessionType) {
  return sessionType === "rest" ? "Rest" : "Focus"
}

function sessionStartMessage(sessionType) {
  return sessionLabel(sessionType) + " session started"
}

function sessionEndMessage(sessionType) {
  return sessionLabel(sessionType) + " session complete"
}

function nextSessionType(sessionType) {
  return sessionType === "rest" ? "focus" : "rest"
}

// e.g. "Rest Session Ended, Let's Focus" for the session that just ended.
function transitionMessage(endedSessionType) {
  return sessionLabel(endedSessionType) + " Session Ended, Let's " + sessionLabel(nextSessionType(endedSessionType))
}

// Formats a whole-second count as "MM:SS", clamped to non-negative.
function formatTime(totalSeconds) {
  var clamped = Math.max(0, Math.floor(totalSeconds))
  var m = Math.floor(clamped / 60)
  var s = clamped % 60
  return (m < 10 ? "0" + m : "" + m) + ":" + (s < 10 ? "0" + s : "" + s)
}
