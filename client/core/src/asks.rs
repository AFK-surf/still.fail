//! What a UI asks of the core that is no station's and no account's call: what one of still.fail's links opens
//! (`link.parse`), whether a newer build of the app is out (`app.update`), a person's picture (`picture`), the buddies a
//! Slack app can wear (`buddies`), a dev cloud's sign-in (`dev.signIn`). A UI never makes a request itself.

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use futures::FutureExt;
use futures::future::{LocalBoxFuture, Shared};
use serde_json::{Value, json};
use stillfail_i18n::t;

use crate::accounts::Accounts;
use crate::error::{CoreError, Result};
use crate::host::{Host, HttpRequest};

#[derive(Debug, Clone, PartialEq)]
pub enum Ask {
    /// What a link opens in the app (a `LinkTarget`), or null: the system opens it.
    LinkParse { url: String },
    /// The newest build of the app for `platform` (android) when newer than `version`, else null; still.fail cloud is
    /// asked at most once an hour unless `now`. A beta app's are the beta builds' (`Host::beta`).
    AppUpdate { platform: String, version: i64, now: bool },
    /// A picture by its URL (a Google account's), `{type, bytes}`, fetched once each for the core's life.
    Picture { url: String },
    Buddies,
    /// Signs in as a dev cloud's user (cloud/test/dev.ts): alice or bob, without Google.
    DevSignIn { user: String },
}

/// The ask `name` names, with its params; `None` when it is none of these.
pub fn parse(name: &str, params: &Value) -> Option<Result<Ask>> {
    let text = |field: &str| params.get(field).and_then(Value::as_str).filter(|s| !s.is_empty()).map(str::to_string)
        .ok_or_else(|| CoreError::invalid(t!("core-misc.params.missing", field = field)));
    Some(match name {
        "link.parse" => text("url").map(|url| Ask::LinkParse { url }),
        "app.update" => text("platform").and_then(|platform| {
            let version = params.get("versionCode").and_then(Value::as_i64).ok_or_else(|| CoreError::invalid(t!("core-misc.params.missing", field = "versionCode")))?;
            Ok(Ask::AppUpdate { platform, version, now: params.get("now").and_then(Value::as_bool).unwrap_or(false) })
        }),
        "picture" => text("url").map(|url| Ask::Picture { url }),
        "buddies" => Ok(Ask::Buddies),
        "dev.signIn" => text("user").map(|user| Ask::DevSignIn { user }),
        _ => return None,
    })
}

/// still.fail cloud's production hosts: it answers on its new one and its old one alike.
const CLOUD_HOSTS: &[&str] = &["app.still.fail", "ember.3720.org"];
/// How often still.fail cloud is asked for the app's newest build.
const UPDATE_EVERY_MS: f64 = 60.0 * 60.0 * 1000.0;
/// Pictures kept at most; past it they are let go, all at once.
const PICTURES: usize = 256;

type Picture = Shared<LocalBoxFuture<'static, std::result::Result<(String, Vec<u8>), CoreError>>>;

pub struct Asks {
    host: Rc<dyn Host>,
    /// By feed (`android`, `android/beta`): when still.fail cloud was last asked, and the newest build it named.
    releases: RefCell<HashMap<String, (f64, Option<Value>)>>,
    pictures: RefCell<HashMap<String, Picture>>,
}

impl Asks {
    pub fn new(host: Rc<dyn Host>) -> Asks {
        Asks { host, releases: RefCell::default(), pictures: RefCell::default() }
    }

    pub async fn run(&self, ask: Ask, accounts: &Accounts) -> Result<Value> {
        match ask {
            Ask::LinkParse { url } => Ok(link_target(&url, &self.host.cloud_origin())),
            Ask::AppUpdate { platform, version, now } => self.update(&platform, version, now, self.host.beta()).await,
            Ask::Picture { url } => {
                let (kind, bytes) = self.picture(&url).await?;
                Ok(json!({ "type": kind, "bytes": crate::core::encode_bytes(self.host.as_ref(), bytes).await? }))
            }
            Ask::Buddies => Ok(buddies()),
            Ask::DevSignIn { user } => {
                let origin = self.host.cloud_origin();
                if !dev_cloud(&origin) {
                    return Err(CoreError::invalid(t!("core-misc.ask.dev_only")));
                }
                let url = format!("{origin}/__dev/account?user={}", crate::accounts::encode_component(&user));
                let response = self.host.fetch(HttpRequest { method: "GET".into(), url, headers: Vec::new(), body: None }).await
                    .map_err(|e| CoreError::new("dev_cloud", t!("core-misc.ask.dev_cloud", error = e)))?;
                let account: Value = serde_json::from_slice(&response.body).ok().filter(|_| response.status == 200)
                    .ok_or_else(|| CoreError::new("dev_cloud", t!("core-misc.ask.dev_cloud", error = response.status)))?;
                accounts.migrate(json!([account])).await?;
                Ok(Value::Null)
            }
        }
    }

