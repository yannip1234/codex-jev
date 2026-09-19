use super::*;
use pretty_assertions::assert_eq;
use serde_json::json;

fn item(value: serde_json::Value) -> ResponseItemEnvelope {
    ResponseItemEnvelope::new(serde_json::from_value(value).unwrap())
}

fn message(role: &str, text: &str) -> ResponseItemEnvelope {
    item(json!({"type":"message", "role":role, "content":[{"type":"input_text", "text":text}]}))
}

fn pair(id: &str, output: &str) -> Vec<ResponseItemEnvelope> {
    vec![
        item(json!({"type":"function_call", "name":"shell", "call_id":id, "arguments":"{}"})),
        item(json!({"type":"function_call_output", "call_id":id, "output":output})),
    ]
}

fn history() -> Vec<ResponseItemEnvelope> {
    let mut items = vec![message("user", "Old task")];
    items.extend(pair("old", &"obsolete log ".repeat(2000)));
    items.push(message("assistant", "Keep this conclusion"));
    items.push(message("user", "Current task"));
    items.extend(pair("current", "active result"));
    items.extend((0..8).map(|_| message("assistant", "Recent text")));
    items
}

#[test]
fn only_complete_older_groups_are_candidates() {
    let mut items = history();
    items.insert(1, item(json!({"type":"function_call", "name":"shell", "call_id":"incomplete", "arguments":"{}"})));
    let groups = candidate_groups(&items);
    assert_eq!(groups, vec![vec![2, 3]]);
}

#[test]
fn summary_marker_does_not_unpin_current_turn_tools() {
    let mut items = history();
    items.push(message(
        "user",
        &format!(
            "{}\nArchived tool exchanges",
            crate::compact::SUMMARY_PREFIX
        ),
    ));
    assert_eq!(candidate_groups(&items), vec![vec![1, 2]]);
}

#[test]
fn ambiguous_or_cross_boundary_groups_are_pinned() {
    let mut items = history();
    items.push(items[2].clone());
    assert_eq!(candidate_groups(&items), Vec::<Vec<usize>>::new());
    let mut items = history();
    items[2] =
        item(json!({"type":"custom_tool_call_output", "call_id":"old", "output":"mixed type"}));
    assert_eq!(candidate_groups(&items), Vec::<Vec<usize>>::new());
}

#[test]
fn replacement_preserves_all_text_order_ids_and_metadata() {
    let mut items = history();
    items[3].metadata = Some(codex_history::CodexHarnessMetadata {
        client_authored: true,
        ..Default::default()
    });
    let marker = message("user", "Archived tool data: /tmp/archive.json");
    let mut expected = items.clone();
    expected.drain(1..3);
    expected.push(marker.clone());
    let mut retained = items.clone();
    retained.drain(1..3);
    assert_eq!(replacement(&items, &retained, marker), Some(expected));
}

#[test]
fn insufficient_reduction_keeps_original_history() {
    let mut items = history();
    items[2] = pair("old", "tiny").remove(1);
    let mut retained = items.clone();
    retained.drain(1..3);
    assert_eq!(
        replacement(&items, &retained, message("user", "archive reference")),
        None
    );
}

