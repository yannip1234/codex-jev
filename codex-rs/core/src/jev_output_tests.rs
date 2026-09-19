use super::*;
use pretty_assertions::assert_eq;
use serde_json::json;
use wiremock::Mock;
use wiremock::MockServer;
use wiremock::ResponseTemplate;
use wiremock::matchers::method;

#[tokio::test]
async fn compression_keeps_errors_and_exact_source_and_archives_original() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .respond_with(|request: &wiremock::Request| {
            let payload: Value = request.body_json().unwrap();
            let answers = payload["questions"]
                .as_object()
                .unwrap()
                .keys()
                .map(|key| (key.clone(), json!({"type":"noul","noul":0.99})))
                .collect::<serde_json::Map<_, _>>();
            ResponseTemplate::new(200).set_body_json(json!({"answers":answers}))
        })
        .mount(&server)
        .await;
    let home = tempfile::tempdir().unwrap();
    let client = crate::jev::JevClient {
        home: home.path().to_path_buf(),
        api_key: "fixture-secret".into(),
        endpoint: server.uri(),
        http: codex_http_client::HttpClientFactory::new(
            codex_http_client::OutboundProxyPolicy::ReqwestDefault,
        )
        .build_client_without_request_logging(
            &server.uri(),
            codex_http_client::ClientRouteClass::Other,
        )
        .unwrap(),
    };
    let mut original = "Build started\n".to_string();
    for n in 0..240 {
        original.push_str(&format!(
            "Progress {n}: repeated incidental build status without a diagnostic.\n"
        ));
    }
    original.push_str("ERROR: missing symbol exact_identifier_123\nBuild finished\n");
    let result = compress_text(&client, &original, "Fix build")
        .await
        .unwrap();
    assert!(result.contains("ERROR: missing symbol exact_identifier_123"));
    assert!(result.contains("Build started"));
    assert!(result.contains("Build finished"));
    assert!(result.len() * 4 < original.len() * 3);
    let files = std::fs::read_dir(home.path().join("jev-originals"))
        .unwrap()
        .collect::<Vec<_>>();
    assert_eq!(files.len(), 1);
    assert_eq!(
        std::fs::read_to_string(files[0].as_ref().unwrap().path()).unwrap(),
        original
    );
}

#[tokio::test]
async fn skips_structured_small_and_credential_outputs_without_network() {
    let server = MockServer::start().await;
    let home = tempfile::tempdir().unwrap();
    let client = crate::jev::JevClient {
        home: home.path().into(),
        api_key: "fixture-secret".into(),
        endpoint: server.uri(),
        http: codex_http_client::HttpClientFactory::new(
            codex_http_client::OutboundProxyPolicy::ReqwestDefault,
        )
        .build_client_without_request_logging(
            &server.uri(),
            codex_http_client::ClientRouteClass::Other,
        )
        .unwrap(),
    };
    for text in [
        "small".to_owned(),
        json!({"data":"x".repeat(12000)}).to_string(),
        format!("fixture-secret{}", "x".repeat(12000)),
    ] {
        assert_eq!(compress_text(&client, &text, "goal").await, None);
    }
    assert!(server.received_requests().await.unwrap().is_empty());
}

