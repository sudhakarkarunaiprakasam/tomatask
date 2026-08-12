use tomatask_core::ipc::{self, Request, Response, StateResponse};
use tomatask_core::models::{PomodoroMode, Task, TimerSettings, TimerStatus};
use tomatask_core::theme::{self, ThemeColors};
use tomatask_core::timer::format_mm_ss;

use iced::alignment;
use iced::widget::{button, checkbox, column, container, row, scrollable, text, text_input};
use iced::{executor, time, Application, Command, Element, Length, Settings, Subscription, Theme};

fn main() -> iced::Result {
    // Enforce a single GUI instance: if one is already running, focus its
    // window instead of opening a new one.
    let _gui_lock = match ipc::acquire_gui_lock() {
        Some(lock) => lock,
        None => {
            ipc::focus_existing_window();
            return Ok(());
        }
    };

    let mut settings = Settings::with_flags(());

    settings.window = iced::window::Settings {
        size: iced::Size::new(420.0, 620.0),
        resizable: false,
        decorations: true,
        transparent: false,
        platform_specific: iced::window::settings::PlatformSpecific {
            application_id: ipc::GUI_APPLICATION_ID.to_string(),
        },
        ..Default::default()
    };

    TomataskApp::run(settings)
}

#[derive(Debug, Clone)]
enum Message {
    Tick,
    StartPausePressed,
    ResetPressed,
    SkipPressed,
    HidePressed,
    TaskInputChanged(String),
    AddTask,
    ToggleTask(u64),
    DeleteTask(u64),
}

struct TomataskApp {
    theme_colors: ThemeColors,
    mode: PomodoroMode,
    status: TimerStatus,
    remaining_secs: u64,
    settings: TimerSettings,
    tasks: Vec<Task>,
    task_input: String,
    last_error: Option<String>,
}

impl Application for TomataskApp {
    type Executor = executor::Default;
    type Message = Message;
    type Theme = Theme;
    type Flags = ();

    fn new(_flags: ()) -> (Self, Command<Message>) {
        let theme_colors = theme::load_theme();
        let mut app = Self {
            theme_colors,
            mode: PomodoroMode::Work,
            status: TimerStatus::Idle,
            remaining_secs: 25 * 60,
            settings: TimerSettings::default(),
            tasks: Vec::new(),
            task_input: String::new(),
            last_error: None,
        };

        if let Err(err) = ipc::ensure_daemon_running() {
            app.last_error = Some(format!("Could not start tomataskd: {err}"));
        } else {
            app.refresh_state();
        }

        (app, Command::none())
    }

    fn title(&self) -> String {
        "Tomatask".to_owned()
    }

    fn theme(&self) -> Theme {
        Theme::Dark
    }

    fn update(&mut self, message: Message) -> Command<Message> {
        match message {
            Message::Tick => {
                self.refresh_state();
            }
            Message::StartPausePressed => {
                self.apply(ipc::send_request(&Request::StartPause));
            }
            Message::ResetPressed => {
                self.apply(ipc::send_request(&Request::Reset));
            }
            Message::SkipPressed => {
                self.apply(ipc::send_request(&Request::Skip));
            }
            Message::HidePressed => {
                // Only close this GUI window. tomataskd (and the Waybar
                // timer) keep running in the background - Waybar's own
                // polling would respawn the daemon instantly anyway.
                std::process::exit(0);
            }
            Message::TaskInputChanged(value) => {
                self.task_input = value;
            }
            Message::AddTask => {
                let title = self.task_input.trim().to_owned();
                if !title.is_empty() {
                    self.apply(ipc::send_request(&Request::AddTask { title }));
                    self.task_input.clear();
                }
            }
            Message::ToggleTask(id) => {
                self.apply(ipc::send_request(&Request::ToggleTask { id }));
            }
            Message::DeleteTask(id) => {
                self.apply(ipc::send_request(&Request::DeleteTask { id }));
            }
        }

        Command::none()
    }

    fn view(&self) -> Element<'_, Message> {
        let timer_text = format_mm_ss(self.remaining_secs);
        let done_count = self.tasks.iter().filter(|task| task.done).count();
        let task_total = self.tasks.len();
        let accent = color_from_hex(&self.theme_colors.accent);

