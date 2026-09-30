//! What the core is waiting on, for the one place a UI says so (the `status` topic): the requests under way to the
//! stations and to still.fail cloud, the connections being opened (the relay, a station's link), still.fail cloud's events
//! sockets that are down, and how fast bytes come in. Only what has taken a while ([`SLOW_MS`]) or is down is worth a
//! word: while all goes as it should the topic says nothing, so a UI shows nothing.
//!
//! Each workspace has its own waits (workspace.rs): its stations' requests, and the relay and links opened for them.
//! The device's are apart: still.fail cloud's requests, the accounts' sockets, the relay opened for no station. A
//! workspace's `status` is its own waits, its account's socket down and the device's relay; the plain `status` all of
//! them ([`value`]).
//!
//! Requests are registered where they leave (station.rs `send`, cloud.rs `request`, the mesh's connects) and let go
//! when their [`Waiting`] is dropped. While anything is waited on, the topic is computed again each second (the
//! seconds waited, the rate); what the rest of the time changes it (a slow wait ending, a socket going down or
//! coming back) invalidates it at once.

use std::cell::{Cell, RefCell};
use std::collections::{BTreeMap, VecDeque};
use std::rc::{Rc, Weak};

use futures::FutureExt;
use serde_json::{Value, json};

use crate::host::Host;

/// A wait shorter than this is how things go: said nothing of.
pub const SLOW_MS: f64 = 2_000.0;
/// The rate is of the bytes received in this long.
const RATE_WINDOW_MS: f64 = 3_000.0;
/// How often what is shown is computed again while anything is waited on.
const TICK_MS: u64 = 1_000;

/// Where a wait is: still.fail cloud, or a station by its address (`"<workspace>/<station>"`).
#[derive(Clone, Debug, PartialEq)]
pub enum Place {
    Cloud,
    Relay,
    Station(String),
}

/// Station names by address, for what is said (the workspace as last read); `None` says "station".
pub type NameOf = Rc<dyn Fn(&str) -> Option<String>>;

/// The waits of a workspace, by its id (the station wire registers a link's waits with its workspace's).
pub type StatusOf = Rc<dyn Fn(&str) -> Rc<Status>>;

/// Every workspace's waits in one (tests, and a wire for one workspace).
pub fn one(status: Rc<Status>) -> StatusOf {
    Rc::new(move |_: &str| status.clone())
}

/// What of a set of waits a status value takes: all of it, or, of the device's in a workspace's, the sockets of the
/// accounts given (the one that reaches it) and the relay opened for no station.
#[derive(Clone, Copy)]
pub enum Take<'a> {
    All,
    For(&'a [String]),
}

pub struct Status {
    host: Rc<dyn Host>,
    me: Weak<Status>,
    inner: RefCell<Inner>,
    changed: RefCell<Option<Rc<dyn Fn()>>>,
    name_of: RefCell<Option<NameOf>>,
    /// Added to the host's clock: tests move time on.
    skew: Cell<f64>,
}

#[derive(Default)]
struct Inner {
    next: u64,
    waits: BTreeMap<u64, Wait>,
    /// When bytes came and how many, the last RATE_WINDOW_MS of them.
    received: VecDeque<(f64, u64)>,
    /// still.fail cloud's events socket per account, while it is down: since when, when it is tried again, why, how many
    /// tries in a row failed.
    sockets: BTreeMap<String, Down>,
    ticking: bool,
}

struct Wait {
    place: Place,
    /// What it does, in words ("读取对话").
    what: String,
    /// A connection being opened, not a request: it goes before the requests waiting on it.
    connecting: bool,
    since: f64,
    bytes: u64,
}

struct Down {
    /// Down since (the first of the tries in a row that failed).
    since: f64,
    retry_at: f64,
    message: String,
    tries: u32,
}

/// A wait under way; dropping it ends it.
pub struct Waiting {
    status: Weak<Status>,
    id: u64,
}

impl Waiting {
    /// `n` bytes of its answer came.
    pub fn received(&self, n: usize) {
        if let Some(status) = self.status.upgrade() {
            status.received(Some(self.id), n);
        }
    }
}

