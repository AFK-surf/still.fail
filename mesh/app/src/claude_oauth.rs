//! Renew Claude credentials without sending a prompt. Share Claude Code 2.1.286's current and legacy
//! directory locks; re-read after locking and save back to the original store, never a credential copy.
use std::path::{Path, PathBuf};
use std::os::unix::fs::MetadataExt;
use std::process::Stdio;
use std::time::{Duration, SystemTime};

use anyhow::{Context, Result, bail};
use serde_json::{Value, json};
use tokio::io::AsyncWriteExt;
use tokio::process::Command;

use crate::machine_logins::{Env, home_of};
use crate::store::now_ms;

pub(crate) const TOKEN_URL: &str = "https://platform.claude.com/v1/oauth/token";
const CLIENT_ID: &str = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
const ITEM: &str = "Claude Code-credentials";
const MARGIN: i64 = 5 * 60_000;

pub async fn token(
    env: &Env,
    profile_home: Option<&Path>,
    rejected: Option<&str>,
) -> Result<(String, i64)> {
    token_at(env, profile_home, rejected, TOKEN_URL).await
}

struct Credentials {
    data: Value,
    keychain: bool,
}

impl Credentials {
    fn access(&self) -> Result<(String, i64)> {
        let oauth = &self.data["claudeAiOauth"];
        let token = oauth["accessToken"]
            .as_str()
            .filter(|s| !s.is_empty())
            .context("没找到 Claude 登录凭据，请重新登录")?;
        Ok((token.into(), oauth["expiresAt"].as_i64().unwrap_or(0)))
    }

    fn usable(&self, rejected: Option<&str>) -> bool {
        self.access().is_ok_and(|(token, expires)| {
            rejected != Some(token.as_str()) && (expires == 0 || expires - now_ms() > MARGIN)
        })
    }
}

async fn read(env: &Env, home: &Path, machine: bool) -> Result<Credentials> {
    if machine && cfg!(target_os = "macos") {
        let mut cmd = Command::new("security");
        cmd.args(["find-generic-password", "-w", "-s", ITEM])
            .env_clear()
            .envs(env)
            .stdin(Stdio::null())
            .stderr(Stdio::null())
            .kill_on_drop(true);
        if let Ok(Ok(out)) = tokio::time::timeout(Duration::from_secs(10), cmd.output()).await {
            if out.status.success() {
                // An unreadable/malformed keychain entry must not be replaced with a stale file's login.
                let data =
                    serde_json::from_slice(&out.stdout).context("Claude 钥匙串凭据无法解析")?;
                return Ok(Credentials {
                    data,
                    keychain: true,
                });
            }
        }
    }
    let text = std::fs::read(home.join(".credentials.json"))
        .context("没找到 Claude 登录凭据，请重新登录")?;
    Ok(Credentials {
        data: serde_json::from_slice(&text).context("Claude 登录凭据无法解析")?,
        keychain: false,
    })
}

async fn save(env: &Env, home: &Path, credentials: &Credentials) -> Result<()> {
    if !credentials.keychain {
        return crate::no_keychain::write_private(
            &home.join(".credentials.json"),
            &credentials.data.to_string(),
        )
        .context("无法保存续期后的 Claude 登录");
    }
    // Keep secrets off argv, as Claude Code does. security -i reads its commands from stdin.
    let who = Command::new("/usr/bin/id").arg("-un").output().await?;
    let account = String::from_utf8(who.stdout)?.trim().to_string();
    if !who.status.success() || account.is_empty() || account.contains(['"', '\\', '\n', '\r']) {
        bail!("无法确定 Claude 钥匙串的账号名");
    }
    let input = format!(
        "add-generic-password -U -a \"{account}\" -s \"{ITEM}\" -X \"{}\"\n",
        hex::encode(credentials.data.to_string())
    );
    let mut child = Command::new("security")
        .arg("-i")
        .env_clear()
        .envs(env)
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .kill_on_drop(true)
        .spawn()?;
    tokio::time::timeout(Duration::from_secs(10), async {
        let mut stdin = child.stdin.take().context("无法写入钥匙串命令")?;
        stdin.write_all(input.as_bytes()).await?;
        drop(stdin);
        if !child.wait().await?.success() {
            bail!("无法把续期后的 Claude 登录保存到钥匙串");
        }
        Ok::<_, anyhow::Error>(())
    })
    .await
    .context("保存 Claude 钥匙串超时")??;
    Ok(())
}

