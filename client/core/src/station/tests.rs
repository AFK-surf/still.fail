use super::*;
use crate::testing::{FakeHost, run};
use futures::channel::mpsc;
use std::time::Duration;

// ── fakes ──

fn wants_stream(head: &RequestHead) -> bool {
    head.headers.iter().any(|(k, v)| k.eq_ignore_ascii_case("accept") && v.contains(EVENT_STREAM))
}

#[derive(Default)]
struct FakeSink {
    values: RefCell<HashMap<Topic, Result<Value>>>,
}

impl TopicSink for FakeSink {
    fn set(&self, topic: &Topic, value: Result<Value>) {
        self.values.borrow_mut().insert(topic.clone(), value);
    }
    fn update(&self, topic: &Topic, change: &mut dyn FnMut(&mut Value)) {
        if let Some(Ok(value)) = self.values.borrow_mut().get_mut(topic) {
            change(value);
        }
    }
    fn get(&self, topic: &Topic) -> Option<Value> {
        self.values.borrow().get(topic).and_then(|v| v.as_ref().ok().cloned())
    }
}

type Chunk = Result<Vec<u8>>;

#[derive(Default)]
struct FakeWire {
    /// (station, method, path, body) of every request.
    calls: RefCell<Vec<(StationAddr, String, String, Vec<u8>)>>,
    /// "METHOD path" → (status, JSON). Missing: 200 {}.
    answers: RefCell<HashMap<String, (u16, Value)>>,
    /// Open streams by path, newest last.
    streams: RefCell<Vec<(String, mpsc::UnboundedSender<Chunk>)>>,
    /// Status for stream requests (200 opens one); None: the wire fails.
    stream_status: RefCell<Option<u16>>,
    /// Stream requests are never answered.
    stream_hangs: std::cell::Cell<bool>,
    /// The `traceparent` of every request, in order.
    traceparents: RefCell<Vec<String>>,
}

impl FakeWire {
    fn new() -> Rc<FakeWire> {
        let wire = FakeWire::default();
        *wire.stream_status.borrow_mut() = Some(200);
        Rc::new(wire)
    }
    fn answer(&self, what: &str, status: u16, value: Value) {
        self.answers.borrow_mut().insert(what.into(), (status, value));
    }
    fn count(&self, method: &str, path: &str) -> usize {
        self.calls.borrow().iter().filter(|(_, m, p, _)| m == method && p == path).count()
    }
    fn paths(&self) -> Vec<String> {
        self.calls.borrow().iter().map(|(_, m, p, _)| format!("{m} {p}")).collect()
    }
    /// Sends SSE text on the newest open stream whose path starts with `prefix`.
    fn push(&self, prefix: &str, text: &str) {
        let streams = self.streams.borrow();
        let (_, tx) = streams.iter().rev().find(|(p, tx)| p.starts_with(prefix) && !tx.is_closed()).expect("stream open");
        tx.unbounded_send(Ok(text.as_bytes().to_vec())).unwrap();
    }
    fn event(&self, name: &str, data: Value) {
        self.push("/admin/api/events", &format!("event: {name}\ndata: {data}\n\n"));
    }
    fn end(&self, prefix: &str) {
        let mut streams = self.streams.borrow_mut();
        streams.retain(|(p, _)| !p.starts_with(prefix));
    }
    /// Paths of the streams still open (the core has not let go of them).
    fn open(&self) -> Vec<String> {
        self.streams.borrow().iter().filter(|(_, tx)| !tx.is_closed()).map(|(p, _)| p.clone()).collect()
    }
}

