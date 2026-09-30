//! The station's app (stillfail-app), run in this process, and its loopback port. The station has no page of its own
//! any more (its pages are still.fail cloud's): the port is kept so that links to the page it had, sent to Slack and
//! kept in browsers, still lead somewhere: `/admin/...` is sent to the same page in the cloud's web app (`moved`), or,
//! while the station is in no workspace, told how to join one. Nothing on it reaches the admin API. The port is the
//! usual 4760 unless something else holds it (then any free one), or the one asked for with --port (then taken is an
//! error); it is written to <data>/run/ports.json.

use std::{convert::Infallible, path::{Path, PathBuf}, sync::{Arc, OnceLock, Weak}};

use anyhow::{Result, bail};
use bytes::Bytes;
use http_body_util::{BodyExt, Full, combinators::UnsyncBoxBody};
use hyper::{Request, Response, StatusCode, body::Incoming, service::service_fn};
use serde_json::Value;
use stillfail_app::handoff::{Door, serve_http1};
use tokio::{net::TcpListener, sync::watch};
use tracing::{info, warn};

pub type Body = UnsyncBoxBody<Bytes, Box<dyn std::error::Error + Send + Sync>>;

/// Who a request is from: the member the mesh verified.
pub type MeshViewer = stillfail_app::access::Viewer;

/// Where requests go: the app in this process, once it has started.
#[derive(Clone, Default)]
pub struct Backend(pub Arc<OnceLock<Arc<stillfail_app::server::App>>>);

impl Backend {
    /// One request of the admin API, on behalf of `viewer`.
    pub async fn call<B>(&self, request: Request<B>, viewer: &MeshViewer) -> Result<Response<Body>>
    where
        B: hyper::body::Body<Data = Bytes> + Send + Unpin + 'static,
        B::Error: std::error::Error + Send + Sync + 'static,
    {
        let app = self.0.get().ok_or_else(|| anyhow::anyhow!("not started"))?;
        let response = app.handle(request, viewer.clone()).await;
        Ok(response.map(|b| b.map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>).boxed_unsync()))
    }
}

/// Listens on 127.0.0.1:`port`; when it is only the usual one (`named` false) and something holds it, on any free
/// port. The port it got is written to <data>/run/ports.json.
pub async fn bind(data: &Path, port: u16, named: bool) -> Result<TcpListener> {
    let listener = match TcpListener::bind(("127.0.0.1", port)).await {
        Ok(listener) => listener,
        Err(error) if error.kind() == std::io::ErrorKind::AddrInUse && !named => {
            warn!(port, "the loopback port's usual number is taken; listening on a free one");
            TcpListener::bind(("127.0.0.1", 0)).await?
        }
        Err(error) if error.kind() == std::io::ErrorKind::AddrInUse => {
            bail!("端口 127.0.0.1:{port} 已被别的程序占用（--port 指定了这个端口）。用 `lsof -nP -iTCP:{port} -sTCP:LISTEN` 看是谁，或换一个端口。")
        }
        Err(error) => return Err(error.into()),
    };
    let got = listener.local_addr()?.port();
    let run = data.join("run");
    std::fs::create_dir_all(&run)?;
    std::fs::write(run.join("ports.json"), format!("{{\"admin\":{got}}}\n"))?;
    info!(port = got, "loopback port listening (old /admin links go to still.fail cloud)");
    Ok(listener)
}

/// Answers the loopback port: old page links sent on to still.fail cloud, by where <data>/mesh/cloud.json says the
/// station is (read at each request: an enrollment or a removal shows at once). The door can pause, to hand the socket
/// over to the next binary.
pub fn serve(listener: TcpListener, data: PathBuf, ready: watch::Receiver<bool>) -> Arc<Door> {
    let data = Arc::new(data);
    let cell: Arc<OnceLock<Weak<Door>>> = Arc::default();
    let door_of = cell.clone();
    let door = Door::open(listener, move |stream, closing| {
        let (data, ready, door) = (data.clone(), ready.clone(), door_of.clone());
        tokio::spawn(async move {
            let service = service_fn(move |req: Request<Incoming>| {
                let up = *ready.borrow();
                let busy = door.get().and_then(Weak::upgrade).map(|d| d.busy());
                let place = Place::read(&data);
                async move {
                    let answer = answer(req.uri().path(), req.uri().query(), up, place.as_ref());
                    drop(busy);
                    Ok::<_, Infallible>(answer)
                }
            });
            serve_http1(stream, service, closing).await;
        });
    });
    let _ = cell.set(Arc::downgrade(&door));
    door
}

/// Where the station is, as far as its old links care: its cloud, workspace and id there; `removed_at` when the cloud
/// took it out of that workspace.
#[derive(Debug, Clone, PartialEq)]
pub struct Place {
    pub origin: String,
    pub workspace: String,
    pub workspace_name: String,
    pub station: String,
    pub removed_at: Option<u64>,
}

