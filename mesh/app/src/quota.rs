//! How much of a profile's allowance is used, where the provider says:
//! - OpenCode Go: GET /zen/go/v1/usage (rolling, weekly and monthly windows);
//! - ChatGPT subscription (Codex): the app-server's account/rateLimits/read;
//! - Claude subscription: Claude Code's OAuth usage endpoint (what /usage shows), with the token Claude Code keeps in
//!   the profile's home (profile logins live in files, never the keychain: see the runtime's stand-in `security`);
//! - Anthropic API keys bill per use and have no allowance to show.

use std::path::Path;
use std::time::Duration;

use anyhow::{Result, bail};
use stillfail_shapes::{AccessKind, RuntimeKind};
use futures_util::future::BoxFuture;
use serde_json::Value;

use crate::config::Profile;
use crate::machine_logins::{Env, codex_auth_file};
use crate::profiles::{OPENCODE, ProfileQuota, QuotaWindow};
use crate::store::now_ms;
use crate::transcript::parse_iso;

const ANTHROPIC: &str = "https://api.anthropic.com";
const CHATGPT: &str = "https://chatgpt.com";
const TIMEOUT: Duration = Duration::from_secs(15);

fn quota(state: &str, windows: Vec<QuotaWindow>, detail: Option<String>) -> ProfileQuota {
    ProfileQuota { credits: None, reset_count: None, state: state.into(), windows, detail, checked_at: now_ms() }
}

fn ok_or_unavailable(windows: Vec<QuotaWindow>, empty: &str) -> ProfileQuota {
    if windows.is_empty() { quota("unavailable", vec![], Some(empty.into())) } else { quota("ok", windows, None) }
}

/// A time as a provider gives it: epoch seconds or ms, or an ISO string.
fn at(value: Option<&Value>) -> Option<i64> {
    match value? {
        Value::Number(n) => {
            let n = n.as_f64()?;
            Some(if n > 1e12 { n as i64 } else { (n * 1000.0) as i64 })
        }
        Value::String(s) if !s.is_empty() => parse_iso(s),
        _ => None,
    }
}

fn percent(value: Option<&Value>) -> f64 {
    let n = match value {
        Some(Value::Number(n)) => n.as_f64().unwrap_or(0.0),
        Some(Value::String(s)) => s.trim().parse().unwrap_or(0.0),
        _ => 0.0,
    };
    n.round().clamp(0.0, 100.0)
}

fn window_label(minutes: Option<f64>, fallback: &str) -> String {
    let Some(minutes) = minutes.filter(|m| *m > 0.0) else { return fallback.into() };
    if minutes <= 60.0 * 6.0 {
        return format!("{} 小时", (minutes / 60.0).round());
    }
    if (60.0 * 24.0 * 6.0..=60.0 * 24.0 * 8.0).contains(&minutes) {
        return "每周".into();
    }
    if minutes >= 60.0 * 24.0 * 27.0 {
        return "每月".into();
    }
    format!("{} 天", (minutes / 60.0 / 24.0).round())
}

fn http() -> reqwest::Client {
    reqwest::Client::builder().timeout(TIMEOUT).build().unwrap_or_default()
}

/// Whether a provider's words refuse an account itself, not a token or a request.
pub fn blocked(text: &str) -> bool {
    let lower = text.to_lowercase();
    ["on hold", "restricted", "suspend", "disabled", "deactivat", "banned", "terminated", "violat"].iter().any(|w| lower.contains(w))
}

/// A provider's error body, in a line when it has one.
fn message(text: &str) -> String {
    let Ok(body) = serde_json::from_str::<Value>(text) else { return String::new() };
    let said = match body.get("error") {
        Some(Value::String(s)) => Some(s.clone()),
        Some(error) => error.get("message").and_then(Value::as_str).map(String::from),
        None => None,
    }
    .or_else(|| body.get("detail").and_then(Value::as_str).map(String::from))
    .or_else(|| body.get("message").and_then(Value::as_str).map(String::from));
    match said {
        Some(said) => format!("：{}", said.chars().take(200).collect::<String>()),
        None => String::new(),
    }
}

