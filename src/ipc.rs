use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use serde::{Deserialize, Serialize};

use crate::models::{PomodoroMode, Task, TimerSettings, TimerStatus};

/// A request sent from a client (GUI or Waybar helper) to the daemon.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum Request {
    GetState,
    StartPause,
    Reset,
    Skip,
    AddTask { title: String },
    ToggleTask { id: u64 },
    DeleteTask { id: u64 },
    Shutdown,
}

/// The current state of the timer + task list, as reported by the daemon.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StateResponse {
    pub mode: PomodoroMode,
    pub status: TimerStatus,
    pub remaining_secs: u64,
    pub completed_work_sessions: u32,
    pub settings: TimerSettings,
    pub tasks: Vec<Task>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum Response {
    State(StateResponse),
    Ok,
    Error { message: String },
}

/// Path to the daemon's Unix domain socket.
pub fn socket_path() -> PathBuf {
    if let Some(runtime_dir) = std::env::var_os("XDG_RUNTIME_DIR") {
        return PathBuf::from(runtime_dir).join("tomatask.sock");
    }

    dirs::cache_dir()
        .unwrap_or_else(std::env::temp_dir)
        .join("tomatask.sock")
}

/// Sends a single request to the daemon and waits for its response.
/// Each request opens a fresh connection (simple, robust, no framing issues).
pub fn send_request(request: &Request) -> Result<Response> {
    let mut stream = UnixStream::connect(socket_path()).context("failed to connect to tomataskd")?;
    stream.set_read_timeout(Some(Duration::from_secs(2)))?;
    stream.set_write_timeout(Some(Duration::from_secs(2)))?;

    let mut payload = serde_json::to_string(request).context("failed to encode request")?;
    payload.push('\n');
    stream
        .write_all(payload.as_bytes())
        .context("failed to send request to tomataskd")?;

    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    reader
        .read_line(&mut line)
        .context("failed to read response from tomataskd")?;

    if line.trim().is_empty() {
        return Err(anyhow!("tomataskd closed the connection without responding"));
    }

    let response: Response = serde_json::from_str(line.trim()).context("failed to decode daemon response")?;
    Ok(response)
}

/// Connects to the daemon, spawning it if it is not already running.
pub fn ensure_daemon_running() -> Result<()> {
    if UnixStream::connect(socket_path()).is_ok() {
        return Ok(());
    }

    let daemon_path = daemon_binary_path();

    Command::new(daemon_path)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .context("failed to spawn tomataskd")?;

    for _ in 0..40 {
        if UnixStream::connect(socket_path()).is_ok() {
            return Ok(());
        }
        std::thread::sleep(Duration::from_millis(50));
    }

    Err(anyhow!("timed out waiting for tomataskd to start"))
}

fn daemon_binary_path() -> PathBuf {
    if let Ok(current_exe) = std::env::current_exe() {
        if let Some(dir) = current_exe.parent() {
            let candidate = dir.join("tomataskd");
            if candidate.exists() {
                return candidate;
            }
        }
    }

    PathBuf::from("tomataskd")
}

/// The Wayland/Hyprland application id (window class) used by the GUI window.
/// Kept in sync with `config/tomatask.desktop`.
pub const GUI_APPLICATION_ID: &str = "tomatask";

/// Path to the lock socket used to enforce a single GUI instance.
fn gui_lock_path() -> PathBuf {
    if let Some(runtime_dir) = std::env::var_os("XDG_RUNTIME_DIR") {
        return PathBuf::from(runtime_dir).join("tomatask-gui.sock");
    }

    dirs::cache_dir()
        .unwrap_or_else(std::env::temp_dir)
        .join("tomatask-gui.sock")
}

/// Attempts to become the single running GUI instance.
///
/// Returns `Some(listener)` if this process is the first instance - the
/// caller must keep the listener alive (e.g. by holding it in `main`) for as
/// long as the GUI is running, as dropping it releases the lock. Returns
/// `None` if another GUI instance is already running.
pub fn acquire_gui_lock() -> Option<UnixListener> {
    let path = gui_lock_path();

    // If a live instance is already listening, we are not the first one.
    if UnixStream::connect(&path).is_ok() {
        return None;
    }

    // Otherwise, any existing socket file is stale - remove it and bind fresh.
    let _ = std::fs::remove_file(&path);
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }

    UnixListener::bind(&path).ok()
}

/// Asks Hyprland to focus the already-running GUI window, best-effort.
pub fn focus_existing_window() {
    let _ = Command::new("hyprctl")
        .args([
            "dispatch",
            "focuswindow",
            &format!("class:^({GUI_APPLICATION_ID})$"),
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}
