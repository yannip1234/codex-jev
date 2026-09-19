//! Bounded Jev judgments and private recovery files for the optional custom harness.
//!
//! Credentials and response bodies are deliberately excluded from diagnostic logging.
use std::io::Write;
use std::path::Path;
use std::path::PathBuf;
use std::time::Duration;

use codex_http_client::ClientRouteClass;
use codex_http_client::HttpClient;
use codex_http_client::HttpClientBuilder;
use codex_http_client::HttpClientFactory;
use codex_http_client::OutboundProxyPolicy;
use serde_json::Value;
use serde_json::json;

pub(crate) struct JevClient {
    pub(crate) home: PathBuf,
    pub(crate) api_key: String,
    pub(crate) http: HttpClient,
    pub(crate) endpoint: String,
}

impl JevClient {
    pub(crate) fn from_home(home: &Path) -> Option<Self> {
        let api_key = codex_config::jev::load_api_key(home)?;
        let endpoint = "https://api.typesafe.ai/v1/systemone".to_owned();
        let factory = HttpClientFactory::new(OutboundProxyPolicy::RespectSystemProxy);
        let http = HttpClientBuilder::new()
            .without_request_logging()
            .without_redirects()
            .connect_timeout(Duration::from_secs(5))
            .build_respecting_outbound_proxy_policy(&factory, &endpoint, ClientRouteClass::Other)
            .ok()?;
        Some(Self {
            home: home.to_path_buf(),
            api_key,
            http,
            endpoint,
        })
    }

    /// Returns strictly validated Noul probabilities in the caller's question order.
    pub(crate) async fn judge(
        &self,
        state: Value,
        questions: Vec<(String, String)>,
    ) -> Option<Vec<f64>> {
        if self.api_key.is_empty() || questions.is_empty() || questions.len() > 48 {
            return None;
        }
        let entries = questions
            .iter()
            .map(|(id, instructions)| {
                (
                    id.clone(),
                    json!({"type":"noul","instructions":instructions}),
                )
            })
            .collect::<serde_json::Map<_, _>>();
        if entries.len() != questions.len() {
            return None;
        }
        let payload = json!({"model":"jev-latest","state":state,"questions":entries});
        let encoded = serde_json::to_vec(&payload).ok()?;
        if encoded.len() > 120_000
            || encoded
                .windows(self.api_key.len())
                .any(|s| s == self.api_key.as_bytes())
        {
            return None;
        }
        let component = if payload["state"].get("goal").is_some() {
            "tool_output"
        } else {
            "history"
        };
        record_activity(
            &self.home,
            component,
            "api_started",
            "jev_api_request",
            /*tokens*/ None,
        );
        let result = tokio::time::timeout(Duration::from_secs(15), async {
            let mut response = self
                .http
                .post(&self.endpoint)
                .bearer_auth(&self.api_key)
                .json(&payload)
                .timeout(Duration::from_secs(15))
                .send()
                .await
                .ok()?;
            if !response.status().is_success() {
                return None;
            }
            let mut bytes = Vec::new();
            while let Some(chunk) = response.chunk().await.ok()? {
                if bytes.len() + chunk.len() > 65_536 {
                    return None;
                }
                bytes.extend_from_slice(&chunk);
            }
            let body: Value = serde_json::from_slice(&bytes).ok()?;
            let answers = body.get("answers")?.as_object()?;
            questions
                .iter()
                .map(|(id, _)| {
                    let answer = answers.get(id)?;
                    if answer.get("type")?.as_str()? != "noul" {
                        return None;
                    }
                    let probability = answer.get("noul")?.as_f64()?;
                    (probability.is_finite() && (0.0..=1.0).contains(&probability))
                        .then_some(probability)
                })
                .collect()
        })
        .await
        .ok()
        .flatten();
        record_activity(
            &self.home,
            component,
            "api_completed",
            if result.is_some() {
                "valid_response"
            } else {
                "api_failed_or_invalid_response"
            },
            /*tokens*/ None,
        );
        result
    }

    /// Saves exact source bytes before any accepted omission. Never follows a chosen filename.
    pub(crate) fn archive(&self, kind: &str, data: &[u8]) -> Option<PathBuf> {
        if !matches!(kind, "tool" | "history") || data.len() > 32 * 1024 * 1024 {
            return None;
        }
        let dir = self.home.join("jev-originals");
        if std::fs::symlink_metadata(&dir).is_ok_and(|metadata| metadata.file_type().is_symlink()) {
            return None;
        }
        std::fs::create_dir_all(&dir).ok()?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o700)).ok()?;
        }
        let path = dir.join(format!("{kind}-{}.txt", uuid::Uuid::new_v4()));
        let mut options = std::fs::OpenOptions::new();
        options.create_new(true).write(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut file = options.open(&path).ok()?;
        if file.write_all(data).and_then(|()| file.sync_all()).is_err() {
            let _ = std::fs::remove_file(&path);
            return None;
        }
        Some(path)
    }
}

#[cfg(test)]
#[path = "jev_tests.rs"]
mod tests;

/// Private metadata only; never accepts message bodies or credentials as log fields.
pub(crate) fn record_activity(
    home: &Path,
    component: &'static str,
    event: &'static str,
    reason: &'static str,
    tokens: Option<(usize, usize)>,
) {
    let _ = (|| -> std::io::Result<()> {
        let directory = home.join("jev-bridge");
        if std::fs::symlink_metadata(&directory).is_ok_and(|m| m.file_type().is_symlink()) {
            return Ok(());
        }
        std::fs::create_dir_all(&directory)?;
        let mut options = std::fs::OpenOptions::new();
        options.append(true).create(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&directory, std::fs::Permissions::from_mode(0o700))?;
            options.mode(0o600).custom_flags(libc::O_NOFOLLOW);
        }
        let mut log = options.open(directory.join("engine-activity.jsonl"))?;
        let mut entry = json!({"time":chrono::Utc::now().timestamp_millis() as f64 / 1000.0,
            "component":component,"event":event,"reason":reason});
        if let Some((before, after)) = tokens {
            entry["originalTokens"] = json!(before);
            entry["compactedTokens"] = json!(after);
        }
        let mut bytes = serde_json::to_vec(&entry)?;
        bytes.push(b'\n');
        log.write_all(&bytes)
    })();
}
