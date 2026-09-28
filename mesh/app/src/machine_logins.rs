//! Who this machine's own Claude Code and Codex are signed in as (in their usual homes, ~/.claude and ~/.codex), for the
//! pages that ask for a first profile to say so, and the way a profile uses that login itself (`machine` profiles).
//! Never copied: both vendors rotate single-use refresh tokens, so a copy would sign one side out later.
//! - Codex: the profile's home links auth.json to the machine's; Codex saves it in place (through the link) and reads it
//!   again before refreshing, so both share one login.
//! - Claude Code: a link does not hold (it replaces the file when it refreshes), so the profile's processes are handed
//!   the machine's current access token (CLAUDE_CODE_OAUTH_TOKEN) and never refresh; when it is about to run out, the
//!   machine's own claude is asked for a moment, which refreshes it in its own file.
//! Only logins kept in files: one in the macOS keychain cannot be used so (the pages offer a sign-in instead).

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use anyhow::{Result, anyhow, bail};
use base64::Engine;
use ember_shapes::RuntimeKind;
use futures_util::future::BoxFuture;
use serde::Serialize;
use serde_json::Value;
use tokio::process::Command;
use tokio::sync::watch;
use tracing::{info, warn};

use crate::store::now_ms;

pub type Env = BTreeMap<String, String>;

/// The station's own environment.
pub fn process_env() -> Env {
    std::env::vars().collect()
}

#[derive(Serialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MachineLogin {
    pub runtime: RuntimeKind,
    /// Its command is on the station's PATH.
    pub installed: bool,
    /// Signed in with an account (a subscription or a key).
    pub logged_in: bool,
    /// The account's email, when its files say.
    pub email: Option<String>,
    /// The subscription's plan (max, pro, plus…), when known.
    pub plan: Option<String>,
    /// A profile can use it as it is (kept in a file, not only in the keychain).
    pub usable: bool,
    /// Its allowance, as a profile on it would show (none until read, or when it cannot be).
    pub quota: Option<Value>,
    /// In a line, as the pages show it.
    pub text: String,
}

impl MachineLogin {
    fn new(runtime: RuntimeKind, installed: bool, logged_in: bool, text: String) -> MachineLogin {
        MachineLogin { runtime, installed, logged_in, email: None, plan: None, usable: false, quota: None, text }
    }
}

/// How long a reading serves before the next overview reads again (in the background).
const FRESH_MS: i64 = 2 * 60_000;

fn label(runtime: RuntimeKind) -> &'static str {
    match runtime {
        RuntimeKind::Claude => "Claude Code",
        RuntimeKind::Codex => "Codex",
    }
}

/// How a login's allowance is read (quota.rs's machine_usage).
pub type Usage = Arc<dyn Fn(RuntimeKind, Env) -> BoxFuture<'static, Option<Value>> + Send + Sync>;

/// The machine's logins, read now and then: `get` answers at once with the last reading and reads again when it is
/// old; `changes` moves when a reading differs from the last.
pub struct MachineLogins {
    env: Env,
    usage: Option<Usage>,
    state: Mutex<(Vec<MachineLogin>, i64, bool)>,
    changes: watch::Sender<u64>,
}

impl MachineLogins {
    pub fn new(env: Env, usage: Option<Usage>) -> Arc<MachineLogins> {
        Arc::new(MachineLogins { env, usage, state: Mutex::new((vec![], 0, false)), changes: watch::channel(0).0 })
    }

    /// The environment the logins are read in (whose HOME holds them).
    pub fn env(&self) -> Env {
        self.env.clone()
    }

    pub fn get(self: &Arc<Self>) -> Vec<MachineLogin> {
        let stale = now_ms() - self.state.lock().unwrap().1 > FRESH_MS;
        if stale {
            let me = self.clone();
            tokio::spawn(async move { me.refresh().await });
        }
        self.state.lock().unwrap().0.clone()
    }

    /// Hears each reading that differs from the last.
    pub fn changes(&self) -> watch::Receiver<u64> {
        self.changes.subscribe()
    }

    pub async fn refresh(&self) {
        {
            let mut state = self.state.lock().unwrap();
            if state.2 {
                return;
            }
            state.2 = true;
        }
        let (claude, codex) = tokio::join!(claude_login(&self.env), codex_login(&self.env));
        let mut logins = vec![claude, codex];
        // Each one a profile could use, with its allowance: an account refused (suspended, say) shows before it is used.
        if let Some(usage) = &self.usage {
            for login in logins.iter_mut().filter(|l| l.logged_in && l.usable) {
                login.quota = usage(login.runtime, self.env.clone()).await;
            }
        }
        let changed = {
            let mut state = self.state.lock().unwrap();
            let changed = state.0 != logins;
            *state = (logins, now_ms(), false);
            changed
        };
        if changed {
            self.changes.send_modify(|n| *n += 1);
        }
    }
}

