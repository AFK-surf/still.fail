//! The station's app (ember-app), run in this process, and its admin page on a loopback port for a browser here. The
//! port is the usual 4760 unless something else holds it (then any free one), or the one asked for with --port (then
//! taken is an error); it is written to <data>/run/ports.json.

use std::{convert::Infallible, path::Path, sync::{Arc, OnceLock, Weak}};

use anyhow::{Result, bail};
use bytes::Bytes;
use http_body_util::{BodyExt, Full, combinators::UnsyncBoxBody};
use hyper::{Request, Response, StatusCode, body::Incoming, service::service_fn};
use ember_app::handoff::{Door, serve_http1};
use tokio::{net::TcpListener, sync::watch};
use tracing::{info, warn};

pub type Body = UnsyncBoxBody<Bytes, Box<dyn std::error::Error + Send + Sync>>;

/// Who a request is from, when the mesh verified them (a local request says nothing of itself).
pub type MeshViewer = ember_app::access::Viewer;

/// Where requests go: the app in this process, once it has started.
#[derive(Clone, Default)]
pub struct Backend(pub Arc<OnceLock<Arc<ember_app::server::App>>>);

impl Backend {
    /// One request, on behalf of `viewer` (the mesh's) or of this machine (None).
    pub async fn call<B>(&self, request: Request<B>, viewer: Option<&MeshViewer>) -> Result<Response<Body>>
    where
        B: hyper::body::Body<Data = Bytes> + Send + Unpin + 'static,
        B::Error: std::error::Error + Send + Sync + 'static,
    {
        let app = self.0.get().ok_or_else(|| anyhow::anyhow!("not started"))?;
        let response = app.handle(request, viewer.cloned()).await;
        Ok(response.map(|b| b.map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>).boxed_unsync()))
    }
}

/// Listens on 127.0.0.1:`port`; when it is only the usual one (`named` false) and something holds it, on any free
/// port. The port it got is written to <data>/run/ports.json.
pub async fn bind(data: &Path, port: u16, named: bool) -> Result<TcpListener> {
    let listener = match TcpListener::bind(("127.0.0.1", port)).await {
        Ok(listener) => listener,
        Err(error) if error.kind() == std::io::ErrorKind::AddrInUse && !named => {
            warn!(port, "the admin page's usual port is taken; listening on a free one");
            TcpListener::bind(("127.0.0.1", 0)).await?
        }
        Err(error) if error.kind() == std::io::ErrorKind::AddrInUse => {
            bail!("管理页的端口 127.0.0.1:{port} 已被别的程序占用（--port 指定了这个端口）。用 `lsof -nP -iTCP:{port} -sTCP:LISTEN` 看是谁，或换一个端口。")
        }
        Err(error) => return Err(error.into()),
    };
    let got = listener.local_addr()?.port();
    let run = data.join("run");
    std::fs::create_dir_all(&run)?;
    std::fs::write(run.join("ports.json"), format!("{{\"admin\":{got}}}\n"))?;
    info!(admin = %format!("http://127.0.0.1:{got}/admin"), "admin page listening");
    Ok(listener)
}

/// Serves the admin page here: each request passed on as it is (a browser on this machine is its local viewer), or
/// 503 while the station is not up. The door can pause, to hand the socket over to the next binary.
pub fn serve(listener: TcpListener, backend: Backend, ready: watch::Receiver<bool>) -> Arc<Door> {
    let backend = Arc::new(backend);
    let cell: Arc<OnceLock<Weak<Door>>> = Arc::default();
    let door_of = cell.clone();
    let door = Door::open(listener, move |stream, closing| {
        let (backend, ready, door) = (backend.clone(), ready.clone(), door_of.clone());
        tokio::spawn(async move {
            let service = service_fn(move |req: Request<Incoming>| {
                let (backend, ready) = (backend.clone(), ready.clone());
                let up = *ready.borrow();
                let busy = door.get().and_then(Weak::upgrade).map(|d| d.busy());
                async move {
                    let answer = pass(&backend, up, req).await;
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

async fn pass(backend: &Backend, ready: bool, mut req: Request<Incoming>) -> Response<Body> {
    if !ready {
        return plain(StatusCode::SERVICE_UNAVAILABLE, "ember station is starting");
    }
    // Only the mesh says who a remote viewer is; a local request never does.
    req.headers_mut().remove("x-ember-mesh");
    req.headers_mut().remove("x-ember-viewer");
    match backend.call(req, None).await {
        Ok(response) => response,
        Err(error) => plain(StatusCode::BAD_GATEWAY, &format!("ember station is not answering: {error}")),
    }
}

fn plain(status: StatusCode, text: &str) -> Response<Body> {
    let body = Full::new(Bytes::from(text.to_string())).map_err(|never| match never {}).boxed_unsync();
    Response::builder().status(status).header("content-type", "text/plain; charset=utf-8").body(body).expect("response")
}
