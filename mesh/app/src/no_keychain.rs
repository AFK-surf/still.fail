//! Claude Code on macOS keeps its login in the keychain, under a name made from its config directory's path, and falls
//! back to <config dir>/.credentials.json only when the keychain refuses. A profile's login has to live in its home: the
//! home is renamed after a sign-in (the keychain item stays behind under the old path), quota reads the file, and a
//! keychain item is out of reach of the station's other processes. So profile processes get a `security` first on
//! their PATH that finds nothing and stores nothing (exit 44, "not found"), and Claude Code reads and writes the file,
//! as it does on Linux. The machine's own login is not touched: machine profiles run on a token handed to them.
//! (src/no-keychain.ts)

use std::collections::BTreeMap;
use std::path::PathBuf;

const STUB: &str = "#!/bin/sh\n# ember: profile logins are kept in files, not the keychain (src/no_keychain.rs).\nexit 44\n";

/// The directory with the stand-in `security`, made (again) if missing.
fn stub_dir() -> PathBuf {
    // SAFETY: getuid has no preconditions.
    let uid = unsafe { libc::getuid() };
    let dir = std::env::temp_dir().join(format!("ember-no-keychain-{uid}"));
    let path = dir.join("security");
    if !path.exists() {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::create_dir_all(&dir);
        let _ = std::fs::write(&path, STUB);
        let _ = std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755));
    }
    dir
}

/// Keeps Claude Code off the keychain in `env` (macOS only; elsewhere it uses the file anyway).
pub fn file_credentials(env: &mut BTreeMap<String, String>) {
    if !cfg!(target_os = "macos") {
        return;
    }
    let path = env.get("PATH").cloned().or_else(|| std::env::var("PATH").ok()).unwrap_or_default();
    env.insert("PATH".into(), format!("{}:{path}", stub_dir().display()));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[cfg(target_os = "macos")]
    fn on_macos_a_profiles_processes_find_a_security_that_holds_nothing() {
        let mut env = BTreeMap::from([("PATH".to_string(), "/usr/bin:/bin".to_string())]);
        file_credentials(&mut env);
        let first = env["PATH"].split(':').next().unwrap().to_string();
        assert_ne!(first, "/usr/bin");
        let status = std::process::Command::new(PathBuf::from(first).join("security")).args(["find-generic-password", "-s", "x", "-w"]).status().unwrap();
        assert_eq!(status.code(), Some(44));
    }
}
