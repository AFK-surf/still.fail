//! A web service on this machine, reached through the admin API: GET /admin/api/preview/<port>/<path> is <path> of
//! http://localhost:<port>, passed through as it is. It is how a client shows a page an agent serves here (a dev
//! server, a report) — its requests come over the mesh like any other admin call, so they need no port open to anyone.
//! The HTTP wiring is the server's: this takes the request's parts and gives the answer's.

use std::pin::Pin;
use std::sync::LazyLock;

use bytes::Bytes;
use futures_util::{Stream, StreamExt};

use crate::lang::{spoken, t};

/// Headers that belong to the hop to here (and the admin call's own), not to the service.
const HOP: [&str; 12] = ["connection", "keep-alive", "proxy-connection", "transfer-encoding", "upgrade", "te", "trailer", "host", "authorization", "traceparent", "tracestate", crate::lang::HEADER];
/// Answers the service gives that would stop its page from being shown framed on another origin.
const FRAMING: [&str; 3] = ["x-frame-options", "content-security-policy", "content-security-policy-report-only"];

pub type BodyStream = Pin<Box<dyn Stream<Item = std::io::Result<Bytes>> + Send>>;

/// What goes back to the client: the service's status, its headers (by lowercase name, repeats kept), and its body as
/// it comes.
pub struct PreviewAnswer {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: BodyStream,
}

/// The port and path a /preview/<port>/<path> request is for.
pub fn preview_target(path: &str) -> Option<(u16, String)> {
    let rest = path.strip_prefix("/preview/")?;
    let (port, path) = match rest.find('/') {
        Some(at) => (&rest[..at], &rest[at..]),
        None => (rest, "/"),
    };
    if port.is_empty() || port.len() > 5 || !port.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let port: u32 = port.parse().ok()?;
    (1..=65535).contains(&port).then(|| (port as u16, path.to_string()))
}

static CLIENT: LazyLock<reqwest::Client> = LazyLock::new(|| {
    // The service's redirects go back to the client, as they are; a proxy set for this process is not for localhost.
    reqwest::Client::builder().redirect(reqwest::redirect::Policy::none()).no_proxy().build().expect("an HTTP client")
});

fn plain(status: u16, text: String) -> PreviewAnswer {
    PreviewAnswer {
        status,
        headers: vec![("content-type".into(), "text/plain; charset=utf-8".into())],
        body: Box::pin(futures_util::stream::once(async move { Ok(Bytes::from(text)) })),
    }
}

/// Passes a request to localhost:`port` and its answer back. `headers` are the request's, by lowercase name.
pub async fn proxy_preview(method: &str, headers: &[(String, String)], body: reqwest::Body, port: u16, path: &str) -> PreviewAnswer {
    let Ok(method) = reqwest::Method::from_bytes(method.as_bytes()) else {
        return plain(400, t!(spoken(); "station.preview.badMethod", method = method));
    };
    let mut request = CLIENT.request(method, format!("http://localhost:{port}{path}"));
    for (name, value) in headers {
        if !HOP.contains(&name.as_str()) && !name.starts_with("x-stillfail-") && !name.starts_with("x-ember-") && name != "accept-encoding" {
            request = request.header(name, value);
        }
    }
    // The body goes back as it is: a client that cannot undo an encoding (a service worker's Response does not) gets
    // it plain.
    request = request.header("host", format!("localhost:{port}")).header("accept-encoding", "identity").body(body);
    let answer = match request.send().await {
        Ok(answer) => answer,
        Err(e) => return plain(502, t!(spoken(); "station.preview.noAnswerSaying", port = port, error = e)),
    };
    let service = [format!("http://localhost:{port}"), format!("https://localhost:{port}"), format!("http://127.0.0.1:{port}"), format!("https://127.0.0.1:{port}"), format!("http://[::1]:{port}"), format!("https://[::1]:{port}")];
    let headers = answer
        .headers()
        .iter()
        .filter(|(name, _)| !HOP.contains(&name.as_str()) && !FRAMING.contains(&name.as_str()))
        .filter_map(|(name, value)| {
            let mut value = value.to_str().ok()?.to_string();
            // A redirect to the service itself stays on the preview's path.
            if name.as_str() == "location"
                && let Some(origin) = service.iter().find(|o| value.starts_with(o.as_str()))
            {
                value = value[origin.len()..].to_string();
            }
            Some((name.as_str().to_string(), value))
        })
        .collect();
    PreviewAnswer { status: answer.status().as_u16(), headers, body: Box::pin(answer.bytes_stream().map(|chunk| chunk.map_err(std::io::Error::other))) }
}

