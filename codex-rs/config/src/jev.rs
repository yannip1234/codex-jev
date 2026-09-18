//! Local Jev preferences and private credentials, separate from model-visible configuration.
use serde::Deserialize;
use serde::Serialize;
use std::fs;
use std::fs::OpenOptions;
use std::io;
use std::io::Write;
use std::path::Path;
use std::sync::atomic::AtomicU64;
use std::sync::atomic::Ordering;

const SETTINGS_FILE: &str = "jev-settings.json";
const API_KEY_FILE: &str = "jev-api-key";
const MAX_KEY_BYTES: usize = 8192;

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(default)]
pub struct JevSettings {
    pub tool_compression: bool,
    pub compaction: bool,
}

impl Default for JevSettings {
    fn default() -> Self {
        Self {
            tool_compression: true,
            compaction: true,
        }
    }
}

pub fn load_settings(codex_home: &Path) -> JevSettings {
    fs::read(codex_home.join(SETTINGS_FILE))
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_default()
}

pub fn save_settings(codex_home: &Path, settings: &JevSettings) -> io::Result<()> {
    atomic_write(
        codex_home,
        SETTINGS_FILE,
        &serde_json::to_vec_pretty(settings)?,
    )
}

/// The valid saved Settings key takes precedence; neither source is logged or included in settings Debug.
pub fn load_api_key(codex_home: &Path) -> Option<String> {
    load_api_key_with_env(codex_home, std::env::var("TYPESAFE_API_KEY").ok())
}

fn load_api_key_with_env(codex_home: &Path, environment_key: Option<String>) -> Option<String> {
    fs::read_to_string(codex_home.join(API_KEY_FILE))
        .ok()
        .as_deref()
        .and_then(valid_key)
        .map(str::to_owned)
        .or_else(|| {
            environment_key
                .as_deref()
                .and_then(valid_key)
                .map(str::to_owned)
        })
}

pub fn save_api_key(codex_home: &Path, key: &str) -> io::Result<()> {
    let key = valid_key(key).ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "Enter a nonempty API key without whitespace",
        )
    })?;
    atomic_write(codex_home, API_KEY_FILE, key.as_bytes())
}

pub fn remove_api_key(codex_home: &Path) -> io::Result<()> {
    match fs::remove_file(codex_home.join(API_KEY_FILE)) {
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        result => result,
    }
}

fn valid_key(key: &str) -> Option<&str> {
    let key = key.trim();
    (!key.is_empty()
        && key.len() <= MAX_KEY_BYTES
        && !key.chars().any(char::is_whitespace)
        && !key.chars().any(char::is_control))
    .then_some(key)
}

fn atomic_write(codex_home: &Path, name: &str, bytes: &[u8]) -> io::Result<()> {
    static NEXT_TEMP_ID: AtomicU64 = AtomicU64::new(0);
    fs::create_dir_all(codex_home)?;
    // Exclusive creation prevents following a planted temporary-file symlink. The replacement
    // inode is private from creation, including when replacing an older permissive key file.
    let (temporary_path, mut file) = loop {
        let id = NEXT_TEMP_ID.fetch_add(1, Ordering::Relaxed);
        let path = codex_home.join(format!(".{name}.{}.{id}.tmp", std::process::id()));
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        match options.open(&path) {
            Ok(file) => break (path, file),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error),
        }
    };
    let result = (|| {
        file.write_all(bytes)?;
        file.sync_all()?;
        drop(file);
        fs::rename(&temporary_path, codex_home.join(name))
    })();
    if result.is_err() {
        let _ = fs::remove_file(temporary_path);
    }
    result
}

#[cfg(test)]
#[path = "jev_tests.rs"]
mod tests;
