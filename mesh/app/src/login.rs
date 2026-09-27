//! Signing a subscription profile in from the pages. The runtime's own login command runs here, on the machine the
//! station runs on, so the credentials land in the profile's home; the page only relays what the person has to do in
//! their browser:
//! - Claude: `claude auth login` prints an authorize link; after approving, the browser shows a code, which the person
//!   pastes back and the station types in.
//! - Codex: `codex login --device-auth` prints a link and a one-time code; the person enters the code on that page and
//!   the command finishes by itself.
//!
//! A stand-in `open` on PATH keeps the commands from opening a browser on the server. (src/login.ts)

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::{Result, anyhow, bail};
use ember_shapes::RuntimeKind;
use serde::Serialize;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWriteExt};
use tokio::process::{ChildStdin, Command};
use tokio::sync::broadcast;
use tokio::task::JoinHandle;
use tracing::info;

use crate::config::Profile;
use crate::no_keychain::file_credentials;
use crate::runtime::clean_env;
use crate::store::now_ms;

#[derive(Serialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum LoginState {
    /// Started; waiting for the command to say where to sign in.
    Starting,
    /// Claude: the person approves in the browser and pastes the code shown there.
    NeedsCode,
    /// Codex: the person enters `user_code` at `url`; the command waits for it.
    NeedsApproval,
    /// The code was sent; the command is finishing.
    Verifying,
    Done,
    Failed,
    Cancelled,
}

#[derive(Serialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LoginJob {
    pub profile: String,
    pub runtime: RuntimeKind,
    pub state: LoginState,
    pub url: Option<String>,
    pub user_code: Option<String>,
    pub error: Option<String>,
    pub started_at: i64,
    pub expires_at: i64,
}

const TIMEOUT: Duration = Duration::from_secs(15 * 60);
/// Variables that would make the login command talk to something other than the subscription.
const SCRUBBED: [&str; 8] =
    ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL", "CLAUDE_CONFIG_DIR", "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CODEX_HOME", "OPENAI_API_KEY"];

/// The login commands, by runtime.
#[derive(Debug, Clone)]
pub struct LoginCommands {
    pub claude: String,
    pub codex: String,
}

impl Default for LoginCommands {
    fn default() -> Self {
        LoginCommands { claude: "claude".into(), codex: "codex".into() }
    }
}

struct Running {
    /// Which start this is: a later start of the same profile replaces it.
    run: u64,
    job: LoginJob,
    pid: Option<u32>,
    stdin: Arc<tokio::sync::Mutex<Option<ChildStdin>>>,
    output: String,
    timer: JoinHandle<()>,
    exited: bool,
}

pub struct LoginManager {
    jobs: Mutex<HashMap<String, Running>>,
    finished: Mutex<HashMap<String, LoginJob>>,
    no_browser_dir: PathBuf,
    commands: LoginCommands,
    /// A profile id whenever its login job changes.
    changes: broadcast::Sender<String>,
    runs: std::sync::atomic::AtomicU64,
}

impl LoginManager {
    pub fn new(data_dir: &Path, commands: LoginCommands) -> Arc<LoginManager> {
        Arc::new(LoginManager {
            jobs: Mutex::default(),
            finished: Mutex::default(),
            no_browser_dir: data_dir.join("run").join("no-browser"),
            commands,
            changes: broadcast::channel(256).0,
            runs: Default::default(),
        })
    }

    /// Hears the profile id of each login job that changes.
    pub fn changes(&self) -> broadcast::Receiver<String> {
        self.changes.subscribe()
    }

    pub fn get(&self, profile: &str) -> Option<LoginJob> {
        if let Some(running) = self.jobs.lock().unwrap().get(profile) {
            return Some(running.job.clone());
        }
        self.finished.lock().unwrap().get(profile).cloned()
    }