/// The environment the machine's own CLI would run in: none of what points it at another home or account.
fn machine_env(env: &Env, drop: &[&str]) -> Env {
    env.iter().filter(|(k, _)| !drop.contains(&k.as_str())).map(|(k, v)| (k.clone(), v.clone())).collect()
}

const CLAUDE_DROP: [&str; 4] = ["CLAUDE_CONFIG_DIR", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN"];

pub(crate) fn home_of(env: &Env) -> PathBuf {
    env.get("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("."))
}

/// Where the machine's Claude Code keeps its login when it keeps it in a file.
pub fn claude_credentials_file(env: &Env) -> PathBuf {
    home_of(env).join(".claude").join(".credentials.json")
}

pub(crate) fn codex_home(env: &Env) -> PathBuf {
    env.get("CODEX_HOME").filter(|h| !h.is_empty()).map(PathBuf::from).unwrap_or_else(|| home_of(env).join(".codex"))
}

/// Where the machine's Codex keeps its login when it keeps it in a file.
pub fn codex_auth_file(env: &Env) -> PathBuf {
    codex_home(env).join("auth.json")
}

/// What a command said, and how it ended: None when it could not be run at all (not installed).
struct Ran {
    ok: bool,
    stdout: String,
    stderr: String,
}

async fn run(command: &str, args: &[&str], env: &Env, cwd: Option<&Path>, timeout: Duration) -> Option<Result<Ran>> {
    let mut cmd = Command::new(command);
    cmd.args(args).env_clear().envs(env).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped()).kill_on_drop(true);
    if let Some(dir) = cwd {
        cmd.current_dir(dir);
    }
    let child = match cmd.spawn() {
        Ok(child) => child,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return None,
        Err(e) => return Some(Err(e.into())),
    };
    Some(match tokio::time::timeout(timeout, child.wait_with_output()).await {
        Ok(Ok(out)) => Ok(Ran { ok: out.status.success(), stdout: String::from_utf8_lossy(&out.stdout).into(), stderr: String::from_utf8_lossy(&out.stderr).into() }),
        Ok(Err(e)) => Err(e.into()),
        Err(_) => Err(anyhow!("{command} took too long")),
    })
}

async fn claude_login(env: &Env) -> MachineLogin {
    let rt = RuntimeKind::Claude;
    let ran = run("claude", &["auth", "status"], &machine_env(env, &CLAUDE_DROP), None, Duration::from_secs(20)).await;
    let Some(ran) = ran else { return MachineLogin::new(rt, false, false, format!("没有装 {}", label(rt))) };
    let Ok(ran) = ran else { return MachineLogin::new(rt, true, false, format!("读不到 {} 的登录", label(rt))) };
    // `auth status` exits non-zero when signed out, still printing its JSON.
    let Ok(status) = serde_json::from_str::<Value>(&ran.stdout) else {
        return MachineLogin::new(rt, true, false, format!("读不到 {} 的登录", label(rt)));
    };
    if status.get("loggedIn") != Some(&Value::Bool(true)) {
        return MachineLogin::new(rt, true, false, format!("{} 没有登录", label(rt)));
    }
    let email = status.get("email").and_then(Value::as_str).map(String::from);
    let plan = status.get("subscriptionType").and_then(Value::as_str).map(String::from);
    let usable = read_claude_credentials(env).is_some();
    let text = format!("{}{}", said(label(rt), email.as_deref(), plan.as_deref()), if usable { "" } else { "，登录存在钥匙串里" });
    MachineLogin { runtime: rt, installed: true, logged_in: true, email, plan, usable, quota: None, text }
}

async fn codex_login(env: &Env) -> MachineLogin {
    let rt = RuntimeKind::Codex;
    let home = codex_home(env);
    let mut child_env = machine_env(env, &["OPENAI_API_KEY", "CODEX_API_KEY"]);
    child_env.insert("CODEX_HOME".into(), home.display().to_string());
    let text = match run("codex", &["login", "status"], &child_env, None, Duration::from_secs(20)).await {
        None => return MachineLogin::new(rt, false, false, format!("没有装 {}", label(rt))),
        // `login status` exits non-zero when signed out.
        Some(Ok(ran)) => format!("{}{}", ran.stdout, ran.stderr),
        Some(Err(_)) => String::new(),
    };
    let lower = text.to_lowercase();
    if !lower.contains("logged in") || lower.contains("not logged in") {
        return MachineLogin::new(rt, true, false, format!("{} 没有登录", label(rt)));
    }
    let (email, plan) = codex_account(&home);
    let usable = home.join("auth.json").exists();
    let text = format!("{}{}", said(label(rt), email.as_deref(), plan.as_deref()), if usable { "" } else { "，登录存在钥匙串里" });
    MachineLogin { runtime: rt, installed: true, logged_in: true, email, plan, usable, quota: None, text }
}

/// The machine's Claude Code login as its file keeps it: its access token and when that runs out.
fn read_claude_credentials(env: &Env) -> Option<(String, i64)> {
    let text = std::fs::read_to_string(claude_credentials_file(env)).ok()?;
    let value: Value = serde_json::from_str(&text).ok()?;
    let oauth = value.get("claudeAiOauth")?;
    let token = oauth.get("accessToken")?.as_str().filter(|t| !t.is_empty())?.to_string();
    Some((token, oauth.get("expiresAt").and_then(Value::as_i64).unwrap_or(0)))
}

/// How close to running out a token is taken as run out: Claude Code refreshes its own this close to the end, so a
/// moment of it refreshes then, and a process handed one this close is started again for its next turn.
pub const CLAUDE_TOKEN_MARGIN_MS: i64 = 5 * 60_000;
/// The last refresh that did not give a good token is not tried again for a while (each try is a model call).
const RETRY_MS: i64 = 30 * 60_000;

fn refresh_lock() -> &'static tokio::sync::Mutex<Option<(i64, String)>> {
    static LOCK: OnceLock<tokio::sync::Mutex<Option<(i64, String)>>> = OnceLock::new();
    LOCK.get_or_init(|| tokio::sync::Mutex::new(None))
}

