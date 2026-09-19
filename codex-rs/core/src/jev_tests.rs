use super::*;
use codex_http_client::OutboundProxyPolicy;
use pretty_assertions::assert_eq;
use serde_json::json;
use wiremock::Mock;
use wiremock::MockServer;
use wiremock::ResponseTemplate;
use wiremock::matchers::method;

#[tokio::test]
async fn rejects_incomplete_or_invalid_judgments() {
    let server = MockServer::start().await;
    let home = tempfile::tempdir().unwrap();
    let client = JevClient {
        home: home.path().to_path_buf(),
        api_key: "test-key".into(),
        http: codex_http_client::HttpClientFactory::new(OutboundProxyPolicy::ReqwestDefault)
            .build_client_without_request_logging(
                &server.uri(),
                codex_http_client::ClientRouteClass::Other,
            )
            .unwrap(),
        endpoint: server.uri(),
    };
    for response in [
        json!({"answers":{}}),
        json!({"answers":{"q":{"type":"noul","noul":1.5}}}),
        json!({"answers":{"q":{"type":"choice","noul":0.99}}}),
    ] {
        server.reset().await;
        Mock::given(method("POST"))
            .respond_with(ResponseTemplate::new(200).set_body_json(response))
            .mount(&server)
            .await;
        assert_eq!(
            client
                .judge(
                    json!({"context":"fixture"}),
                    vec![("q".into(), "Is it redundant?".into())]
                )
                .await,
            None
        );
    }
}

#[tokio::test]
async fn preserves_question_order_and_authenticates() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .respond_with(ResponseTemplate::new(200).set_body_json(
            json!({"answers":{"b":{"type":"noul","noul":0.25},"a":{"type":"noul","noul":0.98}}}),
        ))
        .mount(&server)
        .await;
    let home = tempfile::tempdir().unwrap();
    let client = JevClient {
        home: home.path().to_path_buf(),
        api_key: "fixture-secret".into(),
        endpoint: server.uri(),
        http: codex_http_client::HttpClientFactory::new(OutboundProxyPolicy::ReqwestDefault)
            .build_client_without_request_logging(
                &server.uri(),
                codex_http_client::ClientRouteClass::Other,
            )
            .unwrap(),
    };
    assert_eq!(
        client
            .judge(
                json!("fixture"),
                vec![("a".into(), "A?".into()), ("b".into(), "B?".into())]
            )
            .await,
        Some(vec![0.98, 0.25])
    );
    let requests = server.received_requests().await.unwrap();
    assert_eq!(
        requests[0].headers.get("authorization").unwrap(),
        "Bearer fixture-secret"
    );
    let path = client.archive("tool", b"original output").unwrap();
    assert_eq!(std::fs::read(&path).unwrap(), b"original output");
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        assert_eq!(
            std::fs::metadata(path).unwrap().permissions().mode() & 0o777,
            0o600
        );
    }
}

#[tokio::test]
async fn request_budget_prevents_network_and_http_failure_falls_back() {
    let server = MockServer::start().await;
    let home = tempfile::tempdir().unwrap();
    let client = JevClient {
        home: home.path().into(),
        api_key: "fixture-secret".into(),
        endpoint: server.uri(),
        http: codex_http_client::HttpClientFactory::new(OutboundProxyPolicy::ReqwestDefault)
            .build_client_without_request_logging(
                &server.uri(),
                codex_http_client::ClientRouteClass::Other,
            )
            .unwrap(),
    };
    assert_eq!(
        client
            .judge(
                json!("x".repeat(120_001)),
                vec![("q".into(), "Question?".into())]
            )
            .await,
        None
    );
    assert_eq!(
        client
            .judge(
                json!("fixture-secret"),
                vec![("q".into(), "Question?".into())]
            )
            .await,
        None
    );
    assert!(server.received_requests().await.unwrap().is_empty());
    Mock::given(method("POST"))
        .respond_with(ResponseTemplate::new(401).set_body_string("fixture-secret"))
        .mount(&server)
        .await;
    assert_eq!(
        client
            .judge(json!("fixture"), vec![("q".into(), "Question?".into())])
            .await,
        None
    );
}

#[tokio::test]
#[ignore = "requires an explicitly configured TYPESAFE_API_KEY and makes one live Jev request"]
async fn live_jev_client_accepts_real_api_response() {
    let home = tempfile::tempdir().unwrap();
    let client = JevClient::from_home(home.path()).expect("configure TYPESAFE_API_KEY");
    let answer = client
        .judge(
            json!({"message":"Hello, good morning."}),
            vec![("greeting".into(), "Does message contain a greeting?".into())],
        )
        .await
        .expect("live response should validate");
    assert_eq!(answer.len(), 1);
    assert!((0.0..=1.0).contains(&answer[0]));
}

#[test]
fn activity_records_only_metadata_and_token_counts() {
    let home = tempfile::tempdir().unwrap();
    record_activity(
        home.path(),
        "tool_output",
        "compacted",
        "verified_reduction",
        Some((100, 40)),
    );
    let path = home.path().join("jev-bridge/engine-activity.jsonl");
    let mut value: Value = serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
    assert!(value["time"].as_f64().is_some());
    value.as_object_mut().unwrap().remove("time");
    assert_eq!(
        value,
        json!({"component":"tool_output","event":"compacted","reason":"verified_reduction","originalTokens":100,"compactedTokens":40})
    );
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        assert_eq!(
            std::fs::metadata(path).unwrap().permissions().mode() & 0o777,
            0o600
        );
    }
}