#[test_case::test_case(false; "completed command")]
#[test_case::test_case(true; "running command")]
#[tokio::test]
async fn final_code_mode_output_preserves_envelope_and_structured_exit_status(running: bool) {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .respond_with(|request: &wiremock::Request| {
            let payload: Value = request.body_json().unwrap();
            let answers = payload["questions"]
                .as_object()
                .unwrap()
                .keys()
                .map(|key| (key.clone(), json!({"type":"noul","noul":0.99})))
                .collect::<serde_json::Map<_, _>>();
            ResponseTemplate::new(200).set_body_json(json!({"answers":answers}))
        })
        .mount(&server)
        .await;
    let home = tempfile::tempdir().unwrap();
    let client = crate::jev::JevClient {
        home: home.path().into(),
        api_key: "fixture-secret".into(),
        endpoint: server.uri(),
        http: codex_http_client::HttpClientFactory::new(
            codex_http_client::OutboundProxyPolicy::ReqwestDefault,
        )
        .build_client_without_request_logging(
            &server.uri(),
            codex_http_client::ClientRouteClass::Other,
        )
        .unwrap(),
    };
    let original =
        "incidental progress line with no unique relevant facts in this log\n".repeat(240);
    let mut wrapper =
        json!({"output":original,"exit_code":0,"wall_time_seconds":0.2,"chunk_id":"chunk-123"});
    if running {
        wrapper.as_object_mut().unwrap().remove("exit_code");
        wrapper["session_id"] = json!(42);
    }
    let header = "Script completed\nWall time 0.2 seconds\nOutput:\n";
    let mut envelope = ResponseItemEnvelope::new(serde_json::from_value(json!({"type":"custom_tool_call_output","call_id":"code-cell","name":"exec","output":[{"type":"input_text","text":header},{"type":"input_text","text":wrapper.to_string()}]})).unwrap());
    envelope.set_turn_id_if_missing("turn-1");
    let saved_metadata = envelope.metadata.clone();
    let mut items = vec![envelope];
    compress_with_client(&client, "Inspect build progress", &mut items).await;
    assert_eq!(items[0].metadata, saved_metadata);
    let ResponseItem::CustomToolCallOutput {
        call_id, output, ..
    } = &items[0].item
    else {
        panic!("changed item kind")
    };
    assert_eq!(call_id, "code-cell");
    let parts = output.content_items().unwrap();
    assert_eq!(parts.len(), 2);
    assert_eq!(
        parts[0],
        FunctionCallOutputContentItem::InputText {
            text: header.into()
        }
    );
    let FunctionCallOutputContentItem::InputText { text: result_text } = &parts[1] else {
        panic!("lost text block")
    };
    let result: Value = serde_json::from_str(result_text).unwrap();
    let mut expected = wrapper;
    expected["output"] = result["output"].clone();
    assert_eq!(result, expected);
    assert!(result["output"].as_str().unwrap().len() < original.len() / 2);

    // Recording uses the real final-history path and preserves the shortened code-mode result.
    let (session, turn) = crate::session::tests::make_session_and_context().await;
    session
        .record_conversation_items(&turn, turn.model_info(), &[items[0].item.clone()])
        .await;
    let history = session.clone_history().await;
    let ResponseItem::CustomToolCallOutput {
        output: recorded, ..
    } = history.raw_items().last().unwrap()
    else {
        panic!("missing result")
    };
    assert_eq!(recorded, output);
}

#[tokio::test]
async fn combined_verification_failure_keeps_original_and_creates_no_archive() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .respond_with(|request: &wiremock::Request| {
            let payload: Value = request.body_json().unwrap();
            let answers = payload["questions"]
                .as_object()
                .unwrap()
                .keys()
                .map(|key| {
                    (
                        key.clone(),
                        json!({"type":"noul","noul":if key=="preserved" {0.1} else {0.99}}),
                    )
                })
                .collect::<serde_json::Map<_, _>>();
            ResponseTemplate::new(200).set_body_json(json!({"answers":answers}))
        })
        .mount(&server)
        .await;
    let home = tempfile::tempdir().unwrap();
    let client = crate::jev::JevClient {
        home: home.path().into(),
        api_key: "fixture-secret".into(),
        endpoint: server.uri(),
        http: codex_http_client::HttpClientFactory::new(
            codex_http_client::OutboundProxyPolicy::ReqwestDefault,
        )
        .build_client_without_request_logging(
            &server.uri(),
            codex_http_client::ClientRouteClass::Other,
        )
        .unwrap(),
    };
    let original =
        "Repeated text with meaning that a combined verification must preserve.\n".repeat(240);
    assert_eq!(compress_text(&client, &original, "goal").await, None);
    assert!(!home.path().join("jev-originals").exists());
}