    /// The newest build of `platform`'s feed when newer than `version`: the released app's
    /// (`/releases/<platform>/latest.json`), or with `beta` the beta app's (`/releases/<platform>/beta/latest.json`;
    /// their files are where the released ones' are).
    async fn update(&self, platform: &str, version: i64, now: bool, beta: bool) -> Result<Value> {
        let feed = if beta { format!("{platform}/beta") } else { platform.to_string() };
        let newer = |release: &Option<Value>| release.clone().filter(|r| r.get("versionCode").and_then(Value::as_i64).is_some_and(|v| v > version)).unwrap_or(Value::Null);
        let time = self.host.now_ms();
        if let Some((at, release)) = self.releases.borrow().get(&feed) {
            if !now && time - at < UPDATE_EVERY_MS {
                return Ok(newer(release));
            }
        }
        self.releases.borrow_mut().entry(feed.clone()).or_insert((time, None)).0 = time;
        let url = format!("{}/releases/{feed}/latest.json", self.host.cloud_origin());
        let request = HttpRequest { method: "GET".into(), url, headers: vec![("cache-control".into(), "no-cache".into())], body: None };
        // Background checks may keep the last result; an explicit check must not silently use a stale build.
        let response = match self.host.fetch(request).await {
            Ok(response) => response,
            Err(e) if now => return Err(CoreError::new("app_update", t!("core-misc.ask.update_failed", error = e))),
            Err(_) => return Ok(newer(&self.releases.borrow()[&feed].1)),
        };
        let release = serde_json::from_slice::<Value>(&response.body).ok().filter(|_| response.status == 200)
            .and_then(|r| stillfail_shapes::conform::<stillfail_shapes::AppRelease>(r).ok());
        if now && release.is_none() {
            return Err(CoreError::new("app_update", t!("core-misc.ask.update_retry")));
        }
        if release.is_some() {
            self.releases.borrow_mut().insert(feed.clone(), (time, release.clone()));
        }
        Ok(newer(&self.releases.borrow()[&feed].1))
    }

    async fn picture(&self, url: &str) -> Result<(String, Vec<u8>)> {
        if !(url.starts_with("https://") || url.starts_with("http://")) {
            return Err(CoreError::invalid(t!("core-misc.ask.bad_picture_url")));
        }
        let found = self.pictures.borrow().get(url).cloned();
        let picture = match found {
            Some(p) => p,
            None => {
                let (host, address) = (self.host.clone(), url.to_string());
                let p: Picture = async move {
                    let response = host.fetch(HttpRequest { method: "GET".into(), url: address, headers: Vec::new(), body: None }).await
                        .map_err(|e| CoreError::new("picture", t!("core-misc.ask.picture_failed", error = e)))?;
                    if response.status != 200 {
                        return Err(CoreError::new("picture", t!("core-misc.ask.picture_failed", error = response.status)));
                    }
                    Ok((response.header("content-type").unwrap_or("").to_string(), response.body))
                }.boxed_local().shared();
                let mut all = self.pictures.borrow_mut();
                if all.len() >= PICTURES {
                    all.clear();
                }
                all.insert(url.to_string(), p.clone());
                p
            }
        };
        let got = picture.await;
        // One that failed is asked again next time.
        if got.is_err() {
            self.pictures.borrow_mut().remove(url);
        }
        got
    }
}

/// A dev cloud (cloud/test/dev.ts) on this machine or the emulator's host.
fn dev_cloud(origin: &str) -> bool {
    let Some(rest) = origin.strip_prefix("http://") else { return false };
    let Some((host, port)) = rest.split_once(':') else { return false };
    matches!(host, "127.0.0.1" | "localhost" | "10.0.2.2") && !port.is_empty() && port.chars().all(|c| c.is_ascii_digit())
}

