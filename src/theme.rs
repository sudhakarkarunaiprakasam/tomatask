use std::fs;
use std::path::PathBuf;

use anyhow::Result;

#[derive(Debug, Clone)]
pub struct ThemeColors {
    pub background: String,
    pub surface: String,
    pub text: String,
    pub accent: String,
    pub work: String,
    pub r#break: String,
}

impl Default for ThemeColors {
    fn default() -> Self {
        Self {
            background: "#11131a".to_owned(),
            surface: "#1d212b".to_owned(),
            text: "#f2f4f8".to_owned(),
            accent: "#71c7ec".to_owned(),
            work: "#69db7c".to_owned(),
            r#break: "#74c0fc".to_owned(),
        }
    }
}

pub fn load_theme() -> ThemeColors {
    let mut theme = ThemeColors::default();

    let candidates = [
        config_file("tomatask/theme.toml"),
        config_file("omarchy/current/theme/colors.toml"),
    ];

    for candidate in candidates.into_iter().flatten() {
        if let Ok(raw) = fs::read_to_string(&candidate) {
            merge_toml_colors(&mut theme, &raw);
            return theme;
        }
    }

    theme
}

fn config_file(path: &str) -> Option<PathBuf> {
    dirs::config_dir().map(|dir| dir.join(path))
}

fn merge_toml_colors(theme: &mut ThemeColors, raw: &str) {
    let Ok(value) = raw.parse::<toml::Value>() else {
        return;
    };

    let source = value.get("colors").unwrap_or(&value);

    // Omarchy's colors.toml (~/.config/omarchy/current/theme/colors.toml) uses a
    // flat terminal-palette layout: background/foreground/accent + color0..color15.
    theme.background = read_color(source, &["background", "bg"]).unwrap_or(theme.background.clone());
    theme.surface = read_color(source, &["surface", "card", "color0", "color8"]).unwrap_or(theme.surface.clone());
    theme.text = read_color(source, &["foreground", "text", "fg"]).unwrap_or(theme.text.clone());
    theme.accent = read_color(source, &["accent", "primary", "color4"]).unwrap_or(theme.accent.clone());
    theme.work = read_color(source, &["work", "green", "success", "color2"]).unwrap_or(theme.work.clone());
    theme.r#break = read_color(source, &["break", "blue", "info", "color4"]).unwrap_or(theme.r#break.clone());
}

fn read_color(root: &toml::Value, keys: &[&str]) -> Option<String> {
    keys.iter().find_map(|key| {
        root.get(*key)
            .and_then(toml::Value::as_str)
            .map(ToOwned::to_owned)
    })
}

pub fn parse_hex_color(hex: &str) -> Option<iced::Color> {
    let clean = hex.trim_start_matches('#');
    if clean.len() != 6 {
        return None;
    }

    let r = u8::from_str_radix(&clean[0..2], 16).ok()?;
    let g = u8::from_str_radix(&clean[2..4], 16).ok()?;
    let b = u8::from_str_radix(&clean[4..6], 16).ok()?;

    Some(iced::Color::from_rgb8(r, g, b))
}

pub fn _validate_theme_file(path: &PathBuf) -> Result<()> {
    let raw = fs::read_to_string(path)?;
    let _ = raw.parse::<toml::Value>()?;
    Ok(())
}