#[test]
fn compaction_housekeeping_does_not_replace_user_requirements() {
    use crate::context::CompactionSummary;
    use crate::context::ContextualUserFragment;
    let user = |text: &str| {
        ResponseItemEnvelope::new(serde_json::from_value(json!({"type":"message","role":"user","content":[{"type":"input_text","text":text}]})).unwrap())
    };
    let items = vec![
        user("Use Python only."),
        user("Fix the build."),
        ResponseItemEnvelope::new(ContextualUserFragment::into(CompactionSummary::new(
            format!(
                "{}\nArchived older results at /tmp/log",
                crate::compact::SUMMARY_PREFIX
            ),
        ))),
    ];
    assert_eq!(
        compression_goal(&items),
        Some("Use Python only.\nFix the build.\n".into())
    );
    let long_requirements = "Keep this exact requirement. ".repeat(800);
    assert_eq!(
        compression_goal(&[user(&long_requirements)]),
        Some(format!("{long_requirements}\n"))
    );
    assert_eq!(compression_goal(&[user(&"x".repeat(64_001))]), None);
}

#[tokio::test]
async fn exact_duplicate_proposal_retains_blocks_and_repetition_references_and_requires_verification()
 {
    let server = MockServer::start().await;
    let home = tempfile::tempdir().unwrap();
    let client = crate::jev::JevClient {
        home: home.path().into(),
        api_key: "fixture-secret".into(),
        endpoint: server.uri(),
        http: codex_http_client::HttpClientBuilder::new()
            .build_direct()
            .unwrap(),
    };
    let original = format!(
        "Start\n{}FINAL_STATUS=OK\n",
        "Incidental progress; waiting for completion with nothing new to report.\n".repeat(240)
    );
    for confidence in [0.84, 0.89] {
        server.reset().await;
        Mock::given(method("POST"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({"answers":{
                "preserved":{"type":"noul","noul":confidence}
            }})))
            .mount(&server)
            .await;
        let result = compress_text(&client, &original, "Report FINAL_STATUS").await;
        assert_eq!(result.is_some(), confidence >= 0.85);
        if let Some(result) = result {
            assert!(result.contains("Start\n"));
            assert!(result.contains("FINAL_STATUS=OK\n"));
            assert!(result.contains("repeat lines 13-24 verbatim"));
            assert!(result.contains(
                "Incidental progress; waiting for completion with nothing new to report.\n"
            ));
            assert!(result.len() < original.len() / 2);
            // Independently expand the source-line representation and recover the exact log.
            let lines = result.split_inclusive('\n').collect::<Vec<_>>();
            let mut restored = Vec::new();
            let mut cursor = 1; // recovery-file reference
            while cursor < lines.len() {
                let header = lines[cursor].trim();
                let numbers = header
                    .split(|c: char| !c.is_ascii_digit())
                    .filter(|part| !part.is_empty())
                    .map(|part| part.parse::<usize>().unwrap())
                    .collect::<Vec<_>>();
                cursor += 1;
                assert_eq!(numbers[0], restored.len() + 1);
                if numbers.len() == 4 {
                    let repeated = restored[numbers[2] - 1..numbers[3]].to_vec();
                    assert_eq!(repeated.len(), numbers[1] - numbers[0] + 1);
                    restored.extend(repeated);
                } else {
                    assert_eq!(numbers.len(), 2);
                    let count = numbers[1] - numbers[0] + 1;
                    restored.extend_from_slice(&lines[cursor..cursor + count]);
                    cursor += count;
                }
            }
            assert_eq!(restored.concat(), original);
        }
        let requests = server.received_requests().await.unwrap();
        assert_eq!(requests.len(), 1);
        let payload: Value = requests[0].body_json().unwrap();
        assert_eq!(payload["questions"].as_object().unwrap().len(), 1);
    }
}

#[tokio::test]
#[ignore = "requires TYPESAFE_API_KEY and makes a live Jev request"]
async fn live_jev_duplicate_tool_compaction() {
    let home = tempfile::tempdir().unwrap();
    let client = JevClient::from_home(home.path()).expect("configure TYPESAFE_API_KEY");
    let text = format!(
        "Build started\n{}FINAL_STATUS=OK\n",
        "Incidental progress; waiting for completion with nothing new to report.\n".repeat(240)
    );
    let result = compress_text(
        &client,
        &text,
        "Report FINAL_STATUS from the build log. Repeated progress lines are incidental.",
    )
    .await
    .expect("live duplicate proposal should preserve the final status");
    assert!(result.contains("FINAL_STATUS=OK"));
    assert!(result.len() * 4 < text.len() * 3);
}
