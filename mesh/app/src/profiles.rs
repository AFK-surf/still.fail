//! How a runtime account reaches its models. A profile picks one access kind; the station derives the environment (and,
//! for Codex, provider config overrides) from it, so nobody has to know which variables each runtime reads. "env" keeps
//! the raw form for anything else.

use std::collections::BTreeMap;

use stillfail_shapes::{AccessKind, RuntimeKind};

/// The access kinds each runtime can use.
pub fn access_kinds(runtime: RuntimeKind) -> &'static [AccessKind] {
    match runtime {
        RuntimeKind::Claude => &[AccessKind::Subscription, AccessKind::OpencodeGo, AccessKind::AnthropicApi, AccessKind::Env],
        RuntimeKind::Codex => &[AccessKind::Subscription, AccessKind::OpencodeGo, AccessKind::Env],
    }
}

/// Access kinds that authenticate with a key the profile stores.
pub fn keyed(kind: AccessKind) -> bool {
    matches!(kind, AccessKind::OpencodeGo | AccessKind::AnthropicApi)
}

pub const OPENCODE: &str = "https://opencode.ai/zen/go";

/// Environment an access kind needs. `{route}` is expanded per session later.
pub fn access_env(runtime: RuntimeKind, kind: AccessKind, key: &str, model: Option<&str>) -> BTreeMap<String, String> {
    let pairs: Vec<(&str, String)> = match (kind, runtime) {
        (AccessKind::OpencodeGo, RuntimeKind::Claude) => {
            let small = model.unwrap_or("deepseek-flash").to_string();
            vec![
                ("ANTHROPIC_BASE_URL", OPENCODE.to_string()),
                ("ANTHROPIC_API_KEY", key.to_string()),
                ("ANTHROPIC_CUSTOM_HEADERS", "x-opencode-session: {route}".to_string()),
                // Claude Code's background calls use a small model; point it at one the provider has.
                ("ANTHROPIC_DEFAULT_HAIKU_MODEL", small.clone()),
                ("ANTHROPIC_SMALL_FAST_MODEL", small),
                ("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", "1".to_string()),
            ]
        }
        // The provider's session key keeps the name of before the rename: its sessions go on under it.
        (AccessKind::OpencodeGo, RuntimeKind::Codex) => vec![("OPENCODE_GO_KEY", key.to_string()), ("OPENCODE_SESSION", "ember-{route}".to_string())],
        (AccessKind::AnthropicApi, _) => vec![("ANTHROPIC_API_KEY", key.to_string())],
        _ => vec![],
    };
    pairs.into_iter().map(|(k, v)| (k.to_string(), v)).collect()
}

/// Codex features the station's agents have no use for, off for every profile: apps starts the ChatGPT connectors' MCP server
/// (over the network, about 1.5 s of a new thread's start); recommended_plugins fetches and lists plugins that are not
/// installed (several KB of prompt, and a request a turn can wait on).
const CODEX_FEATURES_OFF: [(&str, &str); 2] = [("features.apps", "false"), ("features.recommended_plugins", "false")];

/// Codex reads its model provider from config; the station passes it as `-c` overrides when it starts the app-server,
/// so config.toml stays the user's. Values are TOML.
pub fn codex_overrides(kind: AccessKind, model: Option<&str>) -> BTreeMap<String, String> {
    let mut out: BTreeMap<String, String> = CODEX_FEATURES_OFF.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
    if kind != AccessKind::OpencodeGo {
        return out;
    }
    out.insert("model_provider".into(), "\"opencode-go\"".into());
    if let Some(model) = model {
        out.insert("model".into(), serde_json::to_string(model).unwrap_or_default());
    }
    out.insert("model_providers.opencode-go.name".into(), "\"OpenCode Go\"".into());
    out.insert("model_providers.opencode-go.base_url".into(), format!("\"{OPENCODE}/v1\""));
    out.insert("model_providers.opencode-go.env_key".into(), "\"OPENCODE_GO_KEY\"".into());
    out.insert("model_providers.opencode-go.wire_api".into(), "\"responses\"".into());
    out.insert("model_providers.opencode-go.env_http_headers".into(), "{\"x-opencode-session\"=\"OPENCODE_SESSION\"}".into());
    out
}

/// The command to sign a subscription profile in, run on the station's machine.
pub fn login_command(runtime: RuntimeKind, home: &str) -> String {
    match runtime {
        RuntimeKind::Claude => format!("CLAUDE_CONFIG_DIR={home} claude auth login"),
        RuntimeKind::Codex => format!("CODEX_HOME={home} codex login"),
    }
}