// Exercises live session history replacement, private recovery, and the actual next request.
// Removing only an output, rewriting retained text, or omitting the checkpoint marker breaks it.
#[tokio::test]
async fn successful_compaction_preserves_next_request_and_recoverable_history() -> anyhow::Result<()>
{
    use crate::session::tests::make_session_and_context_with_auth_and_config_and_rx;
    use codex_login::CodexAuth;
    use codex_model_provider_info::ModelProviderInfo;
    use core_test_support::responses;
    use futures::StreamExt;
    use wiremock::Mock;
    use wiremock::ResponseTemplate;
    use wiremock::matchers::path;

    let server = responses::start_mock_server().await;
    Mock::given(path("/jev"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({"answers":{
            "remove_0":{"type":"noul","noul":0.99},
            "safe_together":{"type":"noul","noul":0.99}
        }})))
        .mount(&server)
        .await;
    let mut provider =
        ModelProviderInfo::create_openai_provider(Some(format!("{}/v1", server.uri())));
    provider.supports_websockets = false;
    let (session, turn, _events) = make_session_and_context_with_auth_and_config_and_rx(
        CodexAuth::create_dummy_chatgpt_auth_for_testing(),
        Vec::new(),
        move |config| {
            config.model_provider = provider;
            config.base_instructions = Some("Follow the user request".to_string());
            codex_config::jev::save_settings(
                &config.codex_home,
                &codex_config::jev::JevSettings {
                    tool_compression: false,
                    compaction: true,
                },
            )
            .unwrap();
        },
    )
    .await;
    codex_config::jev::save_settings(
        &turn.config.codex_home,
        &codex_config::jev::JevSettings {
            tool_compression: false,
            compaction: true,
        },
    )?;
    let home = tempfile::tempdir()?;
    let client = JevClient {
        home: home.path().to_path_buf(),
        api_key: "test-jev-secret".to_string(),
        http: codex_http_client::HttpClientBuilder::new().build_direct()?,
        endpoint: format!("{}/jev", server.uri()),
    };
    session
        .record_conversation_items(
            &turn,
            turn.model_info(),
            &history()
                .into_iter()
                .map(ResponseItemEnvelope::into_item)
                .collect::<Vec<_>>(),
        )
        .await;
    let initial = session.clone_history().await;
    let baseline = crate::context::world_state::WorldStateSnapshot::from(
        json!({"test":{"state":"preserved"}}).as_object().unwrap(),
    );
    let (window_number, window_ids) = session.advance_auto_compact_window().await;
    let mut checkpoint_history = initial.annotated_items().to_vec();
    checkpoint_history.push(item(
        json!({"type":"compaction","encrypted_content":"opaque-checkpoint"}),
    ));
    session
        .replace_compacted_history(
            checkpoint_history,
            Some(turn.to_turn_context_item()),
            Some(baseline.clone()),
            CompactedHistoryMetadata {
                message: String::new(),
                window_number,
                window_ids,
                compaction_response_id: None,
                compaction_model_hash: Some("original-producer".to_string()),
                reviewer_compaction_hash: None,
            },
        )
        .await;
    let before = session.clone_history().await;
    assert!(try_compact_with_client(&session, &turn, CompactionTrigger::Manual, &client).await?);
    let after = session.clone_history().await;
    assert_eq!(after.world_state_baseline(), Some(&baseline));
    assert_eq!(
        session.reference_context_item().await,
        Some(turn.to_turn_context_item())
    );
    let mut expected = before.annotated_items().to_vec();
    expected.drain(1..3);
    assert_eq!(
        &after.annotated_items()[..expected.len()],
        expected.as_slice()
    );
    assert_eq!(after.annotated_items().len(), expected.len() + 1);
    let archive_path = std::fs::read_dir(home.path().join("jev-originals"))?
        .next()
        .unwrap()?
        .path();
    let archived: Vec<codex_history::RolloutItem> =
        serde_json::from_slice(&std::fs::read(archive_path)?)?;
    let recovered = archived
        .into_iter()
        .map(|item| match item {
            codex_history::RolloutItem::ResponseItem(item) => item,
            _ => panic!("unexpected recovery item"),
        })
        .collect::<Vec<_>>();
    assert_eq!(recovered, before.annotated_items());

    let capture = responses::mount_sse_once(
        &server,
        responses::sse(vec![responses::ev_completed("after-jev")]),
    )
    .await;
    let prompt = crate::Prompt {
        input: after.raw_items().cloned().collect(),
        ..Default::default()
    };
    let metadata = crate::responses_metadata::CodexResponsesMetadata::new(
        "installation".to_string(),
        "session".to_string(),
        "thread".to_string(),
        "window".to_string(),
    );
    let mut model_session = session.services.model_client.new_session();
    let mut stream = model_session
        .stream(
            &prompt,
            turn.model_info(),
            &turn.session_telemetry,
            /*effort*/ None,
            turn.reasoning_summary(),
            /*service_tier*/ None,
            &metadata,
            &codex_rollout_trace::InferenceTraceContext::disabled(),
        )
        .await?;
    while let Some(event) = stream.next().await {
        event?;
    }
    let input = capture.single_request().body_json()["input"].clone();
    let serialized = serde_json::to_string(&input)?;
    assert!(!serialized.contains("obsolete log"));
    assert!(serialized.contains("Keep this conclusion"));
    assert!(serialized.contains("Current task"));
    assert!(serialized.contains("active result"));
    assert!(serialized.contains("Original history is archived locally"));
    assert_eq!(
        input
            .as_array()
            .unwrap()
            .iter()
            .filter_map(|item| item.get("call_id").and_then(serde_json::Value::as_str))
            .collect::<Vec<_>>(),
        vec!["current", "current"]
    );
    Ok(())
}

