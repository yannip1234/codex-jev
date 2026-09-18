use super::*;
use pretty_assertions::assert_eq;

#[test]
fn key_is_masked_then_saved_without_a_chat_event() {
    let home = tempfile::tempdir().unwrap();
    let mut view = JevSettingsView::new(home.path().to_path_buf());
    view.handle_key_event(KeyEvent::from(KeyCode::Enter));
    view.handle_paste("test-secret-never-render".into());
    let text = render_view(&view);
    assert!(!text.contains("test-secret"));
    insta::assert_snapshot!(text, @r#"
Jev settings
API key (input is hidden)
********

Changes apply to the next compression or compaction.
Enter save · Esc cancel · Ctrl+U clear
"#);
    view.handle_key_event(KeyEvent::from(KeyCode::Enter));
    assert_eq!(
        std::fs::read_to_string(home.path().join("jev-api-key")).unwrap(),
        "test-secret-never-render"
    );
    assert!(view.key_input.is_none());
}

#[test]
fn cancelling_key_edit_leaves_saved_key_unchanged() {
    let home = tempfile::tempdir().unwrap();
    save_api_key(home.path(), "existing-secret").unwrap();
    let mut view = JevSettingsView::new(home.path().to_path_buf());
    view.handle_key_event(KeyEvent::from(KeyCode::Enter));
    view.handle_paste("replacement-secret".into());
    view.handle_key_event(KeyEvent::from(KeyCode::Esc));
    assert_eq!(
        std::fs::read_to_string(home.path().join("jev-api-key")).unwrap(),
        "existing-secret"
    );
    assert!(view.key_input.is_none());
    assert!(!view.is_complete());
}

#[test]
fn toggle_and_remove_are_persisted() {
    let home = tempfile::tempdir().unwrap();
    save_api_key(home.path(), "existing-secret").unwrap();
    let mut view = JevSettingsView::new(home.path().to_path_buf());
    view.handle_key_event(KeyEvent::from(KeyCode::Down));
    view.handle_key_event(KeyEvent::from(KeyCode::Enter));
    assert_eq!(
        load_settings(home.path()),
        JevSettings {
            tool_compression: false,
            compaction: true
        }
    );
    view.handle_key_event(KeyEvent::from(KeyCode::Down));
    view.handle_key_event(KeyEvent::from(KeyCode::Enter));
    assert_eq!(
        load_settings(home.path()),
        JevSettings {
            tool_compression: false,
            compaction: false
        }
    );
    view.handle_key_event(KeyEvent::from(KeyCode::Down));
    view.handle_key_event(KeyEvent::from(KeyCode::Enter));
    assert!(!home.path().join("jev-api-key").exists());
    view.environment_key_configured = false;
    insta::assert_snapshot!(render_view(&view), @r#"
Jev settings
API key: Not configured
Enabled features send eligible conversation text to TypeSafe.

  Add or replace API key
  Tool-output compression: off
  History compaction: off
> Remove saved API key

Saved key removed. An environment key still takes precedence.
↑/↓ select · Enter change · Esc close
"#);
}

fn render_view(view: &JevSettingsView) -> String {
    let area = Rect::new(
        /*x*/ 0,
        /*y*/ 0,
        /*width*/ 76,
        view.desired_height(/*width*/ 76),
    );
    let mut buffer = Buffer::empty(area);
    view.render(area, &mut buffer);
    buffer
        .content
        .chunks(usize::from(area.width))
        .map(|row| {
            row.iter()
                .map(ratatui::buffer::Cell::symbol)
                .collect::<String>()
                .trim_end()
                .to_owned()
        })
        .collect::<Vec<_>>()
        .join("\n")
}

#[test]
fn invalid_key_stays_in_editor_and_preserves_existing_key() {
    let home = tempfile::tempdir().unwrap();
    save_api_key(home.path(), "existing-secret").unwrap();
    let mut view = JevSettingsView::new(home.path().to_path_buf());
    view.handle_key_event(KeyEvent::from(KeyCode::Enter));
    view.handle_paste("two\nlines".into());
    view.handle_key_event(KeyEvent::from(KeyCode::Enter));
    assert!(view.key_input.is_some());
    assert_eq!(
        std::fs::read_to_string(home.path().join("jev-api-key")).unwrap(),
        "existing-secret"
    );
    view.on_ctrl_c();
    assert!(view.key_input.is_none());
    assert!(view.is_complete());
}
