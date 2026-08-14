#!/usr/bin/env node

const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const source = fs.readFileSync(path.join(__dirname, "..", "TimerModel.js"), "utf8")
const model = {}
vm.createContext(model)
vm.runInContext(source, model, { filename: "TimerModel.js" })

const config = model.normalizeConfig({
  workMinutes: 25,
  shortBreakMinutes: 5,
  longBreakMinutes: 15,
  workPhasesPerLongBreak: 4
})

assert.deepEqual(
  { ...model.normalizeConfig({ workMinutes: 0, shortBreakMinutes: 100, longBreakMinutes: 999, workPhasesPerLongBreak: 0 }) },
  { workMinutes: 1, shortBreakMinutes: 60, longBreakMinutes: 120, workPhasesPerLongBreak: 1 }
)

let state = model.startNewCycle(config, 1000, "task-1")
assert.equal(state.phase, model.PhaseWork)
assert.equal(state.taskId, "task-1")
assert.equal(model.remainingSeconds(state, 301000), 1200)

state = model.pause(state, 301000)
assert.equal(state.status, model.StatusPaused)
assert.equal(state.taskId, "task-1")

state = model.resume(state, 901000)
assert.equal(state.status, model.StatusRunning)
assert.equal(state.taskId, "task-1")

state = model.advance(state, config, 902000, "task-2")
assert.equal(state.phase, model.PhaseShortBreak)
assert.equal(state.taskId, "")

state = model.advance(state, config, 903000, "task-2")
assert.equal(state.phase, model.PhaseWork)
assert.equal(state.taskId, "task-2")

for (let i = 0; i < 5; i++) {
  state = model.advance(state, config, 904000 + i, "task-2")
}
assert.equal(state.phase, model.PhaseLongBreak)

state = model.advance(state, config, 910000, "task-2")
assert.equal(state.phase, model.PhaseWork)
assert.equal(state.completedWorkPhases, 0)

assert.equal(model.formatRemaining(65), "01:05")
assert.equal(model.formatRemaining(3605), "60:05")

console.log("timer model tests passed")
