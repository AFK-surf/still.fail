//! Decision transport belongs to an existing profile. Discovery probes only synthetic evidence;
//! real conversation evidence goes only to a transport whose probability response was verified.
use super::{DecisionConfig, Mode, Provider, completion_question, decide};
use crate::{config::Profile, profiles::ProfileCheck};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use stillfail_shapes::{AccessKind, RuntimeKind};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Capability {
    pub state: String,
    pub detail: String,
    pub model: Option<String>,
    pub provider: Option<Provider>,
    pub fingerprint: String,
    #[serde(default)]
    pub models: Vec<String>,
}

// Hash stays station-side (the admin view strips it). Never persist credentials in a probe result.
pub fn fingerprint(profile: &Profile) -> String {
    let connection = connection(profile);
    hex::encode(Sha256::digest(json!([profile.id, profile.access_kind, profile.home,
        profile.models, profile.model, connection.as_ref().map(|c| (&c.base, &c.key, c.provider))]).to_string()))
}

struct Connection { base: String, key: String, provider: Provider }
fn connection(profile: &Profile) -> Option<Connection> {
    let mut env = profile.env(RuntimeKind::Codex);
    env.extend(profile.custom_env.clone());
    let get = |key: &str| env.get(key).filter(|v| !v.trim().is_empty()).cloned();
    if let Some(key) = get("TYPESAFE_API_KEY").or_else(|| get("JEV_API_KEY")) {
        return Some(Connection { base: get("TYPESAFE_BASE_URL").unwrap_or("https://api.typesafe.ai/v1".into()), key, provider: Provider::Jev });
    }
    if profile.access_kind == AccessKind::OpencodeGo {
        return Some(Connection { base: "https://opencode.ai/zen/go/v1".into(), key: profile.key.clone(), provider: Provider::ChatLogprobs });
    }
    if !profile.runtimes.contains(&RuntimeKind::Codex) { return None; }
    let config_path = profile.home.join("config.toml");
    let config: toml::Value = if config_path.exists() {
        std::fs::read_to_string(config_path).ok()?.parse().ok()?
    } else { toml::Value::Table(Default::default()) };
    let provider = config.get("model_provider").and_then(toml::Value::as_str).unwrap_or("openai");
    let entry = config.get("model_providers").and_then(|v| v.get(provider));
    let base = entry.and_then(|v| v.get("base_url")).and_then(toml::Value::as_str).map(String::from)
        .or_else(|| (provider == "openai").then(|| get("OPENAI_BASE_URL").unwrap_or("https://api.openai.com/v1".into())))?;
    let env_key = entry.and_then(|v| v.get("env_key")).and_then(toml::Value::as_str)
        .or_else(|| (provider == "openai").then_some("OPENAI_API_KEY"))?;
    let key = get(env_key).or_else(|| {
        // API-key logins only. OAuth subscription tokens are not API keys.
        if provider != "openai" { return None; }
        let auth: Value = serde_json::from_slice(&std::fs::read(profile.home.join("auth.json")).ok()?).ok()?;
        auth["OPENAI_API_KEY"].as_str().filter(|s| !s.is_empty()).map(String::from)
    })?;
    Some(Connection { base, key, provider: Provider::ChatLogprobs })
}

fn transport(connection: &Connection, model: String) -> DecisionConfig {
    let suffix = match connection.provider { Provider::Jev => "systemone", Provider::ChatLogprobs => "chat/completions" };
    DecisionConfig { provider: connection.provider, endpoint: format!("{}/{suffix}", connection.base.trim_end_matches('/')),
        model, api_key: connection.key.clone(), mode: Mode::Enforce, threshold: 0.85 }
}

pub fn resolved(profile: &Profile, capability: &Capability) -> Option<DecisionConfig> {
    resolved_model(profile, capability, capability.model.as_deref())
}
pub fn resolved_model(profile: &Profile, capability: &Capability, chosen: Option<&str>) -> Option<DecisionConfig> {
    if capability.state != "ready" || capability.fingerprint != fingerprint(profile) { return None; }
    let connection = connection(profile)?;
    if Some(connection.provider) != capability.provider { return None; }
    let model = chosen?;
    if !capability.models.iter().any(|m| m == model) && capability.model.as_deref() != Some(model) { return None; }
    Some(transport(&connection, model.into()))
}

/// Stable preference: native decisions, then small models. Every chosen model must pass a probe;
/// a name, model-list entry or a saved enabled-model toggle alone is never proof of support.
fn priority(model: &str) -> (u8, &str) {
    let name = model.to_ascii_lowercase();
    (if name.contains("jev") { 0 } else if name.contains("luna") { 1 }
        else if name.contains("nano") { 2 } else if name.contains("mini") || name.contains("flash") { 3 } else { 4 }, model)
}

