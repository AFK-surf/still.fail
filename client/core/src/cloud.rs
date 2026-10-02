//! still.fail cloud's account API, called as one of the signed-in accounts.
//! Errors come back as {error: code}; the codes and their Chinese messages
//! mirror web/src/cloud/api.ts.

use std::rc::Rc;

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::accounts::{Accounts, encode_component};
use crate::error::{CoreError, Result};
use crate::host::{Host, HttpRequest};
use crate::status::{Place, Status, cloud_what};
use crate::trace::{Kind, Tracer, route};

/// A mstill.fail's credential for this device (POST /v1/workspaces/:ws/credential {device}): every station of the
/// workspace takes it, checking it offline, until `expires_at` (30 days; seconds).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Credential {
    pub credential: String,
    pub issued_at: f64,
    pub expires_at: f64,
    pub relay_url: String,
}

/// still.fail cloud's answer to a beta app (`x-stillfail-channel: beta`) used by an account not let into the beta.
pub const NOT_BETA: &str = "not_beta";
pub const NOT_BETA_TEXT: &str = "这个账号还没开通测试版";

pub struct Cloud {
    host: Rc<dyn Host>,
    accounts: Rc<Accounts>,
    tracer: Rc<Tracer>,
    status: Rc<Status>,
}

impl Cloud {
    pub fn new(host: Rc<dyn Host>, accounts: Rc<Accounts>, tracer: Rc<Tracer>, status: Rc<Status>) -> Rc<Cloud> {
        Rc::new(Cloud { host, accounts, tracer, status })
    }

    /// One call as `sub`: adds the token (refreshing it), parses JSON, maps errors to CoreError with the cloud's code.
    /// Inside a trace it is a span of it, and says so to still.fail cloud with a `traceparent`.
    pub async fn request(&self, sub: &str, method: &str, path: &str, body: Option<Value>) -> Result<Value> {
        let token = self.accounts.access_token(sub).await?;
        let mut headers = vec![("authorization".to_string(), format!("Bearer {token}"))];
        headers.extend(channel_header(&*self.host));
        if body.is_some() {
            headers.push(("content-type".into(), "application/json".into()));
        }
        let mut span = self.tracer.child(format!("{method} {}", route(path)), Kind::Client);
        if let Some(span) = &mut span {
            span.set("http.request.method", method.to_string());
            span.set("url.path", route(path));
            headers.push(("traceparent".into(), span.context().traceparent()));
        }
        let request = HttpRequest {
            method: method.into(),
            url: format!("{}{path}", self.host.cloud_origin()),
            headers,
            body: body.map(|b| serde_json::to_vec(&b).unwrap()),
        };
        let waiting = self.status.begin(Place::Cloud, cloud_what(method, path), false);
        let response = self.host.fetch(request).await;
        if let Ok(response) = &response {
            waiting.received(response.body.len());
        }
        drop(waiting);
        if let Some(mut span) = span {
            match &response {
                Ok(response) => {
                    span.set("http.response.status_code", response.status);
                    span.set("http.response.body.size", response.body.len());
                    if response.status >= 500 {
                        span.fail();
                    }
                }
                Err(_) => span.fail(),
            }
            span.end();
        }
        let response = response?;
        // Like the web app: an unreadable body counts as {}.
        let data: Value = serde_json::from_slice(&response.body).unwrap_or_else(|_| json!({}));
        if !(200..300).contains(&response.status) {
            let code = data.get("error").and_then(Value::as_str).map(String::from).unwrap_or_else(|| format!("http_{}", response.status));
            return Err(cloud_error(&code, response.status));
        }
        Ok(data)
    }

    /// POST /v1/telemetry/traces as `sub`: a batch of spans (OTLP JSON), which still.fail cloud passes on to Axiom.
    pub async fn traces(&self, sub: &str, body: Vec<u8>) -> Result<()> {
        let token = self.accounts.access_token(sub).await?;
        let request = HttpRequest {
            method: "POST".into(),
            url: format!("{}/v1/telemetry/traces", self.host.cloud_origin()),
            headers: [("authorization".into(), format!("Bearer {token}")), ("content-type".into(), "application/json".into())].into_iter().chain(channel_header(&*self.host)).collect(),
            body: Some(body),
        };
        let response = self.host.fetch(request).await?;
        if !(200..300).contains(&response.status) {
            return Err(cloud_error(&format!("http_{}", response.status), response.status));
        }
        Ok(())
    }

    /// GET /v1/me: {user, workspaces, invitations, relay_url}.
    pub async fn me(&self, sub: &str) -> Result<Value> {
        self.request(sub, "GET", "/v1/me", None).await
    }

    pub async fn credential(&self, sub: &str, workspace: &str, device: &str) -> Result<Credential> {
        let path = format!("/v1/workspaces/{}/credential", encode_component(workspace));
        let answer = self.request(sub, "POST", &path, Some(json!({ "device": device }))).await?;
        serde_json::from_value(answer).map_err(|e| CoreError::new("bad_response", format!("{} cloud 的回复无法解析：{e}", crate::brand::name())))
    }
}

/// A beta app says so on its calls (`x-stillfail-channel: beta`): still.fail cloud lets only the accounts let into
/// the beta use it (`not_beta` otherwise). The released apps send nothing.
pub fn channel_header(host: &dyn Host) -> Option<(String, String)> {
    host.beta().then(|| ("x-stillfail-channel".to_string(), "beta".to_string()))
}