impl StationWire for FakeWire {
    fn request(&self, station: &StationAddr, head: RequestHead, body: Vec<u8>) -> LocalBoxFuture<'static, Result<WireReply>> {
        self.calls.borrow_mut().push((station.clone(), head.method.clone(), head.path.clone(), body));
        let traceparent = head.headers.iter().find(|(k, _)| k == "traceparent").map(|(_, v)| v.clone()).unwrap_or_default();
        self.traceparents.borrow_mut().push(traceparent);
        if wants_stream(&head) && self.stream_hangs.get() {
            return futures::future::pending().boxed_local();
        }
        let reply = if wants_stream(&head) {
            match *self.stream_status.borrow() {
                Some(200) => {
                    let (tx, rx) = mpsc::unbounded();
                    self.streams.borrow_mut().push((head.path.clone(), tx));
                    Ok(WireReply { status: 200, headers: vec![], body: rx.boxed_local(), via: None })
                }
                Some(status) => Ok(WireReply { status, headers: vec![], body: futures::stream::iter([Ok(r#"{"error":"没有权限"}"#.as_bytes().to_vec())]).boxed_local(), via: None }),
                None => Err(CoreError::new("offline", "连不上")),
            }
        } else {
            let (status, value) = self.answers.borrow().get(&format!("{} {}", head.method, head.path)).cloned().unwrap_or((200, json!({})));
            Ok(WireReply { status, headers: vec![("content-type".into(), "application/json".into())], body: futures::stream::iter([Ok(serde_json::to_vec(&value).unwrap())]).boxed_local(), via: None })
        };
        async move { reply }.boxed_local()
    }
    /// A socket nothing answers (an older station waiting for a request's body).
    fn socket(&self, _station: &StationAddr, _head: RequestHead) -> LocalBoxFuture<'static, Result<WireSocket>> {
        futures::future::pending().boxed_local()
    }
}

fn setup() -> (Rc<FakeHost>, Rc<FakeSink>, Rc<FakeWire>, Rc<Stations>) {
    let host = FakeHost::new();
    let sink = Rc::new(FakeSink::default());
    let wire = FakeWire::new();
    let stations = Stations::new(host.clone(), sink.clone(), wire.clone(), Tracer::new(host.clone(), 1.0), Kept::new(host.clone()), Workspaces::new(host.clone()));
    (host, sink, wire, stations)
}

async fn wait(ms: u64) {
    tokio::time::sleep(Duration::from_millis(ms)).await;
}

const ST: &str = "ws/st";
fn session(key: &str) -> Topic {
    Topic::Session { station: ST.into(), key: key.into() }
}
fn live(key: &str) -> Topic {
    Topic::Live { station: ST.into(), key: key.into() }
}
fn sessions() -> Topic {
    Topic::Sessions { station: ST.into() }
}
fn threads() -> Topic {
    Topic::Threads { station: ST.into() }
}
fn thread(id: u64) -> Topic {
    Topic::Thread { station: ST.into(), thread: id }
}
fn overview() -> Topic {
    Topic::Overview { station: ST.into() }
}
fn host_topic() -> Topic {
    Topic::Host { station: ST.into() }
}
fn link() -> Topic {
    Topic::Link { station: ST.into() }
}
fn remote() -> StationAddr {
    StationAddr::parse(ST).unwrap()
}
fn live_of(sink: &FakeSink, key: &str) -> Value {
    sink.get(&live(key)).unwrap()
}
/// A live message for session `key`, as the events stream carries it.
fn with_key(key: &str, mut value: Value) -> Value {
    value["key"] = json!(key);
    value
}

fn summary(key: &str, turns: u64) -> Value {
    json!({"key": key, "title": null, "archivedAt": null, "turns": turns, "lastTurn": null})
}
fn entry(n: u64, text: &str) -> Value {
    json!({"thread": 7, "n": n, "kind": "message", "target": null, "ts": format!("{n}.0"), "authorKind": "person", "author": "a@x.com", "text": text, "at": n})
}
fn edit(n: u64, target: u64, text: &str) -> Value {
    json!({"thread": 7, "n": n, "kind": "edit", "target": target, "ts": null, "authorKind": "person", "author": "a@x.com", "text": text, "at": n})
}
fn entries(from: u64, to: u64) -> Value {
    json!((from..=to).map(|n| entry(n, &format!("m{n}"))).collect::<Vec<_>>())
}
fn thread_view(id: u64, members: &[&str], last: u64, read: u64, unread: u64) -> Value {
    json!({"id": id, "surface": "ember", "createdAt": id, "sessions": members.iter().map(|s| json!({"thread": id, "session": s})).collect::<Vec<_>>(),
        "last": last, "lastMessage": if last > 0 { json!({"seq": last, "text": "…", "createdAt": last}) } else { Value::Null }, "read": read, "unread": unread})
}
/// The thread topic's messages, merged.
fn texts(sink: &FakeSink, id: u64) -> Vec<String> {
    let page = sink.get(&thread(id)).unwrap();
    crate::entries::merge(page["entries"].as_array().unwrap()).iter().map(|m| m["text"].as_str().unwrap().to_string()).collect()
}
fn numbers(sink: &FakeSink, id: u64) -> Vec<u64> {
    sink.get(&thread(id)).unwrap()["entries"].as_array().unwrap().iter().filter_map(n_of).collect()
}

// ── tests ──

#[test]
fn parses_addresses() {
    assert_eq!(StationAddr::parse("ws/st").unwrap(), StationAddr { workspace: "ws".into(), station: "st".into() });
    assert_eq!(StationAddr::parse("ws/st").unwrap().to_string(), "ws/st");
    for bad in ["", "ws", "/st", "ws/", "a/b/c", "Local"] {
        assert_eq!(StationAddr::parse(bad).unwrap_err().code, "invalid_params", "{bad}");
    }
    // A station's own page, still in kept links and prefs: gone, said so.
    assert_eq!(StationAddr::parse("local").unwrap_err().code, "gone");
}

#[test]
fn parses_sse_across_chunks() {
    let mut p = SseParser::default();
    assert!(p.feed(b"retry: 2000\n\n: ping\n\nevent: sess").is_empty());
    assert_eq!(p.feed(b"ion\r\ndata: {\"key\":\"a\"}\r\n\r\ndata: x\ndata:y\n\nevent: e\n"), vec![
        ("session".to_string(), "{\"key\":\"a\"}".to_string()),
        ("message".to_string(), "x\ny".to_string()),
    ]);
    let text = "data: 你好\n\n".as_bytes();
    assert!(p.feed(&text[..7]).is_empty());
    assert_eq!(p.feed(&text[7..]), vec![("e".to_string(), "你好".to_string())]);
}

#[test]
fn encodes_like_the_web() {
    assert_eq!(encode("a b/ç!"), "a%20b%2F%C3%A7!");
}

#[test]
fn maps_request_errors() {
    run(async {
        let (_host, _sink, wire, stations) = setup();
        wire.answer("GET /admin/api/overview", 200, json!({"connects": []}));
        wire.answer("POST /admin/api/sessions/k/stop", 403, json!({"error": "没有权限"}));
        wire.answer("GET /admin/api/host", 500, json!("oops"));
        assert_eq!(stations.get(&remote(), "/overview").await.unwrap(), json!({"connects": []}));
        let e = stations.perform(&remote(), &crate::ops::request("session.stop", &json!({"station": ST, "key":"k"})).unwrap().unwrap()).await.unwrap_err();
        assert_eq!((e.code.as_str(), e.message.as_str(), e.status), ("http_403", "没有权限", Some(403)));
        let e = stations.get(&remote(), "/host").await.unwrap_err();
        assert_eq!((e.code.as_str(), e.message.as_str(), e.status), ("http_500", "请求失败（500）", Some(500)));
        // A bodyless named operation stays bodyless.
        assert!(wire.calls.borrow()[1].3.is_empty());
    });
}

#[test]
fn uploads_and_reads_files() {
    run(async {
        let (_host, _sink, wire, stations) = setup();
        wire.answer("POST /admin/api/uploads?name=a%20b.png", 200, json!({"name": "a b.png"}));
        let saved = stations.upload(&remote(), "a b.png", vec![1, 2, 3]).await.unwrap();
        assert_eq!(saved["name"], "a b.png");
        assert_eq!(wire.calls.borrow()[0].3, vec![1, 2, 3]);
        wire.answer("GET /admin/api/sessions/k/files?name=x", 404, json!({"error": "没有这个文件"}));
        let e = stations.file(&remote(), "k", "x", false, |_, _| {}).await.unwrap_err();
        assert_eq!((e.message.as_str(), e.status), ("读不到文件", Some(404)));
    });
}

#[test]
fn tells_how_far_a_file_has_come() {
    run(async {
        let (_host, _sink, wire, stations) = setup();
        let big = "x".repeat(300 * 1024);
        wire.answer("GET /admin/api/sessions/k/files?name=big", 200, json!(big));
        let heard = RefCell::new(Vec::new());
        let (_, bytes) = stations.file(&remote(), "k", "big", false, |loaded, total| heard.borrow_mut().push((loaded, total))).await.unwrap();
        // At the start, then once past 256 KB (the size not given, it comes in one chunk here).
        assert_eq!(heard.into_inner(), vec![(0, None), (bytes.len() as u64, None)]);
    });
}

#[test]
fn a_station_not_reached_is_down_and_asked_for_nothing_until_it_is() {
    run(async {
        let (host, sink, wire, stations) = setup();
        wire.answer("GET /admin/api/overview", 200, json!({"connects": [], "profiles": []}));
        // Never reached: down (whatever else says otherwise), and kept so for the next start.
        *wire.stream_status.borrow_mut() = None;
        stations.start(&link());
        host.settle().await;
        assert_eq!(sink.get(&link()).unwrap()["state"], "offline");
        assert_eq!(host.stored(&format!("{LINK_KEY}/{ST}")).as_deref(), Some(&b"offline"[..]));
        stations.start(&overview());
        host.settle().await;
        assert_eq!(wire.count("GET", "/admin/api/overview"), 0, "down: nothing asked");
        // Reached: what it wants is read.
        *wire.stream_status.borrow_mut() = Some(200);
        wait(RECONNECT_MS * 2 + 50).await;
        assert_eq!(sink.get(&link()).unwrap()["state"], "online");
        assert_eq!(wire.count("GET", "/admin/api/overview"), 1, "back: what it wants is read");
        assert_eq!(host.stored(&format!("{LINK_KEY}/{ST}")).as_deref(), Some(&b"online"[..]));
    });
}

#[test]
fn a_station_down_shows_it_is_tried_again_as_soon_as_a_person_asks() {
    run(async {
        let fake = FakeHost::new();
        let wakes = Rc::new(crate::wake::Wakes::default());
        let host: Rc<dyn Host> = crate::wake::WakingHost::new(fake.clone(), wakes.clone());
        let sink = Rc::new(FakeSink::default());
        let wire = FakeWire::new();
        let stations = Stations::new(host.clone(), sink.clone(), wire.clone(), Tracer::new(host.clone(), 1.0), Kept::new(host.clone()), Workspaces::new(host.clone()));
        *wire.stream_status.borrow_mut() = None;
        stations.start(&link());
        fake.settle().await;
        assert_eq!(sink.get(&link()).unwrap()["state"], "offline");
        // 重试 (client.wake, network), and the try it starts takes a while: not "down" meanwhile.
        wire.stream_hangs.set(true);
        wakes.wake(crate::wake::Wake { at: host.now_ms(), away: 0.0, network: true, retry: false });
        fake.settle().await;
        assert_eq!(sink.get(&link()).unwrap()["state"], "reconnecting");
    });
}

#[test]
fn writes_bring_what_they_touch_up_to_date() {
    run(async {
        let (host, sink, wire, stations) = setup();
        wire.answer("GET /admin/api/sessions/k%201", 200, json!({"session": summary("k 1", 0), "threads": [], "turns": []}));
        wire.answer("GET /admin/api/threads", 200, json!([]));
        for t in [session("k 1"), session("other"), sessions(), overview(), threads()] {
            stations.start(&t);
        }
        host.settle().await;
        assert!(sink.get(&session("k 1")).is_some());
        let before = |p: &str| wire.count("GET", p);
        let (s, k, o, other) = (before("/admin/api/sessions"), before("/admin/api/sessions/k%201"), before("/admin/api/overview"), before("/admin/api/sessions/other"));
        stations.perform(&remote(), &crate::ops::request("session.stop", &json!({"station": ST, "key":"k 1"})).unwrap().unwrap()).await.unwrap();
        assert_eq!(wire.count("GET", "/admin/api/sessions"), s + 1);
        assert_eq!(wire.count("GET", "/admin/api/sessions/k%201"), k + 1);
        assert_eq!(wire.count("GET", "/admin/api/sessions/other"), other);
        assert_eq!(wire.count("GET", "/admin/api/overview"), o);
        // A profile edit answers the overview: that is the topic's value, nothing is read again.
        let edited = json!({"viewer": {}, "connects": [], "profiles": [{"id": "p"}]});
        wire.answer("PUT /admin/api/profiles/p", 200, edited.clone());
        stations.perform(&remote(), &crate::ops::request("profile.put", &json!({"station": ST, "id":"p", "input":{}})).unwrap().unwrap()).await.unwrap();
        assert_eq!(sink.get(&overview()), Some(edited));
        assert_eq!(wire.count("GET", "/admin/api/overview"), o);
        stations.perform(&remote(), &crate::ops::request("profile.check", &json!({"station": ST, "id":"p"})).unwrap().unwrap()).await.unwrap();
        assert_eq!(wire.count("GET", "/admin/api/overview"), o + 1);
        // Put on another update channel: its versions (the overview's) read again.
        wire.answer("POST /admin/api/updates/channel", 200, json!([]));
        stations.perform(&remote(), &crate::ops::request("software.channel", &json!({"station": ST, "channel":"beta"})).unwrap().unwrap()).await.unwrap();
        assert_eq!(wire.count("GET", "/admin/api/overview"), o + 2);
        // Another chat on a session answers its thread, which goes into the lists without a request.
        let reads = wire.calls.borrow().len();
        wire.answer("POST /admin/api/threads", 200, thread_view(9, &["k 1"], 0, 0, 0));
        stations.perform(&remote(), &crate::ops::request("chat.forSession", &json!({"station": ST, "session":"k 1"})).unwrap().unwrap()).await.unwrap();
        assert_eq!(sink.get(&session("k 1")).unwrap()["threads"][0]["id"], 9);
        assert_eq!(sink.get(&threads()).unwrap()[0]["id"], 9);
        assert_eq!(wire.calls.borrow().len(), reads + 1);
        // A read changes nothing.
        stations.get(&remote(), "/slack/config-token").await.unwrap();
        assert_eq!(wire.count("GET", "/admin/api/overview"), o + 2);
        // The workspace's app configuration token: every connect's app shown is read again, as it now reads.
        let app = Topic::SlackApp { station: ST.into(), connect: "ds".into() };
        wire.answer("GET /admin/api/connects/ds/slack-app", 200, json!({"state": "no_config_token"}));
        stations.start(&app);
        host.settle().await;
        wire.answer("GET /admin/api/connects/ds/slack-app", 200, json!({"state": "ok"}));
        stations.perform(&remote(), &crate::ops::request("slack.addConfigToken", &json!({"station": ST, "refreshToken": "x"})).unwrap().unwrap()).await.unwrap();
        assert_eq!(sink.get(&app).unwrap()["state"], "ok");
    });
}

#[test]
fn operation_effects_do_not_depend_on_the_wire_path() {
    run(async {
        let (host, _sink, wire, stations) = setup();
        stations.start(&overview());
        host.settle().await;
        let before = wire.count("GET", "/admin/api/overview");
        let mut op = crate::ops::request("profile.check", &json!({"station": ST, "id": "p"})).unwrap().unwrap();
        op.path = "/different-endpoint".into();
        stations.perform(&remote(), &op).await.unwrap();
        assert_eq!(wire.count("GET", "/admin/api/overview"), before + 1);
        let verify = crate::ops::request("slack.verify", &json!({"station": ST, "appToken": "app", "botToken": "bot"})).unwrap().unwrap();
        stations.perform(&remote(), &verify).await.unwrap();
        assert_eq!(wire.count("GET", "/admin/api/overview"), before + 1, "checking tokens is not a settings change");
        // A response that happens to resemble an overview does not give a read write effects.
        let op = crate::ops::request("job.get", &json!({"station": ST, "id": "j"})).unwrap().unwrap();
        wire.answer("GET /admin/api/jobs/j", 200, json!({"connects": [], "profiles": []}));
        stations.perform(&remote(), &op).await.unwrap();
        assert_eq!(wire.count("GET", "/admin/api/overview"), before + 1);
    });
}

#[test]
fn archive_fallback_updates_the_session_only_after_success() {
    run(async {
        let (host, _sink, wire, stations) = setup();
        stations.start(&session("k"));
        stations.start(&sessions());
        host.settle().await;
        let op = crate::ops::request("chat.archive", &json!({"station": ST, "thread": 7, "session": "k", "archived": true})).unwrap().unwrap();
        let before = wire.count("GET", "/admin/api/sessions/k");
        wire.answer("POST /admin/api/threads/7/archive", 403, json!({"error": "denied"}));
        assert_eq!(stations.perform(&remote(), &op).await.unwrap_err().status, Some(403));
        assert_eq!(wire.count("POST", "/admin/api/sessions/k/archive"), 0);
        assert_eq!(wire.count("GET", "/admin/api/sessions/k"), before);
        wire.answer("POST /admin/api/threads/7/archive", 404, json!({}));
        wire.answer("POST /admin/api/sessions/k/archive", 500, json!({}));
        assert!(stations.perform(&remote(), &op).await.is_err());
        assert_eq!(wire.count("GET", "/admin/api/sessions/k"), before);
        wire.answer("POST /admin/api/sessions/k/archive", 200, json!({}));
        stations.perform(&remote(), &op).await.unwrap();
        assert_eq!(wire.count("GET", "/admin/api/sessions/k"), before + 1);
        assert_eq!(wire.count("POST", "/admin/api/sessions/k/archive"), 2);
    });
}

#[test]
fn jobs_are_put_in_place_from_their_events_and_from_stopping_them() {
    run(async {
        let (host, sink, wire, stations) = setup();
        let job = |id: &str, state: &str| json!({"id": id, "session": "a", "name": id, "state": state, "port": 4817, "startedAt": 1});
        let open = Topic::Jobs { station: ST.into() };
        wire.answer("GET /admin/api/sessions/a", 200, json!({"session": summary("a", 0), "threads": [], "turns": [], "jobs": [job("j1", "running")]}));
        wire.answer("GET /admin/api/jobs", 200, json!([{"id": "j1", "session": "a", "name": "j1", "state": "running", "port": 4817, "startedAt": 1, "chat": {"id": "7", "title": "t", "archived": false}}]));
        stations.start(&session("a"));
        stations.start(&open);
        host.settle().await;
        let reads = wire.calls.borrow().len();
        // Stopped from a page: the answer is the job as it is now, in its chat and gone from the open ones, with
        // nothing read again.
        wire.answer("POST /admin/api/jobs/j1/stop", 200, job("j1", "stopped"));
        stations.perform(&remote(), &crate::ops::request("job.stop", &json!({"station": ST, "id":"j1"})).unwrap().unwrap()).await.unwrap();
        assert_eq!(sink.get(&session("a")).unwrap()["jobs"][0]["state"], "stopped");
        assert_eq!(sink.get(&open).unwrap(), json!([]));
        assert_eq!(wire.calls.borrow().len(), reads + 1);
        // Started again elsewhere (an agent, another device): its event puts it back; which chat it is in, the list
        // read again says.
        wire.event("job", job("j1", "running"));
        host.settle().await;
        assert_eq!(sink.get(&session("a")).unwrap()["jobs"][0]["state"], "running");
        assert_eq!(sink.get(&open).unwrap()[0]["chat"]["id"], "7");
        assert_eq!(wire.count("GET", "/admin/api/jobs"), 2);
        // A new one goes in front of its session's; one listed keeps its chat as it changes.
        wire.event("job", job("j2", "failed"));
        let mut restarting = job("j1", "exited");
        restarting["restarts"] = json!(1);
        wire.event("job", restarting);
        host.settle().await;
        let jobs = sink.get(&session("a")).unwrap()["jobs"].clone();
        assert_eq!((jobs[0]["id"].as_str(), jobs[1]["state"].as_str()), (Some("j2"), Some("exited")));
        assert_eq!(sink.get(&open).unwrap()[0]["restarts"], 1);
        assert_eq!(sink.get(&open).unwrap()[0]["chat"]["id"], "7");
        assert_eq!(wire.count("GET", "/admin/api/jobs"), 2);
        // One that was over, cleared (here or on another device): out of its chat's.
        wire.event("job-removed", json!({"id": "j2", "session": "a"}));
        host.settle().await;
        let ids: Vec<Value> = sink.get(&session("a")).unwrap()["jobs"].as_array().unwrap().iter().map(|j| j["id"].clone()).collect();
        assert_eq!(ids, [json!("j1")]);
    });
}

#[test]
fn a_jobs_log_is_read_once_and_then_kept_current_by_the_stations_events() {
    run(async {
        let (host, sink, wire, stations) = setup();
        let log = |lines| Topic::JobLog { station: ST.into(), job: "j1".into(), lines };
        wire.answer("GET /admin/api/jobs/j1/log?lines=400", 200, json!({"text": "a\nb", "outputAt": 5, "follows": true}));
        wire.answer("GET /admin/api/jobs/j1/log?lines=1", 200, json!({"text": "b", "outputAt": 5, "follows": true}));
        stations.start(&log(400));
        host.settle().await;
        assert_eq!(sink.get(&log(400)).unwrap(), json!({"text": "a\nb", "outputAt": 5}));
        assert_eq!(wire.open(), vec!["/admin/api/events?job=j1&lines=400"]);
        // As it grows the station says so, each topic its own lines; nothing is read again, and nothing waits to.
        stations.start(&log(1));
        host.settle().await;
        assert_eq!(wire.open(), vec!["/admin/api/events?job=j1&lines=1&job=j1&lines=400"]);
        host.sleeps.borrow_mut().clear();
        wire.event("job-log", json!({"id": "j1", "lines": 400, "text": "a\nb\nc", "outputAt": 9}));
        wire.event("job-log", json!({"id": "j1", "lines": 1, "text": "c", "outputAt": 9}));
        host.settle().await;
        assert_eq!(sink.get(&log(400)).unwrap(), json!({"text": "a\nb\nc", "outputAt": 9}));
        assert_eq!(sink.get(&log(1)).unwrap(), json!({"text": "c", "outputAt": 9}));
        wait(LOG_READ_MS + 200).await;
        assert_eq!((wire.count("GET", "/admin/api/jobs/j1/log?lines=400"), wire.count("GET", "/admin/api/jobs/j1/log?lines=1")), (1, 1));
        assert!(!host.sleeps.borrow().contains(&LOG_READ_MS), "{:?}", host.sleeps.borrow());
        // Given up: the stream no longer asks for it.
        stations.stop(&log(400));
        host.settle().await;
        assert_eq!(wire.open(), vec!["/admin/api/events?job=j1&lines=1"]);
    });
}

#[test]
fn a_jobs_log_on_a_station_that_does_not_follow_it_is_read_again_less_often_while_it_stays_the_same() {
    run(async {
        let (host, sink, wire, stations) = setup();
        host.speed_up(100);
        let topic = Topic::JobLog { station: ST.into(), job: "j1".into(), lines: 1 };
        let path = "/admin/api/jobs/j1/log?lines=1";
        // An older station: no `follows`, and `job=` on its stream passed over.
        wire.answer(&format!("GET {path}"), 200, json!({"text": "a", "outputAt": 5}));
        stations.start(&topic);
        host.settle().await;
        assert_eq!(sink.get(&topic).unwrap(), json!({"text": "a", "outputAt": 5}));
        wire.answer(&format!("GET {path}"), 200, json!({"text": "b", "outputAt": 6}));
        wait(80).await;
        assert_eq!(sink.get(&topic).unwrap(), json!({"text": "b", "outputAt": 6}));
        wait(200).await;
        let waits: Vec<u64> = host.sleeps.borrow().iter().copied().filter(|ms| [LOG_READ_MS, LOG_READ_MS * 2, LOG_READ_MS * 4].contains(ms)).collect();
        assert!(waits.contains(&(LOG_READ_MS * 2)) && waits.contains(&(LOG_READ_MS * 4)), "{waits:?}");
        // Given up: no more reading.
        stations.stop(&topic);
        host.settle().await;
        let reads = wire.count("GET", path);
        wait(200).await;
        assert_eq!(wire.count("GET", path), reads);
    });
}

#[test]
fn requests_carry_the_trace_they_are_made_in() {
    run(async {
        let (host, _sink, wire, stations) = setup();
        let tracer = stations.tracer.clone();
        let root = tracer.root("chat.open", Kind::Internal);
        tracer.enter(Some(root.context()), || {
            stations.start(&threads());
            stations.start(&thread(7));
        });
        host.settle().await;
        // Outside every trace: a trace of its own.
        stations.get(&remote(), "/overview").await.unwrap();
        let trace = hex::encode(root.context().trace);
        let (paths, parents) = (wire.paths(), wire.traceparents.borrow().clone());
        // (With no list of threads to say where reading stopped, the chat asks for its own summary.)
        assert_eq!(paths.len(), 5, "{paths:?}");
        for (path, parent) in paths.iter().zip(&parents) {
            assert!(parent.starts_with("00-") && parent.ends_with("-01") && parent.len() == 55, "{path}: {parent}");
            // Each request is a span of its own under the trace.
            assert_ne!(&parent[36..52], hex::encode(root.context().span), "{path}");
            assert_eq!(parent[3..35] == trace, !path.ends_with("/overview"), "{path}: {parent}");
        }
    });
}

#[test]
fn topics_are_read_once_and_nothing_runs_on_a_timer() {
    run(async {
        let (host, _sink, wire, stations) = setup();
        for t in [session("a"), sessions(), overview(), threads(), thread(7), host_topic(), link(), live("a")] {
            stations.start(&t);
        }
        host.settle().await;
        assert_eq!(wire.open(), vec!["/admin/api/events?host=1&live=a&from=0&last=200"]);
        let requests = wire.calls.borrow().len();
        // (With no list of threads to say where reading stopped, the chat asks for its own summary.)
        assert_eq!(requests, 8, "{:?}", wire.paths());
        host.sleeps.borrow_mut().clear();
        wait(RECONNECT_MS * 2).await;
        assert_eq!(wire.calls.borrow().len(), requests, "idle: no request");
        assert!(host.sleeps.borrow().is_empty(), "idle: no timer {:?}", host.sleeps.borrow());
    });
}

#[test]
fn session_events_update_in_place() {
    run(async {
        let (host, sink, wire, stations) = setup();
        wire.answer("GET /admin/api/sessions", 200, json!([summary("a", 1), summary("b", 0)]));
        wire.answer("GET /admin/api/sessions/a", 200, json!({"session": summary("a", 1), "threads": [], "turns": [{"id": "t1", "kind": "chat", "outcome": null, "declared": null, "detail": null, "startedAt": 1, "endedAt": null}]}));
        stations.start(&sessions());
        stations.start(&session("a"));
        host.settle().await;
        let reads = wire.calls.borrow().len();
        // The same turns: only the summary changes, without a request.
        let mut renamed = summary("a", 1);
        renamed["title"] = json!("新名字");
        renamed["lastTurn"] = json!({"kind": "chat", "outcome": null, "declared": null, "detail": null, "startedAt": 1, "endedAt": null});
        wire.event("session", renamed.clone());
        wire.event("session", summary("c", 0));
        host.settle().await;
        assert_eq!(wire.calls.borrow().len(), reads);
        let list = sink.get(&sessions()).unwrap();
        let keys: Vec<&str> = list.as_array().unwrap().iter().map(|s| s["key"].as_str().unwrap()).collect();
        assert_eq!(keys, vec!["c", "a", "b"]);
        assert_eq!(list[1]["title"], "新名字");
        assert_eq!(sink.get(&session("a")).unwrap()["session"]["title"], "新名字");
        // The turn ended: the detail's turns are read again.
        let mut ended = renamed.clone();
        ended["lastTurn"]["endedAt"] = json!(2);
        wire.event("session", ended);
        host.settle().await;
        assert_eq!(wire.count("GET", "/admin/api/sessions/a"), 2);
        // Archived: gone from the list. Removed: gone, and its topic says so.
        let mut archived = summary("b", 0);
        archived["archivedAt"] = json!(5);
        wire.event("session", archived);
        wire.event("session-removed", json!({"key": "a"}));
        host.settle().await;
        let keys: Vec<String> = sink.get(&sessions()).unwrap().as_array().unwrap().iter().map(|s| s["key"].as_str().unwrap().to_string()).collect();
        assert_eq!(keys, vec!["c"]);
        assert_eq!(sink.values.borrow()[&session("a")].as_ref().unwrap_err().status, Some(404));
    });
}

#[test]
fn overview_and_host_come_from_events() {
    run(async {
        let (host, sink, wire, stations) = setup();
        stations.start(&overview());
        host.settle().await;
        assert_eq!(wire.open(), vec!["/admin/api/events"]);
        wire.event("overview", json!({"connects": [1]}));
        wire.event("host", json!({"hostname": "not asked"}));
        host.settle().await;
        assert_eq!(sink.get(&overview()), Some(json!({"connects": [1]})));
        assert_eq!(sink.get(&host_topic()), None);
        // Host samples are asked for while a host topic is live: the stream opens anew with ?host=1, and the old one goes once it has.
        stations.start(&host_topic());
        host.settle().await;
        assert_eq!(wire.open(), vec!["/admin/api/events?host=1"]);
        wire.event("host", json!({"hostname": "studio"}));
        host.settle().await;
        assert_eq!(sink.get(&host_topic()), Some(json!({"hostname": "studio"})));
        assert_eq!(wire.count("GET", "/admin/api/overview"), 1, "a handover is no reconnect: nothing is read again");
        stations.stop(&host_topic());
        host.settle().await;
        assert_eq!(wire.open(), vec!["/admin/api/events"]);
        assert_eq!(wire.count("GET", "/admin/api/host"), 0);
    });
}

#[test]
fn thread_events_append_entries_and_refresh_summaries() {
    run(async {
        let (host, sink, wire, stations) = setup();
        wire.answer("GET /admin/api/threads/7/entries?limit=50", 200, json!({"last": 12, "entries": [entry(11, "a"), entry(12, "b")]}));
        wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 12, 12, 0)]));
        wire.answer("GET /admin/api/threads/7", 200, thread_view(7, &["k"], 15, 12, 2));
        wire.answer("GET /admin/api/threads/8", 200, thread_view(8, &["k"], 20, 0, 1));
        stations.start(&thread(7));
        stations.start(&threads());
        host.settle().await;
        assert_eq!(texts(&sink, 7), vec!["a", "b"]);
        // New entries (an edit among them), in one burst: appended at once, one known already skipped; the
        // summary is read once after it.
        wire.event("thread", json!({"id": 7, "entries": [entry(13, "c")]}));
        wire.event("thread", json!({"id": 7, "entries": [entry(13, "c"), entry(14, "d"), edit(15, 12, "b 改了")]}));
        host.settle().await;
        assert_eq!(numbers(&sink, 7), vec![11, 12, 13, 14, 15]);
        assert_eq!(texts(&sink, 7), vec!["a", "b 改了", "c", "d"]);
        assert_eq!(sink.get(&thread(7)).unwrap()["last"], 15);
        assert_eq!(sink.get(&thread(7)).unwrap()["caught"], 12, "what was read, not what was said since");
        assert_eq!(wire.count("GET", "/admin/api/threads/7"), 0, "waits for the burst to end");
        wait(EVENTS_COALESCE_MS).await;
        assert_eq!(wire.count("GET", "/admin/api/threads/7"), 1);
        assert_eq!(sink.get(&threads()).unwrap()[0]["unread"], 2);
        // A thread not listed yet comes in, first (its last message is the newest).
        wire.event("thread", json!({"id": 8, "entries": [entry(20, "x")]}));
        host.settle().await;
        wait(EVENTS_COALESCE_MS).await;
        let ids: Vec<u64> = sink.get(&threads()).unwrap().as_array().unwrap().iter().map(|t| t["id"].as_u64().unwrap()).collect();
        assert_eq!(ids, vec![8, 7]);
        // Reading up to the last entry: nothing unread, without a request. Short of it: counted again.
        wire.event("read", json!({"viewer": "a@x.com", "thread": 7, "n": 15}));
        host.settle().await;
        assert_eq!(sink.get(&threads()).unwrap()[1]["unread"], 0);
        assert_eq!(sink.get(&threads()).unwrap()[1]["read"], 15);
        wire.event("read", json!({"viewer": "a@x.com", "thread": 8, "n": 15}));
        host.settle().await;
        wait(EVENTS_COALESCE_MS).await;
        assert_eq!(wire.count("GET", "/admin/api/threads/8"), 2);
        // A thread gone: out of the list.
        wire.answer("GET /admin/api/threads/8", 404, json!({"error": "unknown thread 8"}));
        wire.event("thread", json!({"id": 8, "entries": []}));
        host.settle().await;
        wait(EVENTS_COALESCE_MS).await;
        assert_eq!(sink.get(&threads()).unwrap().as_array().unwrap().len(), 1);
    });
}