        let phase_color = match self.mode {
            PomodoroMode::Work => self.theme_colors.work.as_str(),
            PomodoroMode::ShortBreak | PomodoroMode::LongBreak => self.theme_colors.r#break.as_str(),
        };

        let status_text = match self.status {
            TimerStatus::Idle => "Ready",
            TimerStatus::Running => "Running",
            TimerStatus::Paused => "Paused",
        };

        let header = column![
            text("Tomatask")
                .size(30)
                .style(accent)
                .horizontal_alignment(alignment::Horizontal::Center),
            text(self.mode.label()).size(20).style(color_from_hex(phase_color)),
            text(timer_text).size(64).horizontal_alignment(alignment::Horizontal::Center),
            text(status_text).size(16),
        ]
        .spacing(8)
        .width(Length::Fill)
        .align_items(iced::Alignment::Center);

        let controls = row![
            button(text("Start/Pause")).on_press(Message::StartPausePressed),
            button(text("Reset")).on_press(Message::ResetPressed),
            button(text("Skip")).on_press(Message::SkipPressed),
            button(text("Hide")).on_press(Message::HidePressed),
        ]
        .spacing(10)
        .width(Length::Fill)
        .align_items(iced::Alignment::Center);

        let tasks_header = row![
            text("Tasks").size(22).style(accent),
            text(format!("{done_count}/{task_total} done"))
                .size(14)
                .style(color_from_hex(&self.theme_colors.text)),
        ]
        .spacing(12)
        .align_items(iced::Alignment::Center);

        let input_row = row![
            text_input("Add a task", &self.task_input)
                .on_input(Message::TaskInputChanged)
                .on_submit(Message::AddTask)
                .padding(10)
                .size(16),
            button(text("Add")).on_press(Message::AddTask),
        ]
        .spacing(10);

        let task_list = self.tasks.iter().fold(column![].spacing(8), |col, task| {
            col.push(
                row![
                    checkbox(task.title.clone(), task.done)
                        .on_toggle(move |_| Message::ToggleTask(task.id))
                        .width(Length::Fill),
                    button(text("Remove")).on_press(Message::DeleteTask(task.id)),
                ]
                .spacing(8)
                .align_items(iced::Alignment::Center),
            )
        });

        let body = column![
            header,
            controls,
            text("------------------------------")
                .size(12)
                .style(color_from_hex(&self.theme_colors.surface)),
            text(format!(
                "Focus {}m . Short {}m . Long {}m",
                self.settings.work_minutes, self.settings.short_break_minutes, self.settings.long_break_minutes
            ))
            .size(14)
            .style(accent),
            container(column![tasks_header, input_row, scrollable(task_list).height(Length::Fill)])
                .padding(12)
                .width(Length::Fill)
                .height(Length::Fill),
            maybe_error(self.last_error.as_ref()),
        ]
        .padding(16)
        .spacing(14)
        .width(Length::Fill)
        .height(Length::Fill);

        container(body).width(Length::Fill).height(Length::Fill).into()
    }

    fn subscription(&self) -> Subscription<Message> {
        time::every(std::time::Duration::from_millis(500)).map(|_| Message::Tick)
    }
}

impl TomataskApp {
    fn refresh_state(&mut self) {
        self.apply(ipc::send_request(&Request::GetState));
    }

    fn apply(&mut self, result: anyhow::Result<Response>) {
        match result {
            Ok(Response::State(state)) => self.apply_state(state),
            Ok(Response::Ok) => {
                self.last_error = None;
            }
            Ok(Response::Error { message }) => {
                self.last_error = Some(message);
            }
            Err(err) => {
                self.last_error = Some(format!("tomataskd unreachable: {err}"));
            }
        }
    }

    fn apply_state(&mut self, state: StateResponse) {
        self.mode = state.mode;
        self.status = state.status;
        self.remaining_secs = state.remaining_secs;
        self.settings = state.settings;
        self.tasks = state.tasks;
        self.last_error = None;
    }
}

fn color_from_hex(hex: &str) -> iced::Color {
    theme::parse_hex_color(hex).unwrap_or(iced::Color::WHITE)
}

fn maybe_error(error: Option<&String>) -> Element<'_, Message> {
    match error {
        Some(message) => text(format!("Issue: {message}"))
            .style(iced::Color::from_rgb8(255, 120, 120))
            .size(12)
            .into(),
        None => text("").size(1).into(),
    }
}