impl Drop for Waiting {
    fn drop(&mut self) {
        if let Some(status) = self.status.upgrade() {
            status.end(self.id);
        }
    }
}

impl Status {
    pub fn new(host: Rc<dyn Host>) -> Rc<Status> {
        Rc::new_cyclic(|me| Status { host, me: me.clone(), inner: RefCell::default(), changed: RefCell::default(), name_of: RefCell::default(), skew: Cell::new(0.0) })
    }

    /// What is called when what is shown changed (the store invalidates the topic).
    pub fn on_change(&self, changed: Rc<dyn Fn()>) {
        *self.changed.borrow_mut() = Some(changed);
    }

    pub fn set_names(&self, name_of: NameOf) {
        *self.name_of.borrow_mut() = Some(name_of);
    }

    /// Moves this clock on (tests).
    #[cfg(test)]
    pub(crate) fn skip(&self, ms: f64) {
        self.skew.set(self.skew.get() + ms);
    }

    fn now(&self) -> f64 {
        self.host.now_ms() + self.skew.get()
    }

    pub fn changed(&self) {
        let changed = self.changed.borrow().clone();
        if let Some(changed) = changed {
            changed();
        }
    }

    /// A request (or, `connecting`, a connection being opened) starts.
    pub fn begin(&self, place: Place, what: impl Into<String>, connecting: bool) -> Waiting {
        let id = {
            let mut inner = self.inner.borrow_mut();
            inner.next += 1;
            let id = inner.next;
            inner.waits.insert(id, Wait { place, what: what.into(), connecting, since: self.now(), bytes: 0 });
            id
        };
        self.tick();
        Waiting { status: self.me.clone(), id }
    }

    /// Bytes came: of a wait still under way (its answer), or of a stream already open (`None`).
    pub fn received(&self, id: Option<u64>, n: usize) {
        let now = self.now();
        let mut inner = self.inner.borrow_mut();
        if let Some(wait) = id.and_then(|id| inner.waits.get_mut(&id)) {
            wait.bytes += n as u64;
        }
        inner.received.push_back((now, n as u64));
        while inner.received.front().is_some_and(|(t, _)| now - t > RATE_WINDOW_MS) {
            inner.received.pop_front();
        }
    }

    fn end(&self, id: u64) {
        let slow = {
            let mut inner = self.inner.borrow_mut();
            inner.waits.remove(&id).is_some_and(|w| self.now() - w.since >= SLOW_MS)
        };
        // One that was shown goes at once; one that never was changes nothing.
        if slow {
            self.changed();
        }
    }

    /// An account's events socket failed to open or dropped; it is tried again at `retry_at`.
    pub fn socket_down(&self, account: &str, message: &str, retry_at: f64) {
        {
            let mut inner = self.inner.borrow_mut();
            let (since, tries) = inner.sockets.get(account).map_or((self.now(), 0), |d| (d.since, d.tries));
            inner.sockets.insert(account.to_string(), Down { since, retry_at, message: message.to_string(), tries: tries + 1 });
        }
        self.changed();
        self.tick();
    }

    /// An account's events socket is open, or no longer wanted.
    pub fn socket_up(&self, account: &str) {
        if self.inner.borrow_mut().sockets.remove(account).is_some() {
            self.changed();
        }
    }

    /// Computes again each second while anything is waited on or down.
    fn tick(&self) {
        {
            let mut inner = self.inner.borrow_mut();
            if inner.ticking || (inner.waits.is_empty() && inner.sockets.is_empty()) {
                return;
            }
            inner.ticking = true;
        }
        let (me, host) = (self.me.clone(), self.host.clone());
        self.host.spawn(
            async move {
                loop {
                    host.sleep(TICK_MS).await;
                    let Some(status) = me.upgrade() else { return };
                    let (busy, shown) = {
                        let inner = status.inner.borrow();
                        let now = status.now();
                        (!inner.waits.is_empty() || !inner.sockets.is_empty(), !inner.sockets.is_empty() || inner.waits.values().any(|w| now - w.since >= SLOW_MS))
                    };
                    if shown {
                        status.changed();
                    }
                    if !busy {
                        status.inner.borrow_mut().ticking = false;
                        return;
                    }
                }
            }
            .boxed_local(),
        );
    }