/// The machine's Claude Code access token for a profile's process (token, expiresAt), refreshed first (by the
/// machine's own claude, in its own file) when it is about to run out. Fails, in words for the chat, when there is none.
pub async fn machine_claude_token(env: &Env) -> Result<(String, i64)> {
    let Some(credentials) = read_claude_credentials(env) else {
        bail!("这台机器上的 Claude Code 没有登录（或者登录存在钥匙串里），要在 station 上重新登录");
    };
    if credentials.1 - now_ms() > CLAUDE_TOKEN_MARGIN_MS {
        return Ok(credentials);
    }
    // One refresh at a time; whoever waited reads what it made.
    let mut failed = refresh_lock().lock().await;
    if let Some(fresh) = read_claude_credentials(env).filter(|c| c.1 - now_ms() > CLAUDE_TOKEN_MARGIN_MS) {
        return Ok(fresh);
    }
    if let Some((at, message)) = failed.as_ref() {
        if now_ms() - at < RETRY_MS && credentials.1 <= now_ms() {
            bail!("{message}");
        }
    }
    let said = refresh_claude(env).await;
    if let Some(fresh) = read_claude_credentials(env).filter(|c| c.1 > now_ms()) {
        *failed = None;
        return Ok(fresh);
    }
    // Refused, claude says so (an account on hold, say) rather than refreshing.
    let lower = said.to_lowercase();
    let message = if ["on hold", "restricted", "suspend", "disabled", "banned"].iter().any(|w| lower.contains(w)) {
        let first: String = said.trim().lines().next().unwrap_or("").chars().take(200).collect();
        format!("Anthropic 停用了这台机器上的 Claude 账号：{first}")
    } else {
        "这台机器上 Claude Code 的登录过期了，没能刷新：在 station 上运行一次 claude 看看".to_string()
    };
    *failed = Some((now_ms(), message.clone()));
    bail!("{message}")
}

/// The machine's own claude, asked for a word with the smallest model: it refreshes its login on the way (in its own
/// file, as it always does). Kept out of its history.
async fn refresh_claude(env: &Env) -> String {
    info!("refreshing the machine's Claude Code login");
    let args = ["-p", "--model", "haiku", "--no-session-persistence", "Reply with one word: ok"];
    match run("claude", &args, &machine_env(env, &CLAUDE_DROP), Some(&std::env::temp_dir()), Duration::from_secs(120)).await {
        Some(Ok(ran)) => {
            let said = format!("{}{}", ran.stdout, ran.stderr);
            if !ran.ok {
                warn!(said = &said[..said.len().min(300)], "could not refresh the machine's Claude Code login");
            }
            said
        }
        Some(Err(e)) => {
            warn!(error = %e, "could not refresh the machine's Claude Code login");
            String::new()
        }
        None => String::new(),
    }
}

