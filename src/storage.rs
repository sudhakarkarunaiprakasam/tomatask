use std::fs;
use std::path::PathBuf;

use anyhow::{Context, Result};

use crate::models::PersistedState;

pub fn load_state() -> Result<PersistedState> {
    let path = state_file_path()?;
    if !path.exists() {
        return Ok(PersistedState::default());
    }

    let raw = fs::read_to_string(&path)
        .with_context(|| format!("failed to read state file: {}", path.display()))?;
    let state: PersistedState = toml::from_str(&raw)
        .with_context(|| format!("failed to parse state file: {}", path.display()))?;

    Ok(state)
}

pub fn save_state(state: &PersistedState) -> Result<()> {
    let path = state_file_path()?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create state directory: {}", parent.display()))?;
    }

    let raw = toml::to_string_pretty(state).context("failed to serialize app state")?;
    fs::write(&path, raw).with_context(|| format!("failed to write state file: {}", path.display()))?;
    Ok(())
}

fn state_file_path() -> Result<PathBuf> {
    let config_dir = dirs::config_dir().context("XDG config directory not found")?;
    Ok(config_dir.join("tomatask").join("state.toml"))
}