/// The buddies a Slack app can wear (web/public/avatars/index.json; each is <id>.webp and <id>.thumb.webp beside it,
/// the Android app's assets/avatars/ too): `{id, label, bg}`.
fn buddies() -> Value {
    serde_json::from_str(include_str!("../../../web/public/avatars/index.json")).unwrap_or_else(|_| json!([]))
}

/// A URL's parts: scheme, host, port (none when not written), path segments (decoded, empty ones dropped), query, and
/// fragment.
struct Url {
    scheme: String,
    host: String,
    port: Option<String>,
    segments: Vec<String>,
    query: String,
    fragment: String,
}

fn split_url(url: &str) -> Option<Url> {
    let (scheme, rest) = url.split_once("://")?;
    let (rest, fragment) = rest.split_once('#').unwrap_or((rest, ""));
    let (rest, query) = rest.split_once('?').unwrap_or((rest, ""));
    let (authority, path) = rest.split_once('/').unwrap_or((rest, ""));
    let authority = authority.rsplit_once('@').map_or(authority, |(_, a)| a);
    let (host, port) = match authority.rsplit_once(':') {
        Some((h, p)) if !p.is_empty() && p.chars().all(|c| c.is_ascii_digit()) => (h, Some(p.to_string())),
        _ => (authority, None),
    };
    Some(Url {
        scheme: scheme.to_ascii_lowercase(),
        host: host.to_ascii_lowercase(),
        port,
        segments: path.split('/').filter(|s| !s.is_empty()).map(decode).collect(),
        query: query.to_string(),
        fragment: decode(fragment),
    })
}