// ── a service's WebSocket ────────────────────────────────────────────────────

/// A WebSocket message on a preview's socket stream, as the client core frames it (client/core-ts/src/station/sync.ts): a kind
/// byte, the payload's length (4 bytes, big-endian), then the payload.
pub const FRAME_TEXT: u8 = 1;
pub const FRAME_BINARY: u8 = 2;
/// Its payload: the close code (2 bytes, big-endian) and the reason, when there is one.
pub const FRAME_CLOSE: u8 = 8;
/// A frame longer than this is not a client talking.
const MAX_FRAME: usize = 16 * 1024 * 1024;

/// Request headers passed on to the service's socket: what a page's own WebSocket would send that the service may
/// look at (its sub-protocols, cookies, the browser it is).
const SOCKET_HEADERS: [&str; 3] = ["sec-websocket-protocol", "cookie", "user-agent"];

pub type ServiceSocket = tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

/// Opens `path` of ws://localhost:`port` for a preview's page, with its headers (by lowercase name). Answers the socket
/// and the sub-protocol the service chose, or the status to answer and why: the service's own refusal, 502 when it
/// does not answer.
pub async fn open_socket(headers: &[(String, String)], port: u16, path: &str) -> Result<(ServiceSocket, Option<String>), (u16, String)> {
    use tokio_tungstenite::tungstenite::{self, client::IntoClientRequest, http::HeaderValue};
    let mut request = format!("ws://localhost:{port}{path}").into_client_request().map_err(|e| (400, t!(spoken(); "station.preview.badAddress", error = e)))?;
    for (name, value) in headers {
        if SOCKET_HEADERS.contains(&name.as_str())
            && let (Ok(name), Ok(value)) = (tungstenite::http::HeaderName::from_bytes(name.as_bytes()), HeaderValue::from_str(value))
        {
            request.headers_mut().insert(name, value);
        }
    }
    // As a page of the service itself would: a dev server turns away sockets from other origins.
    request.headers_mut().insert("origin", HeaderValue::from_str(&format!("http://localhost:{port}")).expect("an origin"));
    let connecting = tokio_tungstenite::connect_async(request);
    match tokio::time::timeout(std::time::Duration::from_secs(20), connecting).await {
        Err(_) => Err((502, t!(spoken(); "station.preview.noAnswer", port = port))),
        Ok(Err(tungstenite::Error::Http(answer))) => {
            let status = answer.status().as_u16();
            Err((if status < 400 { 502 } else { status }, t!(spoken(); "station.preview.socketRefused", port = port, status = status)))
        }
        Ok(Err(e)) => Err((502, t!(spoken(); "station.preview.noAnswerSaying", port = port, error = e))),
        Ok(Ok((socket, answer))) => {
            let protocol = answer.headers().get("sec-websocket-protocol").and_then(|v| v.to_str().ok()).map(str::to_string);
            Ok((socket, protocol))
        }
    }
}

/// One frame (module doc of FRAME_TEXT).
pub fn frame(kind: u8, payload: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(5 + payload.len());
    out.push(kind);
    out.extend_from_slice(&(payload.len() as u32).to_be_bytes());
    out.extend_from_slice(payload);
    out
}

/// Reads one frame; None when the stream ended between frames.
async fn read_frame<R: tokio::io::AsyncRead + Unpin>(from: &mut R) -> std::io::Result<Option<(u8, Vec<u8>)>> {
    use tokio::io::AsyncReadExt;
    let mut head = [0u8; 5];
    match from.read_exact(&mut head[..1]).await {
        Ok(_) => {}
        Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(None),
        Err(e) => return Err(e),
    }
    from.read_exact(&mut head[1..]).await?;
    let len = u32::from_be_bytes([head[1], head[2], head[3], head[4]]) as usize;
    if len > MAX_FRAME {
        return Err(std::io::Error::other("frame too long"));
    }
    let mut payload = vec![0u8; len];
    from.read_exact(&mut payload).await?;
    Ok(Some((head[0], payload)))
}