pub async fn discover(profile: &Profile, check: &ProfileCheck) -> Capability {
    let mut capability = Capability { state: "unsupported".into(), detail: "当前登录未提供决策概率接口".into(),
        model: None, provider: None, models:vec![], fingerprint: fingerprint(profile) };
    if matches!(check.state.as_str(), "login" | "failed") {
        capability.state = "unavailable".into(); capability.detail = "账号恢复后自动检查决策能力".into(); return capability;
    }
    let Some(connection) = connection(profile) else { return capability; };
    let mut models = check.models.clone().unwrap_or_default();
    models.extend(profile.models.clone());
    models.extend(profile.model.clone());
    if connection.provider == Provider::Jev { models.push("jev-latest".into()); }
    let sample = transport(&connection, "discovery".into());
    if sample.validate().is_err() {
        capability.detail = "Profile 的接口地址不支持决策检查".into(); return capability;
    }
    // Env profiles are not listed by their coding runtime. Discover using that profile's own API.
    if models.is_empty() {
        if let Ok(client) = reqwest::Client::builder().timeout(std::time::Duration::from_secs(8))
            .redirect(reqwest::redirect::Policy::none()).build() {
            if let Ok(response) = client.get(format!("{}/models", connection.base.trim_end_matches('/'))).bearer_auth(&connection.key).send().await {
                if response.status().is_success() {
                    if let Ok(body) = response.json::<Value>().await {
                        models.extend(body["data"].as_array().into_iter().flatten().filter_map(|m| m["id"].as_str().map(String::from)));
                    }
                }
            }
        }
    }
    models.sort_by(|a,b| priority(a).cmp(&priority(b))); models.dedup();
    // Bound discovery work; no conversation data, tools or coding agent is involved.
    let mut verified = Vec::new();
    let probe = async {
        for model in models.into_iter().take(8) {
            let config = transport(&connection, model);
            if let Ok(result) = decide(&config, &completion_question(), &json!({"user":"What is 2 + 2?", "proposedPost":"4", "done":"Answered the arithmetic question"})).await {
                if result.accepts_completion(config.threshold) { verified.push(config.model); }
            }
        }
    };
    let _ = tokio::time::timeout(std::time::Duration::from_secs(25), probe).await;
    if let Some(model) = verified.first() {
        capability.state = "ready".into(); capability.detail = format!("已识别 {} 个决策模型", verified.len());
        capability.model = Some(model.clone()); capability.provider = Some(connection.provider); capability.models = verified;
    } else {
        capability.state = "unavailable".into(); capability.detail = "尚未验证可用的决策模型".into();
    }
    capability
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    fn profile(base: &str) -> Profile {
        let raw = serde_json::from_value(json!({"profiles":[{"id":"existing","home":"homes/existing","runtime":"codex","access":{"kind":"env"},"env":{
            "OPENAI_API_KEY":"private-profile-key", "OPENAI_BASE_URL":base
        },"models":["gpt-6-luna"]}]})).unwrap();
        crate::config::parse_config(&raw, std::path::Path::new("/nonexistent-decision-test")).unwrap().profiles.remove(0)
    }
    fn check() -> ProfileCheck {
        ProfileCheck { decision:None, model_efforts:None, state:"unknown".into(), detail:String::new(), models:None, checked_at:0 }
    }
    #[tokio::test]
    async fn decision_discovery_uses_profile_credentials_and_requires_real_logprobs() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}",listener.local_addr().unwrap());
        let task = tokio::spawn(async move {
            for valid in [false, true] {
                let (mut socket, _) = listener.accept().await.unwrap();
                let mut bytes = Vec::new(); let mut buffer=[0;8192];
                let offset = loop {
                    let n=socket.read(&mut buffer).await.unwrap(); assert!(n>0);
                    bytes.extend_from_slice(&buffer[..n]);
                    if let Some(end)=bytes.windows(4).position(|w|w==b"\r\n\r\n") {
                        let headers=String::from_utf8_lossy(&bytes[..end]).to_lowercase();
                        let size:usize=headers.lines().find_map(|l|l.strip_prefix("content-length: ")).unwrap().parse().unwrap();
                        if bytes.len()>=end+4+size {
                            assert!(headers.starts_with("post /chat/completions "));
                            assert!(headers.contains("authorization: bearer private-profile-key"));
                            break end+4;
                        }
                    }
                };
                let body:Value=serde_json::from_slice(&bytes[offset..]).unwrap();
                assert_eq!(body["model"],"gpt-6-luna"); assert_eq!(body["reasoning_effort"],"none");
                assert_eq!(body["max_completion_tokens"],1);
                let tokens:Vec<_>=[("A",0.01_f64),("B",0.97),("C",0.01),("D",0.01)].iter()
                    .map(|(token,p)|json!({"token":token,"logprob":p.ln()})).collect();
                let response=if valid {json!({"choices":[{"logprobs":{"content":[{"top_logprobs":tokens}]}}]})}
                    else {json!({"choices":[{"message":{"content":"B"}}]})}.to_string();
                socket.write_all(format!("HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{response}",response.len()).as_bytes()).await.unwrap();
            }
        });
        let mut p=profile(&base);
        let rejected=discover(&p,&check()).await;
        assert_ne!(rejected.state,"ready","a model name and a generated answer are not logprobs");
        let capability=discover(&p,&check()).await;
        assert_eq!(capability.state,"ready");
        let config=resolved(&p,&capability).unwrap();
        assert_eq!(config.api_key,"private-profile-key");
        assert!(!serde_json::to_string(&capability).unwrap().contains("private-profile-key"));
        p.custom_env.insert("OPENAI_BASE_URL".into(),"https://another.example/v1".into());
        assert!(resolved(&p,&capability).is_none(),"changing the destination invalidates the capability");
        task.await.unwrap();
    }
    #[tokio::test]
    async fn decision_discovery_does_not_treat_subscription_model_names_as_api_access() {
        let mut p=profile("http://127.0.0.1:1"); p.envs.clear(); p.custom_env.clear();
        p.access_kind=AccessKind::Subscription;
        let mut check=check();check.models=Some(vec!["gpt-6-luna".into()]);
        assert_eq!(discover(&p,&check).await.state,"unsupported");
    }
}
