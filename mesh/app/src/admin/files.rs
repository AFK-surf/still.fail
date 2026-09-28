//! Files through the admin API: uploads waiting for the message that sends them, a session's uploads for previews, the
//! files a message names, and web services on the station's ports seen through /preview.

use std::path::{Component, Path, PathBuf};
use std::time::{Duration, SystemTime};

use anyhow::Result;
use bytes::Bytes;
use futures_util::{StreamExt, TryStreamExt};
use http_body_util::{BodyExt, BodyStream, StreamBody};
use hyper::Response;
use hyper::body::Frame;
use serde_json::Value;
use tokio::io::AsyncWriteExt;

use super::{AdminApi, Asked, Body, http_error};
use crate::store::{Attachment, Quote, now_ms};
use crate::transcript::iso;

const MAX_UPLOAD: u64 = 50 * 1024 * 1024;
/// Files that waited in the uploads a day without a message taking them are dropped.
const STAGED_FOR: Duration = Duration::from_secs(24 * 3600);

fn mime(path: &Path) -> &'static str {
    match path.extension().and_then(|e| e.to_str()).map(str::to_ascii_lowercase).as_deref() {
        Some("png") => "image/png",
        Some("jpg" | "jpeg") => "image/jpeg",
        Some("gif") => "image/gif",
        Some("webp") => "image/webp",
        Some("svg") => "image/svg+xml",
        Some("pdf") => "application/pdf",
        Some("txt") => "text/plain; charset=utf-8",
        Some("md") => "text/markdown; charset=utf-8",
        Some("json") => "application/json",
        _ => "application/octet-stream",
    }
}

/// A path as `resolve` makes it: absolute, with `.` and `..` worked out (no link followed).
pub fn clean(path: &Path) -> PathBuf {
    let mut out = PathBuf::from("/");
    for part in path.components() {
        match part {
            Component::Normal(p) => out.push(p),
            Component::ParentDir => {
                out.pop();
            }
            _ => {}
        }
    }
    out
}

/// A request's body as a stream of its bytes.
fn bytes_of<B>(body: B) -> impl futures_util::Stream<Item = std::io::Result<Bytes>> + Send + 'static
where
    B: hyper::body::Body<Data = Bytes> + Send + Unpin + 'static,
    B::Error: std::error::Error + Send + Sync + 'static,
{
    BodyStream::new(body).filter_map(|frame| async move {
        match frame {
            Ok(frame) => frame.into_data().ok().map(Ok),
            Err(e) => Some(Err(std::io::Error::other(e.to_string()))),
        }
    })
}

/// Drops uploads that waited a day without a message taking them.
pub async fn sweep_staged(dir: &Path) {
    let Ok(mut entries) = tokio::fs::read_dir(dir).await else { return };
    while let Ok(Some(entry)) = entries.next_entry().await {
        let Ok(meta) = entry.metadata().await else { continue };
        let old = meta.modified().ok().and_then(|m| SystemTime::now().duration_since(m).ok()).is_some_and(|age| age > STAGED_FOR);
        if meta.is_file() && old {
            let _ = tokio::fs::remove_file(entry.path()).await;
        }
    }
}

/// Saves a request's body in `dir` under its name, made safe and unique.
pub async fn save_upload<B>(body: B, dir: &Path, name: &str) -> Result<Attachment>
where
    B: hyper::body::Body<Data = Bytes> + Send + Unpin + 'static,
    B::Error: std::error::Error + Send + Sync + 'static,
{
    let base = name.replace('\\', "/");
    let base = base.rsplit('/').next().unwrap_or("");
    let safe: String = base.chars().map(|c| if (c as u32) < 0x20 { '_' } else { c }).collect::<String>().trim_start_matches('.').chars().take(120).collect();
    let safe = if safe.is_empty() { "file".to_string() } else { safe };
    tokio::fs::create_dir_all(dir).await?;
    let stamp = iso(now_ms())[..19].replace([':', '.'], "-");
    let mut random = [0u8; 3];
    getrandom::fill(&mut random).map_err(|e| anyhow::anyhow!("{e}"))?;
    let path = dir.join(format!("{stamp}-{}-{safe}", hex::encode(random)));
    let mut out = tokio::fs::OpenOptions::new().write(true).create_new(true).open(&path).await?;
    let mut size = 0u64;
    let mut stream = Box::pin(bytes_of(body));
    let written = async {
        while let Some(chunk) = stream.next().await {
            let chunk = chunk?;
            size += chunk.len() as u64;
            if size > MAX_UPLOAD {
                return Err(http_error(413, "文件太大了，最多 50 MB"));
            }
            out.write_all(&chunk).await?;
        }
        out.flush().await?;
        Ok::<_, anyhow::Error>(())
    };
    if let Err(e) = written.await {
        let _ = tokio::fs::remove_file(&path).await;
        return Err(e);
    }
    Ok(Attachment { name: safe, path: path.to_string_lossy().into_owned(), size, width: None, height: None })
}