/// A provider's refusal as a quota: the account refused (blocked), or its sign-in no longer good.
async fn refused(provider: &str, response: reqwest::Response) -> ProfileQuota {
    let status = response.status().as_u16();
    let text: String = response.text().await.unwrap_or_default().chars().take(500).collect();
    if blocked(&text) || status == 403 {
        return quota("blocked", vec![], Some(format!("{provider}拒绝了这个账号（{status}）{}", message(&text))));
    }
    if status == 401 {
        return quota("unavailable", vec![], Some("登录过期或失效了".into()));
    }
    quota("unavailable", vec![], Some(format!("{provider}返回 {status}")))
}

async fn opencode(key: &str) -> Result<ProfileQuota> {
    let response = http().get(format!("{OPENCODE}/v1/usage")).bearer_auth(key).send().await?;
    if !response.status().is_success() {
        bail!("OpenCode Go 返回 {}", response.status().as_u16());
    }
    let body: Value = response.json().await?;
    let windows = body
        .get("usage")
        .and_then(Value::as_object)
        .map(|usage| {
            usage
                .iter()
                .map(|(k, w)| {
                    let label = match k.as_str() {
                        "rolling" => "5 小时",
                        "weekly" => "每周",
                        "monthly" => "每月",
                        other => other,
                    };
                    QuotaWindow { label: label.into(), used_percent: percent(w.get("percent")), resets_at: at(w.get("resetsAt")) }
                })
                .collect()
        })
        .unwrap_or_default();
    Ok(quota("ok", windows, None))
}

/// The OAuth token Claude Code keeps in this config directory.
pub fn claude_token(home: &Path) -> Option<String> {
    let text = std::fs::read_to_string(home.join(".credentials.json")).ok()?;
    let value: Value = serde_json::from_str(&text).ok()?;
    value.get("claudeAiOauth")?.get("accessToken")?.as_str().filter(|t| !t.is_empty()).map(String::from)
}

async fn claude(profile: &Profile, env: &Env) -> Result<ProfileQuota> {
    let home = if profile.machine { None } else { Some(profile.home.as_path()) };
    claude_with_refresh(env, home, ANTHROPIC).await
}

async fn claude_with_refresh(env: &Env, home: Option<&Path>, base: &str) -> Result<ProfileQuota> {
    claude_with_refresh_at(env, home, base, crate::claude_oauth::TOKEN_URL).await
}

pub(crate) async fn claude_with_refresh_at(env: &Env, home: Option<&Path>, base: &str, endpoint: &str) -> Result<ProfileQuota> {
    let (token, _) = crate::claude_oauth::token_at(env, home, None, endpoint).await?;
    let (quota, unauthorized) = claude_usage_response(base, &token).await?;
    if !unauthorized { return Ok(quota); }
    let (renewed, _) = crate::claude_oauth::token_at(env, home, Some(&token), endpoint).await?;
    claude_usage_at(base, &renewed).await
}

/// A Claude subscription's allowance, by its access token: what /usage shows.
pub async fn claude_usage(token: &str) -> Result<ProfileQuota> {
    claude_usage_at(ANTHROPIC, token).await
}

async fn claude_usage_at(base: &str, token: &str) -> Result<ProfileQuota> {
    Ok(claude_usage_response(base, token).await?.0)
}