#[test]
fn a_gap_is_read_once_and_what_came_meanwhile_waits_for_it() {
    run(async {
        let (host, sink, wire, stations) = setup();
        wire.answer("GET /admin/api/threads/7/entries?limit=50", 200, json!({"last": 3, "entries": entries(1, 3)}));
        wire.answer("GET /admin/api/threads/7/entries?from=4&to=5", 200, json!({"last": 7, "entries": entries(4, 5)}));
        stations.start(&thread(7));
        host.settle().await;
        // Entries 4 and 5 never came: 6 shows the gap, and 7 comes while it is read.
        wire.event("thread", json!({"id": 7, "entries": [entry(6, "m6")]}));
        wire.event("thread", json!({"id": 7, "entries": [entry(7, "m7")]}));
        host.settle().await;
        assert_eq!(numbers(&sink, 7), vec![1, 2, 3, 4, 5, 6, 7]);
        assert_eq!(sink.get(&thread(7)).unwrap()["caught"], 7, "a gap is historical loading, including events waiting behind it");
        assert_eq!(wire.count("GET", "/admin/api/threads/7/entries?from=4&to=5"), 1);
        assert_eq!(wire.paths().iter().filter(|p| p.contains("/entries")).count(), 2, "{:?}", wire.paths());
    });
}