fn decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        let hex = |b: u8| (b as char).to_digit(16);
        match (bytes[i], bytes.get(i + 1).copied().and_then(hex), bytes.get(i + 2).copied().and_then(hex)) {
            (b'%', Some(a), Some(b)) => {
                out.push((a * 16 + b) as u8);
                i += 3;
            }
            (b, _, _) => {
                out.push(b);
                i += 1;
            }
        }
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// What one of still.fail's own links opens in the app (as agents post them, and chat references): an invitation
/// (`<cloud>/invite#<token>`), a chat's page (`/w/<workspace>/s/<station>/chats/<key>`), or an item
/// (`/o/<workspace>/<station>/<session>`, `?service=<job>` its web service); null for any other link.
pub fn link_target(url: &str, origin: &str) -> Value {
    let (Some(u), Some(o)) = (split_url(url), split_url(origin)) else { return Value::Null };
    let same = u.scheme == o.scheme && u.host == o.host && u.port == o.port;
    let same_cloud = CLOUD_HOSTS.contains(&o.host.as_str()) && u.scheme == "https" && CLOUD_HOSTS.contains(&u.host.as_str()) && u.port.is_none();
    if !(same || same_cloud) {
        return Value::Null;
    }
    let s: Vec<&str> = u.segments.iter().map(String::as_str).collect();
    match s.as_slice() {
        ["invite"] if !u.fragment.is_empty() => json!({ "opens": "invite", "token": u.fragment }),
        ["w", workspace, "s", station, "chats", chat] => json!({ "opens": "chat", "workspace": workspace, "station": station, "chat": chat }),
        // A station's 共享调试 (adb.rs), as its agent links to it.
        ["w", workspace, "s", station, "adb"] => json!({ "opens": "adbShare", "workspace": workspace, "station": station }),
        ["o", workspace, station, session] => {
            let service = u.query.split('&').filter_map(|kv| kv.split_once('=')).find(|(k, _)| *k == "service").map(|(_, v)| decode(&v.replace('+', " "))).filter(|v| !v.is_empty());
            json!({ "opens": "item", "workspace": workspace, "station": station, "session": session, "service": service })
        }
        _ => Value::Null,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn still_fail_links_open_in_the_app_and_others_do_not() {
        let cloud = "https://app.still.fail";
        assert_eq!(link_target("https://app.still.fail/invite#abc", cloud), json!({ "opens": "invite", "token": "abc" }));
        assert_eq!(link_target("https://app.still.fail/invite", cloud), Value::Null);
        assert_eq!(link_target("https://ember.3720.org/w/ws1/s/st1/chats/k%3A1", cloud), json!({ "opens": "chat", "workspace": "ws1", "station": "st1", "chat": "k:1" }));
        assert_eq!(link_target("https://app.still.fail/o/ws1/st1/ds:C1:1.0?service=web", cloud),
            json!({ "opens": "item", "workspace": "ws1", "station": "st1", "session": "ds:C1:1.0", "service": "web" }));
        assert_eq!(link_target("https://app.still.fail/o/ws1/st1/k/", cloud)["service"], Value::Null);
        assert_eq!(link_target("https://app.still.fail/w/ws1/s/st1/adb", cloud), json!({ "opens": "adbShare", "workspace": "ws1", "station": "st1" }));
        // Another site, the cloud on a port, a path it does not open: the system's.
        assert_eq!(link_target("https://example.com/o/ws1/st1/k", cloud), Value::Null);
        assert_eq!(link_target("https://app.still.fail:8443/o/ws1/st1/k", cloud), Value::Null);
        assert_eq!(link_target("http://app.still.fail/o/ws1/st1/k", cloud), Value::Null);
        assert_eq!(link_target("https://app.still.fail/o/ws1/st1", cloud), Value::Null);
        assert_eq!(link_target("mailto:a@b.c", cloud), Value::Null);
        // A dev cloud's own links, and only its.
        let dev = "http://10.0.2.2:8877";
        assert_eq!(link_target("http://10.0.2.2:8877/o/w/s/k", dev)["opens"], "item");
        assert_eq!(link_target("https://app.still.fail/o/w/s/k", dev), Value::Null);
        assert!(dev_cloud(dev) && dev_cloud("http://localhost:1") && !dev_cloud(cloud) && !dev_cloud("http://10.0.2.2"));
    }

    #[test]
    fn a_newer_app_is_asked_for_at_most_hourly_and_a_picture_once() {
        use crate::testing::{FakeHost, json_response, run};
        run(async {
            let host = FakeHost::new();
            host.on_fetch(|req| match req.url.as_str() {
                "https://stillfail.test/releases/android/latest.json" => json_response(200, json!({
                    "versionCode": 1200, "versionName": "0.1.1200", "file": "android/stillfail-1200.apk", "sha256": "ab", "size": 9, "extra": 1,
                })),
                "https://p.test/a.png" => Ok(crate::host::HttpResponse { status: 200, headers: vec![("content-type".into(), "image/png".into())], body: vec![1, 2, 3] }),
                _ => json_response(404, json!({})),
            });
            let asks = Asks::new(host.clone());
            let asked = || host.requests.borrow().iter().filter(|r| r.url.ends_with("latest.json")).count();
            let newer = asks.update("android", 1100, false, false).await.unwrap();
            assert_eq!((newer["versionCode"].as_i64(), newer["file"].as_str(), newer.get("extra")), (Some(1200), Some("android/stillfail-1200.apk"), None));
            // Within the hour: what was found, not asked again; this build as new or newer, nothing.
            assert_eq!(asks.update("android", 1100, false, false).await.unwrap()["versionCode"], 1200);
            assert_eq!(asks.update("android", 1200, false, false).await.unwrap(), Value::Null);
            assert_eq!(asked(), 1);
            asks.update("android", 1100, true, false).await.unwrap();
            assert_eq!(asked(), 2);
            // A picture is fetched once; together or after, the same bytes.
            let (a, b) = futures::join!(asks.picture("https://p.test/a.png"), asks.picture("https://p.test/a.png"));
            assert_eq!(a.unwrap(), ("image/png".to_string(), vec![1, 2, 3]));
            assert_eq!(b.unwrap().1, vec![1, 2, 3]);
            asks.picture("https://p.test/a.png").await.unwrap();
            assert_eq!(host.requests.borrow().iter().filter(|r| r.url == "https://p.test/a.png").count(), 1);
            // One not there is asked again next time; what is not a web address, never.
            assert!(asks.picture("https://p.test/gone.png").await.is_err());
            assert!(asks.picture("https://p.test/gone.png").await.is_err());
            assert_eq!(host.requests.borrow().iter().filter(|r| r.url.ends_with("gone.png")).count(), 2);
            assert!(asks.picture("file:///etc/passwd").await.is_err());
        });
    }

    #[test]
    fn an_explicit_update_gets_the_newest_build_or_fails_instead_of_using_the_cached_one() {
        use crate::testing::{FakeHost, json_response, run};
        run(async {
            let host = FakeHost::new();
            let version = Rc::new(std::cell::Cell::new(1200));
            let served = version.clone();
            host.on_fetch(move |_| match served.get() {
                0 => Err(crate::host::HostError("offline".into())),
                1 => json_response(503, json!({})),
                2 => json_response(200, json!({"invalid": true})),
                code => json_response(200, json!({"versionCode": code, "versionName": format!("0.1.{code}"),
                    "file": format!("android/stillfail-{code}.apk"), "sha256": "ab", "size": 9})),
            });
            let asks = Asks::new(host.clone());
            assert_eq!(asks.update("android", 1100, false, false).await.unwrap()["versionCode"], 1200);
            version.set(1300);
            assert_eq!(asks.update("android", 1100, false, false).await.unwrap()["versionCode"], 1200);
            let latest = asks.update("android", 1100, true, false).await.unwrap();
            assert_eq!(latest["versionCode"], 1300);
            assert_eq!(latest["file"], "android/stillfail-1300.apk");
            for failure in [0, 1, 2] {
                version.set(failure);
                assert!(asks.update("android", 1100, true, false).await.is_err());
            }
            version.set(1100);
            assert_eq!(asks.update("android", 1100, true, false).await.unwrap(), Value::Null);
        });
    }

    #[test]
    fn a_beta_app_takes_its_builds_from_the_beta_feed() {
        use crate::testing::{FakeHost, json_response, run};
        run(async {
            let release = |code: i64| json!({ "versionCode": code, "versionName": format!("0.1.{code}"), "file": format!("android/stillfail-{code}.apk"), "sha256": "ab", "size": 9 });
            let feeds = move |req: &HttpRequest| match req.url.as_str() {
                "https://stillfail.test/releases/android/latest.json" => json_response(200, release(1200)),
                "https://stillfail.test/releases/android/beta/latest.json" => json_response(200, release(1250)),
                _ => json_response(404, json!({})),
            };
            // The released app: the released feed only.
            let host = FakeHost::new();
            host.on_fetch(feeds);
            let asks = Asks::new(host.clone());
            assert_eq!(asks.run(Ask::AppUpdate { platform: "android".into(), version: 1100, now: false }, &*Accounts::load(host.clone()).await).await.unwrap()["versionCode"], 1200);
            assert!(host.requests.borrow().iter().all(|r| !r.url.contains("/beta/")));
            // The beta app: the beta feed only, its build kept apart from the released one's.
            let host = FakeHost::new();
            host.beta.set(true);
            host.on_fetch(feeds);
            let asks = Asks::new(host.clone());
            let accounts = Accounts::load(host.clone()).await;
            let newer = asks.run(Ask::AppUpdate { platform: "android".into(), version: 1100, now: false }, &accounts).await.unwrap();
            assert_eq!((newer["versionCode"].as_i64(), newer["file"].as_str()), (Some(1250), Some("android/stillfail-1250.apk")));
            assert_eq!(asks.run(Ask::AppUpdate { platform: "android".into(), version: 1250, now: true }, &accounts).await.unwrap(), Value::Null);
            assert!(host.requests.borrow().iter().all(|r| r.url.ends_with("/android/beta/latest.json")));
            assert_eq!(host.requests.borrow().len(), 2);
        });
    }

    #[test]
    fn the_calls_are_known_by_name() {
        assert_eq!(parse("link.parse", &json!({ "url": "https://x" })).unwrap().unwrap(), Ask::LinkParse { url: "https://x".into() });
        assert_eq!(parse("app.update", &json!({ "platform": "android", "versionCode": 3 })).unwrap().unwrap(), Ask::AppUpdate { platform: "android".into(), version: 3, now: false });
        assert!(parse("app.update", &json!({ "platform": "android" })).unwrap().is_err());
        assert_eq!(parse("buddies", &json!({})).unwrap().unwrap(), Ask::Buddies);
        assert!(parse("session.stop", &json!({})).is_none());
    }

    #[test]
    fn the_buddies_are_the_web_s_list() {
        let all = buddies();
        assert!(all.as_array().is_some_and(|a| a.len() > 5));
        assert!(all[0]["id"].is_string() && all[0]["label"].is_string() && all[0]["bg"].is_string());
    }
}