async fn claude_usage_response(base: &str, token: &str) -> Result<(ProfileQuota, bool)> {
    let response = http().get(format!("{base}/api/oauth/usage")).bearer_auth(token).header("anthropic-beta", "oauth-2025-04-20").send().await?;
    if !response.status().is_success() {
        let unauthorized = response.status().as_u16() == 401;
        return Ok((refused("Anthropic ", response).await, unauthorized));
    }
    let body: Value = response.json().await?;
    let label = |k: &str| match k {
        "five_hour" => Some("5 小时"),
        "seven_day" => Some("每周"),
        "seven_day_opus" => Some("每周 · Opus"),
        "seven_day_sonnet" => Some("每周 · Sonnet"),
        _ => None,
    };
    let windows = body
        .as_object()
        .map(|data| {
            data.iter()
                .filter(|(_, w)| w.is_object())
                .filter_map(|(k, w)| {
                    Some(QuotaWindow { label: label(k)?.into(), used_percent: percent(w.get("utilization")), resets_at: at(w.get("resets_at")) })
                })
                .collect()
        })
        .unwrap_or_default();
    Ok((quota("ok", windows, None), false))
}

fn codex_windows(result: &Value) -> Vec<QuotaWindow> {
    let limits = result.get("rateLimits").filter(|l| l.is_object()).unwrap_or(result);
    [("primary", "5 小时"), ("secondary", "每周")]
        .into_iter()
        .filter_map(|(key, fallback)| {
            let w = limits.get(key).filter(|w| w.is_object())?;
            Some(QuotaWindow {
                label: window_label(w.get("windowDurationMins").and_then(Value::as_f64), fallback),
                used_percent: percent(w.get("usedPercent")),
                resets_at: at(w.get("resetsAt")),
            })
        })
        .collect()
}

fn with_codex_credits(mut quota: ProfileQuota, limits: &Value, resets: &Value) -> ProfileQuota {
    quota.credits = limits.get("credits").filter(|v| v.is_object()).map(|c| crate::profiles::QuotaCredits {
        has_credits: c.get("hasCredits").or_else(|| c.get("has_credits")).and_then(Value::as_bool).unwrap_or(false),
        unlimited: c.get("unlimited").and_then(Value::as_bool).unwrap_or(false),
        balance: c.get("balance").and_then(|b| match b { Value::String(s) => Some(s.clone()), Value::Number(n) => Some(n.to_string()), _ => None }),
    });
    quota.reset_count = resets.get("availableCount").or_else(|| resets.get("available_count")).and_then(Value::as_u64);
    if quota.credits.is_some() || quota.reset_count.is_some() { quota.state = "ok".into(); quota.detail = None; }
    quota
}

fn codex_quota(result: &Value) -> ProfileQuota {
    let limits = result.get("rateLimits").filter(|v| v.is_object()).unwrap_or(result);
    with_codex_credits(ok_or_unavailable(codex_windows(result), "ChatGPT 没有返回额度信息"), limits, &result["rateLimitResetCredits"])
}

