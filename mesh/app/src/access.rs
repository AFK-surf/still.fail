//! Who may use the admin API. A request is local (trusted), came through the mesh from ember cloud (it carries the
//! viewer the station's mesh verified, and the secret proving it came that way), or came through a Cloudflare tunnel,
//! which cloudflared also delivers from loopback. Cloudflare's edge always adds cf-connecting-ip, and a client cannot
//! strip it; such requests must carry a valid Cloudflare Access JWT, verified here against the team's signing keys.
//! Without Access configured, tunneled requests are refused: a missing Access policy must not leave the admin page
//! open.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::Result;
use base64::Engine;
use futures_util::future::BoxFuture;
use serde::Serialize;
use serde_json::Value;

use crate::config::AdminAccess;

/// Who is asking.
#[derive(Serialize, Debug, Clone, PartialEq, Eq)]
#[serde(tag = "via", rename_all = "lowercase")]
pub enum Viewer {
    Local,
    Access { email: String },
    /// A person reaching the station through ember cloud; the station's mesh verified their grant.
    Mesh { sub: String, email: String, name: String, role: String, workspace: String, device: String },
}

impl Viewer {
    /// Who did something, for people: a name, else the email.
    pub fn name(&self) -> String {
        match self {
            Viewer::Local => "本机管理页".into(),
            Viewer::Mesh { name, email, .. } => if name.is_empty() { email.clone() } else { name.clone() },
            Viewer::Access { email } => email.clone(),
        }
    }

    /// Who did something, for logs and records: an email, or "local" on the station itself.
    pub fn id(&self) -> String {
        match self {
            Viewer::Local => "local".into(),
            Viewer::Access { email } | Viewer::Mesh { email, .. } => email.clone(),
        }
    }
}

/// A refusal, said to the person refused (403).
#[derive(Debug, thiserror::Error)]
#[error("{0}")]
pub struct AccessDenied(pub String);

fn denied(message: &str) -> anyhow::Error {
    AccessDenied(message.into()).into()
}

/// Fetches a JWKS document ({ keys: [...] }).
pub type FetchJwks = Arc<dyn Fn(String) -> BoxFuture<'static, Result<Value>> + Send + Sync>;

fn default_fetch() -> FetchJwks {
    Arc::new(|url| {
        Box::pin(async move {
            let response = reqwest::get(&url).await?;
            if !response.status().is_success() {
                anyhow::bail!("fetching Access keys failed: {}", response.status().as_u16());
            }
            Ok(response.json().await?)
        })
    })
}

/// An RSA public key: modulus and exponent, big-endian.
type RsaKey = (Vec<u8>, Vec<u8>);

#[derive(Default)]
struct Keys {
    by_kid: HashMap<String, RsaKey>,
    url: String,
    fetched_at: Option<Instant>,
}

pub struct AccessGate {
    config: Arc<dyn Fn() -> Option<AdminAccess> + Send + Sync>,
    fetch: FetchJwks,
    /// What the station's mesh sends to prove a request came through it.
    mesh_secret: Arc<dyn Fn() -> Option<String> + Send + Sync>,
    keys: tokio::sync::Mutex<Keys>,
}

fn b64(text: &str) -> Option<Vec<u8>> {
    base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(text.trim_end_matches('=')).ok()
}

