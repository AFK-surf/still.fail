//! A web service on this machine, reached through the admin API: GET /admin/api/preview/<port>/<path> is <path> of
//! http://localhost:<port>, passed through as it is. It is how a client shows a page an agent serves here (a dev
//! server, a report) — its requests come over the mesh like any other admin call, so they need no port open to anyone.
//! (src/admin/preview.ts) The HTTP wiring is the server's: this takes the request's parts and gives the answer's.

use std::pin::Pin;
use std::sync::LazyLock;

use bytes::Bytes;
use futures_util::{Stream, StreamExt};

/// Headers that belong to the hop to here (and the admin call's own), not to the service.
const HOP: [&str; 11] = ["connection", "keep-alive", "proxy-connection", "transfer-encoding", "upgrade", "te", "trailer", "host", "authorization", "traceparent", "tracestate"];
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
        return plain(400, format!("不认识的请求方法 {method}"));
    };
    let mut request = CLIENT.request(method, format!("http://localhost:{port}{path}"));
    for (name, value) in headers {
        if !HOP.contains(&name.as_str()) && !name.starts_with("x-ember-") && name != "accept-encoding" {
            request = request.header(name, value);
        }
    }
    // The body goes back as it is: a client that cannot undo an encoding (a service worker's Response does not) gets
    // it plain.
    request = request.header("host", format!("localhost:{port}")).header("accept-encoding", "identity").body(body);
    let answer = match request.send().await {
        Ok(answer) => answer,
        Err(e) => return plain(502, format!("这台机器上的 localhost:{port} 没有回应：{e}")),
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
}
