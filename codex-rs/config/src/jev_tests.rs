use super::*;
use pretty_assertions::assert_eq;

#[test]
fn settings_round_trip_and_missing_defaults() {
    let home = tempfile::tempdir().unwrap();
    assert_eq!(load_settings(home.path()), JevSettings::default());
    let settings = JevSettings {
        tool_compression: false,
        compaction: true,
    };
    save_settings(home.path(), &settings).unwrap();
    assert_eq!(load_settings(home.path()), settings);
}

#[test]
fn saved_key_is_trimmed_replaced_and_removed() {
    let home = tempfile::tempdir().unwrap();
    save_api_key(home.path(), "  test-secret-one\n").unwrap();
    assert_eq!(
        load_api_key_with_env(home.path(), /*environment_key*/ None),
        Some("test-secret-one".into())
    );
    save_api_key(home.path(), "test-secret-two").unwrap();
    assert_eq!(
        load_api_key_with_env(home.path(), /*environment_key*/ None),
        Some("test-secret-two".into())
    );
    remove_api_key(home.path()).unwrap();
    remove_api_key(home.path()).unwrap();
    assert_eq!(
        load_api_key_with_env(home.path(), /*environment_key*/ None),
        None
    );
}

#[test]
fn saved_key_takes_precedence_and_environment_is_a_fallback() {
    let home = tempfile::tempdir().unwrap();
    save_api_key(home.path(), "saved-secret").unwrap();
    assert_eq!(
        load_api_key_with_env(home.path(), Some(" env-secret ".into())),
        Some("saved-secret".into())
    );
    assert_eq!(
        load_api_key_with_env(home.path(), Some(" ".into())),
        Some("saved-secret".into())
    );
}

#[test]
fn missing_or_invalid_saved_key_uses_environment_and_replacement_applies_immediately() {
    let home = tempfile::tempdir().unwrap();
    let environment = Some(" env-secret ".to_owned());
    assert_eq!(
        load_api_key_with_env(home.path(), environment.clone()),
        Some("env-secret".into())
    );
    for invalid in ["", "two\nlines"] {
        std::fs::write(home.path().join("jev-api-key"), invalid).unwrap();
        assert_eq!(
            load_api_key_with_env(home.path(), environment.clone()),
            Some("env-secret".into())
        );
    }
    save_api_key(home.path(), "replacement-secret").unwrap();
    assert_eq!(
        load_api_key_with_env(home.path(), environment.clone()),
        Some("replacement-secret".into())
    );
    remove_api_key(home.path()).unwrap();
    assert_eq!(
        load_api_key_with_env(home.path(), environment),
        Some("env-secret".into())
    );
}

#[test]
fn invalid_key_does_not_replace_saved_key() {
    let home = tempfile::tempdir().unwrap();
    save_api_key(home.path(), "saved-secret").unwrap();
    for key in ["", "two\nlines", "tab\tinside"] {
        assert!(save_api_key(home.path(), key).is_err());
    }
    assert_eq!(
        load_api_key_with_env(home.path(), /*environment_key*/ None),
        Some("saved-secret".into())
    );
}

#[cfg(unix)]
#[test]
fn saved_key_and_replacement_are_private() {
    use std::os::unix::fs::PermissionsExt;
    let home = tempfile::tempdir().unwrap();
    let path = home.path().join("jev-api-key");
    std::fs::write(&path, "previous-secret").unwrap();
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o644)).unwrap();
    save_api_key(home.path(), "new-secret").unwrap();
    assert_eq!(
        std::fs::metadata(path).unwrap().permissions().mode() & 0o777,
        0o600
    );
    assert_eq!(std::fs::read_dir(home.path()).unwrap().count(), 1);
}

#[cfg(unix)]
#[test]
fn saving_replaces_key_symlink_without_modifying_its_target() {
    let home = tempfile::tempdir().unwrap();
    let target = home.path().join("other-file");
    std::fs::write(&target, "must-remain-unchanged").unwrap();
    std::os::unix::fs::symlink(&target, home.path().join("jev-api-key")).unwrap();
    save_api_key(home.path(), "new-secret").unwrap();
    assert_eq!(
        std::fs::read_to_string(target).unwrap(),
        "must-remain-unchanged"
    );
    assert_eq!(
        load_api_key_with_env(home.path(), /*environment_key*/ None),
        Some("new-secret".into())
    );
    assert!(
        !std::fs::symlink_metadata(home.path().join("jev-api-key"))
            .unwrap()
            .file_type()
            .is_symlink()
    );
}