/// Reaches a profile's codex app-server for its account/rateLimits/read.
pub type CodexRateLimits<'a> = &'a (dyn Fn(&Profile) -> BoxFuture<'static, Result<Value>> + Send + Sync);

/// Asks the provider. `codex_rate_limits` reaches the profile's codex app-server; `env` is the station's (for a
/// machine profile's login).
pub async fn check_quota(profile: &Profile, env: &Env, codex_rate_limits: CodexRateLimits<'_>) -> ProfileQuota {
    let asked = async {
        match profile.access_kind {
            AccessKind::OpencodeGo => opencode(&profile.key).await,
            AccessKind::AnthropicApi => Ok(quota("unsupported", vec![], Some("按量计费，没有额度上限".into()))),
            AccessKind::Env => Ok(quota("unsupported", vec![], Some("自定义环境变量的账号查不了额度".into()))),
            AccessKind::Subscription if profile.runtime == RuntimeKind::Claude => claude(profile, env).await,
            AccessKind::Subscription => {
                let limits = codex_rate_limits(profile).await?;
                Ok(codex_quota(&limits))
            }
        }
    };
    asked.await.unwrap_or_else(|e| failed(&e))
}

fn failed(error: &anyhow::Error) -> ProfileQuota {
    let detail = format!("{error:#}");
    quota(if blocked(&detail) { "blocked" } else { "unavailable" }, vec![], Some(detail))
}

/// A ChatGPT subscription's allowance read with the tokens of a Codex auth.json (the machine's own login, which no
/// app-server of the station's runs on until a profile uses it): what Codex's /status shows, from the same endpoint.
/// None when there is no such file (or no token in it).
pub async fn codex_usage(auth_file: &Path) -> Result<Option<ProfileQuota>> {
    codex_usage_at(CHATGPT, auth_file).await
}

async fn codex_usage_at(base: &str, auth_file: &Path) -> Result<Option<ProfileQuota>> {
    let Some(tokens) = std::fs::read_to_string(auth_file).ok().and_then(|t| serde_json::from_str::<Value>(&t).ok()).and_then(|v| v.get("tokens").cloned()) else {
        return Ok(None);
    };
    let Some(access) = tokens.get("access_token").and_then(Value::as_str).filter(|t| !t.is_empty()) else { return Ok(None) };
    let mut request = http().get(format!("{base}/backend-api/wham/usage")).bearer_auth(access).header("user-agent", "codex_cli_rs");
    if let Some(account) = tokens.get("account_id").and_then(Value::as_str) {
        request = request.header("chatgpt-account-id", account);
    }
    let response = request.send().await?;
    if !response.status().is_success() {
        return Ok(Some(refused("ChatGPT ", response).await));
    }
    let body: Value = response.json().await?;
    let windows = [("primary_window", "5 小时"), ("secondary_window", "每周")]
        .into_iter()
        .filter_map(|(key, fallback)| {
            let w = body.get("rate_limit")?.get(key).filter(|w| w.is_object())?;
            Some(QuotaWindow {
                label: window_label(w.get("limit_window_seconds").and_then(Value::as_f64).map(|s| s / 60.0), fallback),
                used_percent: percent(w.get("used_percent")),
                resets_at: at(w.get("reset_at")),
            })
        })
        .collect();
    Ok(Some(with_codex_credits(ok_or_unavailable(windows, "ChatGPT 没有返回额度信息"), &body, &body["rate_limit_reset_credits"])))
}

/// The allowance of the machine's own login of a runtime (machine_logins.rs), read without starting anything of the
/// station's. None when there is nothing to read it with.
pub async fn machine_usage(runtime: RuntimeKind, env: Env) -> Option<ProfileQuota> {
    let read = async {
        match runtime {
            RuntimeKind::Codex => codex_usage(&codex_auth_file(&env)).await,
            RuntimeKind::Claude => claude_with_refresh(&env, None, ANTHROPIC).await.map(Some),
        }
    };
    read.await.unwrap_or_else(|e| Some(failed(&e)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    /// A provider that answers every request with `status` and `body`, keeping what it was asked (the request head).
    async fn provider(status: u16, body: String) -> (String, Arc<Mutex<Vec<String>>>) {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let asked = Arc::new(Mutex::new(Vec::new()));
        let seen = asked.clone();
        tokio::spawn(async move {
            while let Ok((mut socket, _)) = listener.accept().await {
                let mut buf = vec![0u8; 16384];
                let n = socket.read(&mut buf).await.unwrap_or(0);
                seen.lock().unwrap().push(String::from_utf8_lossy(&buf[..n]).to_lowercase());
                let reply = format!("HTTP/1.1 {status} X\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{body}", body.len());
                let _ = socket.write_all(reply.as_bytes()).await;
            }
        });
        (base, asked)
    }

    #[tokio::test]
    async fn an_account_its_provider_refuses_is_blocked_a_sign_in_no_longer_good_is_not() {
        let (base, _) = provider(403, r#"{"error":{"message":"This organization has been disabled."}}"#.into()).await;
        let blocked = claude_usage_at(&base, "t").await.unwrap();
        assert_eq!(blocked.state, "blocked");
        assert!(blocked.detail.unwrap().contains("This organization has been disabled"));
        let (base, _) = provider(401, r#"{"error":{"message":"OAuth token has expired"}}"#.into()).await;
        let expired = claude_usage_at(&base, "t").await.unwrap();
        assert_eq!((expired.state.as_str(), expired.detail.as_deref()), ("unavailable", Some("登录过期或失效了")));
        let (base, _) = provider(401, r#"{"detail":"Your account has been deactivated"}"#.into()).await;
        assert_eq!(claude_usage_at(&base, "t").await.unwrap().state, "blocked");
    }

    #[tokio::test]
    async fn a_codex_logins_allowance_is_read_with_its_auth_jsons_tokens() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("auth.json");
        std::fs::write(&file, r#"{"tokens":{"access_token":"at","account_id":"acc"}}"#).unwrap();
        let body = serde_json::json!({ "rate_limit": {
            "primary_window": { "used_percent": 30, "limit_window_seconds": 18_000, "reset_at": 1_900_000_000 },
            "secondary_window": { "used_percent": 80, "limit_window_seconds": 604_800, "reset_at": 1_900_500_000 },
        } });
        let (base, asked) = provider(200, body.to_string()).await;
        let quota = codex_usage_at(&base, &file).await.unwrap().unwrap();
        assert_eq!(
            quota.windows,
            [
                QuotaWindow { label: "5 小时".into(), used_percent: 30.0, resets_at: Some(1_900_000_000_000) },
                QuotaWindow { label: "每周".into(), used_percent: 80.0, resets_at: Some(1_900_500_000_000) },
            ]
        );
        let head = asked.lock().unwrap()[0].clone();
        assert!(head.contains("authorization: bearer at") && head.contains("chatgpt-account-id: acc"), "{head}");
        // No file (the keychain keeps it): nothing to read.
        assert!(codex_usage_at(&base, &dir.path().join("none").join("auth.json")).await.unwrap().is_none());
    }

    #[test]
    fn codex_credits_and_resets_are_independent_of_windows_and_preserve_unknowns() {
        let q = codex_quota(&serde_json::json!({ "rateLimits": {"credits": {"hasCredits": true, "unlimited": false, "balance": "123.45"}}, "rateLimitResetCredits": {"availableCount": 2, "credits": []} }));
        assert_eq!(q.state, "ok");
        assert!(q.windows.is_empty());
        assert_eq!(q.credits.unwrap().balance.as_deref(), Some("123.45"));
        assert_eq!(q.reset_count, Some(2));
        let old = codex_quota(&serde_json::json!({"rateLimits": {"primary": {"usedPercent": 10}}}));
        assert!(old.credits.is_none());
        assert!(old.reset_count.is_none());
        let unlimited = codex_quota(&serde_json::json!({"rateLimits": {"credits": {"hasCredits": true, "unlimited": true, "balance": null}}}));
        assert!(unlimited.credits.unwrap().unlimited);
        let zero = codex_quota(&serde_json::json!({"rateLimits": {"credits": {"hasCredits": false, "unlimited": false, "balance": "0"}}, "rateLimitResetCredits": {"availableCount": 0}}));
        assert_eq!(zero.reset_count, Some(0));
        assert_eq!(zero.credits.unwrap().balance.as_deref(), Some("0"));
    }

    #[test]
    fn codex_app_server_limits_and_window_names() {
        let limits = serde_json::json!({ "rateLimits": { "primary": { "usedPercent": 12.4, "windowDurationMins": 300, "resetsAt": 1_900_000_000 }, "secondary": null } });
        assert_eq!(codex_windows(&limits), [QuotaWindow { label: "5 小时".into(), used_percent: 12.0, resets_at: Some(1_900_000_000_000) }]);
        assert_eq!(window_label(Some(10080.0), "x"), "每周");
        assert_eq!(window_label(Some(43200.0), "x"), "每月");
        assert_eq!(window_label(Some(2880.0), "x"), "2 天");
        assert_eq!(window_label(None, "每周"), "每周");
        assert_eq!(at(Some(&Value::String("2026-09-27T00:00:02.500Z".into()))), parse_iso("2026-09-27T00:00:02.500Z"));
    }
}