impl Place {
    /// None while the station never joined a workspace (no cloud.json, or one that does not read).
    pub fn read(data: &Path) -> Option<Place> {
        let state: Value = serde_json::from_slice(&std::fs::read(data.join("mesh").join("cloud.json")).ok()?).ok()?;
        let text = |k: &str| state[k].as_str().unwrap_or_default().to_string();
        Some(Place { origin: text("origin"), workspace: text("workspace"), workspace_name: text("workspace_name"), station: text("station"), removed_at: state["removed_at"].as_u64() })
    }
}

/// What the loopback port says to `path`?`query`.
pub fn answer(path: &str, query: Option<&str>, ready: bool, place: Option<&Place>) -> Response<Body> {
    if path == "/healthz" {
        return plain(if ready { StatusCode::OK } else { StatusCode::SERVICE_UNAVAILABLE }, "");
    }
    if path.starts_with("/admin/api/") || path == "/admin/api" {
        let body = r#"{"error":"这台 station 不在本机提供管理接口：到 still.fail 打开它"}"#;
        return with_type(StatusCode::NOT_FOUND, "application/json", body);
    }
    if path != "/" && path != "/admin" && !path.starts_with("/admin/") {
        return plain(StatusCode::NOT_FOUND, "");
    }
    match place.filter(|p| p.removed_at.is_none() && !p.origin.is_empty() && !p.workspace.is_empty()) {
        Some(place) => {
            let to = moved(path.strip_prefix("/admin").unwrap_or(path), query, place);
            Response::builder().status(StatusCode::FOUND).header("location", to).header("cache-control", "no-store").body(empty()).expect("response")
        }
        None => plain(StatusCode::NOT_FOUND, &unbound(place)),
    }
}

/// Where a page of the station's old page is in the cloud's web app: `path` under /admin, the query kept as it was
/// (a chat's `?history=&entry=`). A station's pages there are under /w/<workspace>/s/<station>, the workspace's own
/// (settings of this device, its connects and memory, new chats, the archive) under /w/<workspace>.
pub fn moved(path: &str, query: Option<&str>, place: &Place) -> String {
    let (w, s) = (format!("{}/w/{}", place.origin.trim_end_matches('/'), place.workspace), &place.station);
    let parts: Vec<&str> = path.split('/').filter(|p| !p.is_empty()).collect();
    let to = match parts.as_slice() {
        ["chats", key] => format!("{w}/s/{s}/chats/{key}"),
        ["services", id] => format!("{w}/s/{s}/services/{id}"),
        // Bots became connects: their old links too.
        ["connects", id] | ["bots", id] => format!("{w}/s/{s}/connects/{id}"),
        ["settings", "accounts"] => format!("{w}/s/{s}/settings/accounts"),
        ["settings", "accounts", id] => format!("{w}/s/{s}/settings/accounts/{id}"),
        ["settings", page @ ("connects" | "memory" | "appearance" | "shortcuts")] => format!("{w}/settings/{page}"),
        // The machine's page is its station's card among the workspace's.
        ["settings", "device"] => format!("{w}/settings/stations"),
        ["settings"] => format!("{w}/settings"),
        ["new"] => format!("{w}/new"),
        ["archive"] => format!("{w}/archive"),
        _ => format!("{w}/"),
    };
    match query.filter(|q| !q.is_empty()) {
        Some(query) => format!("{to}?{query}"),
        None => to,
    }
}

/// What the port says while the station is in no workspace: that it is not, and how to join one.
fn unbound(place: Option<&Place>) -> String {
    let join = "加入 workspace：stillfail station enroll <cloud> <token>（token 在 still.fail 的「添加 station」里生成）";
    match place.and_then(|p| p.removed_at.map(|at| (p, at))) {
        Some((place, at)) => format!(
            "这台 still.fail station 已被移出 workspace「{}」（{}），现在不接 Slack、不跑 agent。\n重新{join}\n",
            place.workspace_name,
            stillfail_app::transcript::iso(at as i64 * 1000)
        ),
        None => format!("这台 still.fail station 还没有加入 workspace，不接 Slack、不跑 agent。\n{join}\n本机不再提供管理页：加入后到 still.fail 打开它。\n"),
    }
}

fn empty() -> Body {
    Full::new(Bytes::new()).map_err(|never| match never {}).boxed_unsync()
}

fn plain(status: StatusCode, text: &str) -> Response<Body> {
    with_type(status, "text/plain; charset=utf-8", text)
}

