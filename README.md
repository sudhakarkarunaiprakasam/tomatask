# Tomatask

Tomatask is an Omarchy plugin that combines a Pomodoro timer with lightweight task tracking.

Each completed **work** phase is counted under the selected task so you can track focus sessions per task without leaving the bar.

## Install

```bash
omarchy plugin add https://github.com/your-user/tomatask --enable
```

## Use

- Click the bar icon to open the panel.
- Select or create a task.
- Press **Start** to begin a Pomodoro cycle.
- Every completed work session increments the selected task's session count.

## Controls

- Left click bar icon: open/close panel
- Space/Enter: start or pause/resume
- `S`: skip to next phase
- `R`: reset current phase
- `N`: create a task from quick input

## Settings

```bash
omarchy bar plugin set sudhakar.tomatask workMinutes 25 --json
omarchy bar plugin set sudhakar.tomatask shortBreakMinutes 5 --json
omarchy bar plugin set sudhakar.tomatask longBreakMinutes 15 --json
omarchy bar plugin set sudhakar.tomatask workPhasesPerLongBreak 4 --json
omarchy bar plugin set sudhakar.tomatask sound true --json
```

## Notes

- State is persisted in `~/.local/state/omarchy/tomatask.json`.
- If no task exists, Tomatask creates a default `Inbox` task automatically.