#[test_case::test_case(0.94, 0.99; "individual judgment rejects")]
#[test_case::test_case(0.99, 0.94; "combined judgment rejects")]
#[tokio::test]
async fn rejected_judgment_leaves_session_unchanged(first: f64, second: f64) -> anyhow::Result<()> {
    use crate::session::tests::make_session_and_context_with_auth_and_config_and_rx;
    use codex_login::CodexAuth;
    use core_test_support::responses;
    use wiremock::Mock;
    use wiremock::ResponseTemplate;
    use wiremock::matchers::path;
    let server = responses::start_mock_server().await;
    Mock::given(path("/jev"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({"answers":{
            "remove_0":{"type":"noul","noul":first},
            "safe_together":{"type":"noul","noul":second}
        }})))
        .mount(&server)
        .await;
    let (session, turn, _events) = make_session_and_context_with_auth_and_config_and_rx(
        CodexAuth::create_dummy_chatgpt_auth_for_testing(),
        Vec::new(),
        |config| {
            config.base_instructions = Some("Follow the user request".to_string());
            codex_config::jev::save_settings(
                &config.codex_home,
                &codex_config::jev::JevSettings {
                    tool_compression: false,
                    compaction: true,
                },
            )
            .unwrap();
        },
    )
    .await;
    codex_config::jev::save_settings(
        &turn.config.codex_home,
        &codex_config::jev::JevSettings {
            tool_compression: false,
            compaction: true,
        },
    )?;
    let home = tempfile::tempdir()?;
    let client = JevClient {
        home: home.path().to_path_buf(),
        api_key: "test-jev-secret".to_string(),
        http: codex_http_client::HttpClientBuilder::new().build_direct()?,
        endpoint: format!("{}/jev", server.uri()),
    };
    session
        .record_conversation_items(
            &turn,
            turn.model_info(),
            &history()
                .into_iter()
                .map(ResponseItemEnvelope::into_item)
                .collect::<Vec<_>>(),
        )
        .await;
    let before = session.clone_history().await;
    assert!(!try_compact_with_client(&session, &turn, CompactionTrigger::Auto, &client).await?);
    assert_eq!(
        session.clone_history().await.annotated_items(),
        before.annotated_items()
    );
    assert!(!home.path().join("jev-originals").exists());
    Ok(())
}

#[test]
fn oversized_retained_tool_output_does_not_hide_obsolete_candidate() {
    let mut items = history();
    items.splice(1..1, pair("oversized", &"retained output ".repeat(20_000)));
    let (state, groups) = judgment_state(
        &items,
        json!({"text":"system instructions"}),
        &HashSet::new(),
    )
    .unwrap();
    assert_eq!(groups, vec![vec![3, 4]]);
    assert!(serde_json::to_vec(&state).unwrap().len() < MAX_STATE_BYTES);
    assert!(!state.to_string().contains("retained output"));
    assert!(state.to_string().contains("Keep this conclusion"));
}

