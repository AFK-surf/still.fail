//! The admin API as this machine reaches it: a Unix socket the Node part answers on (node.rs), and the admin page on
//! a loopback port for a browser here. The port is the usual 4760 unless something else holds it (then any free one),
//! or the one asked for with --port (then taken is an error); it is written to <data>/run/ports.json.

use std::{convert::Infallible, net::SocketAddr, path::{Path, PathBuf}, sync::Arc};

use anyhow::{Context, Result, bail};
use bytes::Bytes;
use http_body_util::{BodyExt, Full, combinators::BoxBody};
use hyper::{Request, Response, StatusCode, body::Incoming, service::service_fn};
use hyper_util::rt::TokioIo;
use tokio::{net::{TcpListener, UnixStream}, sync::watch};
use tracing::{info, warn};

pub type Body = BoxBody<Bytes, hyper::Error>;

/// One request to the Node part over its socket.
pub async fn request<B>(socket: &Path, request: Request<B>) -> Result<Response<Incoming>>
where
    B: hyper::body::Body + Send + 'static,
    B::Data: Send,
    B::Error: Into<Box<dyn std::error::Error + Send + Sync>>,
{
    let stream = UnixStream::connect(socket).await.with_context(|| format!("connect {}", socket.display()))?;
    let (mut sender, conn) = hyper::client::conn::http1::handshake(TokioIo::new(stream)).await?;
    tokio::spawn(async move {
        if let Err(error) = conn.await {
            info!(%error, "admin socket connection ended");
        }
    });
    Ok(sender.send_request(request).await?)
}

/// Whether the Node part answers now.
pub async fn healthy(socket: &Path) -> bool {
    let Ok(req) = Request::get("/healthz").header("host", "ember").body(Full::<Bytes>::default()) else { return false };
    matches!(request(socket, req).await, Ok(r) if r.status() == StatusCode::OK)
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

/// Serves the admin page here: each request passed to the Node part as it is (a browser on this machine is its
/// local viewer), or 503 while the Node part is not up.
pub async fn serve(listener: TcpListener, socket: PathBuf, ready: watch::Receiver<bool>) {
    let socket = Arc::new(socket);
    loop {
        let (stream, _): (_, SocketAddr) = match listener.accept().await {
            Ok(accepted) => accepted,
            Err(error) => {
                warn!(%error, "admin page accept failed");
                continue;
            }
        };
        let (socket, ready) = (socket.clone(), ready.clone());
        tokio::spawn(async move {
            let service = service_fn(move |req: Request<Incoming>| {
                let (socket, ready) = (socket.clone(), ready.clone());
                let up = *ready.borrow();
                async move { Ok::<_, Infallible>(pass(&socket, up, req).await) }
            });
            let _ = hyper::server::conn::http1::Builder::new().serve_connection(TokioIo::new(stream), service).await;
        });
    }
}

async fn pass(socket: &Path, ready: bool, mut req: Request<Incoming>) -> Response<Body> {
    if !ready {
        return plain(StatusCode::SERVICE_UNAVAILABLE, "ember station is starting");
    }
    // Only the mesh says who a remote viewer is; a local request never does.
    req.headers_mut().remove("x-ember-mesh");
    req.headers_mut().remove("x-ember-viewer");
    match request(socket, req).await {
        Ok(response) => response.map(|b| b.boxed()),
        Err(error) => plain(StatusCode::BAD_GATEWAY, &format!("ember station is not answering: {error}")),
    }
}

fn plain(status: StatusCode, text: &str) -> Response<Body> {
    let body = Full::new(Bytes::from(text.to_string())).map_err(|never| match never {}).boxed();
    Response::builder().status(status).header("content-type", "text/plain; charset=utf-8").body(body).expect("response")
}
