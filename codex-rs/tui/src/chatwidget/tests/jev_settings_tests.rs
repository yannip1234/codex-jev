use super::*;
use pretty_assertions::assert_eq;

#[tokio::test]
async fn jev_key_entry_never_emits_history_or_core_events() {
    let (mut chat, mut events, mut operations) =
        make_chatwidget_manual(/*model_override*/ None).await;
    chat.dispatch_command(SlashCommand::Jev);
    chat.bottom_pane
        .handle_key_event(KeyEvent::from(KeyCode::Enter));
    chat.handle_paste("secret-for-local-storage-only".to_owned());
    assert!(!render_bottom_popup(&chat, /*width*/ 80).contains("secret-for-local-storage-only"));
    chat.bottom_pane
        .handle_key_event(KeyEvent::from(KeyCode::Enter));
    assert_eq!(
        std::fs::read_to_string(chat.config.codex_home.join("jev-api-key")).unwrap(),
        "secret-for-local-storage-only"
    );
    assert_matches!(events.try_recv(), Err(TryRecvError::Empty));
    assert!(operations.try_recv().is_err());
    chat.bottom_pane
        .handle_key_event(KeyEvent::from(KeyCode::Esc));
    assert!(chat.bottom_pane.composer_text().is_empty());
}