pub(crate) async fn token_at(
    env: &Env,
    profile_home: Option<&Path>,
    rejected: Option<&str>,
    endpoint: &str,
) -> Result<(String, i64)> {
    let machine = profile_home.is_none();
    let home = profile_home
        .map(Path::to_path_buf)
        .unwrap_or_else(|| home_of(env).join(".claude"));
    let initial = read(env, &home, machine).await?;
    if initial.usable(rejected) {
        return initial.access();
    }
    std::fs::create_dir_all(&home)?;
    let _current = RefreshLock::acquire(home.join(".oauth_refresh.lock")).await?;
    let legacy = PathBuf::from(format!("{}.lock", std::fs::canonicalize(&home)?.display()));
    let _legacy = RefreshLock::acquire(legacy).await?;
    let credentials = read(env, &home, machine).await?;
    if credentials.usable(rejected) {
        return credentials.access();
    }
    let oauth = &credentials.data["claudeAiOauth"];
    let refresh = oauth["refreshToken"]
        .as_str()
        .filter(|s| !s.is_empty())
        .context("Claude 登录已过期，且没有续期凭据，请重新登录")?;
    let mut body = json!({"grant_type": "refresh_token", "refresh_token": refresh,
        "client_id": oauth["clientId"].as_str().filter(|s| !s.is_empty()).unwrap_or(CLIENT_ID)});
    if let Some(scopes) = oauth["scopes"].as_array() {
        let scopes: Vec<_> = scopes.iter().filter_map(Value::as_str).collect();
        if !scopes.is_empty() {
            body["scope"] = scopes.join(" ").into();
        }
    }
    let http = reqwest::Client::builder()
        .timeout(Duration::from_secs(30))
        .redirect(reqwest::redirect::Policy::none())
        .build()?;
    let response = http
        .post(endpoint)
        .json(&body)
        .send()
        .await
        .context("Claude 登录续期请求失败，请稍后重试")?;
    if !response.status().is_success() {
        // A CLI version using different locks may have won: never erase or roll back its credentials.
        let latest = read(env, &home, machine).await?;
        if latest.usable(rejected) {
            return latest.access();
        }
        let status = response.status().as_u16();
        if status == 400 || status == 401 {
            bail!("Claude 登录续期被拒绝（{status}），请重新登录");
        }
        bail!("Claude 登录暂时无法续期（{status}），请稍后重试");
    }
    let response: Value = response
        .json()
        .await
        .context("Claude 登录续期返回了无效响应")?;
    let access = response["access_token"]
        .as_str()
        .filter(|s| !s.is_empty())
        .context("Claude 续期响应缺少 access_token")?;
    let seconds = response["expires_in"]
        .as_i64()
        .filter(|s| *s > 0 && *s < i64::MAX / 2000)
        .context("Claude 续期响应缺少有效期")?;
    let mut latest = read(env, &home, machine).await?;
    if latest.keychain != credentials.keychain
        || latest.data["claudeAiOauth"]["refreshToken"] != oauth["refreshToken"]
    {
        // A simultaneous login must win over this refresh, even if it is a different account.
        if latest.usable(None) {
            return latest.access();
        }
        bail!("Claude 登录在续期期间已更换，请重试");
    }
    let updated = &mut latest.data["claudeAiOauth"];
    updated["accessToken"] = access.into();
    updated["expiresAt"] = (now_ms() + seconds * 1000).into();
    if let Some(refresh) = response["refresh_token"].as_str().filter(|s| !s.is_empty()) {
        updated["refreshToken"] = refresh.into();
    }
    if let Some(scope) = response["scope"].as_str() {
        updated["scopes"] = json!(scope.split_whitespace().collect::<Vec<_>>());
    }
    if let Some(seconds) = response["refresh_token_expires_in"]
        .as_i64()
        .filter(|s| *s > 0 && *s < i64::MAX / 2000)
    {
        updated["refreshTokenExpiresAt"] = (now_ms() + seconds * 1000).into();
    }
    let mut saved = save(env, &home, &latest).await;
    for _ in 0..2 {
        if saved.is_ok() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
        saved = save(env, &home, &latest).await;
    }
    saved?;
    latest.access()
}