    /// Where a wait is, in words; `None` for a station with no name (the page's own).
    fn place_name(&self, place: &Place) -> Option<String> {
        match place {
            Place::Cloud => Some("still.fail cloud".into()),
            Place::Relay => Some("relay".into()),
            Place::Station(address) => {
                let name_of = self.name_of.borrow().clone();
                name_of.and_then(|n| n(address)).filter(|n| !n.is_empty())
            }
        }
    }

    /// The `status` topic's value of these waits alone (StatusView; see [`value`]).
    pub fn value(&self) -> Value {
        value(&[(self, Take::All)])
    }

    /// What of these waits is worth a word now, as `take` says, onto `into`.
    fn gather(&self, take: Take, into: &mut Gathered) {
        let now = self.now();
        let inner = self.inner.borrow();
        let wanted = |sub: &String| match take {
            Take::All => true,
            Take::For(accounts) => accounts.contains(sub),
        };
        // still.fail cloud's socket, once down for a while (a socket dropped and open again at once is how things go).
        for (_, d) in inner.sockets.iter().filter(|(sub, d)| wanted(sub) && now - d.since >= SLOW_MS) {
            into.downs.push(Shown { retry_in: d.retry_at - now, message: d.message.clone(), tries: d.tries });
        }
        for w in inner.waits.values().filter(|w| now - w.since >= SLOW_MS) {
            if let (Take::For(_), false) = (take, w.place == Place::Relay) {
                continue;
            }
            into.slow.push(Slow { place: self.place_name(&w.place), what: w.what.clone(), connecting: w.connecting, age: now - w.since, bytes: w.bytes });
        }
        if let Some((t, _)) = inner.received.front() {
            into.window = into.window.max((now - t).clamp(1_000.0, RATE_WINDOW_MS));
        }
        into.recent += inner.received.iter().filter(|(t, _)| now - t <= RATE_WINDOW_MS).map(|(_, n)| n).sum::<u64>();
    }
}

/// A socket down, as a status says it.
struct Shown {
    retry_in: f64,
    message: String,
    tries: u32,
}

/// A slow wait, as a status says it.
struct Slow {
    place: Option<String>,
    what: String,
    connecting: bool,
    age: f64,
    bytes: u64,
}

#[derive(Default)]
struct Gathered {
    downs: Vec<Shown>,
    slow: Vec<Slow>,
    /// The bytes of the last RATE_WINDOW_MS, and how long that window has been (the oldest of them).
    recent: u64,
    window: f64,
}

