//! The `Host` of a native app. It lives on the core thread (see lib.rs):
//! HTTP through reqwest, time and tasks on that thread's tokio runtime,
//! storage as files handed to a thread of their own so the core never waits
//! on the disk.

use std::panic::AssertUnwindSafe;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::mpsc;

use ember_core::host::{Host, HostError, HttpRequest, HttpResponse, SocketFrames, StreamResponse};
use ember_core::{ClientId, CoreError, CoreMessage};
use futures::future::LocalBoxFuture;
use futures::stream;
use futures::{FutureExt, StreamExt};
use tokio::sync::{mpsc::UnboundedSender, oneshot};
use tokio_tungstenite::Connector;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::{Error as WsError, Message};

use crate::{Command, CoreListener};

pub struct NativeHost {
    cloud_origin: String,
    tls: Arc<rustls::ClientConfig>,
    http: reqwest::Client,
    storage: Storage,
    listener: Arc<dyn CoreListener>,
    /// Back to the core thread's loop: a task that panicked ends this core.
    commands: UnboundedSender<Command>,
}

impl NativeHost {
    pub fn new(data_dir: PathBuf, cloud_origin: String, listener: Arc<dyn CoreListener>, commands: UnboundedSender<Command>) -> NativeHost {
        let tls = Arc::new(tls_config());
        let http = reqwest::Client::builder()
            .tls_backend_preconfigured((*tls).clone())
            .connect_timeout(std::time::Duration::from_secs(15))
            .build()
            .expect("reqwest client");
        NativeHost { cloud_origin, tls, http, storage: Storage::new(data_dir), listener, commands }
    }
}

/// The crypto provider is iroh's (ring); the roots Mozilla's, as iroh's own TLS
/// uses, so nothing needs the Android platform verifier's JNI setup.
fn tls_config() -> rustls::ClientConfig {
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let roots = rustls::RootCertStore { roots: webpki_roots::TLS_SERVER_ROOTS.to_vec() };
    rustls::ClientConfig::builder_with_provider(provider)
        .with_safe_default_protocol_versions()
        .expect("ring supports the default protocol versions")
        .with_root_certificates(roots)
        .with_no_client_auth()
}

/// Opens a WebSocket that only listens; resolves once it is open. `protocols`
/// are its subprotocols (ember cloud reads the token from one of them).
fn websocket(tls: Arc<rustls::ClientConfig>, url: String, protocols: Vec<String>) -> LocalBoxFuture<'static, Result<SocketFrames, HostError>> {
    Box::pin(async move {
        let mut request = url.as_str().into_client_request().map_err(ws_error)?;
        if !protocols.is_empty() {
            let value = protocols.join(", ").parse().map_err(|_| HostError("websocket 子协议不对".into()))?;
            request.headers_mut().insert("sec-websocket-protocol", value);
        }
        let (socket, _) = tokio_tungstenite::connect_async_tls_with_config(request, None, false, Some(Connector::Rustls(tls))).await.map_err(ws_error)?;
        // Read as one stream (not split): reading is also what answers the server's pings.
        let frames = stream::unfold(Some(socket), |socket| async move {
            let mut socket = socket?;
            loop {
                match socket.next().await {
                    Some(Ok(Message::Text(text))) => return Some((Ok(text.as_str().to_owned()), Some(socket))),
                    Some(Ok(Message::Close(_))) | Some(Err(WsError::ConnectionClosed | WsError::AlreadyClosed)) | None => return None,
                    Some(Ok(_)) => {}
                    Some(Err(error)) => return Some((Err(ws_error(error)), None)),
                }
            }
        });
        Ok(frames.boxed_local())
    })
}

fn ws_error(error: WsError) -> HostError {
    match error {
        WsError::Http(response) => HostError(format!("websocket refused ({})", response.status().as_u16())),
        error => HostError(format!("websocket: {error}")),
    }
}

fn http_error(error: reqwest::Error) -> HostError {
    // reqwest's Display leaves out the cause ("error sending request"); the chain says what failed.
    let mut message = error.to_string();
    let mut source = std::error::Error::source(&error);
    while let Some(cause) = source {
        message.push_str(": ");
        message.push_str(&cause.to_string());
        source = cause.source();
    }
    HostError(message)
}

fn build(http: &reqwest::Client, request: HttpRequest) -> Result<reqwest::RequestBuilder, HostError> {
    let method = reqwest::Method::from_bytes(request.method.as_bytes()).map_err(|e| HostError(e.to_string()))?;
    let mut builder = http.request(method, &request.url);
    for (name, value) in request.headers {
        builder = builder.header(name, value);
    }
    if let Some(body) = request.body {
        builder = builder.body(body);
    }
    Ok(builder)
}