/// A machine profile's Codex home, sharing the machine's login: its auth.json a link to the machine's. Made again when
/// something replaced it (a sign-in in the home, say).
pub fn link_codex_auth(home: &Path, env: &Env) -> Result<()> {
    let target = codex_auth_file(env);
    let link = home.join("auth.json");
    std::fs::create_dir_all(home)?;
    if let Ok(meta) = std::fs::symlink_metadata(&link) {
        if meta.file_type().is_symlink() && std::fs::read_link(&link).ok().as_deref() == Some(target.as_path()) {
            return Ok(());
        }
        std::fs::remove_file(&link)?;
    }
    std::os::unix::fs::symlink(&target, &link)?;
    Ok(())
}

/// The account in Codex's auth.json: its id token's email and ChatGPT plan (none for an API key, or in the keyring).
fn codex_account(home: &Path) -> (Option<String>, Option<String>) {
    let claims = (|| -> Option<Value> {
        let auth: Value = serde_json::from_str(&std::fs::read_to_string(home.join("auth.json")).ok()?).ok()?;
        let payload = auth.get("tokens")?.get("id_token")?.as_str()?.split('.').nth(1)?.to_string();
        let bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(payload.trim_end_matches('=')).ok()?;
        serde_json::from_slice(&bytes).ok()
    })();
    let Some(claims) = claims else { return (None, None) };
    let email = claims
        .get("email")
        .or_else(|| claims.get("https://api.openai.com/profile").and_then(|p| p.get("email")))
        .and_then(Value::as_str)
        .map(String::from);
    let plan = claims.get("https://api.openai.com/auth").and_then(|a| a.get("chatgpt_plan_type")).and_then(Value::as_str).map(String::from);
    (email, plan)
}

pub fn capitalized(plan: &str) -> String {
    let mut chars = plan.chars();
    match chars.next() {
        Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
        None => String::new(),
    }
}