/// A second core on the same device (the page reloaded): the same storage, a new `Stations`.
fn reopened(host: &Rc<FakeHost>) -> (Rc<FakeSink>, Rc<FakeWire>, Rc<Stations>) {
    let sink = Rc::new(FakeSink::default());
    let wire = FakeWire::new();
    let stations = Stations::new(host.clone(), sink.clone(), wire.clone(), Tracer::new(host.clone(), 1.0), Kept::new(host.clone()), Workspaces::new(host.clone()));
    (sink, wire, stations)
}

#[test]
fn a_thread_keeps_a_page_ahead_so_going_back_does_not_wait() {
    run(async {
        let (host, _sink, wire, stations) = setup();
        wire.answer("GET /admin/api/threads/7/entries?limit=50", 200, json!({"last": 300, "entries": entries(251, 300)}));
        wire.answer("GET /admin/api/threads/7/entries?before=251&limit=50", 200, json!({"last": 300, "entries": entries(201, 250)}));
        stations.start(&thread(7));
        host.settle().await;
        assert_eq!(wire.count("GET", "/admin/api/threads/7/entries?before=251&limit=50"), 1, "the page before, brought in ahead");
        // Going back shows it from the device at once, and brings the next one in.
        wire.answer("GET /admin/api/threads/7/entries?before=201&limit=50", 200, json!({"last": 300, "entries": entries(151, 200)}));
        assert!(stations.older(&remote(), 7).await.unwrap());
        assert_eq!(wire.count("GET", "/admin/api/threads/7/entries?before=251&limit=50"), 1, "not asked again");
        host.settle().await;
        assert_eq!(wire.count("GET", "/admin/api/threads/7/entries?before=201&limit=50"), 1);
    });
}