#[test]
fn structured_results_and_oversized_instructions_are_never_pruned() {
    let mut items = history();
    items[2] = pair("old", r#"{"rows":[1,2,3]}"#).remove(1);
    assert_eq!(candidate_groups(&items), Vec::<Vec<usize>>::new());
    assert!(
        judgment_state(
            &history(),
            json!({"text":"instructions ".repeat(20_000)}),
            &HashSet::new()
        )
        .is_none()
    );
}

#[test]
fn code_mode_text_blocks_are_grouped_but_media_remains_pinned() {
    let mut items = history();
    items[1] = item(
        json!({"type":"custom_tool_call","name":"exec","call_id":"old","input":"await tools.exec_command(...)"}),
    );
    items[2] = item(
        json!({"type":"custom_tool_call_output","call_id":"old","output":[
            {"type":"input_text","text":"Completed in 1 sec"},
            {"type":"input_text","text":r#"{"wall_time_seconds":1,"exit_code":0,"output":"obsolete output"}"#}
        ]}),
    );
    assert_eq!(candidate_groups(&items), vec![vec![1, 2]]);
    items[2] = item(
        json!({"type":"custom_tool_call_output","call_id":"old","output":[
            {"type":"input_text","text":"Completed"},
            {"type":"input_image","image_url":"data:image/png;base64,YQ=="}
        ]}),
    );
    assert_eq!(candidate_groups(&items), Vec::<Vec<usize>>::new());
}

#[tokio::test]
async fn sequential_batches_judge_only_history_remaining_after_prior_removal() -> anyhow::Result<()>
{
    use core_test_support::responses;
    use wiremock::Mock;
    use wiremock::ResponseTemplate;
    use wiremock::matchers::path;
    let server = responses::start_mock_server().await;
    Mock::given(path("/jev"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({"answers":{
            "remove_0":{"type":"noul","noul":0.99},
            "safe_together":{"type":"noul","noul":0.99}
        }})))
        .mount(&server)
        .await;
    let home = tempfile::tempdir()?;
    let client = JevClient {
        home: home.path().to_path_buf(),
        api_key: "test-jev-secret".to_string(),
        http: codex_http_client::HttpClientBuilder::new().build_direct()?,
        endpoint: format!("{}/jev", server.uri()),
    };
    let mut items = vec![message("user", "Old task")];
    items.extend(pair("batch-one", &"first obsolete ".repeat(4_000)));
    items.extend(pair("batch-two", &"second obsolete ".repeat(4_000)));
    items.push(message("user", "Current task"));
    items.extend((0..8).map(|_| message("assistant", "Retained text")));
    let retained = select_history(&client, &items, json!({"text":"instructions"}))
        .await
        .unwrap();
    let mut expected = items.clone();
    expected.drain(1..5);
    assert_eq!(retained, expected);
    let requests = server.received_requests().await.unwrap();
    assert_eq!(requests.len(), 4);
    let third: serde_json::Value = serde_json::from_slice(&requests[2].body)?;
    assert!(!third.to_string().contains("batch-one"));
    assert!(third.to_string().contains("batch-two"));
    assert!(!home.path().join("jev-originals").exists());
    Ok(())
}

#[test]
fn judgment_omits_retained_image_bytes_and_opaque_checkpoints_without_mutating_history() {
    let mut items = history();
    let image_url = format!("data:image/png;base64,{}", "a".repeat(200_000));
    items.insert(
        0,
        item(json!({"type":"message", "role":"user", "content":[
            {"type":"input_text","text":"Preserve the screenshot's layout"},
            {"type":"input_image","image_url":image_url}
        ]})),
    );
    items.insert(
        1,
        item(json!({"type":"compaction","encrypted_content":"opaque".repeat(20_000)})),
    );
    let before = items.clone();
    let (state, candidates) = judgment_state(&items, json!("Follow the request"), &HashSet::new())
        .expect("retained binary data must not exhaust the judgment budget");
    let encoded = serde_json::to_string(&state).unwrap();
    assert!(encoded.len() < MAX_STATE_BYTES);
    assert!(!encoded.contains("data:image"));
    assert!(!encoded.contains(&"opaque".repeat(100)));
    assert!(encoded.contains("Preserve the screenshot's layout"));
    assert!(encoded.contains("unavailable_to_judge"));
    assert_eq!(candidates, vec![vec![3, 4]]);
    assert_eq!(items, before);
}