/// The `status` topic's value (StatusView) of these sets of waits: `state` null while all goes as it should, else
/// `slow` (something waited on for a while) or `trouble` (a connection down); `text` the one line that says it,
/// `items` each thing.
pub fn value(parts: &[(&Status, Take)]) -> Value {
    let mut all = Gathered::default();
    for (status, take) in parts {
        status.gather(*take, &mut all);
    }
    let mut items: Vec<Value> = Vec::new();
    // still.fail cloud's socket: one line whatever the number of accounts, by the one tried again first.
    let down = all.downs.iter().min_by(|a, b| a.retry_in.total_cmp(&b.retry_in));
    if let Some(d) = down {
        let wait = (d.retry_in / 1000.0).ceil().max(0.0) as u64;
        let when = if wait > 0 { format!("{wait} 秒后重试") } else { "正在重试".to_string() };
        let tries = if d.tries > 1 { format!("（第 {} 次）", d.tries) } else { String::new() };
        let why = if d.message.is_empty() { String::new() } else { format!("：{}", d.message) };
        items.push(json!({ "state": "trouble", "text": format!("连不上 still.fail cloud，{when}{tries}"), "detail": format!("实时更新暂停{why}") }));
    }
    // What has been waited on for a while: the connections first (the requests wait on them), the oldest first.
    let mut slow: Vec<&Slow> = all.slow.iter().collect();
    slow.sort_by(|a, b| b.connecting.cmp(&a.connecting).then(b.age.total_cmp(&a.age)));
    for w in &slow {
        let secs = (w.age / 1000.0).floor() as u64;
        let text = match (w.connecting, &w.place) {
            (true, place) => format!("正在连接 {}", place.as_deref().unwrap_or("station")),
            (false, Some(place)) => format!("{place} {}", w.what),
            (false, None) => w.what.clone(),
        };
        let detail = if w.connecting {
            format!("已等 {secs} 秒")
        } else if w.bytes == 0 {
            format!("已等 {secs} 秒，还没收到数据")
        } else {
            format!("已收 {}，{secs} 秒", size(w.bytes))
        };
        items.push(json!({ "state": "slow", "text": text, "detail": detail }));
    }
    if items.is_empty() {
        return json!({ "state": null, "text": null, "items": [] });
    }
    let window = if all.window > 0.0 { all.window } else { RATE_WINDOW_MS };
    let rate = (all.recent as f64 / (window / 1000.0)) as u64;
    // The line: the first thing, how long (or how much), the others counted, and the rate while bytes come.
    let first = &items[0];
    let state = if down.is_some() { "trouble" } else { "slow" };
    let mut text = first["text"].as_str().unwrap_or("").to_string();
    if let Some(w) = slow.first().filter(|_| down.is_none()) {
        let secs = (w.age / 1000.0).floor() as u64;
        text.push_str(&format!(" · {secs} 秒"));
    }
    if items.len() > 1 {
        text.push_str(&format!(" · 共 {} 项", items.len()));
    }
    // How much of each came is on hover: the line stays short enough for a sidebar.
    if !slow.is_empty() && rate > 0 {
        text.push_str(&format!(" · {}/s", size(rate)));
    }
    json!({ "state": state, "text": text, "items": items })
}

/// Bytes in words: "820 B", "12 KB", "1.4 MB".
pub fn size(bytes: u64) -> String {
    let b = bytes as f64;
    if b < 1024.0 {
        format!("{bytes} B")
    } else if b < 1024.0 * 1024.0 {
        format!("{} KB", (b / 1024.0).round())
    } else {
        format!("{:.1} MB", b / 1024.0 / 1024.0)
    }
}

/// What a station request does, in words, by its method and path (without `/admin/api`).
pub fn station_what(method: &str, path: &str) -> &'static str {
    let path = path.split('?').next().unwrap_or("");
    let parts: Vec<&str> = path.split('/').filter(|p| !p.is_empty()).collect();
    let get = method.eq_ignore_ascii_case("GET");
    match (get, parts.as_slice()) {
        (true, ["events"]) => "打开实时更新",
        (true, ["threads", _, "entries"]) => "读取对话",
        (true, ["threads", ..]) => "读取对话列表",
        (true, ["chats"]) => "读取会话列表",
        (true, ["sessions", _, "files"]) => "读取文件",
        (true, ["sessions", _, ..]) => "读取 agent",
        (true, ["sessions"]) => "读取 agent 列表",
        (true, ["overview"]) => "读取 station 概况",
        (_, ["preview", ..]) => "读取网页服务",
        (false, ["uploads"]) => "上传文件",
        (true, _) => "读取数据",
        (false, _) => "提交修改",
    }
}