#[test]
fn a_thread_opens_from_what_is_kept_and_asks_only_for_what_came_after() {
    run(async {
        let (host, sink, wire, stations) = setup();
        wire.answer("GET /admin/api/threads/7/entries?limit=50", 200, json!({"last": 300, "entries": entries(251, 300)}));
        wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 300, 300, 0)]));
        stations.start(&thread(7));
        stations.start(&threads());
        host.settle().await;
        wire.event("thread", json!({"id": 7, "entries": [entry(301, "m301")]}));
        host.settle().await;
        assert_eq!(numbers(&sink, 7).len(), 51);
        // Reloaded: the kept page at once, with the summary kept beside it, before anything is answered.
        let (sink, wire, stations) = reopened(&host);
        *wire.stream_status.borrow_mut() = None;
        wire.answer("GET /admin/api/threads/7/entries?after=301", 200, json!({"last": 302, "entries": [entry(302, "m302")]}));
        stations.start(&thread(7));
        host.settle().await;
        // Its latest page came from what is kept (the station was asked only for what came after it).
        let shown = sink.get(&thread(7)).expect("shown from what is kept");
        assert_eq!((shown["first"].clone(), shown["last"].clone(), shown["thread"]["id"].clone()), (json!(253), json!(302), json!(7)));
        // All of it caught up on (kept, then read): none of it was said while the chat was open.
        assert_eq!(shown["caught"], 302);
        assert_eq!(wire.paths().iter().filter(|p| p.contains("/entries")).cloned().collect::<Vec<_>>(), vec!["GET /admin/api/threads/7/entries?after=301"]);
        // Scrolling up reads what is kept first; past it, the station (and what it answers is kept too).
        assert!(stations.older(&remote(), 7).await.unwrap());
        assert_eq!(sink.get(&thread(7)).unwrap()["first"], 251);
        // (Its summary, with no list read to say where reading stopped; the entries after what is kept; the stream.)
        assert_eq!(wire.calls.borrow().len(), 3, "{:?}", wire.paths());
        wire.answer("GET /admin/api/threads/7/entries?before=251&limit=50", 200, json!({"last": 302, "entries": entries(201, 250)}));
        assert!(stations.older(&remote(), 7).await.unwrap());
        assert_eq!(numbers(&sink, 7).first(), Some(&201));
        host.settle().await;
        let (sink, wire, stations) = reopened(&host);
        *wire.stream_status.borrow_mut() = None;
        stations.start(&thread(7));
        host.settle().await;
        assert!(stations.older(&remote(), 7).await.unwrap());
        assert_eq!(numbers(&sink, 7), (203..=302).collect::<Vec<_>>(), "two pages, both from what is kept");
        assert_eq!(wire.paths().iter().filter(|p| p.contains("before=")).count(), 0);
        assert_eq!(texts(&sink, 7).last().unwrap(), "m302");
    });
}

fn window_of(sink: &FakeSink, id: u64) -> (u64, u64, bool) {
    let v = sink.get(&thread(id)).unwrap();
    (v["first"].as_u64().unwrap(), v["last"].as_u64().unwrap(), at_end(&v))
}

#[test]
fn a_chat_with_something_unread_opens_whole_at_it_and_pages_either_way() {
    run(async {
        let (host, sink, wire, stations) = setup();
        // 300 entries, read up to 200: the window is the page before the first unread and the page from it.
        wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 300, 200, 100)]));
        stations.start(&threads());
        host.settle().await;
        wire.answer("GET /admin/api/threads/7/entries?from=151&to=250", 200, json!({"last": 300, "entries": entries(151, 250)}));
        wire.answer("GET /admin/api/threads/7/entries?before=151&limit=50", 200, json!({"last": 300, "entries": entries(101, 150)}));
        wire.answer("GET /admin/api/threads/7/entries?from=251&to=300", 200, json!({"last": 300, "entries": entries(251, 300)}));
        stations.start(&thread(7));
        host.settle().await;
        assert_eq!(window_of(&sink, 7), (151, 250, false));
        assert_eq!(wire.paths().iter().filter(|p| p.contains("/entries")).count(), 3, "the window, then a page ahead either way: {:?}", wire.paths());
        // Said meanwhile, past the window: it waits (kept for when the window comes down to it).
        wire.event("thread", json!({"id": 7, "entries": [entry(301, "m301")]}));
        host.settle().await;
        assert_eq!(window_of(&sink, 7), (151, 250, false));
        // Down: the page after, from what was brought ahead, read (not said); then what waited, and the window is
        // at its end, as many gone at its start.
        assert!(stations.newer(&remote(), 7).await.unwrap());
        assert_eq!(wire.count("GET", "/admin/api/threads/7/entries?from=251&to=300"), 1, "not asked again");
        assert_eq!(window_of(&sink, 7), (151, 300, false));
        host.settle().await;
        assert!(!stations.newer(&remote(), 7).await.unwrap());
        assert_eq!(window_of(&sink, 7), (152, 301, true));
        assert_eq!(sink.get(&thread(7)).unwrap()["caught"], 301);
        // Up: the page before comes in, and as many go at the other end.
        assert!(stations.older(&remote(), 7).await.unwrap());
        assert_eq!(window_of(&sink, 7), (102, 251, false));
        assert_eq!(numbers(&sink, 7).len() as u64, WINDOW);
        // To the end: its latest page in place of the window, from the device; then asked what came after it.
        let asked = wire.paths().len();
        stations.latest(&remote(), 7).await.unwrap();
        assert_eq!(window_of(&sink, 7), (252, 301, true));
        assert_eq!(wire.paths()[asked..], ["GET /admin/api/threads/7/entries?after=301".to_string()], "{:?}", wire.paths());
        // At its end, what is said joins it.
        wire.event("thread", json!({"id": 7, "entries": [entry(302, "m302")]}));
        host.settle().await;
        assert_eq!(window_of(&sink, 7).1, 302);
    });
}

#[test]
fn a_chat_opens_from_the_device_when_what_is_kept_is_current_and_else_waits_to_be_whole() {
    run(async {
        let (host, _sink, wire, stations) = setup();
        wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 300, 300, 0)]));
        wire.answer("GET /admin/api/threads/7/entries?limit=50", 200, json!({"last": 300, "entries": entries(251, 300)}));
        stations.start(&threads());
        stations.start(&thread(7));
        host.settle().await;
        // Opened again, nothing new: from the device alone.
        let (sink, wire, stations) = reopened(&host);
        wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 300, 300, 0)]));
        stations.start(&threads());
        host.settle().await;
        stations.start(&thread(7));
        host.settle().await;
        assert_eq!(window_of(&sink, 7), (251, 300, true));
        // Shown from the device, then asked once what came after it (an event missed is not told again).
        assert!(wire.paths().iter().all(|p| !p.contains("entries?limit=50")), "{:?}", wire.paths());
        assert_eq!(wire.count("GET", "/admin/api/threads/7/entries?after=300"), 1);
        // Opened again with 20 new (read): what came after is read first; the first value is whole.
        let (sink, wire, stations) = reopened(&host);
        wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 320, 320, 0)]));
        wire.answer("GET /admin/api/threads/7/entries?after=300", 200, json!({"last": 320, "entries": entries(301, 320)}));
        stations.start(&threads());
        host.settle().await;
        stations.start(&thread(7));
        host.settle().await;
        assert_eq!(window_of(&sink, 7), (271, 320, true));
        assert_eq!(sink.get(&thread(7)).unwrap()["caught"], 320, "read, not said");
        // Left short of its end and opened again: there.
        stations.place(ST, 7, Some(120), None);
        stations.stop(&thread(7));
        sink.values.borrow_mut().remove(&thread(7));
        wire.answer("GET /admin/api/threads/7/entries?from=70&to=169", 200, json!({"last": 320, "entries": entries(70, 169)}));
        stations.start(&thread(7));
        host.settle().await;
        assert_eq!(window_of(&sink, 7), (70, 169, false));
    });
}

#[test]
fn where_a_chat_was_left_is_kept_on_the_device_for_a_core_started_anew() {
    run(async {
        let (host, _sink, wire, stations) = setup();
        wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 300, 300, 0)]));
        wire.answer("GET /admin/api/threads/7/entries?limit=50", 200, json!({"last": 300, "entries": entries(251, 300)}));
        stations.start(&threads());
        stations.start(&thread(7));
        host.settle().await;
        // Left 180 down: the core goes (the page reloaded) before the chat is opened again.
        stations.place(ST, 7, Some(180), Some(-36.5));
        host.settle().await;
        let (sink, wire, stations) = reopened(&host);
        wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 300, 300, 0)]));
        wire.answer("GET /admin/api/threads/7/entries?from=130&to=229", 200, json!({"last": 300, "entries": entries(130, 229)}));
        stations.start(&threads());
        host.settle().await;
        stations.start(&thread(7));
        host.settle().await;
        assert_eq!(window_of(&sink, 7), (130, 229, false));
        let value = sink.get(&thread(7)).unwrap();
        assert_eq!((value["at"].clone(), value["atOffset"].clone()), (json!(180), json!(-36.5)));
        // Left at its end: the next core opens it there.
        stations.place(ST, 7, None, None);
        host.settle().await;
        let (sink, wire, stations) = reopened(&host);
        wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 300, 300, 0)]));
        stations.start(&threads());
        host.settle().await;
        stations.start(&thread(7));
        host.settle().await;
        assert_eq!(window_of(&sink, 7).2, true);
        assert!(sink.get(&thread(7)).unwrap().get("at").is_none());
    });
}