/// Quotes as the page sends them, bounded.
pub fn quotes_of(input: Option<&Value>) -> Vec<Quote> {
    let text = |q: &Value, k: &str, fallback: &str, max: usize| match q.get(k) {
        None | Some(Value::Null) => fallback.to_string(),
        Some(Value::String(s)) => s.chars().take(max).collect(),
        Some(other) => other.to_string().chars().take(max).collect(),
    };
    input
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .take(20)
        .map(|q| Quote {
            author: text(q, "author", "消息", 100),
            text: text(q, "text", "", 4000),
            comment: text(q, "comment", "", 4000),
            ts: q.get("ts").and_then(Value::as_str).filter(|ts| ts.split_once('.').is_some_and(|(a, b)| !a.is_empty() && !b.is_empty() && a.chars().chain(b.chars()).all(|c| c.is_ascii_digit()))).map(String::from),
            role: q.get("role").and_then(Value::as_str).filter(|r| *r == "agent" || *r == "person").map(String::from),
        })
        .filter(|q| !q.text.trim().is_empty())
        .collect()
}

/// A web service on one of the station's ports, through /preview/<port>/<path>.
pub async fn preview<B>(asked: &Asked, body: B, port: u16, target: &str) -> Result<Response<Body>>
where
    B: hyper::body::Body<Data = Bytes> + Send + Unpin + 'static,
    B::Error: std::error::Error + Send + Sync + 'static,
{
    let request = reqwest::Body::wrap_stream(bytes_of(body));
    let answer = crate::preview::proxy_preview(&asked.method, &asked.headers, request, port, &format!("{target}{}", asked.search)).await;
    let mut response = Response::builder().status(answer.status);
    for (k, v) in &answer.headers {
        response = response.header(k.as_str(), v.as_str());
    }
    let stream = answer.body.map_ok(Frame::data);
    Ok(response.body(StreamBody::new(stream).boxed_unsync())?)
}

impl AdminApi {
    /// Where uploaded files wait for the message that sends them.
    pub(super) fn staged(&self) -> PathBuf {
        self.config().data_dir.join("uploads")
    }

    /// A file sent to a session, for previews: only from its upload directory. `thumb`: an image as a chat shows it, its
    /// thumbnail (the image itself when it has none).
    pub(super) async fn session_file(&self, key: &str, name: &str, thumb: bool) -> Result<Response<Body>> {
        let row = self.deps.store.get_session(key)?.ok_or_else(|| http_error(404, format!("unknown session {key}")))?;
        let uploads = clean(&Path::new(&row.workspace).join("uploads"));
        let base = name.rsplit(['/', '\\']).next().unwrap_or("");
        let path = clean(&uploads.join(base));
        if base.is_empty() || !path.starts_with(&uploads) || path == uploads || !path.is_file() {
            return Err(http_error(404, "没有这个文件"));
        }
        let small = if thumb {
            let (image, dir) = (path.clone(), crate::thumbs::dir(&self.config().data_dir));
            tokio::task::spawn_blocking(move || crate::thumbs::thumbnail(&image, &dir)).await.ok().flatten()
        } else {
            None
        };
        let (path, kind) = small.unwrap_or_else(|| { let kind = mime(&path); (path, kind) });
        let bytes = tokio::fs::read(&path).await?;
        Ok(Response::builder().status(200).header("content-type", kind).header("cache-control", "private, max-age=3600").body(super::full(bytes))?)
    }

    /// Files named in a message: ones waiting in the uploads (they move into the upload directory of the chat's first
    /// session, where its agents read them), or ones already in the upload directory of one of its sessions.
    pub(super) fn attachments(&self, thread: i64, input: Option<&Value>) -> Result<Vec<Attachment>> {
        let dirs: Vec<PathBuf> = self
            .deps
            .store
            .thread_sessions(thread)?
            .into_iter()
            .filter_map(|m| self.deps.store.get_session(&m.session).ok().flatten())
            .map(|s| clean(&Path::new(&s.workspace).join("uploads")))
            .collect();
        let staged = clean(&self.staged());
        input
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .take(20)
            .map(|a| {
                let mut path = clean(Path::new(a.get("path").and_then(Value::as_str).unwrap_or("")));
                if let (true, Some(first)) = (path.starts_with(&staged) && path != staged, dirs.first()) {
                    let into = first.join(path.file_name().unwrap_or_default());
                    // Sent again (a retry after the first try got here): it has moved already.
                    if path.exists() {
                        std::fs::create_dir_all(first)?;
                        std::fs::rename(&path, &into)?;
                    }
                    path = into;
                }
                let uploads = dirs.iter().find(|d| path.starts_with(d) && path != **d).filter(|_| path.exists()).ok_or_else(|| http_error(400, "附件不在上传目录里"))?;
                let dimension = |k: &str| a.get(k).and_then(Value::as_f64).filter(|v| v.fract() == 0.0 && *v > 0.0 && *v < 100_000.0).map(|v| v as u32);
                let (width, height) = match (dimension("width"), dimension("height")) {
                    (Some(w), Some(h)) => (Some(w), Some(h)),
                    _ => (None, None),
                };
                let name = match a.get("name").and_then(Value::as_str) {
                    Some(name) => name.to_string(),
                    None => path.strip_prefix(uploads).map(|p| p.to_string_lossy().into_owned()).unwrap_or_default(),
                };
                Ok(Attachment {
                    name: name.chars().take(200).collect(),
                    path: path.to_string_lossy().into_owned(),
                    size: a.get("size").and_then(Value::as_f64).map(|s| s as u64).unwrap_or(0),
                    width,
                    height,
                })
            })
            .collect()
    }
}