    /// Starts a sign-in for a subscription profile, replacing any running one.
    pub fn start(self: &Arc<Self>, profile: &Profile) -> Result<LoginJob> {
        self.cancel(&profile.id);
        self.finished.lock().unwrap().remove(&profile.id);
        std::fs::create_dir_all(&profile.home)?;
        let no_browser = self.no_browser()?;
        let mut env = clean_env(&SCRUBBED);
        let path = env.get("PATH").cloned().unwrap_or_default();
        env.insert("PATH".into(), format!("{}:{path}", no_browser.display()));
        env.insert("BROWSER".into(), no_browser.join("open").to_string_lossy().into_owned());
        let (command, args): (&str, &[&str]) = match profile.runtime {
            RuntimeKind::Claude => {
                env.insert("CLAUDE_CONFIG_DIR".into(), profile.home.to_string_lossy().into_owned());
                file_credentials(&mut env);
                (&self.commands.claude, &["auth", "login", "--claudeai"])
            }
            RuntimeKind::Codex => {
                env.insert("CODEX_HOME".into(), profile.home.to_string_lossy().into_owned());
                (&self.commands.codex, &["login", "--device-auth"])
            }
        };

        let now = now_ms();
        let job = LoginJob {
            profile: profile.id.clone(),
            runtime: profile.runtime,
            state: LoginState::Starting,
            url: None,
            user_code: None,
            error: None,
            started_at: now,
            expires_at: now + TIMEOUT.as_millis() as i64,
        };
        let run = self.runs.fetch_add(1, std::sync::atomic::Ordering::SeqCst) + 1;
        let id = profile.id.clone();
        let mut child = match Command::new(command)
            .args(args)
            .current_dir(&profile.home)
            .env_clear()
            .envs(&env)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
        {
            Ok(child) => child,
            Err(e) => {
                // Recorded like any other failure, so the page shows why.
                let failed = LoginJob { state: LoginState::Failed, error: Some(format!("无法运行登录命令：{e}")), ..job };
                self.finished.lock().unwrap().insert(id.clone(), failed.clone());
                self.emit(&id);
                return Ok(failed);
            }
        };
        let me = Arc::downgrade(self);
        let timer_id = id.clone();
        let timer = tokio::spawn(async move {
            tokio::time::sleep(TIMEOUT).await;
            if let Some(me) = me.upgrade() {
                me.fail_run(&timer_id, run, "15 分钟内没有完成登录，已取消。".into());
            }
        });
        let readers: Vec<JoinHandle<()>> = [child.stdout.take().map(boxed), child.stderr.take().map(boxed)]
            .into_iter()
            .flatten()
            .map(|stream| {
                let (me, id) = (Arc::downgrade(self), id.clone());
                tokio::spawn(async move {
                    let mut stream = stream;
                    let mut buf = vec![0u8; 4096];
                    while let Ok(n) = stream.read(&mut buf).await {
                        if n == 0 {
                            return;
                        }
                        let Some(me) = me.upgrade() else { return };
                        me.output(&id, run, &String::from_utf8_lossy(&buf[..n]));
                    }
                })
            })
            .collect();
        let pid = child.id();
        self.jobs.lock().unwrap().insert(
            id.clone(),
            Running { run, job: job.clone(), pid, stdin: Arc::new(tokio::sync::Mutex::new(child.stdin.take())), output: String::new(), timer, exited: false },
        );
        let me = Arc::downgrade(self);
        let exit_id = id.clone();
        tokio::spawn(async move {
            let status = child.wait().await;
            // Everything it said is in before its end is judged.
            for reader in readers {
                let _ = reader.await;
            }
            let Some(me) = me.upgrade() else { return };
            let output = {
                let mut jobs = me.jobs.lock().unwrap();
                match jobs.get_mut(&exit_id).filter(|r| r.run == run) {
                    Some(running) => {
                        running.exited = true;
                        running.output.clone()
                    }
                    None => return,
                }
            };
            match status {
                Ok(status) if status.success() => me.finish(&exit_id, LoginState::Done, None),
                Ok(status) => {
                    let said = last_lines(&output);
                    let code = status.code().map(|c| c.to_string()).unwrap_or_else(|| "signal".into());
                    me.finish(&exit_id, LoginState::Failed, Some(if said.is_empty() { format!("登录命令退出（{code}）") } else { said }));
                }
                Err(e) => me.finish(&exit_id, LoginState::Failed, Some(format!("无法运行登录命令：{e}"))),
            }
        });
        info!(profile = id, runtime = ?profile.runtime, "login started");
        self.emit(&id);
        Ok(job)
    }

    /// Claude only: the code the browser showed after approving.
    pub async fn submit_code(&self, profile: &str, code: &str) -> Result<LoginJob> {
        let (stdin, job) = {
            let mut jobs = self.jobs.lock().unwrap();
            let running = jobs.get_mut(profile).filter(|r| r.job.state == LoginState::NeedsCode).ok_or_else(|| anyhow!("这个账号没有在等授权码"))?;
            let clean = code.trim();
            if clean.is_empty() {
                bail!("授权码是空的");
            }
            running.job.state = LoginState::Verifying;
            (running.stdin.clone(), (running.job.clone(), clean.to_string()))
        };
        if let Some(stdin) = stdin.lock().await.as_mut() {
            stdin.write_all(format!("{}\n", job.1).as_bytes()).await?;
            stdin.flush().await?;
        }
        self.emit(profile);
        Ok(job.0)
    }