/// The runtimes an account runs, set up by the station for each: an OpenCode Go key both, an Anthropic key Claude Code;
/// a subscription (and custom variables) the runtime it was made for.
pub fn runtimes_of(kind: AccessKind, runtime: Option<RuntimeKind>) -> Vec<RuntimeKind> {
    match kind {
        AccessKind::OpencodeGo => vec![RuntimeKind::Claude, RuntimeKind::Codex],
        AccessKind::AnthropicApi => vec![RuntimeKind::Claude],
        _ => runtime.into_iter().collect(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_key_runs_every_runtime_it_can_and_a_subscription_its_own() {
        assert_eq!(runtimes_of(AccessKind::OpencodeGo, None), vec![RuntimeKind::Claude, RuntimeKind::Codex]);
        assert_eq!(runtimes_of(AccessKind::AnthropicApi, Some(RuntimeKind::Codex)), vec![RuntimeKind::Claude]);
        assert_eq!(runtimes_of(AccessKind::Subscription, Some(RuntimeKind::Codex)), vec![RuntimeKind::Codex]);
        assert_eq!(runtimes_of(AccessKind::Env, None), Vec::<RuntimeKind>::new());
    }

    #[test]
    fn opencode_go_sets_up_each_runtime_its_own_way() {
        let claude = access_env(RuntimeKind::Claude, AccessKind::OpencodeGo, "k", None);
        assert_eq!(claude["ANTHROPIC_BASE_URL"], OPENCODE);
        assert_eq!(claude["ANTHROPIC_SMALL_FAST_MODEL"], "deepseek-flash");
        let codex = access_env(RuntimeKind::Codex, AccessKind::OpencodeGo, "k", None);
        assert_eq!(codex["OPENCODE_SESSION"], "ember-{route}");
        let overrides = codex_overrides(AccessKind::OpencodeGo, Some("m"));
        assert_eq!(overrides["model"], "\"m\"");
        assert_eq!(codex_overrides(AccessKind::Subscription, None).len(), 2);
    }
}

/// Whether a profile works, and what models it offers (as the station keeps it, JSON the same as the TS station's).
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProfileCheck {
    /// ok: usable; login: needs a subscription sign-in; failed: the key or login was rejected; unknown.
    pub state: String,
    pub detail: String,
    /// Models the account can use, when the provider lists them.
    pub models: Option<Vec<String>>,
    pub checked_at: i64,
}

/// A window of an allowance.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QuotaWindow {
    pub label: String,
    /// 0–100.
    pub used_percent: f64,
    /// Epoch ms; none when the provider does not say.
    pub resets_at: Option<i64>,
}

/// How much of a profile's allowance is used, where the provider says.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProfileQuota {
    /// ok: windows filled; unsupported: nothing to show for this kind; unavailable: could not ask; blocked: the
    /// provider refuses the account (suspended, on hold, deactivated).
    pub state: String,
    pub windows: Vec<QuotaWindow>,
    pub detail: Option<String>,
    pub checked_at: i64,
}

// ── checks ─────────────────────────────────────────────────────────────────

/// What a profile check is given: the account and where it lives.
pub struct CheckOptions<'a> {
    pub runtime: RuntimeKind,
    pub kind: AccessKind,
    pub key: &'a str,
    pub home: &'a std::path::Path,
    pub env: &'a crate::machine_logins::Env,
    /// On the machine's own login (machine_logins.rs).
    pub machine: bool,
}

fn check(state: &str, detail: impl Into<String>, models: Option<Vec<String>>) -> ProfileCheck {
    ProfileCheck { state: state.into(), detail: detail.into(), models, checked_at: crate::store::now_ms() }
}

fn http() -> reqwest::Client {
    reqwest::Client::builder().timeout(std::time::Duration::from_secs(15)).build().unwrap_or_default()
}

/// The ids of a `/v1/models` answer.
async fn model_ids(response: reqwest::Response) -> anyhow::Result<Vec<String>> {
    let body: serde_json::Value = response.json().await?;
    Ok(body["data"].as_array().map(|a| a.iter().filter_map(|m| m["id"].as_str().map(String::from)).collect()).unwrap_or_default())
}

/// The models a Claude subscription's OAuth token may use; None when Anthropic does not say.
async fn claude_models(token: &str) -> Option<Vec<String>> {
    let response = http()
        .get("https://api.anthropic.com/v1/models?limit=100")
        .bearer_auth(token)
        .header("anthropic-version", "2023-06-01")
        .header("anthropic-beta", "oauth-2025-04-20")
        .send()
        .await
        .ok()?;
    if !response.status().is_success() {
        return None;
    }
    model_ids(response).await.ok()
}

/// Runs a runtime's own status command; its output, or why it could not run.
async fn status_of(command: &str, args: &[&str], env: &crate::machine_logins::Env) -> anyhow::Result<std::process::Output> {
    let run = tokio::process::Command::new(command).args(args).env_clear().envs(env).stdin(std::process::Stdio::null()).kill_on_drop(true).output();
    Ok(tokio::time::timeout(std::time::Duration::from_secs(20), run).await.map_err(|_| anyhow::anyhow!("{command} {} timed out", args.join(" ")))??)
}