fn headers(response: &reqwest::Response) -> Vec<(String, String)> {
    response.headers().iter().map(|(k, v)| (k.to_string(), String::from_utf8_lossy(v.as_bytes()).into_owned())).collect()
}

impl Host for NativeHost {
    fn cloud_origin(&self) -> String {
        self.cloud_origin.clone()
    }

    fn fetch(&self, request: HttpRequest) -> LocalBoxFuture<'static, Result<HttpResponse, HostError>> {
        let request = build(&self.http, request);
        Box::pin(async move {
            let response = request?.send().await.map_err(http_error)?;
            let (status, headers) = (response.status().as_u16(), headers(&response));
            let body = response.bytes().await.map_err(http_error)?.to_vec();
            Ok(HttpResponse { status, headers, body })
        })
    }

    fn websocket(&self, url: String, protocols: Vec<String>) -> LocalBoxFuture<'static, Result<SocketFrames, HostError>> {
        websocket(self.tls.clone(), url, protocols)
    }

    fn fetch_stream(&self, request: HttpRequest) -> LocalBoxFuture<'static, Result<StreamResponse, HostError>> {
        let request = build(&self.http, request);
        Box::pin(async move {
            let response = request?.send().await.map_err(http_error)?;
            let (status, headers) = (response.status().as_u16(), headers(&response));
            // Dropping the stream drops the response, which closes the connection.
            let body = response.bytes_stream().map(|chunk| chunk.map(|c| c.to_vec()).map_err(http_error)).boxed_local();
            Ok(StreamResponse { status, headers, body })
        })
    }

    fn storage_get(&self, key: &str) -> LocalBoxFuture<'static, Result<Option<Vec<u8>>, HostError>> {
        let path = self.storage.path(key);
        self.storage.run(move || match std::fs::read(&path) {
            Ok(bytes) => Ok(Some(bytes)),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(io_error("读取", error)),
        })
    }

    fn storage_set(&self, key: &str, value: Vec<u8>) -> LocalBoxFuture<'static, Result<(), HostError>> {
        let path = self.storage.path(key);
        self.storage.run(move || {
            // Written aside and renamed over: a crash leaves the old value or the new one, never half.
            let partial = path.with_extension("partial");
            std::fs::write(&partial, &value).map_err(|e| io_error("写入", e))?;
            std::fs::File::open(&partial).and_then(|f| f.sync_all()).map_err(|e| io_error("写入", e))?;
            std::fs::rename(&partial, &path).map_err(|e| io_error("写入", e))
        })
    }

    fn storage_delete(&self, key: &str) -> LocalBoxFuture<'static, Result<(), HostError>> {
        let path = self.storage.path(key);
        self.storage.run(move || match std::fs::remove_file(&path) {
            Err(error) if error.kind() != std::io::ErrorKind::NotFound => Err(io_error("删除", error)),
            _ => Ok(()),
        })
    }

    fn now_ms(&self) -> f64 {
        let since = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default();
        since.as_secs_f64() * 1000.0
    }

    fn utc_offset_min(&self, at_ms: f64) -> i32 {
        utc_offset_min(at_ms)
    }

    fn sleep(&self, ms: u64) -> LocalBoxFuture<'static, ()> {
        Box::pin(tokio::time::sleep(std::time::Duration::from_millis(ms)))
    }

    fn spawn(&self, task: LocalBoxFuture<'static, ()>) {
        let commands = self.commands.clone();
        tokio::task::spawn_local(async move {
            if let Err(panic) = AssertUnwindSafe(task).catch_unwind().await {
                let _ = commands.send(Command::Fatal(panic_message(&*panic)));
            }
        });
    }

    fn random_bytes(&self, buf: &mut [u8]) {
        getrandom::fill(buf).expect("the system's random source");
    }

    fn emit(&self, client: ClientId, message: CoreMessage) {
        let json = serde_json::to_string(&message).unwrap_or_else(|error| {
            // Someone is waiting on this id: tell them instead of dropping it.
            let id = match &message {
                CoreMessage::Ok { id, .. } | CoreMessage::Error { id, .. } | CoreMessage::Value { id, .. } | CoreMessage::Delta { id, .. } => *id,
            };
            let error = CoreMessage::Error { id, error: CoreError::new("host", format!("无法传给界面：{error}")) };
            serde_json::to_string(&error).expect("an error serializes")
        });
        self.listener.on_message(client, json);
    }
}