/// Compares without saying where the first difference is.
fn same(a: &[u8], b: &[u8]) -> bool {
    a.len() == b.len() && a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

impl AccessGate {
    pub fn new(
        config: impl Fn() -> Option<AdminAccess> + Send + Sync + 'static,
        fetch: Option<FetchJwks>,
        mesh_secret: impl Fn() -> Option<String> + Send + Sync + 'static,
    ) -> AccessGate {
        AccessGate { config: Arc::new(config), fetch: fetch.unwrap_or_else(default_fetch), mesh_secret: Arc::new(mesh_secret), keys: Default::default() }
    }

    /// Resolves the viewer of a request, given its headers (by lowercase name) and whether it came from this machine
    /// (the admin socket, or loopback). A refusal is an AccessDenied; failing to fetch Access's keys is another error.
    pub async fn check(&self, header: impl Fn(&str) -> Option<String>, from_this_machine: bool) -> Result<Viewer> {
        if let Some(supplied) = header("x-ember-mesh") {
            return self.mesh(&supplied, header("x-ember-viewer").unwrap_or_default(), from_this_machine);
        }
        if header("cf-connecting-ip").is_none() && header("cf-ray").is_none() {
            return Ok(Viewer::Local);
        }
        let Some(config) = (self.config)() else {
            return Err(denied("通过公网访问需要先在 ember 配置 Cloudflare Access（admin.access.teamDomain 和 aud）"));
        };
        let token = header("cf-access-jwt-assertion").unwrap_or_default();
        if token.is_empty() {
            return Err(denied("缺少 Cloudflare Access 凭证"));
        }
        Ok(Viewer::Access { email: self.verify(&token, &config).await? })
    }

    fn mesh(&self, supplied: &str, viewer: String, from_this_machine: bool) -> Result<Viewer> {
        let secret = (self.mesh_secret)();
        if !from_this_machine || !secret.is_some_and(|s| same(s.as_bytes(), supplied.as_bytes())) {
            return Err(denied("mesh 请求无效"));
        }
        let v: Value = b64(&viewer).and_then(|b| serde_json::from_slice(&b).ok()).ok_or_else(|| denied("mesh 请求缺少身份"))?;
        let text = |k: &str| v.get(k).and_then(Value::as_str).unwrap_or("").to_string();
        if text("email").is_empty() || text("sub").is_empty() {
            return Err(denied("mesh 请求缺少身份"));
        }
        Ok(Viewer::Mesh { sub: text("sub"), email: text("email"), name: text("name"), role: text("role"), workspace: text("workspace"), device: text("device") })
    }

    async fn verify(&self, token: &str, config: &AdminAccess) -> Result<String> {
        let mut parts = token.split('.');
        let (Some(head), Some(body), Some(signature), None) = (parts.next(), parts.next(), parts.next(), parts.next()) else {
            return Err(denied("Access 凭证格式不对"));
        };
        if head.is_empty() || body.is_empty() || signature.is_empty() {
            return Err(denied("Access 凭证格式不对"));
        }
        let json = |part: &str| b64(part).and_then(|b| serde_json::from_slice::<Value>(&b).ok());
        let (Some(header), Some(claims)) = (json(head), json(body)) else {
            return Err(denied("Access 凭证无法解析"));
        };
        let kid = header.get("kid").and_then(Value::as_str).unwrap_or("");
        if header.get("alg").and_then(Value::as_str) != Some("RS256") || kid.is_empty() {
            return Err(denied("Access 凭证的签名算法不对"));
        }
        let key = self.key(kid, config).await?;
        let signed = key.is_some_and(|(n, e)| {
            let sig = b64(signature).unwrap_or_default();
            ring::signature::RsaPublicKeyComponents { n: &n, e: &e }
                .verify(&ring::signature::RSA_PKCS1_2048_8192_SHA256, format!("{head}.{body}").as_bytes(), &sig)
                .is_ok()
        });
        if !signed {
            return Err(denied("Access 凭证签名无效"));
        }
        let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_secs_f64();
        let issuer = format!("https://{}.cloudflareaccess.com", config.team_domain);
        let audiences: Vec<&str> = match claims.get("aud") {
            Some(Value::Array(a)) => a.iter().filter_map(Value::as_str).collect(),
            Some(Value::String(s)) => vec![s.as_str()],
            _ => vec![],
        };
        if claims.get("iss").and_then(Value::as_str) != Some(issuer.as_str()) {
            return Err(denied("Access 凭证来自别的团队"));
        }
        if !audiences.contains(&config.aud.as_str()) {
            return Err(denied("Access 凭证不属于这个应用"));
        }
        match claims.get("exp").and_then(Value::as_f64) {
            Some(exp) if exp >= now - 30.0 => {}
            _ => return Err(denied("Access 凭证已过期")),
        }
        if claims.get("nbf").and_then(Value::as_f64).is_some_and(|nbf| nbf > now + 30.0) {
            return Err(denied("Access 凭证还未生效"));
        }
        match claims.get("email").and_then(Value::as_str) {
            Some(email) if !email.is_empty() => Ok(email.to_string()),
            _ => Err(denied("Access 凭证里没有邮箱")),
        }
    }

    /// Signing keys are cached; an unknown kid (key rotation) refetches at most once a minute.
    async fn key(&self, kid: &str, config: &AdminAccess) -> Result<Option<RsaKey>> {
        let url = format!("https://{}.cloudflareaccess.com/cdn-cgi/access/certs", config.team_domain);
        let mut keys = self.keys.lock().await;
        let stale = keys.url != url || (!keys.by_kid.contains_key(kid) && keys.fetched_at.is_none_or(|at| at.elapsed() > Duration::from_secs(60)));
        if stale {
            let jwks = (self.fetch)(url.clone()).await?;
            let listed = jwks.get("keys").and_then(Value::as_array).cloned().unwrap_or_default();
            keys.by_kid = listed
                .iter()
                .filter_map(|k| {
                    let text = |name: &str| k.get(name).and_then(Value::as_str);
                    Some((text("kid")?.to_string(), (b64(text("n")?)?, b64(text("e")?)?)))
                })
                .collect();
            keys.url = url;
            keys.fetched_at = Some(Instant::now());
        }
        Ok(keys.by_kid.get(kid).cloned())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// A throwaway key made for these tests (access/test-key.*), standing in for Cloudflare's.
    const KEY: &[u8] = include_bytes!("access/test-key.der");
    const JWK: &str = include_str!("access/test-key.jwk.json");

    fn jwt(claims: Value, kid: &str) -> String {
        let part = |v: Value| base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(v.to_string());
        let head = format!("{}.{}", part(json!({ "alg": "RS256", "kid": kid })), part(claims));
        let pair = ring::signature::RsaKeyPair::from_der(KEY).unwrap();
        let mut sig = vec![0; pair.public().modulus_len()];
        pair.sign(&ring::signature::RSA_PKCS1_SHA256, &ring::rand::SystemRandom::new(), head.as_bytes(), &mut sig).unwrap();
        format!("{head}.{}", base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(sig))
    }

    fn gate(access: Option<AdminAccess>) -> AccessGate {
        let fetch: FetchJwks = Arc::new(|_| Box::pin(async { Ok(json!({ "keys": [serde_json::from_str::<Value>(JWK).unwrap()] })) }));
        AccessGate::new(move || access.clone(), Some(fetch), || Some("mesh-secret".into()))
    }

    async fn check(gate: &AccessGate, headers: &[(&str, &str)], local: bool) -> std::result::Result<Viewer, String> {
        let headers: HashMap<String, String> = headers.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
        gate.check(|name| headers.get(name).cloned(), local).await.map_err(|e| {
            assert!(e.is::<AccessDenied>(), "{e}");
            e.to_string()
        })
    }

    #[tokio::test]
    async fn local_visits_need_no_sign_in_and_tunneled_ones_are_refused_until_access_is_configured() {
        let open = gate(None);
        assert_eq!(check(&open, &[], true).await, Ok(Viewer::Local));
        assert!(check(&open, &[("cf-connecting-ip", "203.0.113.9")], true).await.unwrap_err().contains("Cloudflare Access"));
    }

    #[tokio::test]
    async fn tunneled_visits_need_a_valid_access_token_for_this_team_and_application() {
        let g = gate(Some(AdminAccess { team_domain: "afk".into(), aud: "app-aud".into() }));
        let exp = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs_f64();
        let good = json!({ "iss": "https://afk.cloudflareaccess.com", "aud": ["app-aud"], "email": "dev@example.com", "exp": exp + 600.0 });
        let with = |key: &str, value: Value| {
            let mut claims = good.clone();
            claims[key] = value;
            jwt(claims, "k1")
        };
        async fn via(g: &AccessGate, token: &str) -> std::result::Result<Viewer, String> {
            check(g, &[("cf-connecting-ip", "203.0.113.9"), ("cf-access-jwt-assertion", token)], true).await
        }
        assert_eq!(via(&g, &jwt(good.clone(), "k1")).await, Ok(Viewer::Access { email: "dev@example.com".into() }));
        assert!(check(&g, &[("cf-connecting-ip", "203.0.113.9")], true).await.unwrap_err().contains("缺少"));
        let tampered = {
            let token = jwt(good.clone(), "k1");
            format!("{}.AAAA", &token[..token.rfind('.').unwrap()])
        };
        for (token, message) in [
            (with("aud", json!(["other"])), "不属于这个应用"),
            (with("iss", json!("https://evil.cloudflareaccess.com")), "别的团队"),
            (with("exp", json!(exp - 3600.0)), "过期"),
            (tampered, "签名无效"),
            (jwt(good.clone(), "unknown-kid"), "签名无效"),
        ] {
            let refused = via(&g, &token).await.unwrap_err();
            assert!(refused.contains(message), "{refused} should say {message}");
        }
    }

    #[tokio::test]
    async fn mesh_requests_need_the_secret_from_this_machine_and_a_viewer() {
        let g = gate(None);
        let viewer = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(json!({ "sub": "u1", "email": "a@b.c", "name": "A", "role": "member", "workspace": "w", "device": "d" }).to_string());
        let ok = check(&g, &[("x-ember-mesh", "mesh-secret"), ("x-ember-viewer", &viewer)], true).await.unwrap();
        assert_eq!((ok.id(), ok.name()), ("a@b.c".to_string(), "A".to_string()));
        assert_eq!(serde_json::to_value(&ok).unwrap()["via"], "mesh");
        assert!(check(&g, &[("x-ember-mesh", "mesh-secret"), ("x-ember-viewer", &viewer)], false).await.unwrap_err().contains("无效"));
        assert!(check(&g, &[("x-ember-mesh", "wrong-secret"), ("x-ember-viewer", &viewer)], true).await.unwrap_err().contains("无效"));
        assert!(check(&g, &[("x-ember-mesh", "mesh-secret")], true).await.unwrap_err().contains("缺少身份"));
    }
}