#[test]
fn a_chat_not_open_keeps_up_on_the_device() {
    run(async {
        let (host, sink, wire, stations) = setup();
        wire.answer("GET /admin/api/threads/7/entries?limit=50", 200, json!({"last": 300, "entries": entries(251, 300)}));
        wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 300, 300, 0)]));
        stations.start(&thread(7));
        stations.start(&threads());
        host.settle().await;
        // Closed (let go by the store, its value with it); what is said meanwhile carries on what is kept. Past a
        // gap, what came after what is kept is read then, so it stays whole.
        stations.stop(&thread(7));
        sink.values.borrow_mut().remove(&thread(7));
        wire.answer("GET /admin/api/threads/7/entries?after=301", 200, json!({"last": 303, "entries": [entry(302, "m302"), entry(303, "m303")]}));
        wire.event("thread", json!({"id": 7, "entries": [entry(301, "m301")]}));
        wire.event("thread", json!({"id": 7, "entries": [entry(303, "m303")]}));
        host.settle().await;
        assert_eq!(wire.count("GET", "/admin/api/threads/7/entries?after=301"), 1, "asked only for what came after what was kept");
        // Opened: whole from the device, then only asked what came after it.
        let asked = wire.paths().len();
        stations.start(&thread(7));
        host.settle().await;
        assert_eq!(texts(&sink, 7).last().unwrap(), "m303");
        let read: Vec<String> = wire.paths()[asked..].iter().filter(|p| p.contains("entries?")).cloned().collect();
        assert_eq!(read, ["GET /admin/api/threads/7/entries?after=303"], "{:?}", wire.paths());
        assert_eq!(sink.get(&thread(7)).unwrap()["caught"], 303);
    });
}

#[test]
fn a_removed_thread_and_a_removed_sessions_transcript_are_forgotten() {
    run(async {
        let (host, _sink, wire, stations) = setup();
        wire.answer("GET /admin/api/threads/7/entries?limit=50", 200, json!({"last": 2, "entries": entries(1, 2)}));
        stations.start(&thread(7));
        stations.start(&live("k"));
        host.settle().await;
        wire.event("live", with_key("k", json!({"type": "timeline", "start": 0, "entries": ["a"], "usage": {}})));
        host.settle().await;
        assert!(host.stored("thread/ws/st/7/0").is_some() && host.stored("transcript/ws/st/k/0").is_some());
        wire.event("thread-removed", json!({"id": 7}));
        wire.event("session-removed", json!({"key": "k"}));
        host.settle().await;
        assert_eq!((host.stored("thread/ws/st/7/0"), host.stored("thread/ws/st/7/meta")), (None, None));
        assert_eq!(host.stored("transcript/ws/st/k/0"), None);
    });
}

#[test]
fn chat_rows_come_from_the_station_and_follow_its_events() {
    run(async {
        let (host, sink, wire, stations) = setup();
        let rows = Topic::ChatRows { station: ST.into() };
        let row = |id: &str, thread: Option<u64>, last: u64, unread: bool| json!({"id": id, "thread": thread, "title": id, "last": if last > 0 { json!({"seq": last, "text": "…"}) } else { Value::Null }, "unread": unread});
        wire.answer("GET /admin/api/chats", 200, json!([row("7", Some(7), 12, true), row("k", None, 0, false)]));
        stations.start(&rows);
        host.settle().await;
        assert_eq!(wire.open(), vec!["/admin/api/events"]);
        let ids = |sink: &FakeSink| sink.get(&rows).unwrap().as_array().unwrap().iter().map(|r| r["id"].as_str().unwrap().to_string()).collect::<Vec<_>>();
        assert_eq!(ids(&sink), vec!["7", "k"]);
        let reads = wire.calls.borrow().len();
        // Rows change, come and go as the station says, without a request.
        let mut renamed = row("7", Some(7), 13, true);
        renamed["title"] = json!("排查");
        wire.event("chat", renamed);
        wire.event("chat", row("8", Some(8), 1, false));
        wire.event("chat-removed", json!({"id": "k"}));
        host.settle().await;
        assert_eq!(ids(&sink), vec!["7", "8"]);
        assert_eq!(sink.get(&rows).unwrap()[0]["title"], "排查");
        assert_eq!(wire.calls.borrow().len(), reads);
        // Read short of the last message: still unread; up to it: read, at once.
        wire.event("read", json!({"viewer": "a@x.com", "thread": 7, "n": 12}));
        host.settle().await;
        assert_eq!(sink.get(&rows).unwrap()[0]["unread"], true);
        stations.read(&remote(), 7, 13).await.unwrap();
        assert_eq!(sink.get(&rows).unwrap()[0]["unread"], false);
        // A new chat is written: the rows are current when the write answers.
        wire.answer("GET /admin/api/chats", 200, json!([row("9", Some(9), 0, false)]));
        wire.answer("POST /admin/api/threads", 200, thread_view(9, &["k"], 0, 0, 0));
        stations.perform(&remote(), &crate::ops::request("chat.forSession", &json!({"station": ST, "session":"k"})).unwrap().unwrap()).await.unwrap();
        assert_eq!(ids(&sink), vec!["9"]);
        // So is saying who one is on Slack.
        wire.answer("PUT /admin/api/me/slack/U7", 200, json!({"viewer": {}, "connects": [], "profiles": [], "slackUsers": ["U7"]}));
        let before = wire.count("GET", "/admin/api/chats");
        stations.perform(&remote(), &crate::ops::request("slack.identity", &json!({"station": ST, "user":"U7", "bound":true})).unwrap().unwrap()).await.unwrap();
        assert_eq!(wire.count("GET", "/admin/api/chats"), before + 1);
    });
}

#[test]
fn a_session_topic_follows_its_threads() {
    run(async {
        let (host, sink, wire, stations) = setup();
        wire.answer("GET /admin/api/sessions/k", 200, json!({"session": summary("k", 0), "threads": [thread_view(7, &["k"], 12, 0, 1)], "turns": []}));
        wire.answer("GET /admin/api/threads/9", 200, thread_view(9, &["k", "j"], 30, 0, 1));
        stations.start(&session("k"));
        host.settle().await;
        wire.event("thread", json!({"id": 9, "entries": []}));
        wire.event("read", json!({"viewer": "a@x.com", "thread": 7, "n": 12}));
        host.settle().await;
        wait(EVENTS_COALESCE_MS).await;
        let detail = sink.get(&session("k")).unwrap();
        let ids: Vec<u64> = detail["threads"].as_array().unwrap().iter().map(|t| t["id"].as_u64().unwrap()).collect();
        assert_eq!(ids, vec![9, 7]);
        assert_eq!(detail["threads"][1]["unread"], 0);
        // The session left thread 9.
        wire.answer("GET /admin/api/threads/9", 200, thread_view(9, &["j"], 30, 0, 1));
        wire.event("thread", json!({"id": 9, "entries": []}));
        host.settle().await;
        wait(EVENTS_COALESCE_MS).await;
        assert_eq!(sink.get(&session("k")).unwrap()["threads"].as_array().unwrap().len(), 1);
    });
}

#[test]
fn a_thread_pages_back_and_catches_up() {
    run(async {
        let (host, sink, wire, stations) = setup();
        wire.answer("GET /admin/api/threads/7/entries?limit=50", 200, json!({"last": 4, "entries": [entry(3, "c"), entry(4, "d")]}));
        wire.answer("GET /admin/api/threads/7/entries?before=3&limit=50", 200, json!({"last": 4, "entries": [entry(1, "a"), entry(2, "b")]}));
        stations.start(&thread(7));
        stations.start(&link());
        host.settle().await;
        assert!(!stations.older(&remote(), 7).await.unwrap());
        assert_eq!(texts(&sink, 7), vec!["a", "b", "c", "d"]);
        assert_eq!(sink.get(&thread(7)).unwrap()["caught"], 4);
        // Nothing older: no request.
        assert!(!stations.older(&remote(), 7).await.unwrap());
        assert_eq!(wire.paths().iter().filter(|p| p.contains("before=")).count(), 1);
        // The stream was down: what came after the last entry is read, and the pages stay.
        wire.answer("GET /admin/api/threads/7/entries?after=4", 200, json!({"last": 5, "entries": [entry(5, "e")]}));
        wire.end("/admin/api/events");
        host.settle().await;
        assert_eq!(sink.get(&link()).unwrap()["state"], "reconnecting");
        wait(RECONNECT_MS + 50).await;
        assert_eq!(sink.get(&link()).unwrap()["state"], "online");
        assert_eq!(texts(&sink, 7), vec!["a", "b", "c", "d", "e"]);
        assert_eq!(sink.get(&thread(7)).unwrap()["caught"], 5, "what was missed while the stream was down is caught up on");
        assert_eq!(wire.count("GET", "/admin/api/threads/7/entries?limit=50"), 1);
    });
}

#[test]
fn posts_into_a_thread_and_answers_once_it_shows() {
    run(async {
        let (host, sink, wire, stations) = setup();
        wire.answer("GET /admin/api/threads/7/entries?limit=50", 200, json!({"last": 12, "entries": [entry(12, "d")]}));
        wire.answer("POST /admin/api/threads/7/messages", 200, json!({"n": 13}));
        wire.answer("GET /admin/api/threads/7/entries?after=12", 200, json!({"last": 13, "entries": [entry(13, "你好")]}));
        stations.start(&thread(7));
        host.settle().await;
        assert_eq!(stations.post(&remote(), 7, json!({"text": "你好"})).await.unwrap(), 13);
        assert_eq!(texts(&sink, 7), vec!["d", "你好"]);
        // Reading: sent once, not again for less.
        stations.start(&threads());
        wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 13, 0, 1)]));
        host.settle().await;
        wire.answer("PUT /admin/api/threads/7/read", 200, json!({"viewer": "a@x.com", "thread": 7, "n": 13}));
        stations.read(&remote(), 7, 13).await.unwrap();
        stations.read(&remote(), 7, 12).await.unwrap();
        assert_eq!(wire.count("PUT", "/admin/api/threads/7/read"), 1);
        assert_eq!(wire.calls.borrow().iter().find(|(_, m, _, _)| m == "PUT").unwrap().3, br#"{"n":13}"#.to_vec());
        assert_eq!(sink.get(&threads()).unwrap()[0]["unread"], 0);
    });
}