/// The viewer's time zone at `at_ms` from the C library, which on Android
/// follows the system's zone setting (and its changes) and knows its DST rules.
pub fn utc_offset_min(at_ms: f64) -> i32 {
    let at = (at_ms / 1000.0).floor() as libc::time_t;
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    // SAFETY: both pointers are valid for the call; localtime_r is the thread-safe variant.
    if unsafe { libc::localtime_r(&at, &mut tm) }.is_null() {
        return 0;
    }
    (tm.tm_gmtoff / 60) as i32
}

pub fn panic_message(panic: &(dyn std::any::Any + Send)) -> String {
    let text = panic.downcast_ref::<&str>().map(|s| s.to_string()).or_else(|| panic.downcast_ref::<String>().cloned());
    format!("核心崩溃：{}", text.unwrap_or_else(|| "未知原因".into()))
}

fn io_error(what: &str, error: std::io::Error) -> HostError {
    HostError(format!("{what}本地存储失败：{error}"))
}

type Job = Box<dyn FnOnce() + Send>;

/// Small values as files in the app's data directory, one per key. One thread
/// does every file operation in the order they were asked for, so a write is
/// never overtaken by an earlier one.
struct Storage {
    dir: PathBuf,
    jobs: mpsc::Sender<Job>,
}

impl Storage {
    fn new(dir: PathBuf) -> Storage {
        let (jobs, queue) = mpsc::channel::<Job>();
        std::thread::Builder::new()
            .name("ember-storage".into())
            .spawn(move || {
                for job in queue {
                    job();
                }
            })
            .expect("storage thread");
        Storage { dir, jobs }
    }

    /// Keys may hold anything; file names only letters, digits, `-` and `_` (the rest is %XX).
    fn path(&self, key: &str) -> PathBuf {
        let mut name = String::new();
        for byte in key.bytes() {
            match byte {
                b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' => name.push(byte as char),
                _ => name.push_str(&format!("%{byte:02X}")),
            }
        }
        self.dir.join(name)
    }

    fn run<T: Send + 'static>(&self, job: impl FnOnce() -> Result<T, HostError> + Send + 'static) -> LocalBoxFuture<'static, Result<T, HostError>> {
        let (done, result) = oneshot::channel();
        let sent = self.jobs.send(Box::new(move || {
            let _ = done.send(job());
        }));
        Box::pin(async move {
            sent.map_err(|_| HostError("本地存储已关闭".into()))?;
            result.await.map_err(|_| HostError("本地存储已关闭".into()))?
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio_tungstenite::tungstenite::handshake::server::{Request, Response};

    #[test]
    fn a_websocket_hands_over_its_text_frames_until_it_closes() {
        let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
        tokio::task::LocalSet::new().block_on(&runtime, async {
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let port = listener.local_addr().unwrap().port();
            let server = tokio::spawn(async move {
                let (tcp, _) = listener.accept().await.unwrap();
                let mut asked = None;
                let mut socket = tokio_tungstenite::accept_hdr_async(tcp, |request: &Request, mut response: Response| {
                    asked = request.headers().get("sec-websocket-protocol").map(|v| v.to_str().unwrap().to_string());
                    response.headers_mut().insert("sec-websocket-protocol", "ember-events".parse().unwrap());
                    Ok(response)
                })
                .await
                .unwrap();
                use futures::SinkExt;
                for frame in [Message::text("one"), Message::Ping(vec![1].into()), Message::binary(vec![2]), Message::text("two")] {
                    socket.send(frame).await.unwrap();
                }
                socket.close(None).await.unwrap();
                asked
            });
            let protocols = vec!["ember-events".to_string(), "ember-token.abc".to_string()];
            let frames = websocket(Arc::new(tls_config()), format!("ws://127.0.0.1:{port}/v1/events"), protocols).await.unwrap();
            let frames: Vec<_> = frames.collect().await;
            assert_eq!(frames, vec![Ok("one".to_string()), Ok("two".to_string())]);
            assert_eq!(server.await.unwrap().as_deref(), Some("ember-events, ember-token.abc"));

            let refused = websocket(Arc::new(tls_config()), "ws://127.0.0.1:9/".into(), vec![]).await;
            assert!(refused.is_err());
        });
    }

    #[test]
    fn keys_become_safe_file_names() {
        let (commands, _) = tokio::sync::mpsc::unbounded_channel();
        struct Quiet;
        impl CoreListener for Quiet {
            fn on_message(&self, _: u64, _: String) {}
        }
        let host = NativeHost::new(PathBuf::from("/data"), String::new(), Arc::new(Quiet), commands);
        assert_eq!(host.storage.path("device"), PathBuf::from("/data/device"));
        assert_eq!(host.storage.path("../x.y"), PathBuf::from("/data/%2E%2E%2Fx%2Ey"));
    }
}
