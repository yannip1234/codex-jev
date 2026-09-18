//! Jev credentials stay in this local view: never use the chat composer or AppEvent for secrets.
use codex_config::jev::JevSettings;
use codex_config::jev::load_settings;
use codex_config::jev::remove_api_key;
use codex_config::jev::save_api_key;
use codex_config::jev::save_settings;
use crossterm::event::KeyCode;
use crossterm::event::KeyEvent;
use crossterm::event::KeyEventKind;
use crossterm::event::KeyModifiers;
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::Stylize;
use ratatui::text::Line;
use ratatui::widgets::Paragraph;
use ratatui::widgets::Widget;
use std::path::PathBuf;

use super::BottomPaneView;
use super::CancellationEvent;
use super::ViewCompletion;
use crate::render::renderable::Renderable;

pub(crate) struct JevSettingsView {
    codex_home: PathBuf,
    settings: JevSettings,
    environment_key_configured: bool,
    selected: usize,
    // Deliberately no Debug derive and no ordinary text input widget/history.
    key_input: Option<String>,
    message: &'static str,
    completion: Option<ViewCompletion>,
}

impl JevSettingsView {
    pub(crate) fn new(codex_home: PathBuf) -> Self {
        Self {
            settings: load_settings(&codex_home),
            environment_key_configured: std::env::var("TYPESAFE_API_KEY")
                .is_ok_and(|key| !key.trim().is_empty()),
            codex_home,
            selected: 0,
            key_input: None,
            message: "Changes apply to the next compression or compaction.",
            completion: None,
        }
    }

    fn activate(&mut self) {
        match self.selected {
            0 => {
                self.key_input = Some(String::new());
            }
            1 | 2 => {
                let mut settings = self.settings;
                if self.selected == 1 {
                    settings.tool_compression = !settings.tool_compression;
                } else {
                    settings.compaction = !settings.compaction;
                }
                match save_settings(&self.codex_home, &settings) {
                    Ok(()) => {
                        self.settings = settings;
                        self.message = "Settings saved.";
                    }
                    Err(_) => {
                        self.message = "Could not save settings. Check CODEX_HOME permissions."
                    }
                }
            }
            3 => {
                self.message = match remove_api_key(&self.codex_home) {
                    Ok(()) => {
                        "Saved key removed. A valid environment key will be used as fallback."
                    }
                    Err(_) => "Could not remove saved key. Check CODEX_HOME permissions.",
                };
            }
            _ => unreachable!("selection is bounded to four rows"),
        }
    }

    fn lines(&self) -> Vec<Line<'static>> {
        let mut lines = vec!["Jev settings".bold().into()];
        if let Some(key) = &self.key_input {
            lines.extend([
                "API key (input is hidden)".into(),
                if key.is_empty() {
                    "Paste or type your Jev API key".dim().into()
                } else {
                    "********".cyan().into()
                },
                "".into(),
                self.message.dim().into(),
                "Enter save · Esc cancel · Ctrl+U clear".dim().into(),
            ]);
        } else {
            let source = if self.codex_home.join("jev-api-key").is_file() {
                "Saved locally (preferred if valid)"
            } else if self.environment_key_configured {
                "TYPESAFE_API_KEY (fallback)"
            } else {
                "Not configured"
            };
            lines.push(format!("API key: {source}").dim().into());
            lines.push(
                "Enabled features send eligible conversation text to TypeSafe."
                    .dim()
                    .into(),
            );
            lines.push("".into());
            for (index, label) in [
                "Add or replace API key".to_owned(),
                format!(
                    "Tool-output compression: {}",
                    if self.settings.tool_compression {
                        "on"
                    } else {
                        "off"
                    }
                ),
                format!(
                    "History compaction: {}",
                    if self.settings.compaction {
                        "on"
                    } else {
                        "off"
                    }
                ),
                "Remove saved API key".to_owned(),
            ]
            .into_iter()
            .enumerate()
            {
                lines.push(if index == self.selected {
                    format!("> {label}").cyan().into()
                } else {
                    format!("  {label}").into()
                });
            }
            lines.extend([
                "".into(),
                self.message.dim().into(),
                "↑/↓ select · Enter change · Esc close".dim().into(),
            ]);
        }
        lines
    }
}

impl BottomPaneView for JevSettingsView {
    fn handle_key_event(&mut self, event: KeyEvent) {
        if event.kind == KeyEventKind::Release {
            return;
        }
        if let Some(key) = &mut self.key_input {
            match event.code {
                KeyCode::Esc => {
                    self.key_input = None;
                    self.message = "Key entry cancelled.";
                }
                KeyCode::Enter => match save_api_key(&self.codex_home, key) {
                    Ok(()) => {
                        self.key_input = None;
                        self.message = "API key saved privately in CODEX_HOME.";
                    }
                    Err(_) => {
                        self.message = "Could not save key. Check input and CODEX_HOME permissions."
                    }
                },
                KeyCode::Backspace => {
                    key.pop();
                }
                KeyCode::Char('u') if event.modifiers.contains(KeyModifiers::CONTROL) => {
                    key.clear()
                }
                KeyCode::Char(ch)
                    if !event
                        .modifiers
                        .intersects(KeyModifiers::CONTROL | KeyModifiers::ALT)
                        && !ch.is_control()
                        && key.len() + ch.len_utf8() <= 8192 =>
                {
                    key.push(ch);
                }
                _ => {}
            }
            return;
        }
        match event.code {
            KeyCode::Up | KeyCode::BackTab => self.selected = (self.selected + 3) % 4,
            KeyCode::Down | KeyCode::Tab => self.selected = (self.selected + 1) % 4,
            KeyCode::Enter | KeyCode::Char(' ') => self.activate(),
            KeyCode::Esc => {
                self.on_ctrl_c();
            }
            _ => {}
        }
    }

    fn handle_paste(&mut self, pasted: String) -> bool {
        if let Some(key) = &mut self.key_input {
            let pasted = pasted.trim();
            if key.len() + pasted.len() <= 8192 {
                key.push_str(pasted);
            }
            return true;
        }
        false
    }

    fn on_ctrl_c(&mut self) -> CancellationEvent {
        self.key_input = None;
        self.completion = Some(ViewCompletion::Cancelled);
        CancellationEvent::Handled
    }

    fn prefer_esc_to_handle_key_event(&self) -> bool {
        true
    }
    fn is_complete(&self) -> bool {
        self.completion.is_some()
    }
    fn completion(&self) -> Option<ViewCompletion> {
        self.completion
    }
}

impl Renderable for JevSettingsView {
    fn desired_height(&self, _width: u16) -> u16 {
        self.lines().len() as u16
    }
    fn render(&self, area: Rect, buf: &mut Buffer) {
        Paragraph::new(self.lines()).render(area, buf);
    }
}

#[cfg(test)]
#[path = "jev_settings_view_tests.rs"]
mod tests;