/// What an still.fail cloud request does, in words.
pub fn cloud_what(method: &str, path: &str) -> &'static str {
    let path = path.split('?').next().unwrap_or("");
    let get = method.eq_ignore_ascii_case("GET");
    if path.ends_with("/credential") {
        "获取 station 授权"
    } else if !get {
        "提交修改"
    } else if path == "/v1/me" {
        "读取账号"
    } else if path.starts_with("/v1/workspaces/") {
        "读取 workspace"
    } else {
        "读取数据"
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::{FakeHost, run};

    #[test]
    fn says_nothing_until_a_wait_is_slow_then_what_and_how_fast() {
        run(async {
        let host = FakeHost::new();
        let status = Status::new(host.clone());
        status.set_names(Rc::new(|a: &str| (a == "ws/s1").then(|| "studio".to_string())));
        let wait = status.begin(Place::Station("ws/s1".into()), station_what("GET", "/threads/3/entries?limit=50"), false);
        assert_eq!(status.value()["state"], Value::Null);
        status.skew.set(status.skew.get() + 3_000.0);
        assert_eq!(status.value()["text"], "studio 读取对话 · 3 秒");
        assert_eq!(status.value()["items"][0]["detail"], "已等 3 秒，还没收到数据");
        wait.received(300 * 1024);
        let v = status.value();
        assert_eq!(v["items"][0]["detail"], "已收 300 KB，3 秒");
        assert_eq!(v["text"], "studio 读取对话 · 3 秒 · 300 KB/s");
        drop(wait);
        assert_eq!(status.value()["state"], Value::Null);
        });
    }

    #[test]
    fn a_connection_goes_first_and_a_socket_down_is_trouble() {
        run(async {
        let host = FakeHost::new();
        let status = Status::new(host.clone());
        let _request = status.begin(Place::Station("ws/s1".into()), "读取对话", false);
        let _link = status.begin(Place::Relay, "连接", true);
        status.skew.set(status.skew.get() + 2_500.0);
        let v = status.value();
        assert_eq!(v["state"], "slow");
        assert_eq!(v["text"], "正在连接 relay · 2 秒 · 共 2 项");
        assert_eq!(v["items"][1]["text"], "读取对话");
        let now = status.now();
        status.socket_down("a", "网络错误", now + 4_000.0);
        assert_eq!(status.value()["state"], "slow", "not yet: it may be back at once");
        status.skew.set(status.skew.get() + 2_000.0);
        let v = status.value();
        assert_eq!(v["state"], "trouble");
        assert_eq!(v["text"], "连不上 still.fail cloud，2 秒后重试 · 共 3 项");
        status.socket_down("a", "网络错误", now + 8_000.0);
        assert_eq!(status.value()["items"][0]["text"], "连不上 still.fail cloud，6 秒后重试（第 2 次）");
        status.socket_up("a");
        assert_eq!(status.value()["state"], "slow");
        });
    }

    #[test]
    fn a_workspaces_status_is_its_own_waits_its_accounts_socket_and_the_relay() {
        run(async {
        let host = FakeHost::new();
        let (w1, w2, device) = (Status::new(host.clone()), Status::new(host.clone()), Status::new(host.clone()));
        let _read = w1.begin(Place::Station("w1/s".into()), "读取对话", false);
        let _cloud = device.begin(Place::Cloud, "读取 workspace", false);
        let _relay = device.begin(Place::Relay, "连接", true);
        let now = device.now();
        device.socket_down("a1", "网络错误", now + 9_000.0);
        device.socket_down("a2", "网络错误", now + 4_000.0);
        for s in [&w1, &w2, &device] {
            s.skip(2_500.0);
        }
        let texts = |v: &Value| v["items"].as_array().unwrap().iter().map(|i| i["text"].as_str().unwrap().to_string()).collect::<Vec<_>>();
        let (a1, a2) = (["a1".to_string()], ["a2".to_string()]);
        // W1's slow read is not W2's; the relay opened for no station and W2's account's socket are.
        let of_w2 = value(&[(&*w2, Take::All), (&*device, Take::For(&a2))]);
        assert_eq!(texts(&of_w2), ["连不上 still.fail cloud，2 秒后重试", "正在连接 relay"]);
        let of_w1 = value(&[(&*w1, Take::All), (&*device, Take::For(&a1))]);
        assert_eq!(texts(&of_w1), ["连不上 still.fail cloud，7 秒后重试", "正在连接 relay", "读取对话"]);
        // No account known to reach it yet: no socket.
        assert_eq!(texts(&value(&[(&*w2, Take::All), (&*device, Take::For(&[]))])), ["正在连接 relay"]);
        // The plain status: all of it.
        let all = value(&[(&*w1, Take::All), (&*w2, Take::All), (&*device, Take::All)]);
        assert_eq!(texts(&all), ["连不上 still.fail cloud，2 秒后重试", "正在连接 relay", "读取对话", "still.fail cloud 读取 workspace"]);
        });
    }
}