#[test]
fn events_reconnect_report_the_link_and_read_everything_once() {
    run(async {
        let (host, sink, wire, stations) = setup();
        stations.start(&link());
        stations.start(&sessions());
        host.settle().await;
        assert_eq!(sink.get(&link()).unwrap()["state"], "online");
        *wire.stream_status.borrow_mut() = None;
        wire.end("/admin/api/events");
        host.settle().await;
        // It was up and dropped: coming back, for a few tries.
        assert_eq!(sink.get(&link()).unwrap()["state"], "reconnecting");
        wait(RECONNECT_MS + 50).await;
        assert_eq!(sink.get(&link()).unwrap(), json!({"state": "reconnecting", "message": "连不上"}));
        *wire.stream_status.borrow_mut() = Some(403);
        wait(RECONNECT_MS + 50).await;
        assert_eq!(sink.get(&link()).unwrap(), json!({"state": "error", "message": "没有权限"}));
        let s = wire.count("GET", "/admin/api/sessions");
        *wire.stream_status.borrow_mut() = Some(200);
        // Tries come less often as they miss: twice the wait by now.
        wait(RECONNECT_MS * 2 + 50).await;
        assert_eq!(sink.get(&link()).unwrap()["state"], "online");
        assert_eq!(wire.count("GET", "/admin/api/sessions"), s + 1, "a reconnect reads the station's topics once");
        // Nothing live: the stream closes and stays closed.
        stations.stop(&link());
        stations.stop(&sessions());
        let e = wire.count("GET", "/admin/api/events");
        wait(RECONNECT_MS + 100).await;
        assert_eq!(wire.count("GET", "/admin/api/events"), e);
        assert!(wire.open().is_empty());
    });
}

#[test]
fn live_holds_the_transcript_and_its_usage() {
    run(async {
        let (host, sink, wire, stations) = setup();
        stations.start(&live("k"));
        host.settle().await;
        assert_eq!(live_of(&sink, "k"), live_start());
        assert!(wire.paths().contains(&"GET /admin/api/events?live=k&from=0&last=200".to_string()));
        let push = |v: Value| wire.event("live", with_key("k", v));
        push(json!({"type": "timeline", "start": 0, "entries": ["a", "b"], "usage": {"modelCalls": 1, "model": "claude-opus"}}));
        push(json!({"type": "steps", "steps": [], "phase": null}));
        host.settle().await;
        let v = live_of(&sink, "k");
        assert_eq!((v["loaded"].clone(), v["timeline"].clone(), v["usage"]["model"].clone()), (json!(true), json!(["a", "b"]), json!("claude-opus")));
        push(json!({"type": "timeline", "start": 2, "entries": ["c"], "usage": {"modelCalls": 2}}));
        host.settle().await;
        assert_eq!(live_of(&sink, "k")["timeline"], json!(["a", "b", "c"]));
        assert_eq!(live_of(&sink, "k")["usage"]["modelCalls"], 2);
        // Overlap: replaced from `start`.
        push(json!({"type": "timeline", "start": 1, "entries": ["B", "c", "d"], "usage": {}}));
        host.settle().await;
        assert_eq!(live_of(&sink, "k")["timeline"], json!(["a", "B", "c", "d"]));
        // Reconnects ask from what is known.
        wire.end("/admin/api/events");
        wait(RECONNECT_MS + 50).await;
        assert!(wire.paths().contains(&"GET /admin/api/events?live=k&from=4&last=200".to_string()), "{:?}", wire.paths());
        // Reloaded: the kept transcript at once, and only what came after it is asked for.
        host.settle().await;
        let (reloaded, again, other) = reopened(&host);
        other.start(&live("k"));
        host.settle().await;
        assert_eq!(live_of(&reloaded, "k")["timeline"], json!(["a", "B", "c", "d"]));
        assert!(again.paths().contains(&"GET /admin/api/events?live=k&from=4&last=200".to_string()), "{:?}", again.paths());
        // Written anew and shorter: what is kept is cut there too.
        again.event("live", with_key("k", json!({"type": "timeline", "start": 1, "entries": [], "usage": {}})));
        host.settle().await;
        assert_eq!(live_of(&reloaded, "k")["timeline"], json!(["a"]));
        let (reloaded, _, other) = reopened(&host);
        other.start(&live("k"));
        host.settle().await;
        assert_eq!(live_of(&reloaded, "k")["timeline"], json!(["a"]));
        // Past what is here (the station sent only its latest page): the timeline starts there, and so does what
        // is kept.
        wire.event("live", with_key("k", json!({"type": "timeline", "start": 9, "entries": ["z"], "usage": {}})));
        host.settle().await;
        assert_eq!((live_of(&sink, "k")["first"].clone(), live_of(&sink, "k")["timeline"].clone()), (json!(9), json!(["z"])));
        let (reloaded, again, other) = reopened(&host);
        other.start(&live("k"));
        host.settle().await;
        assert_eq!((live_of(&reloaded, "k")["first"].clone(), live_of(&reloaded, "k")["timeline"].clone()), (json!(9), json!(["z"])));
        assert!(again.paths().contains(&"GET /admin/api/events?live=k&from=10&last=200".to_string()), "{:?}", again.paths());
    });
}

#[test]
fn a_transcript_shows_its_latest_page_and_the_ones_before_as_asked() {
    run(async {
        let (host, sink, wire, stations) = setup();
        let entries = |from: u64, to: u64| (from..=to).map(|i| json!(format!("e{i}"))).collect::<Vec<_>>();
        stations.start(&live("k"));
        host.settle().await;
        wire.event("live", with_key("k", json!({"type": "timeline", "start": 300, "entries": entries(300, 499), "usage": {}})));
        host.settle().await;
        assert_eq!(live_of(&sink, "k")["first"], 300);
        // From the station, and kept.
        wire.answer("GET /admin/api/sessions/k/timeline?before=300&limit=200", 200, json!({"start": 100, "entries": entries(100, 299)}));
        assert!(stations.history_older(&remote(), "k").await.unwrap());
        let v = live_of(&sink, "k");
        assert_eq!((v["first"].clone(), v["timeline"].as_array().unwrap().len(), v["timeline"][0].clone()), (json!(100), 400, json!("e100")));
        wire.answer("GET /admin/api/sessions/k/timeline?before=100&limit=200", 200, json!({"start": 0, "entries": entries(0, 99)}));
        assert!(!stations.history_older(&remote(), "k").await.unwrap());
        assert_eq!(live_of(&sink, "k")["first"], 0);
        assert!(!stations.history_older(&remote(), "k").await.unwrap());
        host.settle().await;
        // Opened again: the latest page from the device, the one before it from the device too.
        let (reloaded, again, other) = reopened(&host);
        other.start(&live("k"));
        host.settle().await;
        assert_eq!((live_of(&reloaded, "k")["first"].clone(), live_of(&reloaded, "k")["timeline"][0].clone()), (json!(300), json!("e300")));
        assert!(again.paths().contains(&"GET /admin/api/events?live=k&from=500&last=200".to_string()), "{:?}", again.paths());
        assert!(other.history_older(&remote(), "k").await.unwrap());
        assert_eq!(live_of(&reloaded, "k")["first"], 100);
        assert!(!again.paths().iter().any(|p| p.contains("/timeline")), "{:?}", again.paths());
    });
}

#[test]
fn a_stream_silent_past_its_keepalive_is_read_again() {
    run(async {
        let (host, _sink, wire, stations) = setup();
        // Timers 100 times faster: 40 s of silence is 0.4 s here.
        host.speed_up(100);
        let wait = |ms: u64| wait(ms / 100);
        stations.start(&live("k"));
        host.settle().await;
        assert_eq!(wire.count("GET", "/admin/api/events?live=k&from=0&last=200"), 1);
        // The keepalive keeps it open.
        wait(STREAM_IDLE_MS / 2).await;
        wire.push("/admin/api/events", ": ping\n\n");
        wait(STREAM_IDLE_MS / 2 + 5_000).await;
        assert_eq!(wire.count("GET", "/admin/api/events?live=k&from=0&last=200"), 1);
        // Nothing at all for longer: the link is taken for gone, and it is asked for again.
        wait(STREAM_IDLE_MS + RECONNECT_MS + 5_000).await;
        assert_eq!(wire.count("GET", "/admin/api/events?live=k&from=0&last=200"), 2);
    });
}

#[test]
fn a_stream_replaced_after_it_went_quiet_reads_again_what_it_may_have_missed() {
    run(async {
        let (host, sink, wire, stations) = setup();
        wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 12, 12, 0)]));
        wire.answer("GET /admin/api/threads/7/entries?limit=50", 200, json!({"last": 12, "entries": [entry(11, "a"), entry(12, "b")]}));
        stations.start(&threads());
        stations.start(&thread(7));
        host.settle().await;
        assert_eq!(numbers(&sink, 7), vec![11, 12]);
        // Opened for something more while its stream is heard from: nothing is read again.
        let lists = wire.count("GET", "/admin/api/threads");
        stations.start(&host_topic());
        host.settle().await;
        assert_eq!(wire.count("GET", "/admin/api/threads"), lists);
        // The app away for a minute: its stream died unnoticed, and 13 was said meanwhile (its event never came).
        wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 13, 12, 1)]));
        wire.answer("GET /admin/api/threads/7/entries?after=12", 200, json!({"last": 13, "entries": [entry(13, "c")]}));
        host.advance(60_000);
        // Back, a new stream opened in its place (asking for something else): what it missed is read.
        stations.stop(&host_topic());
        host.settle().await;
        assert_eq!(numbers(&sink, 7), vec![11, 12, 13]);
        assert_eq!(sink.get(&threads()).unwrap()[0]["last"], 13);
    });
}

