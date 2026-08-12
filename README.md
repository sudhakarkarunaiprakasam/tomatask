# tomatask

Omarchy-native Pomodoro app: a background timer + task list daemon, a simple
popup GUI, and a Waybar status module.

## Scope

- Omarchy only (Wayland + Hyprland environment)
- Native Rust, split into three small binaries (see Architecture below)
- Full Pomodoro cycle (Focus / Short break / Long break)
- Minimal task list
- Timer visible in Waybar at all times, independent of whether the popup window is open
- Omarchy theme (`~/.config/omarchy/current/theme/colors.toml`) color integration

## Architecture

Tomatask is split into three binaries that share one core library
(`src/lib.rs`, `src/models.rs`, `src/storage.rs`, `src/theme.rs`, `src/timer.rs`, `src/ipc.rs`):

- **`tomataskd`** - background daemon. Owns the Pomodoro timer and task list,
  ticks every second, persists state to `~/.config/tomatask/state.toml`, and
  fires desktop notifications on phase changes - all independent of whether
  any window is open. Listens on a Unix socket
  (`$XDG_RUNTIME_DIR/tomatask.sock`) for commands. Only one instance ever
  runs; it auto-starts the first time `tomatask` or `tomatask-status` needs it.
- **`tomatask`** - the GUI. A single, ordinary window (Iced) with timer
  controls (Start/Pause, Reset, Skip) and the task list. It is a thin client:
  every action is sent to `tomataskd` over the socket, and the view polls the
  daemon twice a second to stay in sync. Closing the window like any other
  app just closes the GUI - `tomataskd` (and the Waybar timer) keeps running.
  Use the "Quit" button to stop the daemon as well.
- **`tomatask-status`** - a tiny one-shot helper for a Waybar `custom` module.
  It queries `tomataskd` and prints the JSON Waybar expects
  (`text`/`tooltip`/`class`), then exits.

This design replaced an earlier StatusNotifier-tray + multi-window
implementation that turned out to be unreliable on Wayland/Hyprland (windows
cannot be reliably hidden/shown by an app itself, and spurious windows could
appear). The new architecture avoids all of that: the only "window" is the
one normal popup window, and the timer keeps running/reporting via the
daemon regardless of the GUI's state.

## Waybar Integration

Tomatask does **not** touch your Waybar config unless you explicitly ask it
to. Two options:

**Automatic (opt-in):**

```
./install.sh --configure-waybar
```

or, standalone, at any time:

```
./scripts/configure-waybar.sh --dry-run   # preview the change first
./scripts/configure-waybar.sh             # apply it
```

This adds a `custom/tomatask` module to `~/.config/waybar/config.jsonc` and
inserts it into whichever of `modules-right` / `modules-center` /
`modules-left` exists first. It is idempotent (safe to run repeatedly - does
nothing if already configured), always writes a timestamped `.bak` file
before editing, and validates the result is well-formed JSON(C) before
committing it. Run `omarchy restart waybar` afterwards to apply the change.

**Manual:** add this yourself to `~/.config/waybar/config.jsonc`:

```jsonc
"custom/tomatask": {
  "exec": "tomatask-status",
  "interval": 1,
  "return-type": "json",
  "on-click": "tomatask"
}
```

Then add `"custom/tomatask"` to one of your `modules-left` / `modules-center`
/ `modules-right` arrays, and run `omarchy restart waybar` (Waybar does not
hot-reload custom module additions).

## Local Development

Requirements:

- Rust toolchain (stable)
- Omarchy desktop environment

Run in development (two terminals):

1. `cargo run --bin tomataskd` (or just let `tomatask`/`tomatask-status` auto-start it)
2. `cargo run --bin tomatask`

## Install (Omarchy plugin style)

1. `./install.sh`
2. Run `tomatask` from the app launcher or `~/.local/bin/tomatask`
3. Optional immediate start: `./install.sh --start`
4. Optional Waybar setup: `./install.sh --configure-waybar` (see below), or add the module snippet yourself

Installer behavior:

- Builds all three release binaries
- Installs `tomatask`, `tomataskd`, `tomatask-status` to `~/.local/bin`
- Installs desktop entry to `~/.local/share/applications/tomatask.desktop`
- Installs app icon to `~/.local/share/icons/hicolor/scalable/apps/tomatask.svg`
- Creates default config at `~/.config/tomatask/state.toml` when missing

## Uninstall

1. `./uninstall.sh`

Uninstall behavior:

- Stops `tomataskd` if running
- Removes all three binaries and the desktop entry
- Preserves user data under `~/.config/tomatask`

## Configuration

Primary state file (managed by `tomataskd`):

- `~/.config/tomatask/state.toml`

Theme file lookup order:

- `~/.config/tomatask/theme.toml` (optional override)
- `~/.config/omarchy/current/theme/colors.toml` (Omarchy's active theme)
- built-in defaults

## Diagnostics

Run `./scripts/doctor.sh` to check installed binaries, whether `tomataskd`
is running, the Waybar status output, and which theme file is in use.
