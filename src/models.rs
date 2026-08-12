use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Task {
    pub id: u64,
    pub title: String,
    pub done: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PomodoroMode {
    Work,
    ShortBreak,
    LongBreak,
}

impl PomodoroMode {
    pub fn label(self) -> &'static str {
        match self {
            Self::Work => "Focus",
            Self::ShortBreak => "Short Break",
            Self::LongBreak => "Long Break",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TimerStatus {
    Idle,
    Running,
    Paused,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimerSettings {
    pub work_minutes: u64,
    pub short_break_minutes: u64,
    pub long_break_minutes: u64,
    pub long_break_interval: u32,
}

impl Default for TimerSettings {
    fn default() -> Self {
        Self {
            work_minutes: 25,
            short_break_minutes: 5,
            long_break_minutes: 15,
            long_break_interval: 4,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimerSnapshot {
    pub mode: PomodoroMode,
    pub status: TimerStatus,
    pub remaining_secs: u64,
    pub completed_work_sessions: u32,
    pub target_end_epoch: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PersistedState {
    pub version: u32,
    pub settings: TimerSettings,
    pub timer: TimerSnapshot,
    pub tasks: Vec<Task>,
    pub next_task_id: u64,
}

impl Default for PersistedState {
    fn default() -> Self {
        let settings = TimerSettings::default();
        Self {
            version: 1,
            timer: TimerSnapshot {
                mode: PomodoroMode::Work,
                status: TimerStatus::Idle,
                remaining_secs: settings.work_minutes * 60,
                completed_work_sessions: 0,
                target_end_epoch: None,
            },
            settings,
            tasks: Vec::new(),
            next_task_id: 1,
        }
    }
}