fn with_type(status: StatusCode, kind: &str, text: &str) -> Response<Body> {
    let body = Full::new(Bytes::from(text.to_string())).map_err(|never| match never {}).boxed_unsync();
    Response::builder().status(status).header("content-type", kind).body(body).expect("response")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn place() -> Place {
        Place { origin: "https://app.still.fail/".into(), workspace: "W1".into(), workspace_name: "Dev".into(), station: "abc".into(), removed_at: None }
    }

    fn location(path: &str, query: Option<&str>, place: Option<&Place>) -> (u16, Option<String>) {
        let r = answer(path, query, true, place);
        (r.status().as_u16(), r.headers().get("location").map(|v| v.to_str().unwrap().to_string()))
    }

    #[test]
    fn old_links_to_the_page_go_to_the_same_page_in_the_cloud() {
        let p = place();
        let at = |path: &str, query: Option<&str>| location(path, query, Some(&p)).1.unwrap();
        let (w, s) = ("https://app.still.fail/w/W1", "https://app.still.fail/w/W1/s/abc");
        assert_eq!(at("/admin/chats/ember%3Ac-1", Some("history=k&entry=3")), format!("{s}/chats/ember%3Ac-1?history=k&entry=3"));
        assert_eq!(at("/admin/chats/ember%3Ac-1", None), format!("{s}/chats/ember%3Ac-1"));
        assert_eq!(at("/admin/services/j1", None), format!("{s}/services/j1"));
        assert_eq!(at("/admin/connects/c1", None), format!("{s}/connects/c1"));
        assert_eq!(at("/admin/bots/c1", None), format!("{s}/connects/c1"));
        assert_eq!(at("/admin/settings/accounts", None), format!("{s}/settings/accounts"));
        assert_eq!(at("/admin/settings/accounts/p1", None), format!("{s}/settings/accounts/p1"));
        for page in ["connects", "memory", "appearance", "shortcuts"] {
            assert_eq!(at(&format!("/admin/settings/{page}"), None), format!("{w}/settings/{page}"));
        }
        assert_eq!(at("/admin/settings/device", None), format!("{w}/settings/stations"));
        assert_eq!(at("/admin/new", None), format!("{w}/new"));
        assert_eq!(at("/admin/archive", None), format!("{w}/archive"));
        for path in ["/admin/", "/admin", "/", "/admin/chats", "/admin/whatever/else"] {
            assert_eq!(at(path, None), format!("{w}/"), "{path}");
        }
        assert_eq!(location("/admin/new", None, Some(&p)).0, 302);
    }

    #[test]
    fn the_loopback_port_serves_no_admin_api_nor_page() {
        let p = place();
        for path in ["/admin/api/overview", "/admin/api/events", "/admin/api/preview/5180/", "/admin/api"] {
            let r = answer(path, None, true, Some(&p));
            assert_eq!(r.status(), 404, "{path}");
            assert!(r.headers().get("location").is_none());
        }
        assert_eq!(answer("/assets/index.js", None, true, Some(&p)).status(), 404);
        assert_eq!(answer("/healthz", None, true, None).status(), 200);
        assert_eq!(answer("/healthz", None, false, None).status(), 503);
    }

    #[tokio::test]
    async fn in_no_workspace_it_says_so_and_how_to_join_one() {
        let text = |r: Response<Body>| async move { String::from_utf8(r.into_body().collect().await.unwrap().to_bytes().to_vec()).unwrap() };
        let never = answer("/admin/chats/k", None, true, None);
        assert_eq!(never.status(), 404);
        let said = text(never).await;
        assert!(said.contains("还没有加入 workspace") && said.contains("stillfail station enroll"), "{said}");
        let removed = Place { removed_at: Some(1_790_000_000), ..place() };
        let r = answer("/admin/chats/k", None, true, Some(&removed));
        assert!(r.headers().get("location").is_none());
        let said = text(r).await;
        assert!(said.contains("已被移出 workspace「Dev」") && said.contains("2026-09-21T"), "{said}");
    }

    #[test]
    fn where_the_station_is_is_read_from_its_cloud_json() {
        let dir = std::env::temp_dir().join(format!("stillfail-local-{}", std::process::id()));
        std::fs::create_dir_all(dir.join("mesh")).unwrap();
        assert_eq!(Place::read(&dir), None);
        std::fs::write(dir.join("mesh/cloud.json"), r#"{"origin":"https://x","station":"s","workspace":"w","workspace_name":"W","name":"n","relay_url":"r","grant_keys":{}}"#).unwrap();
        assert_eq!(Place::read(&dir).unwrap().removed_at, None);
        std::fs::write(dir.join("mesh/cloud.json"), r#"{"origin":"https://x","station":"s","workspace":"w","workspace_name":"W","removed_at":5,"removed_code":4004}"#).unwrap();
        assert_eq!(Place::read(&dir).unwrap().removed_at, Some(5));
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
