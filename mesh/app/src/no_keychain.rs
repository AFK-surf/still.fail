//! Claude Code on macOS keeps its login in the keychain, under a name made from its config directory's path, and falls
//! back to <config dir>/.credentials.json only when the keychain refuses; once it has saved to the keychain it deletes
//! the file. A profile's login has to live in its home: the home is renamed after a sign-in (the keychain item stays
//! behind under the old path), quota and checks read the file, and a keychain item is out of reach of the station's
//! processes outside the desktop session. So profile processes (sign-in, checks and the sessions' own, which refresh
//! it) get a `security` first on their PATH that finds and stores nothing of Claude Code's (exit 44, "not found"), and
//! Claude Code reads and writes the file, as it does on Linux; anything else is passed to the real one, so an agent's
//! own `security` commands still work. The machine's own login is not touched: machine profiles run on a token handed
//! to them.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::time::Duration;

use sha2::{Digest, Sha256};
use tracing::{info, warn};

/// Claude Code asks with its item's name in the arguments, or (`security -i`) in the commands it writes to stdin.
const STUB: &str = r#"#!/bin/sh
# ember: profile logins are kept in files, not the keychain (src/no_keychain.rs); the rest goes to the real security.
case "$*" in *"Claude Code"*) exit 44 ;; esac
if [ "$1" = "-i" ]; then
  input=$(cat)
  case "$input" in *"Claude Code"*) exit 44 ;; esac
  printf '%s\n' "$input" | /usr/bin/security "$@"
  exit $?
fi
exec /usr/bin/security "$@"
"#;

/// The directory with the stand-in `security`, made (again) when missing or an older one.
fn stub_dir() -> PathBuf {
    // SAFETY: getuid has no preconditions.
    let uid = unsafe { libc::getuid() };
    let dir = std::env::temp_dir().join(format!("ember-no-keychain-{uid}"));
    let path = dir.join("security");
    if std::fs::read_to_string(&path).ok().as_deref() != Some(STUB) {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::create_dir_all(&dir);
        // Written aside and moved in: a process may be running the old one.
        let fresh = dir.join(format!("security.{}", std::process::id()));
        let _ = std::fs::write(&fresh, STUB);
        let _ = std::fs::set_permissions(&fresh, std::fs::Permissions::from_mode(0o755));
        let _ = std::fs::rename(&fresh, &path);
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

/// The keychain item Claude Code keeps the login of a config directory in.
fn keychain_item(home: &Path) -> String {
    let hash = hex::encode(Sha256::digest(home.to_string_lossy().as_bytes()));
    format!("Claude Code-credentials-{}", &hash[..8])
}

/// A profile's login that Claude Code moved into the keychain (a session that ran without the stand-in, before
/// sessions had it), moved back into its home's file. Nothing when the file is there or the keychain cannot be read.
pub async fn take_back(home: &Path) {
    if !cfg!(target_os = "macos") {
        return;
    }
    let file = home.join(".credentials.json");
    if file.exists() {
        return;
    }
    let item = keychain_item(home);
    let security = |args: &[&str]| {
        let mut cmd = tokio::process::Command::new("/usr/bin/security");
        cmd.args(args).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null()).kill_on_drop(true);
        async move { tokio::time::timeout(Duration::from_secs(5), cmd.output()).await.ok().and_then(Result::ok) }
    };
    let Some(found) = security(&["find-generic-password", "-w", "-s", &item]).await.filter(|o| o.status.success()) else { return };
    let text = String::from_utf8_lossy(&found.stdout).trim().to_string();
    let is_login = serde_json::from_str::<serde_json::Value>(&text).ok().is_some_and(|v| v.get("claudeAiOauth").is_some());
    if !is_login {
        return;
    }
    if let Err(e) = write_private(&file, &text) {
        warn!(home = %home.display(), error = %e, "could not move a profile's login out of the keychain");
        return;
    }
    security(&["delete-generic-password", "-s", &item]).await;
    info!(home = %home.display(), "a profile's login moved back from the keychain to its file");
}

/// Written aside (readable by its owner only) and moved in.
fn write_private(file: &Path, text: &str) -> std::io::Result<()> {
    use std::io::Write;
    use std::os::unix::fs::OpenOptionsExt;
    let aside = file.with_extension(format!("json.{}", std::process::id()));
    let mut out = std::fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(&aside)?;
    out.write_all(text.as_bytes())?;
    out.sync_all()?;
    std::fs::rename(&aside, file)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[cfg(target_os = "macos")]
    fn on_macos_a_profiles_processes_find_a_security_that_holds_nothing_of_claude_codes() {
        use std::io::Write;
        let mut env = BTreeMap::from([("PATH".to_string(), "/usr/bin:/bin".to_string())]);
        file_credentials(&mut env);
        let first = env["PATH"].split(':').next().unwrap().to_string();
        assert_ne!(first, "/usr/bin");
        let stub = PathBuf::from(first).join("security");
        let status = std::process::Command::new(&stub).args(["find-generic-password", "-s", "Claude Code-credentials-12345678", "-w"]).status().unwrap();
        assert_eq!(status.code(), Some(44));
        // How Claude Code saves: commands on stdin.
        let mut saving = std::process::Command::new(&stub).arg("-i").stdin(Stdio::piped()).stdout(Stdio::null()).stderr(Stdio::null()).spawn().unwrap();
        saving.stdin.take().unwrap().write_all(b"add-generic-password -U -a \"me\" -s \"Claude Code-credentials\" -X \"7b7d\"\n").unwrap();
        assert_eq!(saving.wait().unwrap().code(), Some(44));
        // Anything else is the real one's.
        let other = std::process::Command::new(&stub).args(["find-generic-password", "-s", "ember-no-such-item"]).stderr(Stdio::null()).output().unwrap();
        let real = std::process::Command::new("/usr/bin/security").args(["find-generic-password", "-s", "ember-no-such-item"]).stderr(Stdio::null()).output().unwrap();
        assert_eq!(other.status.code(), real.status.code());
        assert_eq!(std::process::Command::new(&stub).args(["list-keychains", "-d", "user"]).stdout(Stdio::null()).status().unwrap().code(), Some(0));
    }

    #[test]
    fn a_homes_keychain_item_is_named_as_claude_code_names_it() {
        // As found in a station's keychain, left there by a profile's sessions (Claude Code 2.1.284).
        assert_eq!(keychain_item(Path::new("/Users/admin/.ember/homes/cuesurf2-proton-me")), "Claude Code-credentials-bba6043c");
    }
}
