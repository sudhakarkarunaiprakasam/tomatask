use tomatask_core::ipc::{self, Request, Response};
use tomatask_core::models::{PomodoroMode, TimerStatus};
use tomatask_core::timer::format_mm_ss;

fn main() {
    if let Err(err) = ipc::ensure_daemon_running() {
        print_json("Tomatask", &format!("tomataskd failed to start: {err}"), "error");
        return;
    }

    match ipc::send_request(&Request::GetState) {
        Ok(Response::State(state)) => {
            let icon = match state.mode {
                PomodoroMode::Work => "\u{1F345}",       // (tomato)
                PomodoroMode::ShortBreak => "\u{2615}",  // (coffee cup)
                PomodoroMode::LongBreak => "\u{1F3D6}",  // (beach)
            };

            let status_marker = match state.status {
                TimerStatus::Running => "",
                TimerStatus::Paused => " (paused)",
                TimerStatus::Idle => " (ready)",
            };

            let text = format!("{icon} {}{status_marker}", format_mm_ss(state.remaining_secs));

            let done_count = state.tasks.iter().filter(|task| task.done).count();
            let tooltip = format!(
                "{} - {}\n{done_count}/{} tasks done",
                state.mode.label(),
                match state.status {
                    TimerStatus::Running => "Running",
                    TimerStatus::Paused => "Paused",
                    TimerStatus::Idle => "Ready",
                },
                state.tasks.len(),
            );

            let class = match state.mode {
                PomodoroMode::Work => "work",
                PomodoroMode::ShortBreak => "short-break",
                PomodoroMode::LongBreak => "long-break",
            };

            print_json(&text, &tooltip, class);
        }
        Ok(other) => {
            print_json("Tomatask", &format!("Unexpected daemon response: {other:?}"), "error");
        }
        Err(err) => {
            print_json("Tomatask", &format!("tomataskd unreachable: {err}"), "error");
        }
    }
}

fn print_json(text: &str, tooltip: &str, class: &str) {
    let payload = serde_json::json!({
        "text": text,
        "tooltip": tooltip,
        "class": class,
    });
    println!("{payload}");
}