#[test]
fn a_preview_socket_nothing_answers_fails_in_time() {
    run(async {
        let (host, _sink, _wire, stations) = setup();
        host.speed_up(100);
        let opened = stations.preview_socket(&remote(), 5180, "/", vec![]).await;
        assert_eq!(opened.err().map(|e| e.code).as_deref(), Some("timeout"));
        assert!(host.sleeps.borrow().contains(&SOCKET_OPEN_MS));
    });
}

#[test]
fn live_steps_and_phase() {
    run(async {
        let (host, sink, wire, stations) = setup();
        stations.start(&live("k"));
        host.settle().await;
        let push = |v: Value| wire.event("live", with_key("k", v));
        let now = host.now_ms();
        push(json!({"type": "steps", "steps": [{"id": "s0", "step": "text", "input": "", "startedAt": 1}], "phase": {"phase": "thinking", "elapsedMs": 5000}}));
        host.settle().await;
        let v = live_of(&sink, "k");
        assert_eq!(v["steps"][0]["id"], "s0");
        assert_eq!(v["phase"]["phase"], "thinking");
        assert!(v["phase"]["since"].is_i64(), "a whole number of ms: clients read it as one");
        let since = v["phase"]["since"].as_f64().unwrap();
        assert!((since - (now - 5000.0)).abs() < 1000.0, "{since} vs {now}");
        push(json!({"type": "step", "event": {"kind": "start", "id": "t1", "step": "tool", "tool": "Bash", "input": "ls"}}));
        push(json!({"type": "step", "event": {"kind": "end", "id": "t1"}}));
        push(json!({"type": "step", "event": {"kind": "phase", "phase": "responding"}}));
        host.settle().await;
        let v = live_of(&sink, "k");
        let t1 = &v["steps"][1];
        // What it is, not what it wrote: the station tells turning points only.
        assert_eq!((t1["tool"].as_str(), t1["input"].as_str(), t1["ended"].as_bool()), (Some("Bash"), Some("ls"), Some(true)));
        assert!(t1.get("output").is_none() && t1.get("text").is_none());
        assert!(t1.get("subagent").is_none());
        assert_eq!(v["phase"]["phase"], "responding");
        assert!(v["phase"]["since"].as_f64().unwrap() >= now);
        // No entries: ended steps stay.
        push(json!({"type": "timeline", "start": 0, "entries": [], "usage": {}}));
        host.settle().await;
        assert_eq!(live_of(&sink, "k")["steps"].as_array().unwrap().len(), 2);
        // Entries: they recorded the ended step.
        push(json!({"type": "timeline", "start": 0, "entries": ["x"], "usage": {}}));
        host.settle().await;
        let v = live_of(&sink, "k");
        assert_eq!(v["steps"].as_array().unwrap().len(), 1);
        assert_eq!(v["steps"][0]["id"], "s0");
        // A restarted id replaces the old step.
        push(json!({"type": "step", "event": {"kind": "start", "id": "s0", "step": "text", "subagent": true, "parent": "t0"}}));
        host.settle().await;
        let v = live_of(&sink, "k");
        assert_eq!(v["steps"].as_array().unwrap().len(), 1);
        assert_eq!((v["steps"][0]["step"].as_str(), v["steps"][0]["subagent"].as_bool(), v["steps"][0]["parent"].as_str()), (Some("text"), Some(true), Some("t0")));
        push(json!({"type": "clear"}));
        host.settle().await;
        let v = live_of(&sink, "k");
        assert_eq!((v["steps"].clone(), v["phase"].clone(), v["timeline"].clone()), (json!([]), Value::Null, json!(["x"])));
    });
}

#[test]
fn a_bad_station_and_a_stations_no_are_errors_a_passing_failure_keeps_loading() {
    run(async {
        let (host, sink, wire, stations) = setup();
        let bad = Topic::Overview { station: "nope".into() };
        stations.start(&bad);
        wire.answer("GET /admin/api/sessions", 404, json!({"error": "没有"}));
        stations.start(&sessions());
        host.settle().await;
        assert_eq!(sink.values.borrow()[&bad].as_ref().unwrap_err().code, "invalid_params");
        assert_eq!(sink.values.borrow()[&sessions()].as_ref().unwrap_err().message, "没有");
        // A failure that passes (a 502 while the link is down): no error, still loading, read again shortly.
        wire.answer("GET /admin/api/threads", 502, json!({"error": "坏了"}));
        stations.start(&threads());
        host.settle().await;
        assert!(!sink.values.borrow().contains_key(&threads()), "loading, not an error");
        wire.answer("GET /admin/api/threads", 200, json!([]));
        wait(RETRY_MS + 50).await;
        host.settle().await;
        assert_eq!(sink.values.borrow()[&threads()].as_ref().unwrap(), &json!([]));
    });
}

#[test]
fn socket_frames_are_taken_whole_however_they_come_apart() {
    let frames = [SocketFrame::Text("héllo".into()), SocketFrame::Binary(vec![0, 255]), SocketFrame::Close(4001, "done".into())];
    let bytes: Vec<u8> = frames.iter().flat_map(SocketFrame::encode).collect();
    assert_eq!(&bytes[..5], &[1, 0, 0, 0, 6], "kind, then the length big-endian");
    // One byte at a time: each frame once it is all there, nothing before.
    let (mut buf, mut got) = (Vec::new(), Vec::new());
    for b in &bytes {
        buf.push(*b);
        got.extend(SocketFrame::take(&mut buf));
    }
    assert_eq!(got, frames);
    assert!(buf.is_empty());
    // All at once, with the start of another after them.
    let mut buf = [&bytes[..], &[2, 0, 0]].concat();
    assert_eq!(SocketFrame::take(&mut buf), frames);
    assert_eq!(buf, vec![2, 0, 0]);
    // A close with no code says 1005, as a WebSocket does.
    assert_eq!(SocketFrame::take(&mut vec![8, 0, 0, 0, 0]), vec![SocketFrame::Close(1005, String::new())]);
}

#[test]
fn updating_available_software_skips_installs_and_updates_station_last() {
    run(async {
        let (_, _, wire, stations) = setup();
        let items = json!([
            {"id":"station", "installed":true, "updatable":true, "newer":true},
            {"id":"claude", "installed":true, "updatable":true, "newer":true},
            {"id":"codex", "installed":false, "updatable":true, "newer":true},
            {"id":"manual", "installed":true, "updatable":false, "newer":true}
        ]);
        wire.answer("GET /admin/api/overview", 200, json!({"updates":items}));
        wire.answer("POST /admin/api/updates", 200, items);
        let op = crate::ops::request("software.updateAll", &json!({"station":ST})).unwrap().unwrap();
        stations.perform(&remote(), &op).await.unwrap();
        let ids: Vec<Value> = wire.calls.borrow().iter().filter(|(_, m, p, _)| m == "POST" && p == "/admin/api/updates")
            .map(|(_, _, _, body)| serde_json::from_slice::<Value>(body).unwrap()["id"].clone()).collect();
        assert_eq!(ids, vec![json!("claude"), json!("station")]);
        assert_eq!(wire.count("POST", "/admin/api/updates/all"), 0, "batch remains compatible with the existing station API");
    });
}

#[test]
fn a_failed_runtime_stops_the_batch_before_station_restarts() {
    run(async {
        let (_, _, wire, stations) = setup();
        wire.answer("GET /admin/api/overview", 200, json!({"updates":[
            {"id":"station", "installed":true, "updatable":true, "newer":true},
            {"id":"claude", "installed":true, "updatable":true, "newer":true}
        ]}));
        wire.answer("POST /admin/api/updates", 200, json!([{"id":"claude", "state":"failed", "message":"download failed"}]));
        let op = crate::ops::request("software.updateAll", &json!({"station":ST})).unwrap().unwrap();
        let error = stations.perform(&remote(), &op).await.unwrap_err();
        assert!(error.message.contains("download failed"));
        assert_eq!(wire.count("POST", "/admin/api/updates"), 1);
    });
}

#[test]
fn an_existing_update_is_not_started_twice_by_a_batch() {
    run(async {
        let (_, _, wire, stations) = setup();
        wire.answer("GET /admin/api/overview", 200, json!({"updates":[{"id":"codex", "state":"updating"}]}));
        let op = crate::ops::request("software.updateAll", &json!({"station":ST})).unwrap().unwrap();
        assert!(stations.perform(&remote(), &op).await.unwrap_err().message.contains("正在更新"));
        assert_eq!(wire.count("POST", "/admin/api/updates"), 0);
    });
}

#[test]
fn a_batch_waits_for_a_runtime_to_finish_before_starting_station() {
    run(async {
        let (_, _, wire, stations) = setup();
        let items = json!([
            {"id":"station", "installed":true, "updatable":true, "newer":true},
            {"id":"claude", "installed":true, "updatable":true, "newer":true}
        ]);
        wire.answer("GET /admin/api/overview", 200, json!({"updates":items}));
        wire.answer("POST /admin/api/updates", 200, json!([{"id":"claude","state":"updating"}]));
        let op = crate::ops::request("software.updateAll", &json!({"station":ST})).unwrap().unwrap();
        let finish = async {
            while wire.count("POST", "/admin/api/updates") == 0 { wait(1).await; }
            wait(10).await;
            assert_eq!(wire.count("POST", "/admin/api/updates"), 1, "station cannot restart during a runtime update");
            wire.answer("GET /admin/api/overview", 200, json!({"updates":[{"id":"claude","state":"idle"}]}));
        };
        let addr = remote();
        let (result, ()) = futures::join!(stations.perform(&addr, &op), finish);
        result.unwrap();
        assert_eq!(wire.count("POST", "/admin/api/updates"), 2);
    });
}