/// The error for a cloud error code, with its Chinese message when there is one.
pub fn cloud_error(code: &str, status: u16) -> CoreError {
    let text = match code {
        "invalid_email" => format!("要填对方登录 {} 用的邮箱", crate::brand::name()),
        _ => message(code).unwrap_or(code).to_string(),
    };
    CoreError::new(code, text).with_status(status)
}

fn message(code: &str) -> Option<&'static str> {
    Some(match code {
        "workspace_not_found" => "找不到这个 workspace，或者你已经不在里面了",
        "member_not_found" => "找不到这个成员",
        "station_not_found" => "找不到这台 station",
        "invitation_not_found" => "邀请链接无效或已过期",
        "invitation_for_other_email" => "这个邀请是发给另一个邮箱的，请换对应的账号接受",
        "forbidden" => "你在这个 workspace 里没有这个权限",
        "invalid_name" => "名字不能为空，最长 80 个字",
        "already_member" => "这个邮箱的主人已经在 workspace 里了",
        "last_owner" => "workspace 至少要保留一个 owner",
        "too_many_workspaces" => "你创建的 workspace 太多了",
        "too_many_invitations" => "未处理的邀请太多了，先撤回一些",
        "too_many_members" => "成员数量到上限了",
        "too_many_stations" => "station 数量到上限了",
        "invalid_session" => "登录已失效，请重新登录",
        NOT_BETA => NOT_BETA_TEXT,
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::accounts::{STORAGE_KEY, StoredAccount};
    use crate::host::HttpResponse;
    use crate::testing::{FakeHost, json_response, run};

    async fn cloud(host: &Rc<FakeHost>) -> Rc<Cloud> {
        let far = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs_f64() + 3600.0;
        let account = StoredAccount {
            sub: "s".into(),
            email: "s@x.com".into(),
            name: String::new(),
            picture: String::new(),
            access: "tok".into(),
            refresh: "ref".into(),
            access_expires: far,
        };
        host.store(STORAGE_KEY, serde_json::to_vec(&[account]).unwrap());
        Cloud::new(host.clone(), Accounts::load(host.clone()).await, Tracer::new(host.clone(), 1.0), Status::new(host.clone()))
    }

    fn header(request: &HttpRequest, name: &str) -> Option<String> {
        request.headers.iter().find(|(k, _)| k == name).map(|(_, v)| v.clone())
    }

    #[test]
    fn request_adds_the_token_and_json() {
        run(async {
            let host = FakeHost::new();
            host.on_fetch(|_| json_response(200, json!({ "ok": true })));
            let cloud = cloud(&host).await;
            assert_eq!(cloud.me("s").await.unwrap(), json!({ "ok": true }));
            cloud.request("s", "PATCH", "/v1/workspaces/w", Some(json!({ "name": "新" }))).await.unwrap();
            let requests = host.requests.borrow().clone();
            assert_eq!((requests[0].method.as_str(), requests[0].url.as_str()), ("GET", "https://stillfail.test/v1/me"));
            assert_eq!(header(&requests[0], "authorization").as_deref(), Some("Bearer tok"));
            assert_eq!(header(&requests[0], "content-type"), None);
            assert!(requests[0].body.is_none());
            assert_eq!(header(&requests[1], "content-type").as_deref(), Some("application/json"));
            assert_eq!(serde_json::from_slice::<Value>(requests[1].body.as_deref().unwrap()).unwrap(), json!({ "name": "新" }));
        });
    }

    #[test]
    fn errors_map_to_codes_and_messages() {
        run(async {
            let host = FakeHost::new();
            host.on_fetch(|req| match req.url.rsplit('/').next().unwrap() {
                "known" => json_response(404, json!({ "error": "workspace_not_found" })),
                "unknown" => json_response(409, json!({ "error": "something_new" })),
                _ => Ok(HttpResponse { status: 502, headers: vec![], body: b"<html>bad gateway".to_vec() }),
            });
            let cloud = cloud(&host).await;
            let e = cloud.request("s", "GET", "/v1/known", None).await.unwrap_err();
            assert_eq!(e, CoreError::new("workspace_not_found", "找不到这个 workspace，或者你已经不在里面了").with_status(404));
            let e = cloud.request("s", "GET", "/v1/unknown", None).await.unwrap_err();
            assert_eq!(e, CoreError::new("something_new", "something_new").with_status(409));
            let e = cloud.request("s", "GET", "/v1/html", None).await.unwrap_err();
            assert_eq!(e, CoreError::new("http_502", "http_502").with_status(502));
            // Not signed in as that account: no request at all.
            assert_eq!(cloud.me("nobody").await.unwrap_err().code, "signed_out");
            assert_eq!(host.requests.borrow().len(), 3);
        });
    }

    #[test]
    fn a_credential_is_asked_for_the_device() {
        run(async {
            let host = FakeHost::new();
            host.on_fetch(|_| json_response(200, json!({ "credential": "c", "issued_at": 1.0, "expires_at": 10.0, "relay_url": "https://relay" })));
            let cloud = cloud(&host).await;
            let credential = cloud.credential("s", "ws 1", "dev-key").await.unwrap();
            assert_eq!((credential.credential.as_str(), credential.expires_at), ("c", 10.0));
            let request = host.requests.borrow()[0].clone();
            assert_eq!((request.method.as_str(), request.url.as_str()), ("POST", "https://stillfail.test/v1/workspaces/ws%201/credential"));
            assert_eq!(serde_json::from_slice::<Value>(request.body.as_deref().unwrap()).unwrap(), json!({ "device": "dev-key" }));
        });
    }
}
