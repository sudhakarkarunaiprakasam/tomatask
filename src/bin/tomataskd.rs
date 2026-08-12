use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tomatask_core::ipc::{socket_path, Request, Response, StateResponse};
use tomatask_core::models::{PersistedState, Task};
use tomatask_core::storage;
use tomatask_core::timer::{epoch_now, TimerEngine};

struct Daemon {
    timer: TimerEngine,
    tasks: Vec<Task>,
    next_task_id: u64,
}

impl Daemon {
    fn state_response(&self) -> StateResponse {
        let snapshot = self.timer.snapshot();
        StateResponse {
            mode: snapshot.mode,
            status: snapshot.status,
            remaining_secs: snapshot.remaining_secs,
            completed_work_sessions: snapshot.completed_work_sessions,
            settings: self.timer.settings().clone(),
            tasks: self.tasks.clone(),
        }
    }

    fn persist(&self) {
        let state = PersistedState {
            version: 1,
            settings: self.timer.settings().clone(),
            timer: self.timer.snapshot().clone(),
            tasks: self.tasks.clone(),
            next_task_id: self.next_task_id,
        };

        if let Err(err) = storage::save_state(&state) {
            eprintln!("tomataskd: failed to persist state: {err:?}");
        }
    }
}

fn main() {
    let socket = socket_path();

    // Refuse to start a second instance: if a daemon is already listening, exit quietly.
    if UnixStream::connect(&socket).is_ok() {
        eprintln!("tomataskd: already running at {}", socket.display());
        return;
    }

    // Remove a stale socket file left behind by a previous crashed instance.
    let _ = std::fs::remove_file(&socket);
    if let Some(parent) = socket.parent() {
        let _ = std::fs::create_dir_all(parent);
    }

    let listener = match UnixListener::bind(&socket) {
        Ok(listener) => listener,
        Err(err) => {
            eprintln!("tomataskd: failed to bind socket {}: {err}", socket.display());
            std::process::exit(1);
        }
    };

    let initial = storage::load_state().unwrap_or_default();
    let daemon = Daemon {
        timer: TimerEngine::new(initial.settings, initial.timer),
        tasks: initial.tasks,
        next_task_id: initial.next_task_id,
    };

    let state = Arc::new(Mutex::new(daemon));

    // Ticking thread: advances the timer and fires notifications independently
    // of whether any GUI is connected, so reminders work even with no window open.
    {
        let state = Arc::clone(&state);
        std::thread::spawn(move || loop {
            std::thread::sleep(Duration::from_secs(1));
            let mut daemon = state.lock().unwrap();
            let transitioned = daemon.timer.tick(epoch_now());
            if transitioned {
                let phase = daemon.timer.snapshot().mode.label();
                let _ = notify_rust::Notification::new()
                    .summary("Tomatask")
                    .body(&format!("Time for: {phase}"))
                    .show();
            }
            daemon.persist();
        });
    }

    for incoming in listener.incoming() {
        let Ok(stream) = incoming else { continue };
        let state = Arc::clone(&state);
        std::thread::spawn(move || handle_client(stream, state));
    }
}

fn handle_client(stream: UnixStream, state: Arc<Mutex<Daemon>>) {
    let mut reader = BufReader::new(match stream.try_clone() {
        Ok(clone) => clone,
        Err(_) => return,
    });
    let mut writer = stream;

    let mut line = String::new();
    if reader.read_line(&mut line).unwrap_or(0) == 0 {
        return;
    }

    let request: Request = match serde_json::from_str(line.trim()) {
        Ok(request) => request,
        Err(err) => {
            let _ = send(&mut writer, &Response::Error { message: err.to_string() });
            return;
        }
    };

    let mut shutdown = false;
    let response = {
        let mut daemon = state.lock().unwrap();
        match request {
            Request::GetState => Response::State(daemon.state_response()),
            Request::StartPause => {
                daemon.timer.start_or_pause(epoch_now());
                daemon.persist();
                Response::State(daemon.state_response())
            }
            Request::Reset => {
                daemon.timer.reset_current_mode();
                daemon.persist();
                Response::State(daemon.state_response())
            }
            Request::Skip => {
                daemon.timer.skip_mode();
                daemon.persist();
                Response::State(daemon.state_response())
            }
            Request::AddTask { title } => {
                let title = title.trim().to_owned();
                if !title.is_empty() {
                    let id = daemon.next_task_id;
                    daemon.next_task_id += 1;
                    daemon.tasks.push(Task { id, title, done: false });
                    daemon.persist();
                }
                Response::State(daemon.state_response())
            }
            Request::ToggleTask { id } => {
                if let Some(task) = daemon.tasks.iter_mut().find(|task| task.id == id) {
                    task.done = !task.done;
                }
                daemon.persist();
                Response::State(daemon.state_response())
            }
            Request::DeleteTask { id } => {
                daemon.tasks.retain(|task| task.id != id);
                daemon.persist();
                Response::State(daemon.state_response())
            }
            Request::Shutdown => {
                daemon.persist();
                shutdown = true;
                Response::Ok
            }
        }
    };

    let _ = send(&mut writer, &response);

    if shutdown {
        std::process::exit(0);
    }
}

fn send(writer: &mut UnixStream, response: &Response) -> std::io::Result<()> {
    let mut payload = serde_json::to_string(response)
        .unwrap_or_else(|_| "{\"type\":\"Error\",\"message\":\"encode failure\"}".to_owned());
    payload.push('\n');
    writer.write_all(payload.as_bytes())
}