    pub fn cancel(&self, profile: &str) {
        if self.jobs.lock().unwrap().contains_key(profile) {
            self.finish(profile, LoginState::Cancelled, None);
        }
    }

    pub fn stop_all(&self) {
        let ids: Vec<String> = self.jobs.lock().unwrap().keys().cloned().collect();
        for id in ids {
            self.cancel(&id);
        }
    }

    fn output(&self, profile: &str, run: u64, chunk: &str) {
        let changed = {
            let mut jobs = self.jobs.lock().unwrap();
            let Some(running) = jobs.get_mut(profile).filter(|r| r.run == run) else { return };
            running.output.push_str(&strip_ansi(chunk));
            let excess = running.output.chars().count().saturating_sub(8000);
            if excess > 0 {
                running.output = running.output.chars().skip(excess).collect();
            }
            parse(&mut running.job, &running.output)
        };
        if changed {
            self.emit(profile);
        }
    }

    fn fail_run(&self, profile: &str, run: u64, error: String) {
        let current = self.jobs.lock().unwrap().get(profile).is_some_and(|r| r.run == run);
        if current {
            self.finish(profile, LoginState::Failed, Some(error));
        }
    }

    fn finish(&self, profile: &str, state: LoginState, error: Option<String>) {
        let Some(running) = self.jobs.lock().unwrap().remove(profile) else { return };
        running.timer.abort();
        if let (false, Some(pid)) = (running.exited, running.pid) {
            // SAFETY: a plain signal to the login command this manager started.
            unsafe {
                libc::kill(pid as i32, libc::SIGTERM);
            }
        }
        let job = LoginJob { state, error: error.clone(), ..running.job };
        self.finished.lock().unwrap().insert(profile.to_string(), job);
        info!(profile, state = ?state, error = ?error, "login ended");
        self.emit(profile);
    }

    fn emit(&self, profile: &str) {
        let _ = self.changes.send(profile.to_string());
    }

    /// A directory whose `open` and `xdg-open` do nothing, put first on the login command's PATH.
    fn no_browser(&self) -> Result<PathBuf> {
        use std::os::unix::fs::PermissionsExt;
        std::fs::create_dir_all(&self.no_browser_dir)?;
        for name in ["open", "xdg-open"] {
            let path = self.no_browser_dir.join(name);
            std::fs::write(&path, "#!/bin/sh\nexit 0\n")?;
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755))?;
        }
        Ok(self.no_browser_dir.clone())
    }
}

fn boxed(stream: impl AsyncRead + Send + Unpin + 'static) -> Box<dyn AsyncRead + Send + Unpin> {
    Box::new(stream)
}

/// Reads where to sign in from what the command said so far. Whether the job changed.
fn parse(job: &mut LoginJob, output: &str) -> bool {
    if job.state != LoginState::Starting {
        return false;
    }
    let urls = || output.split_whitespace().filter_map(|w| w.find("https://").map(|at| &w[at..]));
    match job.runtime {
        RuntimeKind::Claude => {
            let url = urls().find(|u| u.contains("/oauth/authorize?") && !u.ends_with('?'));
            if let (Some(url), true) = (url, output.to_lowercase().contains("paste code")) {
                job.url = Some(url.to_string());
                job.state = LoginState::NeedsCode;
                return true;
            }
        }
        RuntimeKind::Codex => {
            let url = urls().find(|u| u.starts_with("https://auth.openai.com/") && u.contains("device"));
            if let (Some(url), Some(code)) = (url, device_code(output)) {
                job.url = Some(url.to_string());
                job.user_code = Some(code);
                job.state = LoginState::NeedsApproval;
                return true;
            }
        }
    }
    false
}

/// A one-time code like ABCD-12345: four capitals or digits, a dash, four to six more.
fn device_code(output: &str) -> Option<String> {
    let code = |s: &str, lengths: std::ops::RangeInclusive<usize>| lengths.contains(&s.len()) && s.chars().all(|c| c.is_ascii_uppercase() || c.is_ascii_digit());
    for word in output.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_' || c == '-')) {
        let parts: Vec<&str> = word.split('-').collect();
        for pair in parts.windows(2) {
            if code(pair[0], 4..=4) && code(pair[1], 4..=6) {
                return Some(format!("{}-{}", pair[0], pair[1]));
            }
        }
    }
    None
}

