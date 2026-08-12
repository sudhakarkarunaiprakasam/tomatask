use crate::models::{PomodoroMode, TimerSettings, TimerSnapshot, TimerStatus};

#[derive(Debug, Clone)]
pub struct TimerEngine {
    snapshot: TimerSnapshot,
    settings: TimerSettings,
}

impl TimerEngine {
    pub fn new(settings: TimerSettings, snapshot: TimerSnapshot) -> Self {
        Self { settings, snapshot }
    }

    pub fn snapshot(&self) -> &TimerSnapshot {
        &self.snapshot
    }

    pub fn settings(&self) -> &TimerSettings {
        &self.settings
    }

    pub fn start_or_pause(&mut self, now_epoch: u64) {
        match self.snapshot.status {
            TimerStatus::Idle | TimerStatus::Paused => {
                self.snapshot.status = TimerStatus::Running;
                self.snapshot.target_end_epoch = Some(now_epoch + self.snapshot.remaining_secs);
            }
            TimerStatus::Running => {
                self.recompute_remaining(now_epoch);
                self.snapshot.status = TimerStatus::Paused;
                self.snapshot.target_end_epoch = None;
            }
        }
    }

    pub fn reset_current_mode(&mut self) {
        self.snapshot.status = TimerStatus::Idle;
        self.snapshot.target_end_epoch = None;
        self.snapshot.remaining_secs = self.mode_duration(self.snapshot.mode);
    }

    pub fn skip_mode(&mut self) {
        self.advance_mode();
        self.snapshot.status = TimerStatus::Idle;
        self.snapshot.target_end_epoch = None;
    }

    pub fn tick(&mut self, now_epoch: u64) -> bool {
        if self.snapshot.status != TimerStatus::Running {
            return false;
        }

        self.recompute_remaining(now_epoch);
        if self.snapshot.remaining_secs == 0 {
            self.advance_mode();
            self.snapshot.status = TimerStatus::Idle;
            self.snapshot.target_end_epoch = None;
            return true;
        }

        false
    }

    pub fn status_text(&self) -> &'static str {
        match self.snapshot.status {
            TimerStatus::Idle => "Ready",
            TimerStatus::Running => "Running",
            TimerStatus::Paused => "Paused",
        }
    }

    fn recompute_remaining(&mut self, now_epoch: u64) {
        if let Some(end_epoch) = self.snapshot.target_end_epoch {
            self.snapshot.remaining_secs = end_epoch.saturating_sub(now_epoch);
        }
    }

    fn advance_mode(&mut self) {
        self.snapshot.mode = match self.snapshot.mode {
            PomodoroMode::Work => {
                self.snapshot.completed_work_sessions += 1;
                if self.snapshot.completed_work_sessions % self.settings.long_break_interval == 0 {
                    PomodoroMode::LongBreak
                } else {
                    PomodoroMode::ShortBreak
                }
            }
            PomodoroMode::ShortBreak | PomodoroMode::LongBreak => PomodoroMode::Work,
        };

        self.snapshot.remaining_secs = self.mode_duration(self.snapshot.mode);
    }

    fn mode_duration(&self, mode: PomodoroMode) -> u64 {
        match mode {
            PomodoroMode::Work => self.settings.work_minutes * 60,
            PomodoroMode::ShortBreak => self.settings.short_break_minutes * 60,
            PomodoroMode::LongBreak => self.settings.long_break_minutes * 60,
        }
    }
}

pub fn epoch_now() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};

    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

pub fn format_mm_ss(total_secs: u64) -> String {
    let minutes = total_secs / 60;
    let secs = total_secs % 60;
    format!("{minutes:02}:{secs:02}")
}