/// Passes messages between the service's socket and the client's stream until either closes; a close on one is
/// passed on to the other.
pub async fn pump_socket<R, W>(socket: ServiceSocket, mut from_client: R, mut to_client: W)
where
    R: tokio::io::AsyncRead + Unpin,
    W: tokio::io::AsyncWrite + Unpin,
{
    use futures_util::SinkExt;
    use tokio::io::AsyncWriteExt;
    use tokio_tungstenite::tungstenite::Message;
    use tokio_tungstenite::tungstenite::protocol::{CloseFrame, frame::coding::CloseCode};
    let (mut to_service, mut from_service) = socket.split();
    let up = async {
        loop {
            let message = match read_frame(&mut from_client).await {
                Ok(Some((FRAME_TEXT, payload))) => Message::text(String::from_utf8_lossy(&payload).into_owned()),
                Ok(Some((FRAME_BINARY, payload))) => Message::binary(payload),
                Ok(Some((FRAME_CLOSE, payload))) => {
                    let code = if payload.len() >= 2 { u16::from_be_bytes([payload[0], payload[1]]) } else { 1000 };
                    let reason = String::from_utf8_lossy(payload.get(2..).unwrap_or_default()).into_owned();
                    let _ = to_service.send(Message::Close(Some(CloseFrame { code: CloseCode::from(code), reason: reason.into() }))).await;
                    return;
                }
                Ok(Some(_)) => continue,
                // The client went (its page, its tab): the service's socket goes too.
                Ok(None) | Err(_) => {
                    let _ = to_service.send(Message::Close(Some(CloseFrame { code: CloseCode::Away, reason: "".into() }))).await;
                    return;
                }
            };
            if to_service.send(message).await.is_err() {
                return;
            }
        }
    };
    let down = async {
        while let Some(message) = from_service.next().await {
            let bytes = match message {
                Ok(Message::Text(text)) => frame(FRAME_TEXT, text.as_bytes()),
                Ok(Message::Binary(data)) => frame(FRAME_BINARY, &data),
                Ok(Message::Close(close)) => {
                    let (code, reason) = close.map(|c| (u16::from(c.code), c.reason.to_string())).unwrap_or((1005, String::new()));
                    let mut payload = code.to_be_bytes().to_vec();
                    payload.extend_from_slice(reason.as_bytes());
                    let _ = to_client.write_all(&frame(FRAME_CLOSE, &payload)).await;
                    break;
                }
                // Pings are answered by the socket itself.
                Ok(_) => continue,
                Err(_) => {
                    let _ = to_client.write_all(&frame(FRAME_CLOSE, &1006u16.to_be_bytes())).await;
                    break;
                }
            };
            if to_client.write_all(&bytes).await.is_err() {
                return;
            }
        }
        let _ = to_client.shutdown().await;
    };
    // The service's side ending ends both: the client's half is dropped (its stream is reset). The client's ending (its
    // close sent on, or its page gone) leaves the service a moment to answer its close, which goes back as it would.
    tokio::pin!(up, down);
    tokio::select! {
        _ = &mut up => {
            let _ = tokio::time::timeout(std::time::Duration::from_secs(5), &mut down).await;
        }
        _ = &mut down => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    /// A one-request-at-a-time HTTP service: echoes what it was asked in x-seen, forbids framing, redirects /old.
    async fn service() -> (u16, tokio::task::JoinHandle<()>) {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let task = tokio::spawn(async move {
            loop {
                let (mut socket, _) = listener.accept().await.unwrap();
                let mut got = Vec::new();
                let mut buf = [0u8; 4096];
                let head_end = loop {
                    let n = socket.read(&mut buf).await.unwrap();
                    got.extend_from_slice(&buf[..n]);
                    if let Some(at) = got.windows(4).position(|w| w == b"\r\n\r\n") {
                        break at;
                    }
                };
                let head = String::from_utf8_lossy(&got[..head_end]).to_string();
                let header = |name: &str| head.lines().find_map(|l| l.split_once(':').filter(|(k, _)| k.eq_ignore_ascii_case(name)).map(|(_, v)| v.trim().to_string()));
                let length: usize = header("content-length").and_then(|l| l.parse().ok()).unwrap_or(0);
                while got.len() < head_end + 4 + length {
                    let n = socket.read(&mut buf).await.unwrap();
                    got.extend_from_slice(&buf[..n]);
                }
                let body = String::from_utf8_lossy(&got[head_end + 4..]).to_string();
                let target = head.lines().next().unwrap().split(' ').take(2).collect::<Vec<_>>().join(" ");
                let answer = if target.ends_with(" /old") {
                    format!("HTTP/1.1 302 Found\r\nlocation: http://localhost:{port}/new?x=1\r\ncontent-length: 0\r\nconnection: close\r\n\r\n")
                } else {
                    let seen = format!("{target} {} {} {body}", header("host").unwrap_or_default(), header("traceparent").unwrap_or("-".into()));
                    let text = "hello from the service";
                    format!("HTTP/1.1 200 OK\r\ncontent-type: text/plain\r\nx-frame-options: DENY\r\ncontent-security-policy: frame-ancestors 'none'\r\nx-seen: {seen}\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{text}", text.len())
                };
                socket.write_all(answer.as_bytes()).await.unwrap();
                let _ = socket.shutdown().await;
            }
        });
        (port, task)
    }

    async fn text(body: BodyStream) -> String {
        let chunks: Vec<std::io::Result<Bytes>> = body.collect().await;
        String::from_utf8(chunks.into_iter().flat_map(|c| c.unwrap().to_vec()).collect()).unwrap()
    }

    fn header<'a>(answer: &'a PreviewAnswer, name: &str) -> Option<&'a str> {
        answer.headers.iter().find(|(k, _)| k == name).map(|(_, v)| v.as_str())
    }

    #[tokio::test]
    async fn a_web_service_on_the_machine_is_reached_as_it_answers_framing_allowed() {
        let (port, task) = service().await;
        let asked = vec![
            ("traceparent".to_string(), "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01".to_string()),
            ("x-stillfail-mesh".to_string(), "secret".to_string()),
            ("x-ember-mesh".to_string(), "secret".to_string()),
            ("content-type".to_string(), "text/plain".to_string()),
        ];
        let (target_port, path) = preview_target(&format!("/preview/{port}/a/b?q=1")).unwrap();
        let got = proxy_preview("POST", &asked, reqwest::Body::from("x=1"), target_port, &path).await;
        assert_eq!(got.status, 200);
        assert_eq!(header(&got, "x-seen"), Some(format!("POST /a/b?q=1 localhost:{port} - x=1").as_str()), "the path and query as asked, the service's own host, none of the admin call's headers");
        assert_eq!((header(&got, "x-frame-options"), header(&got, "content-security-policy")), (None, None));
        assert_eq!(text(got.body).await, "hello from the service");
        let moved = proxy_preview("GET", &[], reqwest::Body::from(""), port, "/old").await;
        assert_eq!((moved.status, header(&moved, "location")), (302, Some("/new?x=1")), "a redirect to the service stays on it");
        task.abort();
        let _ = task.await;
        let gone = proxy_preview("GET", &[], reqwest::Body::from(""), port, "/").await;
        assert_eq!(gone.status, 502);
        assert!(text(gone.body).await.contains(&format!("localhost:{port} 没有回应")));
        assert_eq!(preview_target("/preview/99999/"), None, "not a port");
        assert_eq!(preview_target("/preview/8080"), Some((8080, "/".into())));
    }

    /// A WebSocket service: checks the origin it was opened from and the sub-protocol asked for, then echoes each
    /// message back with what it saw first, and closes with 4001 when told "bye".
    #[allow(clippy::result_large_err)] // tungstenite's handshake callback answers its own Response as the error
    async fn socket_service() -> u16 {
        use tokio_tungstenite::tungstenite::{Message, handshake::server::{Request, Response}};
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        tokio::spawn(async move {
            while let Ok((tcp, _)) = listener.accept().await {
                tokio::spawn(async move {
                    let mut seen = String::new();
                    let socket = tokio_tungstenite::accept_hdr_async(tcp, |request: &Request, mut response: Response| {
                        let h = |n: &str| request.headers().get(n).and_then(|v| v.to_str().ok()).unwrap_or("-").to_string();
                        seen = format!("{} {} {} {} {}", request.uri(), h("origin"), h("sec-websocket-protocol"), h("x-stillfail-mesh"), h("x-ember-mesh"));
                        if let Some(asked) = request.headers().get("sec-websocket-protocol") {
                            response.headers_mut().insert("sec-websocket-protocol", asked.clone());
                        }
                        Ok(response)
                    })
                    .await
                    .unwrap();
                    let (mut to, mut from) = socket.split();
                    use futures_util::SinkExt;
                    while let Some(Ok(message)) = from.next().await {
                        match message {
                            Message::Text(t) if t.as_str() == "bye" => {
                                let close = tokio_tungstenite::tungstenite::protocol::CloseFrame { code: 4001u16.into(), reason: "done".into() };
                                let _ = to.send(Message::Close(Some(close))).await;
                                break;
                            }
                            Message::Text(t) => to.send(Message::text(format!("{seen} | {t}"))).await.unwrap(),
                            Message::Binary(b) => to.send(Message::binary(b)).await.unwrap(),
                            _ => {}
                        }
                    }
                });
            }
        });
        port
    }

    #[tokio::test]
    async fn a_services_websocket_passes_messages_both_ways_framed_until_it_closes() {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let port = socket_service().await;
        let asked = vec![
            ("sec-websocket-protocol".to_string(), "vite-hmr".to_string()),
            ("x-stillfail-mesh".to_string(), "secret".to_string()),
            ("x-ember-mesh".to_string(), "secret".to_string()),
        ];
        let (socket, protocol) = open_socket(&asked, port, "/hmr?token=1").await.unwrap();
        assert_eq!(protocol.as_deref(), Some("vite-hmr"));
        // The client's side of the stream: frames written to `client`, read from it.
        let (client, station) = tokio::io::duplex(64 * 1024);
        let (from_client, to_client) = tokio::io::split(station);
        let pump = tokio::spawn(pump_socket(socket, from_client, to_client));
        let (mut reading, mut writing) = tokio::io::split(client);
        writing.write_all(&frame(FRAME_TEXT, b"hi")).await.unwrap();
        writing.write_all(&frame(FRAME_BINARY, &[0, 1, 2])).await.unwrap();
        let got = read_frame(&mut reading).await.unwrap().unwrap();
        assert_eq!((got.0, String::from_utf8(got.1).unwrap()), (FRAME_TEXT, format!("/hmr?token=1 http://localhost:{port} vite-hmr - - | hi")), "the path, the service's own origin, the sub-protocol; none of still.fail's headers (either name)");
        assert_eq!(read_frame(&mut reading).await.unwrap().unwrap(), (FRAME_BINARY, vec![0, 1, 2]));
        writing.write_all(&frame(FRAME_TEXT, b"bye")).await.unwrap();
        let (kind, payload) = read_frame(&mut reading).await.unwrap().unwrap();
        assert_eq!((kind, u16::from_be_bytes([payload[0], payload[1]]), &payload[2..]), (FRAME_CLOSE, 4001, &b"done"[..]), "the service's close, with its code and reason");
        let mut rest = Vec::new();
        reading.read_to_end(&mut rest).await.unwrap();
        assert!(rest.is_empty(), "then the stream ends");
        pump.await.unwrap();
    }

    #[tokio::test]
    async fn a_close_from_the_client_is_answered_by_the_services_own() {
        let port = socket_service().await;
        let (socket, _) = open_socket(&[], port, "/").await.unwrap();
        let (client, station) = tokio::io::duplex(1024);
        let (from_client, to_client) = tokio::io::split(station);
        let pump = tokio::spawn(pump_socket(socket, from_client, to_client));
        let (mut reading, mut writing) = tokio::io::split(client);
        use tokio::io::AsyncWriteExt;
        writing.write_all(&frame(FRAME_CLOSE, &[&4002u16.to_be_bytes()[..], b"leaving"].concat())).await.unwrap();
        let (kind, payload) = read_frame(&mut reading).await.unwrap().unwrap();
        assert_eq!((kind, u16::from_be_bytes([payload[0], payload[1]])), (FRAME_CLOSE, 4002), "the service's close comes back");
        tokio::time::timeout(std::time::Duration::from_secs(5), pump).await.expect("then it ends").unwrap();
    }

    #[tokio::test]
    async fn a_client_gone_closes_the_services_socket_and_a_refusal_says_why() {
        let port = socket_service().await;
        let (socket, _) = open_socket(&[], port, "/").await.unwrap();
        let (client, station) = tokio::io::duplex(1024);
        let (from_client, to_client) = tokio::io::split(station);
        let pump = tokio::spawn(pump_socket(socket, from_client, to_client));
        drop(client);
        tokio::time::timeout(std::time::Duration::from_secs(5), pump).await.expect("the pump ends with its client").unwrap();
        // A port with plain HTTP on it (no socket there) and one with nothing at all.
        let (http, task) = service().await;
        let refused = open_socket(&[], http, "/").await.err().unwrap();
        assert!(refused.0 >= 400, "{refused:?}");
        task.abort();
        let _ = task.await;
        let none = open_socket(&[], http, "/").await.err().unwrap();
        assert_eq!(none.0, 502);
        assert!(none.1.contains(&format!("localhost:{http} 没有回应")), "{}", none.1);
    }
}