fn said(label: &str, email: Option<&str>, plan: Option<&str>) -> String {
    format!(
        "{label} 已登录{}{}",
        email.map(|e| format!(" {e}")).unwrap_or_default(),
        plan.map(|p| format!("（{}）", capitalized(p))).unwrap_or_default()
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    /// A machine: a HOME, and a bin/ with stand-ins for the CLIs (shell scripts), on a PATH of only that and the system's.
    fn machine(clis: &[(&str, &str)]) -> (tempfile::TempDir, Env) {
        let home = tempfile::tempdir().unwrap();
        let bin = home.path().join("bin");
        std::fs::create_dir(&bin).unwrap();
        for (name, script) in clis {
            let path = bin.join(name);
            std::fs::write(&path, format!("#!/bin/sh\n{script}\n")).unwrap();
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        }
        let env = Env::from([("HOME".into(), home.path().display().to_string()), ("PATH".into(), format!("{}:/usr/bin:/bin", bin.display()))]);
        (home, env)
    }

    fn id_token(claims: Value) -> String {
        format!("x.{}.y", base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(claims.to_string()))
    }

    #[tokio::test]
    async fn the_machines_own_logins_are_read_from_the_machines_own_homes() {
        let (home, mut env) = machine(&[
            // Only answers for the machine's own home: no CLAUDE_CONFIG_DIR may reach it.
            ("claude", r#"[ -n "$CLAUDE_CONFIG_DIR" ] && exit 3; echo '{"loggedIn":true,"authMethod":"claude.ai","email":"a@x.com","subscriptionType":"max"}'"#),
            ("codex", r#"[ "$CODEX_HOME" = "$HOME/.codex" ] || exit 3; echo "Logged in using ChatGPT""#),
        ]);
        std::fs::create_dir(home.path().join(".codex")).unwrap();
        std::fs::create_dir(home.path().join(".claude")).unwrap();
        std::fs::write(home.path().join(".claude/.credentials.json"), serde_json::json!({"claudeAiOauth": {"accessToken": "at", "expiresAt": now_ms() + 3_600_000}}).to_string()).unwrap();
        let token = id_token(serde_json::json!({"email": "b@x.com", "https://api.openai.com/auth": {"chatgpt_plan_type": "plus"}}));
        std::fs::write(home.path().join(".codex/auth.json"), serde_json::json!({"tokens": {"id_token": token}}).to_string()).unwrap();
        env.insert("CLAUDE_CONFIG_DIR".into(), "/elsewhere".into());
        let usage: Usage = Arc::new(|runtime, _| Box::pin(async move { Some(serde_json::json!({"state": "ok", "detail": format!("{runtime:?}")})) }));
        let logins = MachineLogins::new(env, Some(usage));
        let mut changes = logins.changes();
        logins.refresh().await;
        logins.refresh().await;
        assert_eq!(*changes.borrow_and_update(), 1, "the pages hear of the first reading, and not of one that says the same");
        let got = logins.state.lock().unwrap().0.clone();
        assert_eq!(got[0].text, "Claude Code 已登录 a@x.com（Max）");
        assert_eq!((got[0].usable, got[0].quota.clone().unwrap()["detail"].clone()), (true, serde_json::json!("Claude")));
        assert_eq!((got[1].email.as_deref(), got[1].plan.as_deref(), got[1].text.as_str()), (Some("b@x.com"), Some("plus"), "Codex 已登录 b@x.com（Plus）"));
    }

    #[tokio::test]
    async fn signed_out_not_installed_and_keychain_only_are_said_as_such() {
        let (_home, env) = machine(&[("claude", r#"echo '{"loggedIn":false}'; exit 1"#)]);
        let got = MachineLogins::new(env, None);
        got.refresh().await;
        let got = got.state.lock().unwrap().0.clone();
        assert_eq!((got[0].installed, got[0].logged_in, got[0].text.as_str()), (true, false, "Claude Code 没有登录"));
        assert_eq!((got[1].installed, got[1].text.as_str()), (false, "没有装 Codex"));
        let (_home, env) = machine(&[
            ("claude", r#"echo '{"loggedIn":true,"email":"a@x.com","subscriptionType":"pro"}'"#),
            ("codex", r#"echo "Logged in using ChatGPT""#),
        ]);
        let keychain = MachineLogins::new(env, None);
        keychain.refresh().await;
        let got = keychain.state.lock().unwrap().0.clone();
        assert_eq!((got[0].usable, got[0].text.as_str()), (false, "Claude Code 已登录 a@x.com（Pro），登录存在钥匙串里"));
        assert_eq!((got[1].usable, got[1].text.as_str()), (false, "Codex 已登录，登录存在钥匙串里"));
    }

    #[tokio::test]
    async fn the_machines_claude_token_is_handed_over_and_refreshed_by_its_own_claude() {
        let (home, env) = machine(&[(
            "claude",
            // Refreshing, as claude does in its own file: a new token good for hours.
            r#"echo '{"claudeAiOauth":{"accessToken":"new","expiresAt":'$(( $(date +%s) * 1000 + 28800000 ))'}}' > "$HOME/.claude/.credentials.json"; echo "$@" > "$HOME/asked""#,
        )]);
        std::fs::create_dir(home.path().join(".claude")).unwrap();
        let file = home.path().join(".claude/.credentials.json");
        std::fs::write(&file, serde_json::json!({"claudeAiOauth": {"accessToken": "old", "expiresAt": now_ms() + 3_600_000}}).to_string()).unwrap();
        assert_eq!(machine_claude_token(&env).await.unwrap().0, "old");
        std::fs::write(&file, serde_json::json!({"claudeAiOauth": {"accessToken": "old", "expiresAt": now_ms() + 60_000}}).to_string()).unwrap();
        let fresh = machine_claude_token(&env).await.unwrap();
        assert_eq!(fresh.0, "new");
        assert!(fresh.1 > now_ms() + 3_600_000);
        assert!(std::fs::read_to_string(home.path().join("asked")).unwrap().contains("--no-session-persistence"));
    }

    #[test]
    fn a_machine_profiles_codex_home_links_the_machines_auth_json() {
        let (home, env) = machine(&[]);
        let profile = home.path().join("profile");
        link_codex_auth(&profile, &env).unwrap();
        assert_eq!(std::fs::read_link(profile.join("auth.json")).unwrap(), home.path().join(".codex/auth.json"));
        std::fs::remove_file(profile.join("auth.json")).unwrap();
        std::fs::write(profile.join("auth.json"), "{}").unwrap();
        link_codex_auth(&profile, &env).unwrap();
        assert!(std::fs::symlink_metadata(profile.join("auth.json")).unwrap().file_type().is_symlink());
    }
}