/// Drops terminal escapes (colours, cursor moves): ESC [ parameters letter.
fn strip_ansi(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\u{1b}' && chars.peek() == Some(&'[') {
            chars.next();
            while let Some(&p) = chars.peek() {
                chars.next();
                if p.is_ascii_alphabetic() {
                    break;
                }
                if !(p.is_ascii_digit() || p == ';' || p == '?') {
                    break;
                }
            }
            continue;
        }
        out.push(c);
    }
    out
}

fn last_lines(output: &str) -> String {
    let lines: Vec<&str> = output.trim().lines().filter(|l| !l.trim().is_empty()).collect();
    let text = lines[lines.len().saturating_sub(4)..].join("\n");
    text.chars().take(600).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const FAKE_LOGIN: &str = r#"#!/bin/sh
if [ "$1" = "auth" ]; then
  echo "Opening browser to sign in…"
  echo "If the browser didn't open, visit: https://claude.com/cai/oauth/authorize?code=true&client_id=x&state=y"
  printf "Paste code here if prompted > "
  read code
  [ "$code" = "good-code" ] && { echo "Login successful"; exit 0; }
  echo "OAuth error: invalid code"; exit 1
fi
printf "1. Open this link\n   \033[94mhttps://auth.openai.com/codex/device\033[0m\n2. Enter this one-time code\n   \033[94mABCD-12345\033[0m\n"
sleep 0.3
echo "Successfully logged in"
"#;

    fn profile(dir: &Path, id: &str, runtime: &str) -> Profile {
        let raw = serde_json::json!({ "profiles": [{ "id": id, "runtime": runtime, "access": { "kind": "subscription" }, "home": format!("homes/{id}") }] });
        crate::config::parse_config(&serde_json::from_value(raw).unwrap(), dir).unwrap().profiles.remove(0)
    }

    async fn wait(logins: &LoginManager, profile: &str, state: LoginState) -> LoginJob {
        for _ in 0..500 {
            if let Some(job) = logins.get(profile).filter(|j| j.state == state) {
                return job;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
        panic!("login of {profile} never reached {state:?}: {:?}", logins.get(profile));
    }

    #[tokio::test]
    async fn a_subscription_sign_in_relays_the_link_the_code_and_the_result() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempfile::tempdir().unwrap();
        let fake = dir.path().join("fake-login");
        std::fs::write(&fake, FAKE_LOGIN).unwrap();
        std::fs::set_permissions(&fake, std::fs::Permissions::from_mode(0o755)).unwrap();
        let command = fake.to_string_lossy().into_owned();
        let logins = LoginManager::new(dir.path(), LoginCommands { claude: command.clone(), codex: command });
        let mut changes = logins.changes();

        let sub = profile(dir.path(), "sub", "claude");
        logins.start(&sub).unwrap();
        let job = wait(&logins, "sub", LoginState::NeedsCode).await;
        assert!(job.url.as_deref().unwrap().starts_with("https://claude.com/cai/oauth/authorize?"), "{job:?}");
        assert_eq!(changes.recv().await.unwrap(), "sub");
        logins.submit_code("sub", "wrong").await.unwrap();
        assert!(wait(&logins, "sub", LoginState::Failed).await.error.unwrap().contains("invalid code"));
        assert!(logins.submit_code("sub", "x").await.unwrap_err().to_string().contains("没有在等授权码"));
        logins.start(&sub).unwrap();
        wait(&logins, "sub", LoginState::NeedsCode).await;
        assert!(logins.submit_code("sub", "  ").await.unwrap_err().to_string().contains("空"));
        logins.submit_code("sub", " good-code ").await.unwrap();
        wait(&logins, "sub", LoginState::Done).await;

        let cxs = profile(dir.path(), "cxs", "codex");
        logins.start(&cxs).unwrap();
        let device = wait(&logins, "cxs", LoginState::NeedsApproval).await;
        assert_eq!((device.url.as_deref(), device.user_code.as_deref()), (Some("https://auth.openai.com/codex/device"), Some("ABCD-12345")));
        wait(&logins, "cxs", LoginState::Done).await;

        // A cancelled sign-in stops its command and says so.
        logins.start(&sub).unwrap();
        wait(&logins, "sub", LoginState::NeedsCode).await;
        logins.cancel("sub");
        assert_eq!(logins.get("sub").unwrap().state, LoginState::Cancelled);
    }

    #[test]
    fn device_codes_and_escapes_are_read() {
        assert_eq!(device_code("enter\n   ABCD-12345\n").as_deref(), Some("ABCD-12345"));
        assert_eq!(device_code("a one-time code"), None);
        assert_eq!(strip_ansi("\u{1b}[94mhttps://x\u{1b}[0m"), "https://x");
    }
}
