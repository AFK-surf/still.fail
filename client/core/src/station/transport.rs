//! Request transport, streamed files and service previews.
use super::*;

impl Stations {
    /// A JSON read of the admin API; writes use `perform` with an explicit update policy.
    pub async fn get(&self, station: &StationAddr, path: &str) -> Result<Value> {
        self.json(station, "GET", path, None).await
    }
    /// An operation and its compatibility fallback both carry their own effects. The result is returned only once
    /// the topics changed by the successful request are current.
    pub async fn perform(&self, station: &StationAddr, op: &Request) -> Result<Value> {
        // A client-side batch uses the existing per-item endpoint, including on older stations.
        if op.method == "POST" && op.path == "/updates/all" { return self.update_all(station).await; }
        let mut current = op;
        loop {
            match self.json(station, current.method, &current.path, current.body.clone()).await {
                Err(error) if error.status == Some(404) && current.fallback.is_some() => current = current.fallback.as_deref().unwrap(),
                Err(error) => return Err(error),
                Ok(value) => {
                    self.after_write(station, &current.effect, &value).await;
                    return Ok(value);
                }
            }
        }
    }
    /// Runtimes must finish before station replaces itself. Stop on a failure, leaving the rest available to retry.
    async fn update_all(&self, station: &StationAddr) -> Result<Value> {
        let overview = self.get(station, "/overview").await?;
        let updates = overview.get("updates").and_then(Value::as_array)
            .ok_or_else(|| CoreError::invalid("这台 station 还不支持更新"))?;
        if updates.iter().any(|v| v["state"] == "updating") {
            return Err(CoreError::invalid("已有软件正在更新，请等它完成"));
        }
        let mut selected: Vec<Value> = updates.iter().filter(|v| {
            v["installed"] == true && v["updatable"] == true
                && (v["newer"] == true || v["downgrade"] == true || v["state"] == "failed")
        }).cloned().collect();
        selected.sort_by_key(|v| v["id"] == "station");
        let mut answer = json!(updates);
        for item in selected {
            let id = item["id"].as_str().ok_or_else(|| CoreError::invalid("软件缺少标识"))?;
            answer = self.json(station, "POST", "/updates", Some(json!({"id": id}))).await?;
            self.after_write(station, &Effect::Overview, &answer).await;
            // The station's restart is reflected by its connection and overview, not another queued write.
            if id == "station" { break; }
            let deadline = self.host.now_ms() + 15.0 * 60_000.0;
            loop {
                let status = answer.as_array().and_then(|items| items.iter().find(|v| v["id"] == id))
                    .ok_or_else(|| CoreError::invalid("读不到更新进度，后续更新未开始"))?;
                if status["state"] == "failed" {
                    return Err(CoreError::invalid(format!("{} 更新失败：{}", item["name"].as_str().unwrap_or(id), status["message"].as_str().unwrap_or("请在详情中重试"))));
                }
                if status["state"] != "updating" { break; }
                if self.host.now_ms() >= deadline {
                    return Err(CoreError::invalid("更新仍未完成，后续更新未开始，请在详情中查看进度"));
                }
                self.host.sleep(1000).await;
                let overview = self.get(station, "/overview").await?;
                self.sink.set(&Topic::Overview { station: station.to_string() }, Ok(overview.clone()));
                answer = overview["updates"].clone();
            }
        }
        Ok(answer)
    }
    pub(super) async fn json(&self, station: &StationAddr, method: &str, path: &str, body: Option<Value>) -> Result<Value> {
        let (headers, bytes) = match body {
            Some(body) => (vec![("content-type".into(), "application/json".into())], serde_json::to_vec(&body).unwrap_or_default()),
            None => (Vec::new(), Vec::new()),
        };
        self.call(station, method, path, headers, bytes).await
    }
    /// POST /uploads?name= with the raw bytes: the file waits on the station, in no chat, until a message sends it.
    /// Answers the attachment.
    pub async fn upload(&self, station: &StationAddr, name: &str, bytes: Vec<u8>) -> Result<Value> {
        let path = format!("/uploads?name={}", encode(name));
        self.call(station, "POST", &path, vec![("content-type".into(), "application/octet-stream".into())], bytes).await
    }
    /// GET /sessions/:key/files?name=(&thumb=1): (content type, bytes). `progress` hears the bytes so far and the
    /// whole size (when the station gives it) as they come: now and then, not for every chunk.
    pub async fn file(&self, station: &StationAddr, key: &str, name: &str, thumb: bool, progress: impl Fn(u64, Option<u64>)) -> Result<(String, Vec<u8>)> {
        // A station from before thumbnails answers the image itself.
        let path = format!("/sessions/{}/files?name={}{}", encode(key), encode(name), if thumb { "&thumb=1" } else { "" });
        let (mut span, waiting, reply) = self.send(station, "GET", &path, Vec::new(), Vec::new(), false);
        let result = async {
            let mut reply = reply.await?;
            answered(&mut span, &reply);
            if reply.status != 200 {
                let status = reply.status;
                return Err(CoreError::new(format!("http_{status}"), "读不到文件").with_status(status));
            }
            let kind = reply.header("content-type").unwrap_or("").to_string();
            let total = reply.header("content-length").and_then(|n| n.trim().parse::<u64>().ok());
            // Every hundredth of it, or every 256 KB when its size is not known.
            let step = total.map_or(256 * 1024, |t| (t / 100).max(64 * 1024));
            progress(0, total);
            let (mut bytes, mut told) = (Vec::with_capacity(total.unwrap_or(0).min(64 << 20) as usize), 0u64);
            while let Some(chunk) = reply.body.next().await {
                let chunk = chunk?;
                match &waiting {
                    Some(waiting) => waiting.received(chunk.len()),
                    None => self.of(&station.to_string()).status.received(None, chunk.len()),
                }
                bytes.extend(chunk);
                let loaded = bytes.len() as u64;
                if loaded - told >= step {
                    progress(loaded, total);
                    told = loaded;
                }
            }
            span.set("http.response.body.size", bytes.len());
            Ok((kind, bytes))
        }
        .await;
        if let Err(error) = &result {
            failed(&mut span, error);
        }
        span.end();
        result
    }
    /// A request to a web service on the station's machine (`localhost:port`), passed through as it is: for a page
    /// of that service shown here. Answers its status, headers and body whatever the status.
    pub async fn preview(&self, station: &StationAddr, port: u16, method: &str, path: &str, headers: Vec<(String, String)>, body: Vec<u8>) -> Result<(u16, Vec<(String, String)>, Vec<u8>)> {
        let path = format!("/preview/{port}{}", if path.starts_with('/') { path.to_string() } else { format!("/{path}") });
        self.exchange(station, method, &path, headers, body, false, |reply| reply.headers.clone()).await
    }
    /// A preview request whose answer is handed on as it comes (an event stream, a long poll, a page still loading):
    /// its status and headers once they are there, then its body. It is waited on (status.rs) only until then; its
    /// body is dropped to stop it, and the station then stops asking the service.
    pub async fn preview_stream(&self, station: &StationAddr, port: u16, method: &str, path: &str, headers: Vec<(String, String)>, body: Vec<u8>) -> Result<(u16, Vec<(String, String)>, LocalBoxStream<'static, Result<Vec<u8>>>)> {
        let path = format!("/preview/{port}{}", if path.starts_with('/') { path.to_string() } else { format!("/{path}") });
        let (mut span, waiting, reply) = self.send(station, method, &path, headers, body, false);
        span.set("stillfail.stream", true);
        let reply = match reply.await {
            Ok(reply) => reply,
            Err(error) => {
                failed(&mut span, &error);
                span.end();
                return Err(error);
            }
        };
        drop(waiting);
        answered(&mut span, &reply);
        span.end();
        let status = Rc::downgrade(&self.of(&station.to_string()).status);
        let body = reply.body.inspect(move |chunk| {
            if let (Ok(chunk), Some(status)) = (chunk, status.upgrade()) {
                status.received(None, chunk.len());
            }
        });
        Ok((reply.status, reply.headers, body.boxed_local()))
    }
    /// A preview page's WebSocket to `path` of the service at `port`: open once the station answers 101 (else the
    /// station's reason, as an error with its status).
    pub async fn preview_socket(&self, station: &StationAddr, port: u16, path: &str, headers: Vec<(String, String)>) -> Result<WireSocket> {
        let path = format!("/admin/api/preview/{port}{}", if path.starts_with('/') { path.to_string() } else { format!("/{path}") });
        let _waiting = self.of(&station.to_string()).status.begin(Place::Station(station.to_string()), "打开网页服务的 WebSocket", false);
        let mut span = self.tracer.span(format!("SOCKET {}", route(&path)), Kind::Client);
        span.set("url.path", route(&path));
        span.set("stillfail.stream", true);
        let mut headers = headers;
        headers.push(("traceparent".into(), span.context().traceparent()));
        let opening = self.tracer.instrument(Some(span.context()), self.wire.socket(station, RequestHead { method: "GET".into(), path, headers }));
        let opened = match futures::future::select(opening, self.host.sleep(SOCKET_OPEN_MS)).await {
            Either::Left((opened, _)) => opened,
            // Let go, its stream is reset.
            Either::Right(_) => Err(CoreError::new("timeout", "网页服务的 WebSocket 没有打开：station 没有回应")),
        };
        let socket = match opened {
            Ok(socket) => socket,
            Err(error) => {
                failed(&mut span, &error);
                span.end();
                return Err(error);
            }
        };
        answered(&mut span, &socket.reply);
        span.end();
        if socket.reply.status != 101 {
            let status = socket.reply.status;
            let bytes = socket.reply.bytes().await.unwrap_or_default();
            let data: Value = serde_json::from_slice(&bytes).unwrap_or_else(|_| json!({}));
            return Err(http_error(status, &data));
        }
        Ok(socket)
    }
    /// Starts a request: its span (under the current trace, or a trace of its own), whose `traceparent` the
    /// request carries, what it is waited on as (none for one in the background, `quiet`), and the reply's head.
    pub(super) fn send(&self, station: &StationAddr, method: &str, path: &str, mut headers: Vec<(String, String)>, body: Vec<u8>, quiet: bool) -> (Span, Option<Waiting>, LocalBoxFuture<'static, Result<WireReply>>) {
        let waiting = (!quiet).then(|| self.of(&station.to_string()).status.begin(Place::Station(station.to_string()), station_what(method, path), false));
        let path = format!("/admin/api{path}");
        let mut span = self.tracer.span(format!("{method} {}", route(&path)), Kind::Client);
        span.set("http.request.method", method.to_string());
        span.set("url.path", route(&path));
        span.set("stillfail.station", station.station.clone());
        if !body.is_empty() {
            span.set("http.request.body.size", body.len());
        }
        headers.push(("traceparent".into(), span.context().traceparent()));
        // A write carries a key of its own: a station that keeps writes to once (mesh/app/src/admin/once.rs) does it
        // once however often it arrives, so the wire may send it again on another way there (a link that went quiet).
        if !method.eq_ignore_ascii_case("GET") && !method.eq_ignore_ascii_case("HEAD") && !headers.iter().any(|(k, _)| k.eq_ignore_ascii_case(IDEMPOTENCY_KEY)) {
            let mut key = [0u8; 16];
            self.host.random_bytes(&mut key);
            headers.push((IDEMPOTENCY_KEY.into(), hex::encode(key)));
        }
        let head = RequestHead { method: method.to_string(), path, headers };
        // Under the request's span: opening the link it needs (a credential, a connection) shows as part of it.
        let reply = self.tracer.instrument(Some(span.context()), self.wire.request(station, head, body));
        (span, waiting, reply)
    }
    /// A reply's whole body, its bytes counted as they come (status.rs).
    pub(super) async fn read_body(&self, station: &StationAddr, reply: WireReply, waiting: Option<&Waiting>) -> Result<Vec<u8>> {
        let mut body = reply.body;
        let mut out = Vec::new();
        while let Some(chunk) = body.next().await {
            let chunk = chunk?;
            match waiting {
                Some(waiting) => waiting.received(chunk.len()),
                None => self.of(&station.to_string()).status.received(None, chunk.len()),
            }
            out.extend(chunk);
        }
        Ok(out)
    }
    /// One whole request: its status, what `head` takes from the reply's head, and the body.
    pub(super) async fn exchange<T>(&self, station: &StationAddr, method: &str, path: &str, headers: Vec<(String, String)>, body: Vec<u8>, quiet: bool, head: impl FnOnce(&WireReply) -> T) -> Result<(u16, T, Vec<u8>)> {
        let (mut span, waiting, reply) = self.send(station, method, path, headers, body, quiet);
        let result = async {
            let reply = reply.await?;
            answered(&mut span, &reply);
            let (status, taken) = (reply.status, head(&reply));
            let bytes = self.read_body(station, reply, waiting.as_ref()).await?;
            span.set("http.response.body.size", bytes.len());
            Ok((status, taken, bytes))
        }
        .await;
        if let Err(error) = &result {
            failed(&mut span, error);
        }
        span.end();
        result
    }
    pub(super) async fn call(&self, station: &StationAddr, method: &str, path: &str, headers: Vec<(String, String)>, body: Vec<u8>) -> Result<Value> {
        self.call_as(station, method, path, headers, body, false).await
    }
    /// A call, in the background (`quiet`): nobody waits on it, so it is not said to be waited on.
    pub(super) async fn call_as(&self, station: &StationAddr, method: &str, path: &str, headers: Vec<(String, String)>, body: Vec<u8>, quiet: bool) -> Result<Value> {
        let (status, (), bytes) = self.exchange(station, method, path, headers, body, quiet, |_| ()).await?;
        // Like the web's `response.json().catch(() => ({}))`.
        let data: Value = serde_json::from_slice(&bytes).unwrap_or_else(|_| json!({}));
        if !(200..300).contains(&status) {
            return Err(http_error(status, &data));
        }
        Ok(data)
    }
    /// Opens an event stream; a non-2xx answer is an error. Its span ends when the stream is open.
    pub(super) async fn open_stream(&self, station: &StationAddr, path: &str) -> Result<LocalBoxStream<'static, Result<Vec<u8>>>> {
        let (mut span, waiting, reply) = self.send(station, "GET", path, vec![("accept".into(), EVENT_STREAM.into())], Vec::new(), false);
        span.set("stillfail.stream", true);
        let reply = match reply.await {
            Ok(reply) => reply,
            Err(error) => {
                failed(&mut span, &error);
                return Err(error);
            }
        };
        // Open: what comes on it is no longer waited on, only counted.
        drop(waiting);
        answered(&mut span, &reply);
        span.end();
        if !(200..300).contains(&reply.status) {
            let status = reply.status;
            let bytes = reply.bytes().await.unwrap_or_default();
            let data: Value = serde_json::from_slice(&bytes).unwrap_or_else(|_| json!({}));
            return Err(http_error(status, &data));
        }
        let status = Rc::downgrade(&self.of(&station.to_string()).status);
        let body = reply.body.inspect(move |chunk| {
            if let (Ok(chunk), Some(status)) = (chunk, status.upgrade()) {
                status.received(None, chunk.len());
            }
        });
        Ok(idle_guarded(self.host.clone(), body.boxed_local()))
    }
}