/// Asks the provider or runtime whether this profile works, and what models it offers. (checkProfile)
pub async fn check_profile(o: CheckOptions<'_>) -> ProfileCheck {
    match check_inner(&o).await {
        Ok(check) => check,
        Err(e) => check("failed", format!("检查失败：{e}"), None),
    }
}

async fn check_inner(o: &CheckOptions<'_>) -> anyhow::Result<ProfileCheck> {
    match (o.kind, o.runtime) {
        (AccessKind::OpencodeGo, _) => {
            // The model list answers any key; the usage is the key's own, so it is what tells a key that works.
            let usage = http().get(format!("{OPENCODE}/v1/usage")).bearer_auth(o.key).send().await?;
            if !usage.status().is_success() {
                return Ok(check("failed", format!("OpenCode Go 拒绝了这个 key（{}）", usage.status().as_u16()), None));
            }
            let response = http().get(format!("{OPENCODE}/v1/models")).bearer_auth(o.key).send().await?;
            if !response.status().is_success() {
                return Ok(check("failed", format!("读不到 OpenCode Go 的模型（{}）", response.status().as_u16()), None));
            }
            let mut models = model_ids(response).await?;
            models.sort();
            Ok(check("ok", format!("可用，{} 个模型", models.len()), Some(models)))
        }
        (AccessKind::AnthropicApi, _) => {
            let response = http()
                .get("https://api.anthropic.com/v1/models?limit=100")
                .header("x-api-key", o.key)
                .header("anthropic-version", "2023-06-01")
                .send()
                .await?;
            if !response.status().is_success() {
                return Ok(check("failed", format!("Anthropic 拒绝了这个 key（{}）", response.status().as_u16()), None));
            }
            let models = model_ids(response).await?;
            Ok(check("ok", format!("可用，{} 个模型", models.len()), Some(models)))
        }
        (AccessKind::Subscription, RuntimeKind::Claude) => {
            let mut env = o.env.clone();
            env.insert("CLAUDE_CONFIG_DIR".into(), o.home.to_string_lossy().into_owned());
            let machine_token = if o.machine { Some(crate::machine_logins::machine_claude_token(o.env).await?.0) } else { None };
            match &machine_token {
                Some(token) => {
                    env.insert("CLAUDE_CODE_OAUTH_TOKEN".into(), token.clone());
                }
                None => {
                    crate::no_keychain::take_back(o.home).await;
                    crate::no_keychain::file_credentials(&mut env);
                }
            }
            let output = status_of("claude", &["auth", "status"], &env).await?;
            // Signed out, it says so and exits 1: its answer is still the JSON on stdout.
            let stdout = String::from_utf8_lossy(&output.stdout);
            if !output.status.success() && !(output.status.code() == Some(1) && stdout.trim_start().starts_with('{')) {
                anyhow::bail!("Command failed: claude auth status\n{}", String::from_utf8_lossy(&output.stderr));
            }
            let status: serde_json::Value = serde_json::from_str(&stdout)?;
            if status["loggedIn"] != true {
                return Ok(check("login", "还没登录", None));
            }
            // What the subscription runs, as Anthropic lists it for the account's own token.
            let token = machine_token.or_else(|| crate::quota::claude_token(o.home));
            let models = match token {
                Some(token) => claude_models(&token).await,
                None => None,
            };
            let detail: Vec<&str> = ["已登录", status["email"].as_str().unwrap_or(""), status["subscriptionType"].as_str().unwrap_or("")].into_iter().filter(|s| !s.is_empty()).collect();
            Ok(check("ok", detail.join("，"), models))
        }
        (AccessKind::Subscription, RuntimeKind::Codex) => {
            if o.machine {
                crate::machine_logins::link_codex_auth(o.home, o.env)?;
            }
            let mut env = o.env.clone();
            env.insert("CODEX_HOME".into(), o.home.to_string_lossy().into_owned());
            let output = status_of("codex", &["login", "status"], &env).await?;
            let text = format!("{}{}", String::from_utf8_lossy(&output.stdout), String::from_utf8_lossy(&output.stderr)).trim().to_string();
            if text.to_lowercase().contains("not logged in") {
                return Ok(check("login", "还没登录", None));
            }
            if !output.status.success() {
                anyhow::bail!("Command failed: codex login status\n{text}");
            }
            Ok(check("ok", text.lines().next().unwrap_or("已登录").to_string(), None))
        }
        _ => Ok(check("unknown", "自定义环境变量，still.fail 无法自动检查", None)),
    }
}