/// proper-lockfile-compatible mkdir locks: a 5s heartbeat and 60s stale threshold, as in Claude Code.
/// Keep an open descriptor so an old owner cannot touch or remove a replacement lock.
struct RefreshLock {
    path: PathBuf,
    directory: std::fs::File,
    heartbeat: tokio::task::JoinHandle<()>,
}

impl RefreshLock {
    async fn acquire(path: PathBuf) -> Result<Self> {
        let deadline = tokio::time::Instant::now() + Duration::from_secs(40);
        loop {
            match std::fs::create_dir(&path) {
                Ok(()) => break,
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {
                    if std::fs::metadata(&path).and_then(|m| m.modified()).ok()
                        .and_then(|t| t.elapsed().ok()).is_some_and(|age| age > Duration::from_secs(60))
                    {
                        match std::fs::remove_dir(&path) {
                            Ok(()) => continue,
                            Err(e) if e.kind() == std::io::ErrorKind::NotFound => continue,
                            Err(_) => {}
                        }
                    }
                    if tokio::time::Instant::now() >= deadline {
                        bail!("另一个 Claude 进程正在续期，稍后重试");
                    }
                    tokio::time::sleep(Duration::from_millis(100)).await;
                }
                Err(e) => return Err(e).context("无法取得 Claude 登录续期锁"),
            }
        }
        let directory = std::fs::File::open(&path)?;
        let beat = directory.try_clone()?;
        let heartbeat = tokio::spawn(async move {
            loop {
                tokio::time::sleep(Duration::from_secs(5)).await;
                if beat.set_modified(SystemTime::now()).is_err() { break; }
            }
        });
        Ok(Self { path, directory, heartbeat })
    }
}

impl Drop for RefreshLock {
    fn drop(&mut self) {
        self.heartbeat.abort();
        if let (Ok(held), Ok(current)) = (self.directory.metadata(), std::fs::metadata(&self.path)) {
            if (held.dev(), held.ino()) == (current.dev(), current.ino()) {
                let _ = std::fs::remove_dir(&self.path);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};
    use tokio::io::AsyncReadExt;

    fn credentials(expires: i64) -> Value {
        json!({"otherCredential":{"keep":true}, "claudeAiOauth": {
            "accessToken":"old", "refreshToken":"refresh-old", "expiresAt": expires,
            "scopes":["user:profile","user:inference"], "subscriptionType":"max", "clientId":"test-client"
        }})
    }

    async fn provider(
        status: u16,
    ) -> (
        String,
        Arc<Mutex<Vec<(String, Value)>>>,
        tokio::task::JoinHandle<()>,
    ) {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let seen = Arc::new(Mutex::new(vec![]));
        let record = seen.clone();
        let task = tokio::spawn(async move {
            loop {
                let (mut socket, _) = listener.accept().await.unwrap();
                let mut bytes = vec![];
                let header_end;
                loop {
                    let mut buf = [0; 4096];
                    let n = socket.read(&mut buf).await.unwrap();
                    if n == 0 {
                        return;
                    }
                    bytes.extend_from_slice(&buf[..n]);
                    if let Some(i) = bytes.windows(4).position(|s| s == b"\r\n\r\n") {
                        header_end = i + 4;
                        break;
                    }
                }
                let head = String::from_utf8(bytes[..header_end].to_vec())
                    .unwrap()
                    .to_lowercase();
                let length: usize = head
                    .lines()
                    .find_map(|l| l.strip_prefix("content-length: "))
                    .unwrap_or("0")
                    .parse()
                    .unwrap();
                while bytes.len() < header_end + length {
                    let mut buf = [0; 4096];
                    let n = socket.read(&mut buf).await.unwrap();
                    bytes.extend_from_slice(&buf[..n]);
                }
                let body = serde_json::from_slice(&bytes[header_end..]).unwrap_or(Value::Null);
                record.lock().unwrap().push((head.clone(), body));
                let (code, body) = if head.starts_with("post ") {
                    tokio::time::sleep(Duration::from_millis(50)).await;
                    (
                        status,
                        json!({"access_token":"new", "refresh_token":"refresh-new", "expires_in":28800,
                        "refresh_token_expires_in":86400, "scope":"user:profile user:inference"}),
                    )
                } else if head.contains("authorization: bearer new") {
                    (200, json!({"five_hour":{"utilization":42}}))
                } else {
                    (401, json!({"error":{"message":"expired"}}))
                };
                let body = body.to_string();
                let reply = format!(
                    "HTTP/1.1 {code} Test\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{body}",
                    body.len()
                );
                socket.write_all(reply.as_bytes()).await.unwrap();
            }
        });
        (base, seen, task)
    }

    #[tokio::test]
    async fn abandoned_locks_recover_and_old_owner_cannot_remove_a_replacement() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join(".oauth_refresh.lock");
        std::fs::create_dir(&path).unwrap();
        std::fs::File::open(&path).unwrap().set_modified(SystemTime::now() - Duration::from_secs(61)).unwrap();
        let owner = RefreshLock::acquire(path.clone()).await.unwrap();
        std::fs::remove_dir(&path).unwrap();
        std::fs::create_dir(&path).unwrap();
        drop(owner);
        assert!(path.exists());
    }

    #[tokio::test]
    async fn parallel_quota_reads_renew_once_without_a_claude_process_and_preserve_metadata() {
        use std::os::unix::fs::PermissionsExt;
        let home = tempfile::tempdir().unwrap();
        let path = home.path().join(".credentials.json");
        std::fs::write(&path, credentials(1).to_string()).unwrap();
        let (base, seen, task) = provider(200).await;
        let env = Env::new();
        let check = || crate::quota::claude_with_refresh_at(&env, Some(home.path()), &base, &base);
        let (a, b) = tokio::join!(check(), check());
        for result in [a, b] {
            assert_eq!(result.unwrap().windows[0].used_percent, 42.0);
        }
        let requests = seen.lock().unwrap();
        let posts: Vec<_> = requests
            .iter()
            .filter(|(h, _)| h.starts_with("post "))
            .collect();
        assert_eq!(posts.len(), 1);
        assert_eq!(posts[0].1["refresh_token"], "refresh-old");
        assert_eq!(posts[0].1["client_id"], "test-client");
        drop(requests);
        let stored: Value = serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
        assert_eq!(stored["claudeAiOauth"]["refreshToken"], "refresh-new");
        assert_eq!(stored["claudeAiOauth"]["subscriptionType"], "max");
        assert_eq!(stored["otherCredential"]["keep"], true);
        assert_eq!(
            std::fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert!(!home.path().join(".oauth_refresh.lock").exists());
        task.abort();
    }

    #[tokio::test]
    async fn early_401_refreshes_and_retries_usage_once() {
        let home = tempfile::tempdir().unwrap();
        std::fs::write(
            home.path().join(".credentials.json"),
            credentials(now_ms() + 3_600_000).to_string(),
        )
        .unwrap();
        let (base, seen, task) = provider(200).await;
        let got =
            crate::quota::claude_with_refresh_at(&Env::new(), Some(home.path()), &base, &base)
                .await
                .unwrap();
        assert_eq!(got.state, "ok");
        let requests = seen.lock().unwrap();
        assert_eq!(requests.len(), 3);
        assert!(
            requests[0].0.starts_with("get ")
                && requests[1].0.starts_with("post ")
                && requests[2].0.starts_with("get ")
        );
        task.abort();
    }

    #[tokio::test]
    async fn failed_refresh_keeps_credentials_and_does_not_impose_a_30_minute_cooldown() {
        let home = tempfile::tempdir().unwrap();
        let path = home.path().join(".credentials.json");
        let original = credentials(1).to_string();
        std::fs::write(&path, &original).unwrap();
        let (base, _, task) = provider(503).await;
        let error = token_at(&Env::new(), Some(home.path()), None, &base)
            .await
            .unwrap_err()
            .to_string();
        assert!(error.contains("503") && !error.contains("refresh-old"));
        assert_eq!(std::fs::read_to_string(&path).unwrap(), original);
        task.abort();
        let (base, _, task) = provider(200).await;
        assert_eq!(
            token_at(&Env::new(), Some(home.path()), None, &base)
                .await
                .unwrap()
                .0,
            "new"
        );
        task.abort();
    }

    #[tokio::test]
    async fn waits_for_cli_legacy_lock_and_rereads_its_new_token() {
        let home = tempfile::tempdir().unwrap();
        let path = home.path().join(".credentials.json");
        std::fs::write(&path, credentials(1).to_string()).unwrap();
        let lock = PathBuf::from(format!(
            "{}.lock",
            std::fs::canonicalize(home.path()).unwrap().display()
        ));
        std::fs::create_dir(&lock).unwrap();
        let other = tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(100)).await;
            let mut data = credentials(now_ms() + 3_600_000);
            data["claudeAiOauth"]["accessToken"] = "cli-won".into();
            std::fs::write(path, data.to_string()).unwrap();
            std::fs::remove_dir(lock).unwrap();
        });
        let token = token_at(&Env::new(), Some(home.path()), None, "http://127.0.0.1:1")
            .await
            .unwrap();
        assert_eq!(token.0, "cli-won");
        other.await.unwrap();
    }

    #[tokio::test]
    #[cfg(target_os = "macos")]
    async fn machine_login_renews_in_keychain_and_never_uses_the_stale_file() {
        use std::os::unix::fs::PermissionsExt;
        let home = tempfile::tempdir().unwrap();
        let config = home.path().join(".claude");
        std::fs::create_dir(&config).unwrap();
        let file = config.join(".credentials.json");
        std::fs::write(&file, "stale file must not be read or replaced").unwrap();
        let keychain = home.path().join("keychain");
        std::fs::write(&keychain, credentials(1).to_string()).unwrap();
        let stub = home.path().join("security");
        std::fs::write(
            &stub,
            r#"#!/usr/bin/python3
import sys, os, json
p = os.path.join(os.environ['HOME'], 'keychain')
if sys.argv[1] == '-i':
    command = sys.stdin.read()
    value = bytes.fromhex(command.split(' -X "')[1].split('"')[0]).decode()
    json.loads(value)
    open(p, 'w').write(value)
else:
    print(open(p).read())
"#,
        )
        .unwrap();
        std::fs::set_permissions(stub, std::fs::Permissions::from_mode(0o700)).unwrap();
        let env = Env::from([
            ("HOME".into(), home.path().display().to_string()),
            ("PATH".into(), home.path().display().to_string()),
        ]);
        let (base, _, task) = provider(200).await;
        assert_eq!(token_at(&env, None, None, &base).await.unwrap().0, "new");
        let stored: Value = serde_json::from_slice(&std::fs::read(keychain).unwrap()).unwrap();
        assert_eq!(stored["claudeAiOauth"]["refreshToken"], "refresh-new");
        assert_eq!(
            std::fs::read_to_string(file).unwrap(),
            "stale file must not be read or replaced"
        );
        task.abort();
    }
}
