use super::*;

#[test]
fn the_relays_are_the_list_or_the_one_from_before_there_were_several() {
    assert_eq!(relays_of(&json!({ "relay_url": "https://a", "relay_urls": ["https://a", "https://b"] })), Some(vec!["https://a".to_string(), "https://b".to_string()]));
    assert_eq!(relays_of(&json!({ "relay_url": "https://a" })), Some(vec!["https://a".to_string()]));
    assert_eq!(relays_of(&json!({ "relay_url": "https://a", "relay_urls": [] })), Some(vec!["https://a".to_string()]));
    assert_eq!(relays_of(&json!({})), None);
}

fn code(result: Result<Call>) -> String {
    result.unwrap_err().code
}

#[test]
fn parses_the_client_messages_of_the_protocol() {
    let call: ClientMessage = serde_json::from_value(json!({"id": 7, "call": "job.stop", "params": {"station": "ws1/st1", "id": "j1"}})).unwrap();
    assert_eq!(call, ClientMessage::Call { id: 7, call: "job.stop".into(), params: json!({"station": "ws1/st1", "id": "j1"}) });
    let bare: ClientMessage = serde_json::from_value(json!({"id": 1, "call": "auth.signOut"})).unwrap();
    assert_eq!(bare, ClientMessage::Call { id: 1, call: "auth.signOut".into(), params: Value::Null });
    let subscribe: ClientMessage = serde_json::from_value(json!({"id": 8, "subscribe": {"topic": "session", "station": "ws1/st1", "key": "k"}})).unwrap();
    let chats: ClientMessage = serde_json::from_value(json!({"id": 4, "subscribe": {"topic": "chats", "scope": "w", "mine": true}})).unwrap();
    assert_eq!(chats, ClientMessage::Subscribe { id: 4, subscribe: Topic::Chats { scope: "w".into(), mine: true, watching: false } });
    let chats: ClientMessage = serde_json::from_value(json!({"id": 4, "subscribe": {"topic": "chats", "scope": "ws"}})).unwrap();
    assert_eq!(chats, ClientMessage::Subscribe { id: 4, subscribe: Topic::Chats { scope: "ws".into(), mine: false, watching: false } });
    let chat: ClientMessage = serde_json::from_value(json!({"id": 5, "subscribe": {"topic": "chat", "station": "w/s", "thread": 7}})).unwrap();
    assert_eq!(chat, ClientMessage::Subscribe { id: 5, subscribe: Topic::Chat { station: "w/s".into(), thread: Some(7), session: None } });
    let agent: ClientMessage = serde_json::from_value(json!({"id": 6, "subscribe": {"topic": "chat", "station": "w/s", "session": "ds:C1:1.0"}})).unwrap();
    assert_eq!(agent, ClientMessage::Subscribe { id: 6, subscribe: Topic::Chat { station: "w/s".into(), thread: None, session: Some("ds:C1:1.0".into()) } });
    assert_eq!(subscribe, ClientMessage::Subscribe { id: 8, subscribe: Topic::Session { station: "ws1/st1".into(), key: "k".into() } });
    let accounts: ClientMessage = serde_json::from_value(json!({"id": 2, "subscribe": {"topic": "accounts"}})).unwrap();
    assert_eq!(accounts, ClientMessage::Subscribe { id: 2, subscribe: Topic::Accounts });
    let workspace: ClientMessage = serde_json::from_value(json!({"id": 3, "subscribe": {"topic": "workspace", "workspace": "w"}})).unwrap();
    assert_eq!(workspace, ClientMessage::Subscribe { id: 3, subscribe: Topic::Workspace { workspace: "w".into() } });
    let unsubscribe: ClientMessage = serde_json::from_value(json!({"id": 8, "unsubscribe": true})).unwrap();
    assert_eq!(unsubscribe, ClientMessage::Unsubscribe { id: 8, unsubscribe: true });
}

#[test]
fn answers_take_the_shapes_of_the_protocol() {
    assert_eq!(serde_json::to_value(answer(7, Ok(json!({"url": "u"})))).unwrap(), json!({"id": 7, "ok": {"url": "u"}}));
    assert_eq!(serde_json::to_value(answer(7, Ok(Value::Null))).unwrap(), json!({"id": 7, "ok": null}));
    let refused = CoreError::new("forbidden", "没有权限").with_status(403);
    assert_eq!(serde_json::to_value(answer(7, Err(refused))).unwrap(), json!({"id": 7, "error": {"code": "forbidden", "message": "没有权限", "status": 403}}));
    let delta = CoreMessage::Delta { id: 8, delta: crate::delta::diff(&json!({"t": [1]}), &json!({"t": [1, 2]})) };
    assert_eq!(serde_json::to_value(delta).unwrap(), json!({"id": 8, "delta": [{"path": ["t"], "append": [2]}]}));
    let local = answer(9, Err(CoreError::new("unknown_call", "没有这个调用：x")));
    assert_eq!(serde_json::to_value(local).unwrap(), json!({"id": 9, "error": {"code": "unknown_call", "message": "没有这个调用：x"}}));
}

#[test]
fn unknown_calls_are_refused() {
    assert_eq!(code(parse_call("station.delete", json!({}))), "unknown_call");
    assert_eq!(code(parse_call("", Value::Null)), "unknown_call");
}

#[test]
fn parses_each_call() {
    assert_eq!(
        parse_call("auth.begin", json!({"redirect_uri": "r", "return_to": "/", "device_name": "Mac"})).unwrap(),
        Call::AuthBegin { redirect_uri: "r".into(), return_to: "/".into(), device_name: Some("Mac".into()) }
    );
    assert_eq!(parse_call("auth.complete", json!({"query": "?code=c&state=s"})).unwrap(), Call::AuthComplete { query: "?code=c&state=s".into() });
    assert_eq!(parse_call("auth.signOut", json!({"account": "sub1"})).unwrap(), Call::SignOut { account: "sub1".into() });
    assert_eq!(
        parse_call("client.error", json!({"source": "android.decode", "message": "chat: 读不懂"})).unwrap(),
        Call::ClientError { source: "android.decode".into(), message: "chat: 读不懂".into() }
    );
    assert_eq!(
        parse_call("workspace.rename", json!({"account": "a", "workspace": "w", "name": "n"})).unwrap(),
        Call::Op(crate::ops::Request { target: crate::ops::Target::Cloud("a".into()), method: "PATCH", path: "/v1/workspaces/w".into(), body: Some(json!({"name": "n"})), fallback: None, effect: crate::ops::Effect::None })
    );
    assert_eq!(
        parse_call("job.stop", json!({"station": "ws/st", "id": "j1"})).unwrap(),
        Call::Op(crate::ops::Request { target: crate::ops::Target::Station("ws/st".into()), method: "POST", path: "/jobs/j1/stop".into(), body: None, fallback: None, effect: crate::ops::Effect::Job })
    );
    // Requests by method and path are not the UIs' to make.
    assert_eq!(code(parse_call("station.request", json!({"station": "ws/st", "method": "GET", "path": "/sessions"}))), "unknown_call");
    assert_eq!(code(parse_call("cloud.request", json!({"account": "a", "method": "GET", "path": "/v1/me"}))), "unknown_call");
    assert_eq!(
        parse_call("station.upload", json!({"station": "w/s", "name": "a.png", "bytes": "aGVsbG8="})).unwrap(),
        Call::StationUpload { station: "w/s".into(), name: "a.png".into(), bytes: b"hello".to_vec() }
    );
    assert_eq!(
        parse_call("station.file", json!({"station": "w/s", "key": "k", "name": "a.png"})).unwrap(),
        Call::StationFile { station: "w/s".into(), key: "k".into(), name: "a.png".into(), thumb: false, progress: false }
    );
    assert_eq!(
        parse_call("station.file", json!({"station": "w/s", "key": "k", "name": "a.png", "thumb": true})).unwrap(),
        Call::StationFile { station: "w/s".into(), key: "k".into(), name: "a.png".into(), thumb: true, progress: false }
    );
    assert_eq!(
        parse_call("station.file", json!({"station": "w/s", "key": "k", "name": "a.png", "progress": true})).unwrap(),
        Call::StationFile { station: "w/s".into(), key: "k".into(), name: "a.png".into(), thumb: false, progress: true }
    );
    assert_eq!(
        parse_call("chat.send", json!({"station": "w/s", "thread": 7, "text": "hi"})).unwrap(),
        Call::ChatSend { station: "w/s".into(), thread: 7, text: "hi".into(), attachments: json!([]), quotes: json!([]), client: None }
    );
    assert_eq!(
        parse_call("chat.send", json!({"station": "w/s", "thread": 7, "text": "hi", "client": "android 0.1.1123"})).unwrap(),
        Call::ChatSend { station: "w/s".into(), thread: 7, text: "hi".into(), attachments: json!([]), quotes: json!([]), client: Some("android 0.1.1123".into()) }
    );
    assert_eq!(
        parse_call("chat.retry", json!({"station": "w/s", "thread": 7, "id": "out-1"})).unwrap(),
        Call::ChatRetry { station: "w/s".into(), thread: 7, id: "out-1".into() }
    );
    assert_eq!(
        parse_call("chat.discard", json!({"station": "w/s", "thread": 7, "id": "out-1"})).unwrap(),
        Call::ChatDiscard { station: "w/s".into(), thread: 7, id: "out-1".into() }
    );
    assert_eq!(parse_call("chat.older", json!({"station": "w/s", "thread": 7})).unwrap(), Call::ChatOlder { station: "w/s".into(), thread: 7 });
    assert_eq!(parse_call("history.older", json!({"station": "w/s", "key": "ember:c-1"})).unwrap(), Call::HistoryOlder { station: "w/s".into(), key: "ember:c-1".into() });
    assert_eq!(parse_call("station.measure", json!({"station": "w/s"})).unwrap(), Call::StationMeasure { station: "w/s".into() });
    assert_eq!(parse_call("chat.read", json!({"station": "w/s", "thread": 7, "seq": 12})).unwrap(), Call::ChatRead { station: "w/s".into(), thread: 7, seq: 12 });
    // A chat is a thread: a session key does not name one.
    assert_eq!(code(parse_call("chat.send", json!({"station": "w/s", "key": "k", "text": "hi"}))), "invalid_params");
    assert_eq!(
        parse_call("chat.create", json!({"station": "w/s", "runtime": "claude", "model": "opus", "effort": ""})).unwrap(),
        Call::ChatCreate { station: "w/s".into(), ask: json!({"runtime": "claude", "model": "opus"}) }
    );
    assert_eq!(
        parse_call("chat.send", json!({"station": "w/s", "session": "new:1-1", "text": "hi"})).unwrap(),
        Call::ChatSendTo { station: "w/s".into(), session: "new:1-1".into(), text: "hi".into(), attachments: json!([]), quotes: json!([]), client: None }
    );
    assert_eq!(parse_call("chat.retry", json!({"station": "w/s", "session": "k", "id": "out-1"})).unwrap(), Call::ChatRetryIn { station: "w/s".into(), session: "k".into(), id: "out-1".into() });
    // A decision answered with an option, set aside; dismissed is the station's (ops.rs).
    assert_eq!(
        parse_call("decision.answer", json!({"station": "w/s", "thread": 7, "seq": 4, "option": " 先不改 "})).unwrap(),
        Call::DecisionAnswer { station: "w/s".into(), thread: 7, seq: 4, option: "先不改".into() }
    );
    assert_eq!(code(parse_call("decision.answer", json!({"station": "w/s", "thread": 7, "seq": 4, "option": " "}))), "invalid_params");
    assert_eq!(code(parse_call("decision.answer", json!({"station": "w/s", "thread": 7, "option": "x"}))), "invalid_params");
    assert_eq!(parse_call("decision.defer", json!({"station": "w/s", "thread": 7, "seq": 4})).unwrap(), Call::DecisionDefer { station: "w/s".into(), thread: 7, seq: 4 });
    assert_eq!(code(parse_call("decision.defer", json!({"station": "w/s", "thread": 7}))), "invalid_params");
    // A text card answered with what was written.
    assert_eq!(
        parse_call("decision.reply", json!({"station": "w/s", "thread": 7, "seq": 4, "text": " sk_test_1 "})).unwrap(),
        Call::DecisionReply { station: "w/s".into(), thread: 7, seq: 4, text: "sk_test_1".into(), attachments: json!([]), quotes: json!([]) }
    );
    assert_eq!(code(parse_call("decision.reply", json!({"station": "w/s", "thread": 7, "seq": 4, "text": "  "}))), "invalid_params");
    assert_eq!(code(parse_call("decision.reply", json!({"station": "w/s", "thread": 7, "text": "x"}))), "invalid_params");
    assert_eq!(parse_call("chat.discard", json!({"station": "w/s", "session": "k", "id": "out-1"})).unwrap(), Call::ChatDiscardIn { station: "w/s".into(), session: "k".into(), id: "out-1".into() });
}

#[test]
fn checks_params() {
    let missing = parse_call("auth.begin", json!({"redirect_uri": "r"})).unwrap_err();
    assert_eq!(missing.code, "invalid_params");
    assert!(missing.message.contains("return_to"), "{}", missing.message);
    assert_eq!(code(parse_call("auth.signOut", Value::Null)), "invalid_params");
    assert_eq!(code(parse_call("workspace.rename", json!({"account": "a", "name": "n"}))), "invalid_params");
    assert_eq!(code(parse_call("station.upload", json!({"station": "w/s", "name": "n", "bytes": "not base64!"}))), "invalid_params");
}

#[test]
fn migrate_takes_accounts_and_a_32_byte_device_key() {
    let key = BASE64.encode([7u8; 32]);
    assert_eq!(
        parse_call("migrate", json!({"accounts": [{"sub": "s"}], "device": key})).unwrap(),
        Call::Migrate { accounts: Some(json!([{"sub": "s"}])), device: Some(vec![7u8; 32]) }
    );
    assert_eq!(parse_call("migrate", json!({"accounts": null})).unwrap(), Call::Migrate { accounts: None, device: None });
    assert_eq!(parse_call("migrate", Value::Null).unwrap(), Call::Migrate { accounts: None, device: None });
    assert_eq!(code(parse_call("migrate", json!({"device": BASE64.encode([1u8; 16])}))), "invalid_params");
}

// ── still.fail cloud's events ──

use crate::accounts::{STORAGE_KEY, StoredAccount};
use crate::testing::{FakeHost, json_response, run};

/// Timers this many times faster: eviction in 0.6 s, a socket's first retry in 10 ms.
const SPEEDUP: u64 = 100;

fn now_s() -> f64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs_f64()
}

/// A core with one signed-in account whose token expires in 30 s (so every socket opens with a fresh one),
/// still.fail cloud answering `/v1/me`, the workspace and token refreshes.
async fn cloud_core() -> (Rc<FakeHost>, Core) {
    let host = FakeHost::new();
    host.speed_up(SPEEDUP);
    let account = StoredAccount { sub: "s1".into(), email: "a@x.com".into(), name: "阿一".into(), picture: String::new(), access: "stale".into(), refresh: "r0".into(), access_expires: now_s() + 30.0 };
    host.store(STORAGE_KEY, serde_json::to_vec(&vec![account]).unwrap());
    let refreshes = Cell::new(0);
    host.on_fetch(move |req| {
        let path = req.url.trim_start_matches("https://stillfail.test");
        match path {
            "/v1/me" => json_response(200, json!({"workspaces": [{"id": "ws", "name": "W"}], "invitations": [], "relay_url": "https://relay.test"})),
            "/v1/workspaces/ws" => json_response(200, json!({"id": "ws", "stations": [{"id": "st", "name": "studio", "online": false, "last_seen": 1}]})),
            "/v1/auth/sessions" => json_response(200, json!({"sessions": [{"id": "d1", "current": true}]})),
            "/v1/auth/sessions/d2" => json_response(200, json!({"ok": true})),
            "/v1/auth/refresh" => {
                refreshes.set(refreshes.get() + 1);
                json_response(200, json!({"access_token": format!("fresh-{}", refreshes.get()), "refresh_token": "r", "subject": "s1", "email": "a@x.com", "expires_at": now_s() + 30.0}))
            }
            _ => json_response(404, json!({"error": "not_found"})),
        }
    });
    let core = Core::new(host.clone()).await;
    (host, core)
}

#[test]
fn a_kept_credential_reaches_the_stations_without_ember_cloud() {
    run(async {
        let host = FakeHost::new();
        let account = StoredAccount { sub: "s1".into(), email: "a@x.com".into(), name: "阿一".into(), picture: String::new(), access: "a".into(), refresh: "r".into(), access_expires: now_s() + 3600.0 };
        host.store(STORAGE_KEY, serde_json::to_vec(&vec![account]).unwrap());
        let up = Rc::new(Cell::new(true));
        let asked = Rc::new(Cell::new(0));
        let (cloud_up, times) = (up.clone(), asked.clone());
        host.on_fetch(move |req| {
            let path = req.url.trim_start_matches("https://stillfail.test");
            if !cloud_up.get() {
                return Err(crate::host::HostError("offline".into()));
            }
            match path {
                "/v1/me" => json_response(200, json!({"workspaces": [{"id": "ws", "name": "W"}], "invitations": [], "relay_url": "https://relay.test"})),
                "/v1/workspaces/ws/credential" => {
                    times.set(times.get() + 1);
                    json_response(200, json!({"credential": format!("c{}", times.get()), "issued_at": now_s(), "expires_at": now_s() + 30.0 * 86400.0, "relay_url": "https://relay.test"}))
                }
                _ => json_response(404, json!({"error": "not_found"})),
            }
        });
        let core = Core::new(host.clone()).await;
        let inner = core.inner.clone();
        let credential = |fresh| { let inner = inner.clone(); async move { inner.credential("ws", "dev", fresh).await } };
        let kept = |c: &Credential| KeptCredential { device: "dev".into(), credential: c.clone() };
        // Asked for once, then kept for the day.
        assert_eq!(credential(false).await.unwrap().credential, "c1");
        assert_eq!(credential(false).await.unwrap().credential, "c1");
        assert_eq!(asked.get(), 1);
        // A station refused it: a new one.
        assert_eq!(credential(true).await.unwrap().credential, "c2");
        // A day old, with still.fail cloud unreachable: the kept one serves on.
        let old = Credential { credential: "old".into(), issued_at: now_s() - 2.0 * 86400.0, expires_at: now_s() + 28.0 * 86400.0, relay_url: "https://relay.test".into() };
        host.store(&format!("{CREDENTIAL_KEY}/s1/ws"), serde_json::to_vec(&kept(&old)).unwrap());
        up.set(false);
        assert_eq!(credential(false).await.unwrap().credential, "old");
        // Refused, or run out, and no still.fail cloud: none.
        assert!(credential(true).await.is_err());
        let spent = Credential { expires_at: now_s() - 1.0, ..old.clone() };
        host.store(&format!("{CREDENTIAL_KEY}/s1/ws"), serde_json::to_vec(&kept(&spent)).unwrap());
        assert!(credential(false).await.is_err());
        // A day old, still.fail cloud back: a new one.
        host.store(&format!("{CREDENTIAL_KEY}/s1/ws"), serde_json::to_vec(&kept(&old)).unwrap());
        up.set(true);
        assert_eq!(credential(false).await.unwrap().credential, "c3");
        // One for another device key (the page's taken over): a new one.
        host.store(&format!("{CREDENTIAL_KEY}/s1/ws"), serde_json::to_vec(&KeptCredential { device: "other".into(), credential: old.clone() }).unwrap());
        assert_eq!(credential(false).await.unwrap().credential, "c4");
        // Signed out: it goes.
        inner.accounts.sign_out("s1").await.unwrap();
        pass(10).await;
        assert_eq!(host.stored(&format!("{CREDENTIAL_KEY}/s1/ws")), None);
    });
}

fn count(host: &FakeHost, path: &str) -> usize {
    host.requests.borrow().iter().filter(|r| r.url.ends_with(path) && r.method == "GET").count()
}

/// The value subscription `id` has now, deltas applied.
fn apply(host: &FakeHost, values: &mut HashMap<RequestId, Value>) {
    for (_, message) in host.take_emitted() {
        match message {
            CoreMessage::Value { id, value } => {
                values.insert(id, value);
            }
            CoreMessage::Delta { id, delta } => crate::delta::apply(values.get_mut(&id).expect("a delta needs a value"), &delta),
            _ => {}
        }
    }
}

async fn pass(ms: u64) {
    tokio::time::sleep(std::time::Duration::from_micros(ms * 1000 / SPEEDUP)).await;
    for _ in 0..10 {
        tokio::task::yield_now().await;
    }
}

#[test]
fn an_accounts_devices_are_a_topic_read_again_after_a_write() {
    run(async {
        let (host, core) = cloud_core().await;
        let ui = core.connect();
        let mut values = HashMap::new();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::LoginSessions { account: "s1".into() } });
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!(values[&1], json!([{"id": "d1", "current": true}]));
        let before = count(&host, "/v1/auth/sessions");
        // Signing a device out, through the core: the list is read again, nobody asks for it.
        core.receive(ui, ClientMessage::Call { id: 2, call: "loginSession.revoke".into(), params: json!({"account": "s1", "id": "d2"}) });
        host.settle().await;
        assert_eq!(count(&host, "/v1/auth/sessions"), before + 1);
    });
}

#[test]
fn what_a_person_does_is_under_way_until_it_answers_and_reads_are_not() {
    run(async {
        let (host, core) = cloud_core().await;
        let ui = core.connect();
        let mut values = HashMap::new();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Doing });
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!(values[&1], json!({ "doing": [] }));
        core.receive(ui, ClientMessage::Call { id: 2, call: "loginSession.revoke".into(), params: json!({"account": "s1", "id": "d2"}) });
        core.receive(ui, ClientMessage::Call { id: 3, call: "admin.me".into(), params: json!({"account": "s1"}) });
        let doing = core.inner.doing.value(&|_| false);
        assert_eq!(doing["doing"].as_array().map(Vec::len), Some(1));
        assert_eq!(doing["doing"][0]["call"], "loginSession.revoke");
        assert_eq!(doing["doing"][0]["params"], json!({"account": "s1", "id": "d2"}));
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!(values[&1], json!({ "doing": [] }));
    });
}

#[test]
fn what_was_known_shows_after_a_restart_with_no_network() {
    run(async {
        let (host, core) = cloud_core().await;
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Workspaces });
        core.receive(ui, ClientMessage::Subscribe { id: 2, subscribe: Topic::Workspace { workspace: "ws".into() } });
        host.settle().await;
        drop(core);
        host.take_emitted();
        // Started again, offline.
        host.on_fetch(|_| json_response(503, json!({"error": "unavailable"})));
        let core = Core::new(host.clone()).await;
        let ui = core.connect();
        let mut values = HashMap::new();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Workspaces });
        core.receive(ui, ClientMessage::Subscribe { id: 2, subscribe: Topic::Workspace { workspace: "ws".into() } });
        core.receive(ui, ClientMessage::Subscribe { id: 3, subscribe: Topic::Chats { scope: "ws".into(), mine: false, watching: false } });
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!(values[&1][0]["workspaces"][0]["id"], "ws");
        // Kept, not confirmed: a UI does not take it for "no workspace yet".
        assert_eq!(values[&1][0]["loaded"], false);
        assert_eq!(values[&2]["stations"][0]["id"], "st");
        // Whose workspace it is is known from what was kept, before any answer.
        assert_eq!(values[&3]["me"]["email"], "a@x.com");
    });
}

#[test]
fn account_topics_follow_the_cloud_socket() {
    run(async {
        let (host, core) = cloud_core().await;
        let ui = core.connect();
        let mut values = HashMap::new();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Workspaces });
        core.receive(ui, ClientMessage::Subscribe { id: 2, subscribe: Topic::Workspace { workspace: "ws".into() } });
        host.settle().await;
        // One socket, the token as a subprotocol (refreshed first: it was about to expire).
        let sockets: Vec<(String, Vec<String>)> = host.sockets.borrow().iter().map(|(u, p, _)| (u.clone(), p.clone())).collect();
        assert_eq!(sockets, vec![("wss://stillfail.test/v1/events".to_string(), vec!["stillfail-events".to_string(), "stillfail-token.fresh-1".to_string()])]);
        // Read once, when the socket opened.
        assert_eq!((count(&host, "/v1/me"), count(&host, "/v1/workspaces/ws")), (1, 1));
        apply(&host, &mut values);
        assert_eq!(values[&1][0]["workspaces"][0]["id"], "ws");
        assert_eq!(values[&1][0]["loaded"], true);
        assert_eq!(values[&2]["stations"][0]["id"], "st");
        pass(crate::store::EVICT_AFTER_MS * 5 / 4).await;
        assert_eq!(host.open_sockets("/v1/events"), 1);
    });
}

#[test]
fn two_workspaces_are_kept_apart() {
    run(async {
        let host = FakeHost::new();
        host.speed_up(SPEEDUP);
        // Two accounts, each reaching a workspace of one station.
        let account = |sub: &str, access: &str| StoredAccount { sub: sub.into(), email: format!("{sub}@x.com"), name: sub.into(), picture: String::new(), access: access.into(), refresh: "r".into(), access_expires: now_s() + 3600.0 };
        host.store(STORAGE_KEY, serde_json::to_vec(&vec![account("s1", "a1"), account("s2", "a2")]).unwrap());
        let w1_stations = Rc::new(Cell::new(true));
        let listed = w1_stations.clone();
        host.on_fetch(move |req| {
            let path = req.url.trim_start_matches("https://stillfail.test");
            let of_s1 = req.headers.iter().any(|(k, v)| k == "authorization" && v == "Bearer a1");
            match path {
                "/v1/me" => json_response(200, json!({"workspaces": [{"id": if of_s1 { "w1" } else { "w2" }, "name": "W"}], "invitations": [], "relay_url": "https://relay.test"})),
                "/v1/workspaces/w1" => json_response(200, json!({"id": "w1", "stations": if listed.get() { json!([{"id": "a", "name": "一号", "online": false}]) } else { json!([]) }})),
                "/v1/workspaces/w2" => json_response(200, json!({"id": "w2", "stations": [{"id": "b", "name": "二号", "online": false}]})),
                _ => json_response(404, json!({"error": "not_found"})),
            }
        });
        let core = Core::new(host.clone()).await;
        let inner = core.inner.clone();
        let ui = core.connect();
        let mut values = HashMap::new();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Workspace { workspace: "w1".into() } });
        core.receive(ui, ClientMessage::Subscribe { id: 2, subscribe: Topic::Workspace { workspace: "w2".into() } });
        host.settle().await;
        assert_eq!((inner.workspaces.owner("w1").as_deref(), inner.workspaces.owner("w2").as_deref()), (Some("s1"), Some("s2")));
        for station in ["w1/a", "w2/b"] {
            inner.data.put("overview", station, json!({ "profiles": [] }));
        }
        // A station slow in W1: W1's status and the plain one say so, W2's does not.
        let _slow = inner.workspaces.of("w1").status.begin(Place::Station("w1/a".into()), "读取对话", false);
        inner.workspaces.of("w1").status.skip(3_000.0);
        for (id, workspace) in [(3, Some("w1")), (4, Some("w2")), (5, None)] {
            core.receive(ui, ClientMessage::Subscribe { id, subscribe: Topic::Status { workspace: workspace.map(str::to_string) } });
        }
        host.settle().await;
        apply(&host, &mut values);
        assert!(values[&3]["text"].as_str().is_some_and(|t| t.starts_with("一号 读取对话 · 3 秒")), "{}", values[&3]);
        assert_eq!(values[&4]["state"], Value::Null, "{}", values[&4]);
        assert_eq!(values[&5]["items"].as_array().map(Vec::len), Some(1));
        // What a new chat was last started on: each workspace's own.
        call(&host, &core, ui, 6, "newChat.pick", json!({ "scope": "w1", "station": "a" })).await.unwrap();
        core.receive(ui, ClientMessage::Subscribe { id: 7, subscribe: Topic::NewChat { scope: "w1".into() } });
        core.receive(ui, ClientMessage::Subscribe { id: 8, subscribe: Topic::NewChat { scope: "w2".into() } });
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!((values[&7]["kept"].as_str(), values[&8]["kept"].as_str()), (Some("a"), Some("")));
        // W1 read again without its station: what was kept of it goes, W2's stays.
        w1_stations.set(false);
        inner.refresh(&Topic::Workspace { workspace: "w1".into() }).await;
        host.settle().await;
        assert!(inner.data.record("overview", "w1/a").is_none());
        assert!(inner.data.record("overview", "w2/b").is_some());
        // W1's account signs out: W1 is no one's, W2 is as it was.
        inner.accounts.sign_out("s1").await.unwrap();
        pass(10).await;
        assert_eq!((inner.workspaces.owner("w1"), inner.workspaces.owner("w2").as_deref()), (None, Some("s2")));
        assert!(inner.data.record("overview", "w2/b").is_some());
    });
}

#[test]
fn a_chats_connection_says_only_what_is_of_its_workspace() {
    run(async {
        let (host, core) = station_core(0.0).await;
        let inner = core.inner.clone();
        let ui = core.connect();
        let mut values = HashMap::new();
        let settle = || async {
            host.settle().await;
            host.settle().await;
        };
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Connection { station: "ws/st".into() } });
        settle().await;
        apply(&host, &mut values);
        assert_eq!(values[&1], json!({ "items": [] }));
        // Slow in another workspace: nothing of it here.
        let other = inner.workspaces.of("w9");
        let _there = other.status.begin(Place::Station("w9/s".into()), "读取对话", false);
        other.status.skip(3_000.0);
        other.status.changed();
        settle().await;
        apply(&host, &mut values);
        assert_eq!(values[&1], json!({ "items": [] }));
        // Slow here: said at once (it has lasted a while), then 已连上 a moment once over.
        let ws = inner.workspaces.of("ws");
        let here = ws.status.begin(Place::Station("ws/st".into()), "读取对话", false);
        ws.status.skip(3_000.0);
        ws.status.changed();
        settle().await;
        apply(&host, &mut values);
        assert_eq!(values[&1]["tone"], "busy");
        assert!(values[&1]["text"].as_str().is_some_and(|t| t.starts_with("studio 读取对话 · 3 秒")), "{}", values[&1]);
        drop(here);
        settle().await;
        apply(&host, &mut values);
        assert_eq!((values[&1]["tone"].as_str(), values[&1]["text"].as_str()), (Some("back"), Some("已连上")));
    });
}

#[test]
fn a_refused_socket_still_reads_the_topics_and_retries_with_backoff() {
    run(async {
        let (host, core) = cloud_core().await;
        host.refuse_sockets.set(true);
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Workspaces });
        host.settle().await;
        assert_eq!(count(&host, "/v1/me"), 1, "read although the socket did not open");
        pass(SOCKET_RETRY_MS * 7).await;
        // 1 s, 2 s, 4 s: waits double (among the station's own retries, which go on beside it).
        let waits: Vec<u64> = host.sleeps.borrow().clone();
        let mut doubling = [1_000u64, 2_000, 4_000].into_iter().peekable();
        for wait in &waits {
            if doubling.peek() == Some(wait) {
                doubling.next();
            }
        }
        assert!(doubling.peek().is_none(), "{waits:?}");
        assert_eq!(count(&host, "/v1/me"), 1, "failed retries read nothing");
        host.refuse_sockets.set(false);
        pass(SOCKET_RETRY_MS * 10).await;
        host.settle().await;
        assert_eq!(host.open_sockets("/v1/events"), 1);
        assert_eq!(count(&host, "/v1/me"), 2, "read again once it opened");
    });
}

#[test]
fn back_after_being_away_a_socket_waiting_to_retry_tries_at_once() {
    run(async {
        let (host, core) = cloud_core().await;
        host.refuse_sockets.set(true);
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Workspaces });
        host.settle().await;
        // Refused for a while: the next try is 32 s away.
        pass(SOCKET_RETRY_MS * 40).await;
        host.refuse_sockets.set(false);
        assert_eq!(host.open_sockets("/v1/events"), 0);
        host.take_emitted();
        core.receive(ui, ClientMessage::Call { id: 9, call: "client.wake".into(), params: json!({ "away": 60_000 }) });
        pass(0).await;
        assert_eq!(host.open_sockets("/v1/events"), 1);
        // Answered, so the page knows the core is there.
        assert!(host.take_emitted().iter().any(|(_, m)| *m == CoreMessage::Ok { id: 9, ok: json!({}) }));
    });
}

#[test]
fn a_socket_that_answered_pings_and_went_silent_is_opened_again() {
    run(async {
        let (host, core) = cloud_core().await;
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Workspaces });
        host.settle().await;
        let opened = host.sockets.borrow().len();
        assert_eq!(host.open_sockets("/v1/events"), 1);
        // Never a pong (a cloud from before them): silence is how it is.
        pass(SOCKET_IDLE_MS * 2).await;
        assert_eq!(host.sockets.borrow().len(), opened);
        host.socket_send("/v1/events", "pong");
        pass(SOCKET_IDLE_MS / 2).await;
        assert_eq!(host.sockets.borrow().len(), opened, "answered a while ago: still there");
        pass(SOCKET_IDLE_MS).await;
        assert_eq!(host.sockets.borrow().len(), opened + 1, "silent past its pings: opened again");
        assert_eq!(host.open_sockets("/v1/events"), 1);
    });
}

#[test]
fn a_beta_app_says_so_and_an_account_not_let_in_is_blocked() {
    run(async {
        let host = FakeHost::new();
        host.speed_up(SPEEDUP);
        host.beta.set(true);
        let account = StoredAccount { sub: "s1".into(), email: "a@x.com".into(), name: "阿一".into(), picture: String::new(), access: "a".into(), refresh: "r".into(), access_expires: now_s() + 3600.0 };
        host.store(STORAGE_KEY, serde_json::to_vec(&vec![account]).unwrap());
        let beta = Rc::new(Cell::new(false));
        let let_in = beta.clone();
        host.on_fetch(move |req| {
            let release = |code: i64| json!({ "versionCode": code, "versionName": format!("0.1.{code}"), "file": format!("android/stillfail-{code}.apk"), "sha256": "ab", "size": 9 });
            let says_beta = req.headers.iter().any(|(k, v)| k == "x-stillfail-channel" && v == "beta");
            match req.url.trim_start_matches("https://stillfail.test") {
                // As still.fail cloud gates a beta app's calls.
                "/v1/me" if says_beta && !let_in.get() => json_response(403, json!({ "error": "not_beta" })),
                "/v1/me" => json_response(200, json!({ "user": { "sub": "s1", "beta": let_in.get() }, "workspaces": [{ "id": "ws", "name": "W" }], "invitations": [], "relay_url": "https://relay.test" })),
                "/releases/android/latest.json" => json_response(200, release(1200)),
                "/releases/android/beta/latest.json" => json_response(200, release(1250)),
                _ => json_response(404, json!({ "error": "not_found" })),
            }
        });
        let core = Core::new(host.clone()).await;
        let ui = core.connect();
        let mut values: HashMap<RequestId, Value> = HashMap::new();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Workspaces });
        host.settle().await;
        apply(&host, &mut values);
        let entry = &values[&1][0];
        assert_eq!((entry["blocked"].as_str(), entry["error"]["code"].as_str(), entry["workspaces"].as_array().map(Vec::len)), (Some("这个账号还没开通测试版"), Some("not_beta"), Some(0)));
        assert!(host.requests.borrow().iter().filter(|r| r.url.contains("/v1/")).all(|r| r.headers.iter().any(|(k, _)| k == "x-stillfail-channel")));
        // Let in: its workspaces, marked as let in, nothing blocked.
        beta.set(true);
        host.socket_send("/v1/events", r#"{"type":"workspaces"}"#);
        host.settle().await;
        apply(&host, &mut values);
        let entry = &values[&1][0];
        assert_eq!((entry["beta"].as_bool(), entry.get("blocked"), entry["workspaces"][0]["id"].as_str()), (Some(true), None, Some("ws")));
        // Its newer builds are the beta feed's.
        core.receive(ui, ClientMessage::Call { id: 2, call: "app.update".into(), params: json!({ "platform": "android", "versionCode": 1100 }) });
        host.settle().await;
        let answer = host.take_emitted().into_iter().find_map(|(_, m)| match m { CoreMessage::Ok { id: 2, ok } => Some(ok), _ => None }).expect("answered");
        assert_eq!(answer["versionCode"], 1250);
    });
}

#[test]
fn a_released_app_says_nothing_of_a_channel() {
    run(async {
        let (host, core) = cloud_core().await;
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Workspaces });
        host.settle().await;
        assert!(count(&host, "/v1/me") > 0);
        assert!(host.requests.borrow().iter().all(|r| r.headers.iter().all(|(k, _)| k != "x-stillfail-channel")));
        let mut values = HashMap::new();
        apply(&host, &mut values);
        assert_eq!((values[&1][0].get("beta"), values[&1][0].get("blocked")), (None, None));
    });
}

#[test]
fn the_network_changing_opens_the_socket_again_at_once() {
    run(async {
        let (host, core) = cloud_core().await;
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Workspaces });
        host.settle().await;
        let opened = host.sockets.borrow().len();
        host.socket_send("/v1/events", "pong");
        pass(0).await;
        core.receive(ui, ClientMessage::Call { id: 9, call: "client.wake".into(), params: json!({ "away": 0, "network": true }) });
        pass(0).await;
        assert_eq!(host.sockets.borrow().len(), opened + 1);
        assert_eq!(host.open_sockets("/v1/events"), 1);
        assert_eq!(host.resets.get(), 1, "the host let its connections go");
    });
}

/// A session as the station lists it.
fn session(key: &str) -> Value {
    json!({
        "key": key, "connect": "ember", "scope": "thread", "title": null, "createdBy": null, "boundTo": [], "creator": null,
        "participants": [], "runtime": "claude", "profile": "p1", "profilePinned": false, "model": null, "effort": null,
        "runtimeSessionId": null, "workspace": "/w", "running": false, "createdAt": 1, "lastActiveAt": 1, "archivedAt": null,
        "process": "cold", "turns": 0, "pending": 0, "firstText": null, "lastTurn": null,
    })
}

/// Signs `host` in as one account, whose workspace `ws` has one station, `st`.
fn sign_in(host: &FakeHost) {
    let account = StoredAccount { sub: "s1".into(), email: "a@x.com".into(), name: String::new(), picture: String::new(), access: "tok".into(), refresh: "r0".into(), access_expires: now_s() + 3600.0 };
    host.store(STORAGE_KEY, serde_json::to_vec(&vec![account]).unwrap());
}

/// Answers still.fail cloud as [`sign_in`] has it, and the station's admin API (the rest) with `station`.
fn station_answers(host: &FakeHost, station: impl Fn(&crate::host::HttpRequest) -> std::result::Result<crate::host::HttpResponse, crate::host::HostError> + 'static) {
    host.on_fetch(move |req| match req.url.trim_start_matches("https://stillfail.test") {
        "/v1/me" => json_response(200, json!({"workspaces": [{"id": "ws", "name": "W"}], "invitations": [], "relay_url": "https://relay.test"})),
        "/v1/workspaces/ws" => json_response(200, json!({"id": "ws", "stations": [{"id": "st", "name": "studio", "last_seen": null}]})),
        _ => station(req),
    });
}

/// A core on `host` whose stations answer over its fetch, at `<origin>/admin/api/…` (testing::HostWire).
async fn over_fetch(host: &Rc<FakeHost>, sample: f64) -> Core {
    Core::with_wire(host.clone(), sample, |host| crate::testing::HostWire::new(host)).await
}

/// A core [signed in](sign_in), whose station `ws/st` has chat 7 with one agent; `sample` of its traces recorded.
/// Its timers run at their real pace.
async fn station_core(sample: f64) -> (Rc<FakeHost>, Core) {
    let host = FakeHost::new();
    sign_in(&host);
    station_answers(&host, |req| {
        let path = req.url.trim_start_matches("https://stillfail.test");
        match path.split('?').next().unwrap() {
            "/admin/api/threads" => json_response(200, json!([{
                "id": 7, "surface": "ember", "channel": "EMBER", "channelName": null, "threadTs": "7.0", "title": null, "createdBy": null,
                "creator": null, "createdAt": 1, "sessions": [{ "thread": 7, "session": "k1", "connect": "ember", "joinedAt": 1 }],
                "last": 0, "lastMessage": null, "read": 0, "unread": 0, "people": [], "firstText": null,
            }])),
            "/admin/api/threads/7/entries" => json_response(200, json!({ "last": 0, "entries": [] })),
            "/admin/api/sessions" => json_response(200, json!([session("k1")])),
            "/admin/api/sessions/k1" => json_response(200, json!({ "session": session("k1"), "threads": [], "turns": [] })),
            "/admin/api/overview" => json_response(200, json!({
                "viewer": { "via": "local" }, "connects": [], "profiles": [], "processes": [], "counts": { "sessions": 1, "running": 0, "warm": 0 },
                "mesh": null, "slackUsers": [], "slackTeams": [], "slackApps": [], "disk": null, "logins": [],
            })),
            "/admin/api/memory" => json_response(200, json!({ "global": "" })),
            "/v1/telemetry/traces" => json_response(202, json!({})),
            _ => json_response(404, json!({})),
        }
    });
    host.on_fetch_stream(|_| Ok(crate::host::StreamResponse { status: 200, headers: vec![], body: futures::stream::pending().boxed_local() }));
    let core = over_fetch(&host, sample).await;
    (host, core)
}

fn header(request: &crate::host::HttpRequest, name: &str) -> Option<String> {
    request.headers.iter().find(|(k, _)| k == name).map(|(_, v)| v.clone())
}

fn exports(host: &FakeHost) -> Vec<crate::host::HttpRequest> {
    host.requests.borrow().iter().filter(|r| r.url.ends_with("/v1/telemetry/traces")).cloned().collect()
}

#[test]
fn a_streamed_preview_hands_its_answer_on_as_it_comes_until_cancelled_or_its_page_goes() {
    run(async {
        let (host, core) = station_core(0.0).await;
        // The service's answer: open, its body coming as it is sent here.
        type Body = futures::channel::mpsc::UnboundedSender<std::result::Result<Vec<u8>, crate::host::HostError>>;
        let bodies: Rc<RefCell<Vec<Body>>> = Rc::default();
        let opened = bodies.clone();
        host.on_fetch_stream(move |req| {
            // The station's own event stream, read beside it: open, and nothing on it.
            if !req.url.contains("/preview/") {
                return Ok(crate::host::StreamResponse { status: 200, headers: vec![], body: futures::stream::pending().boxed_local() });
            }
            let (tx, rx) = futures::channel::mpsc::unbounded();
            opened.borrow_mut().push(tx);
            Ok(crate::host::StreamResponse { status: 200, headers: vec![("content-type".into(), "text/event-stream".into())], body: rx.boxed_local() })
        });
        let ui = core.connect();
        let preview = |id| ClientMessage::Call { id, call: "station.preview".into(), params: json!({ "station": "ws/st", "port": 5180, "method": "GET", "path": "/events", "stream": true }) };
        core.receive(ui, preview(1));
        host.settle().await;
        let asked = host.requests.borrow().iter().rev().find(|r| r.url.contains("/preview/")).cloned().unwrap();
        assert_eq!(asked.url, "https://stillfail.test/admin/api/preview/5180/events");
        let values = |host: &FakeHost| host.take_emitted().into_iter().map(|(_, m)| serde_json::to_value(m).unwrap()).collect::<Vec<_>>();
        assert_eq!(values(&host), vec![json!({ "id": 1, "value": { "head": { "status": 200, "headers": [["content-type", "text/event-stream"]] } } })]);
        let load = Topic::PreviewLoad { station: "ws/st".into(), port: 5180 };
        assert_eq!(core.inner.workspaces.of_station("ws/st").preview_load.value(&load)["percent"], 100);
        // Nothing is said to be waited on once its head came, however long its body goes on.
        core.inner.status.skip(3_000.0);
        assert_eq!(core.inner.status.value()["state"], Value::Null);
        bodies.borrow()[0].unbounded_send(Ok(b"data: 1\n\n".to_vec())).unwrap();
        host.settle().await;
        assert_eq!(values(&host), vec![json!({ "id": 1, "value": { "chunk": BASE64.encode(b"data: 1\n\n") } })]);
        // Cancelled: it answers so, and the body is let go (the station stops asking the service).
        core.receive(ui, ClientMessage::Cancel { id: 1, cancel: true });
        host.settle().await;
        assert_eq!(values(&host), vec![json!({ "id": 1, "error": { "code": "cancelled", "message": "已取消" } })]);
        assert!(bodies.borrow()[0].is_closed());
        // A page gone takes its calls with it.
        core.receive(ui, preview(2));
        host.settle().await;
        core.disconnect(ui);
        host.settle().await;
        assert!(bodies.borrow()[1].is_closed());
        assert!(core.inner.calls.borrow().is_empty());
        // Any other call runs to its end, cancelled or not: a write is not dropped halfway.
        let ui = core.connect();
        core.receive(ui, ClientMessage::Call { id: 3, call: "memory.get".into(), params: json!({ "station": "ws/st" }) });
        core.receive(ui, ClientMessage::Cancel { id: 3, cancel: true });
        core.disconnect(ui);
        host.settle().await;
        assert!(values(&host).iter().any(|v| v["id"] == 3 && v.get("ok").is_some()), "answered, not cancelled");
    });
}

#[test]
fn a_preview_socket_is_only_carried_by_the_mesh_and_its_messages_are_checked() {
    run(async {
        let (host, core) = station_core(0.0).await;
        let ui = core.connect();
        core.receive(ui, ClientMessage::Call { id: 1, call: "preview.socket".into(), params: json!({ "station": "ws/st", "port": 5180, "path": "/", "socket": "s1" }) });
        core.receive(ui, ClientMessage::Call { id: 2, call: "preview.socket.send".into(), params: json!({ "socket": "s1", "text": "hi" }) });
        host.settle().await;
        let answers: HashMap<u64, Value> = host.take_emitted().into_iter().map(|(_, m)| serde_json::to_value(m).unwrap()).map(|v| (v["id"].as_u64().unwrap(), v)).collect();
        assert_eq!(answers[&1]["error"]["code"], "unsupported");
        assert_eq!(answers[&2]["error"]["code"], "not_found", "no socket open by that name");
        assert!(parse_call("preview.socket.send", json!({ "socket": "s1", "text": "a", "close": [1000, ""] })).is_err());
        assert_eq!(parse_call("preview.socket.send", json!({ "socket": "s1", "close": [4001, "done"] })).unwrap(), Call::PreviewSocketSend { socket: "s1".into(), frame: station::SocketFrame::Close(4001, "done".into()) });
        assert_eq!(parse_call("preview.socket.send", json!({ "socket": "s1", "binary": BASE64.encode([0, 1]) })).unwrap(), Call::PreviewSocketSend { socket: "s1".into(), frame: station::SocketFrame::Binary(vec![0, 1]) });
    });
}

#[test]
fn a_preview_socket_closed_before_it_opens_does_not_wait_for_the_station() {
    run(async {
        let (tx, mut from_page) = futures::channel::mpsc::unbounded();
        let mut held = Vec::new();
        tx.unbounded_send(station::SocketFrame::Text("early".into())).unwrap();
        tx.unbounded_send(station::SocketFrame::Close(1001, "gone".into())).unwrap();
        // A station that never answers: the page's close ends it.
        let opened = open_unless_closed(futures::future::pending::<Result<()>>(), &mut from_page, &mut held).await.unwrap();
        assert_eq!(opened, Err((1001, "gone".to_string())));
        assert_eq!(held, vec![station::SocketFrame::Text("early".into())], "what came before is kept");
        // Open first: the open.
        assert_eq!(open_unless_closed(async { Ok(7) }, &mut from_page, &mut held).await.unwrap(), Ok(7));
    });
}

#[test]
fn a_chat_opening_is_one_trace_its_requests_carry_and_ember_cloud_gets() {
    run(async {
        let (host, core) = station_core(1.0).await;
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Chat { station: "ws/st".into(), thread: Some(7), session: None } });
        host.settle().await;
        assert!(host.take_emitted().iter().any(|(_, m)| matches!(m, CoreMessage::Value { id: 1, .. })));
        let admin: Vec<_> = host.requests.borrow().iter().filter(|r| r.url.contains("/admin/api/")).cloned().collect();
        let paths: Vec<&str> = admin.iter().map(|r| r.url.trim_start_matches("https://stillfail.test/admin/api")).collect();
        assert_eq!(paths.len(), 7, "{paths:?}");
        assert!(paths.contains(&"/chats"), "the title as the sidebar has it: {paths:?}");
        assert!(paths.contains(&"/sessions/k1"), "the agent read as the chat opens: {paths:?}");
        let parents: Vec<String> = admin.iter().map(|r| header(r, "traceparent").expect("traceparent")).collect();
        let trace = parents[0][3..35].to_string();
        assert!(parents.iter().all(|p| p[3..35] == trace && p.ends_with("-01")), "{parents:?}");
        // Spans wait to go out together.
        assert!(exports(&host).is_empty());

        pass(SPEEDUP * (trace::EXPORT_MS + 100)).await;
        let sent = exports(&host);
        assert_eq!(sent.len(), 1);
        assert_eq!(header(&sent[0], "authorization").as_deref(), Some("Bearer tok"));
        assert_eq!(header(&sent[0], "traceparent"), None, "sending spans is no trace");
        let body: Value = serde_json::from_slice(sent[0].body.as_deref().unwrap()).unwrap();
        let spans = body["resourceSpans"][0]["scopeSpans"][0]["spans"].as_array().unwrap().clone();
        let named = |name: &str| spans.iter().find(|s| s["name"] == name).unwrap_or_else(|| panic!("no {name}: {spans:?}")).clone();
        let root = named("chat.open");
        assert_eq!(root["traceId"], trace.as_str());
        assert!(root.get("parentSpanId").is_none());
        let threads = named("GET /admin/api/threads");
        assert_eq!(threads["parentSpanId"], root["spanId"]);
        assert!(parents.iter().any(|p| p[36..52] == *threads["spanId"].as_str().unwrap()), "the request carries its own span");
        assert_eq!(named("GET /admin/api/sessions/:id")["parentSpanId"], root["spanId"]);
        let connect = named("station.connect");
        assert_eq!(connect["parentSpanId"], root["spanId"]);
        assert_eq!(named("GET /admin/api/events")["parentSpanId"], connect["spanId"]);
        assert!(spans.iter().all(|s| s["traceId"] == trace.as_str()));
        let text = serde_json::to_string(&spans).unwrap();
        assert!(!text.contains("a@x.com") && !text.contains("tok"), "{text}");

        // Nothing new: nothing more is sent.
        pass(SPEEDUP * (trace::EXPORT_MS + 100)).await;
        assert_eq!(exports(&host).len(), 1);
    });
}

#[test]
fn calls_are_traces_and_nothing_goes_out_when_tracing_is_off() {
    run(async {
        let (host, core) = station_core(1.0).await;
        let ui = core.connect();
        core.receive(ui, ClientMessage::Call { id: 1, call: "memory.get".into(), params: json!({ "station": "ws/st" }) });
        host.settle().await;
        pass(SPEEDUP * (trace::EXPORT_MS + 100)).await;
        let body: Value = serde_json::from_slice(exports(&host)[0].body.as_deref().unwrap()).unwrap();
        let names: Vec<String> = body["resourceSpans"][0]["scopeSpans"][0]["spans"].as_array().unwrap().iter().map(|s| s["name"].as_str().unwrap().to_string()).collect();
        // Beside what the core reads of the station for its notices.
        assert!(names.iter().any(|n| n == "GET /admin/api/memory") && names.iter().any(|n| n == "memory.get"), "{names:?}");

        let (host, core) = station_core(0.0).await;
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Chat { station: "ws/st".into(), thread: Some(7), session: None } });
        core.receive(ui, ClientMessage::Call { id: 2, call: "memory.get".into(), params: json!({ "station": "ws/st" }) });
        host.settle().await;
        pass(SPEEDUP * (trace::EXPORT_MS + 100)).await;
        assert!(exports(&host).is_empty());
        // Stations still hear that these are not recorded.
        let parents: Vec<String> = host.requests.borrow().iter().filter_map(|r| header(r, "traceparent")).collect();
        assert!(!parents.is_empty() && parents.iter().all(|p| p.ends_with("-00")), "{parents:?}");
    });
}

#[test]
fn prefs_are_kept_on_the_device_and_moved_in_once_without_writing_over() {
    run(async {
        let (host, core) = station_core(0.0).await;
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Prefs });
        host.settle().await;
        let mut values = HashMap::new();
        apply(&host, &mut values);
        // Nothing chosen: the defaults.
        assert_eq!((values[&1]["onlyMine"].clone(), values[&1]["appearance"].clone(), values[&1]["rowPicture"].clone()), (json!(false), json!("system"), json!("auto")));
        assert_eq!(values[&1]["device"]["app"], "");
        let set = |id, params: Value| core.receive(ui, ClientMessage::Call { id, call: "prefs.set".into(), params });
        set(2, json!({ "onlyMine": true, "appearance": "dark", "lastChat": { "w1": "/w/w1/s/st/chats/k1", "ws": "/w/ws/new" }, "chatTabs": { "ws/st:t": { "tabs": ["k1"], "active": "k1" } } }));
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!((values[&1]["onlyMine"].clone(), values[&1]["appearance"].clone()), (json!(true), json!("dark")));
        assert_eq!(values[&1]["chatTabs"]["ws/st:t"], json!({ "tabs": ["k1"], "active": "k1" }));
        // The chat list shows 我参与的 or 监控中: choosing one lets go of the other.
        set(20, json!({ "onlyWatching": true }));
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!((values[&1]["onlyMine"].clone(), values[&1]["onlyWatching"].clone()), (json!(false), json!(true)));
        set(21, json!({ "onlyMine": true }));
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!((values[&1]["onlyMine"].clone(), values[&1]["onlyWatching"].clone()), (json!(true), json!(false)));
        // 奏 in the sidebar lets go of both.
        set(22, json!({ "onlyDecisions": true }));
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!((values[&1]["onlyMine"].clone(), values[&1]["onlyWatching"].clone(), values[&1]["onlyDecisions"].clone()), (json!(false), json!(false), json!(true)));
        set(23, json!({ "onlyWatching": true }));
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!((values[&1]["onlyWatching"].clone(), values[&1]["onlyDecisions"].clone()), (json!(true), json!(false)));
        set(24, json!({ "onlyMine": true }));
        host.settle().await;
        apply(&host, &mut values);
        // A map by entry: one gone, the other kept.
        set(3, json!({ "lastChat": { "ws": null } }));
        // What a device kept before, moved in: only what is not chosen here yet.
        set(4, json!({ "fill": true, "appearance": "light", "rowPicture": "people", "lastChat": { "w1": "/w/w1/s/st/chats/old", "other": "/w/other/new" } }));
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!((values[&1]["appearance"].clone(), values[&1]["rowPicture"].clone()), (json!("dark"), json!("people")));
        assert_eq!(values[&1]["lastChat"], json!({ "w1": "/w/w1/s/st/chats/k1", "other": "/w/other/new" }));
        // Not a pref, or not one of its words: refused, nothing changed.
        set(5, json!({ "appearance": "blue" }));
        set(6, json!({ "device": { "app": "web" } }));
        host.settle().await;
        let refused = host.take_emitted().into_iter().filter(|(_, m)| matches!(m, CoreMessage::Error { id: 5 | 6, .. })).count();
        assert_eq!(refused, 2);
        // The invite code a page came with, kept through signing in until a workspace is made.
        set(7, json!({ "invite": "ABCD-EFGH" }));
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!(values[&1]["invite"], "ABCD-EFGH");
        crate::prefs::invite_used(&core.inner.data);
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!(values[&1].get("invite"), None);
        core.receive(ui, ClientMessage::Call { id: 80, call: "station.updateNotice".into(), params: json!({"station":"ws/st", "action":"dismiss", "version":"stable:2"}) });
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!(values[&1]["stationUpdatesDismissed"]["ws/st"], "stable:2");
        // Kept across a restart.
        drop(core);
        let core = Core::new(host.clone()).await;
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Prefs });
        host.settle().await;
        let mut values = HashMap::new();
        apply(&host, &mut values);
        assert_eq!((values[&1]["onlyMine"].clone(), values[&1]["appearance"].clone(), values[&1]["lastChat"]["w1"].clone()), (json!(true), json!("dark"), json!("/w/w1/s/st/chats/k1")));
        assert_eq!(values[&1]["stationUpdatesDismissed"]["ws/st"], "stable:2");
        assert!(values[&1]["stationUpdatesDismissed"]["other/st"].is_null());
        // The tabs of the latest 200 chats are kept.
        for i in 0..205u64 {
            core.receive(ui, ClientMessage::Call { id: 10 + i, call: "prefs.set".into(), params: json!({ "chatTabs": { format!("ws/st:{i}"): { "tabs": [], "active": null } } }) });
            host.settle().await;
        }
        apply(&host, &mut values);
        let tabs = values[&1]["chatTabs"].as_object().unwrap();
        assert_eq!(tabs.len(), 200);
        assert!(tabs.contains_key("ws/st:204") && !tabs.contains_key("ws/st:4") && !tabs.contains_key("ws/st:t"));
    });
}

#[test]
fn a_decision_is_answered_in_its_chat_set_aside_on_the_device_and_dismissed_on_the_station() {
    run(async {
        let (host, core) = station_core(0.0).await;
        let ui = core.connect();
        let decision = json!({ "seq": 4, "options": [{ "label": "合", "recommended": true }, { "label": "先不改" }],
            "message": { "seq": 4, "ts": "9.000004", "text": "合吗？", "authorName": "Claude" }, "before": [] });
        core.inner.data.set(&Topic::ChatRows { station: "ws/st".into() }, json!([{ "id": "k1", "session": "k1", "thread": 7, "decision": decision }]));
        // Set aside: kept on the device; nothing is sent.
        core.receive(ui, ClientMessage::Call { id: 2, call: "decision.defer".into(), params: json!({ "station": "ws/st", "thread": 7, "seq": 4 }) });
        host.settle().await;
        let at = crate::decisions::deferral_key("ws/st", 7, 4);
        assert!(core.inner.data.get(&Topic::Prefs).unwrap()["decisionsDeferred"][&at].is_number());
        let posted = |host: &FakeHost| -> Vec<Value> {
            host.requests.borrow().iter().filter(|r| r.method == "POST" && r.url.ends_with("/threads/7/messages"))
                .map(|r| serde_json::from_slice(r.body.as_deref().unwrap_or_default()).unwrap()).collect()
        };
        assert!(posted(&host).is_empty());
        // Answered: the option's label, quoting the post that asked; no longer set aside.
        core.receive(ui, ClientMessage::Call { id: 3, call: "decision.answer".into(), params: json!({ "station": "ws/st", "thread": 7, "seq": 4, "option": "先不改" }) });
        host.settle().await;
        let sent = posted(&host);
        assert_eq!(sent[0]["text"], "先不改");
        assert_eq!(sent[0]["quotes"], json!([{ "author": "Claude", "text": "合吗？", "comment": "", "role": "agent", "ts": "9.000004" }]));
        assert_eq!(core.inner.data.get(&Topic::Prefs).unwrap()["decisionsDeferred"], json!({}));
        // Dismissed: the station keeps it for the viewer.
        core.receive(ui, ClientMessage::Call { id: 7, call: "decision.dismiss".into(), params: json!({ "station": "ws/st", "thread": 7, "seq": 4 }) });
        host.settle().await;
        let dismissed: Vec<Value> = host.requests.borrow().iter().filter(|r| r.method == "PUT" && r.url.ends_with("/threads/7/dismissed"))
            .map(|r| serde_json::from_slice(r.body.as_deref().unwrap_or_default()).unwrap()).collect();
        assert_eq!(dismissed, vec![json!({ "n": 4 })]);
        // An option it does not offer, or a decision no longer pending: refused.
        core.receive(ui, ClientMessage::Call { id: 4, call: "decision.answer".into(), params: json!({ "station": "ws/st", "thread": 7, "seq": 4, "option": "别的" }) });
        core.receive(ui, ClientMessage::Call { id: 5, call: "decision.answer".into(), params: json!({ "station": "ws/st", "thread": 7, "seq": 3, "option": "合" }) });
        host.settle().await;
        let refused = host.take_emitted().into_iter().filter(|(_, m)| matches!(m, CoreMessage::Error { id: 4 | 5, .. })).count();
        assert_eq!(refused, 2);
        assert_eq!(posted(&host).len(), 1);
        // Both options and text cards accept free-form replies; text cards have no choices.
        station_answers(&host, |req| {
            if req.method == "POST" && req.url.ends_with("/threads/7/messages") {
                json_response(200, json!({ "n": 7 }))
            } else {
                json_response(404, json!({}))
            }
        });
        core.inner.data.set(&Topic::ChatRows { station: "ws/st".into() }, json!([{ "id": "k1", "session": "k1", "thread": 7, "decision": decision }]));
        core.receive(ui, ClientMessage::Call { id: 8, call: "decision.reply".into(), params: json!({ "station": "ws/st", "thread": 7, "seq": 4, "text": "随便" }) });
        host.settle().await;
        let replies = host.take_emitted();
        assert!(!replies.iter().any(|(_, m)| matches!(m, CoreMessage::Error { id: 8, .. })), "{replies:?}");
        assert_eq!(posted(&host)[1]["text"], "随便");
        assert_eq!(posted(&host)[1]["quotes"][0]["ts"], "9.000004");
        // The shared chat composer can send a file alone and additional quoted passages.
        let attachments = json!([{ "name": "screen.png", "path": "uploads/screen.png", "size": 12 }]);
        let extra_quotes = json!([{ "author": "林晓", "text": "看这一处", "comment": "", "role": "person" }]);
        core.receive(ui, ClientMessage::Call { id: 12, call: "decision.reply".into(), params: json!({ "station": "ws/st", "thread": 7, "seq": 4, "text": "", "attachments": attachments, "quotes": extra_quotes }) });
        host.settle().await;
        assert_eq!(posted(&host)[2]["attachments"], attachments);
        assert_eq!(posted(&host)[2]["quotes"][0]["ts"], "9.000004");
        assert_eq!(posted(&host)[2]["quotes"][1], extra_quotes[0]);
        let card = json!({ "seq": 6, "card": { "type": "text", "placeholder": "sk_" }, "message": { "seq": 6, "ts": "9.000006", "text": "key？", "authorName": "Claude" }, "before": [] });
        core.inner.data.set(&Topic::ChatRows { station: "ws/st".into() }, json!([{ "id": "k1", "session": "k1", "thread": 7, "card": card }]));
        core.receive(ui, ClientMessage::Call { id: 9, call: "decision.answer".into(), params: json!({ "station": "ws/st", "thread": 7, "seq": 6, "option": "sk_" }) });
        core.receive(ui, ClientMessage::Call { id: 10, call: "decision.reply".into(), params: json!({ "station": "ws/st", "thread": 7, "seq": 5, "text": "sk_test_1" }) });
        host.settle().await;
        let refused = host.take_emitted().into_iter().filter(|(_, m)| matches!(m, CoreMessage::Error { id: 9 | 10, .. })).count();
        assert_eq!(refused, 2, "an option of a text card; a card no longer pending");
        core.receive(ui, ClientMessage::Call { id: 11, call: "decision.reply".into(), params: json!({ "station": "ws/st", "thread": 7, "seq": 6, "text": " sk_test_1 " }) });
        host.settle().await;
        let sent = posted(&host);
        assert_eq!(sent.len(), 4);
        assert_eq!(sent[3]["text"], "sk_test_1");
        assert_eq!(sent[3]["quotes"], json!([{ "author": "Claude", "text": "key？", "comment": "", "role": "agent", "ts": "9.000006" }]));
    });
}

#[test]
fn the_device_says_what_it_is_once_and_the_core_decides_what_follows() {
    run(async {
        let (host, core) = station_core(0.0).await;
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Prefs });
        let phone = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
        core.receive(ui, ClientMessage::Call { id: 2, call: "client.device".into(), params: json!({ "app": "web", "build": "0.1.9", "userAgent": phone }) });
        host.settle().await;
        let mut values = HashMap::new();
        apply(&host, &mut values);
        assert_eq!(values[&1]["device"], json!({ "app": "web", "phone": true, "handoff": false }));
        // A message goes with the app it is sent from, unless the UI says.
        core.receive(ui, ClientMessage::Call { id: 3, call: "chat.send".into(), params: json!({ "station": "ws/st", "thread": 7, "text": "hi" }) });
        host.settle().await;
        let sent: Vec<Value> = host.requests.borrow().iter().filter(|r| r.method == "POST" && r.url.ends_with("/threads/7/messages"))
            .map(|r| serde_json::from_slice(r.body.as_deref().unwrap_or_default()).unwrap()).collect();
        assert_eq!(sent[0]["client"], "web 0.1.9 (phone)");
        // A computer's browser: its links are offered to the desktop app first; it signs in by its browser's name.
        let mac = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36";
        core.receive(ui, ClientMessage::Call { id: 4, call: "client.device".into(), params: json!({ "app": "web", "userAgent": mac }) });
        core.receive(ui, ClientMessage::Call { id: 5, call: "auth.begin".into(), params: json!({ "redirect_uri": "r", "return_to": "/" }) });
        core.receive(ui, ClientMessage::Call { id: 6, call: "client.device".into(), params: json!({ "app": "phone" }) });
        host.settle().await;
        let emitted = host.take_emitted();
        let url = emitted.iter().find_map(|(_, m)| match m { CoreMessage::Ok { id: 5, ok } => ok["url"].as_str().map(str::to_string), _ => None }).unwrap();
        assert!(url.contains(&format!("name={}", encode("still.fail 网页版 · Chrome · macOS"))), "{url}");
        assert!(emitted.iter().any(|(_, m)| matches!(m, CoreMessage::Error { id: 6, .. })));
        core.receive(ui, ClientMessage::Unsubscribe { id: 1, unsubscribe: true });
        core.receive(ui, ClientMessage::Subscribe { id: 7, subscribe: Topic::Prefs });
        host.settle().await;
        let mut values = HashMap::new();
        apply(&host, &mut values);
        assert_eq!(values[&7]["device"], json!({ "app": "web", "phone": false, "handoff": true }));
    });
}

#[test]
fn the_language_is_as_chosen_else_as_the_device_is() {
    run(async {
        let (host, core) = station_core(0.0).await;
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Prefs });
        host.settle().await;
        let mut values = HashMap::new();
        apply(&host, &mut values);
        // Nothing told yet: none (the clients go by their device themselves).
        assert_eq!(values[&1]["lang"], Value::Null);
        // An English device, nothing chosen: English, and it signs in by an English name.
        let mac = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36";
        core.receive(ui, ClientMessage::Call { id: 2, call: "client.device".into(), params: json!({ "app": "web", "userAgent": mac, "locale": "en-US" }) });
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!(values[&1]["lang"], "en");
        assert_eq!(crate::prefs::device_name(&core.inner.data).as_deref(), Some("still.fail Web · Chrome · macOS"));
        // Chosen: as chosen; no longer chosen: as the device is.
        let set = |id, params: Value| core.receive(ui, ClientMessage::Call { id, call: "prefs.set".into(), params });
        set(3, json!({ "language": "zh" }));
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!(values[&1]["lang"], "zh");
        set(4, json!({ "language": null }));
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!(values[&1]["lang"], "en");
        set(5, json!({ "language": "fr" }));
        host.settle().await;
        assert!(host.take_emitted().iter().any(|(_, m)| matches!(m, CoreMessage::Error { id: 5, .. })));
        // A Chinese device, English chosen.
        core.receive(ui, ClientMessage::Call { id: 6, call: "client.device".into(), params: json!({ "app": "web", "userAgent": mac, "locale": "zh-CN" }) });
        set(7, json!({ "language": "en" }));
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!(values[&1]["lang"], "en");
        // The core's own words stay Chinese in tests (they run side by side).
        assert_eq!(stillfail_i18n::current(), stillfail_i18n::Lang::Zh);
        assert_eq!(stillfail_i18n::t!(stillfail_i18n::Lang::En; "core-misc.params.missing", field = "x"), "Invalid params: missing x");
    });
}

#[test]
fn a_draft_is_kept_on_the_device_until_emptied() {
    run(async {
        let (host, core) = station_core(0.0).await;
        let ui = core.connect();
        let topic = Topic::Draft { station: "ws/st".into(), chat: "new".into() };
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: topic.clone() });
        host.settle().await;
        let mut values = HashMap::new();
        apply(&host, &mut values);
        // Nothing written: empty, not waiting.
        assert_eq!(values[&1], json!({ "text": "", "quotes": [], "files": [] }));
        core.receive(ui, ClientMessage::Call { id: 2, call: "draft.put".into(), params: json!({
            "station": "ws/st", "chat": "new", "text": "修一下登录",
            "quotes": [{ "author": "a", "text": "b", "comment": "" }], "files": [{ "name": "x.png", "path": "up/x.png", "size": 3 }],
        }) });
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!(values[&1]["text"], "修一下登录");
        assert_eq!(values[&1]["files"][0]["path"], "up/x.png");
        // Kept across a restart, with no station to ask (written a moment after the last change).
        host.sleep(crate::data::SOON_MS + 50).await;
        drop(core);
        host.take_emitted();
        let core = Core::new(host.clone()).await;
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: topic.clone() });
        host.settle().await;
        let mut values = HashMap::new();
        apply(&host, &mut values);
        assert_eq!(values[&1]["text"], "修一下登录");
        assert_eq!(values[&1]["quotes"][0]["author"], "a");
        // Emptied (sent): gone, from the device too.
        core.receive(ui, ClientMessage::Call { id: 2, call: "draft.put".into(), params: json!({ "station": "ws/st", "chat": "new", "text": " ", "quotes": [], "files": [] }) });
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!(values[&1], json!({ "text": "", "quotes": [], "files": [] }));
        drop(core);
        let core = Core::new(host.clone()).await;
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: topic });
        host.settle().await;
        let mut values = HashMap::new();
        apply(&host, &mut values);
        assert_eq!(values[&1]["text"], "");
        // What is not a draft is refused.
        core.receive(ui, ClientMessage::Call { id: 3, call: "draft.put".into(), params: json!({ "station": "ws/st", "chat": "new", "text": 3 }) });
        core.receive(ui, ClientMessage::Call { id: 4, call: "draft.put".into(), params: json!({ "chat": "new", "text": "x" }) });
        host.settle().await;
        let refused = host.take_emitted().into_iter().filter(|(_, m)| matches!(m, CoreMessage::Error { id: 3 | 4, .. })).count();
        assert_eq!(refused, 2);
    });
}

/// A profile as the station lists it: `used` percent of its five hours used; checked since the station started or not.
fn profile(id: &str, runtime: &str, models: &[&str], checked: bool, used: f64) -> Value {
    json!({
        "id": id, "name": format!("{id}@x.com"), "runtime": runtime, "runtimes": [runtime], "access": { "kind": "subscription", "key": "" },
        "home": "/h", "homeExists": true, "model": null, "models": models, "env": [], "usedBy": [], "loginCommand": "",
        "check": if checked { json!({ "state": "ok", "detail": "", "checkedAt": 1 }) } else { Value::Null },
        "quota": { "state": "ok", "windows": [{ "label": "5 小时", "usedPercent": used, "resetsAt": null }], "detail": null, "checkedAt": 1 },
    })
}

/// A core whose station has three profiles: p1 (unchecked) and p2 run Claude Code, p3 Codex.
async fn choosing_core() -> (Rc<FakeHost>, Core) {
    choosing_core_speed(false).await
}

async fn choosing_core_speed(speed: bool) -> (Rc<FakeHost>, Core) {
    choosing_core_speed_defaults(speed, false, None).await
}

async fn choosing_core_speed_defaults(speed: bool, profile_fast: bool, session_fast: Option<bool>) -> (Rc<FakeHost>, Core) {
    let (host, core) = station_core(0.0).await;
    station_answers(&host, move |req| {
        let session = |key: &str| {
            let mut s = session(key);
            if speed { s["runtime"] = json!("codex"); s["model"] = json!("gpt-6-astra"); s["profile"] = json!("p3"); s["fast"] = json!(session_fast); }
            s
        };
        let path = req.url.trim_start_matches("https://stillfail.test");
        match (req.method.as_str(), path.split('?').next().unwrap()) {
            ("GET", "/admin/api/overview") => json_response(200, json!({
                "viewer": { "via": "local" }, "connects": [], "processes": [], "counts": { "sessions": 1, "running": 0, "warm": 0 },
                "mesh": null, "slackUsers": [], "slackTeams": [], "slackApps": [], "disk": null, "logins": [],
                "profiles": [
                    profile("p1", "claude", &["claude-opus-5-5", "claude-sonnet-5"], false, 10.0),
                    profile("p2", "claude", &["claude-opus-5-5"], true, 80.0),
                    ({ let mut p = profile("p3", "codex", &["gpt-6-astra"], true, 0.0); if speed { p["fast"] = json!(profile_fast); } p }),
                ],
            })),
            ("GET", "/admin/api/sessions") => json_response(200, json!([session("k1")])),
            ("GET", "/admin/api/sessions/k1") => json_response(200, json!({ "session": session("k1"), "threads": [], "turns": [] })),
            ("GET", "/admin/api/machine-sessions") => json_response(200, json!({ "sessions": [{ "runtime": "codex", "id": "m1", "cwd": "/Users/bob/src/x", "updatedAt": 0 }] })),
            ("POST", "/admin/api/profiles/p1/check") => json_response(200, json!({ "state": "ok", "detail": "", "checkedAt": 2 })),
            ("POST", "/admin/api/sessions/k1/settings") => json_response(200, json!({ "ok": true })),
            ("POST", "/admin/api/sessions") => json_response(400, json!({ "error": "not now" })),
            _ => json_response(404, json!({})),
        }
    });
    (host, core)
}

fn call(host: &Rc<FakeHost>, core: &Core, ui: ClientId, id: RequestId, name: &str, params: Value) -> impl std::future::Future<Output = Result<Value>> {
    core.receive(ui, ClientMessage::Call { id, call: name.into(), params });
    let host = host.clone();
    async move {
        host.settle().await;
        let mut out = None;
        let mut rest = Vec::new();
        for (c, m) in host.take_emitted() {
            match m {
                CoreMessage::Ok { id: i, ok } if i == id => out = Some(Ok(ok)),
                CoreMessage::Error { id: i, error } if i == id => out = Some(Err(error)),
                m => rest.push((c, m)),
            }
        }
        host.emitted.borrow_mut().extend(rest);
        out.expect("answered")
    }
}

fn posted(host: &FakeHost, path: &str) -> Vec<Value> {
    host.requests.borrow().iter().filter(|r| r.method == "POST" && r.url.ends_with(&format!("/admin/api{path}")))
        .map(|r| serde_json::from_slice(r.body.as_deref().unwrap_or(b"null")).unwrap_or(Value::Null)).collect()
}

#[test]
fn a_profile_added_through_the_flow_is_posted_and_answers_its_id() {
    run(async {
        let (host, core) = station_core(0.0).await;
        station_answers(&host, |req| {
            let path = req.url.trim_start_matches("https://stillfail.test");
            match (req.method.as_str(), path.split('?').next().unwrap()) {
                ("GET", "/admin/api/overview") => json_response(200, json!({
                    "viewer": { "via": "local" }, "connects": [], "processes": [], "counts": { "sessions": 0, "running": 0, "warm": 0 },
                    "mesh": null, "slackUsers": [], "slackTeams": [], "slackApps": [], "disk": null, "logins": [], "profiles": [],
                    "apiProviders": [{ "id": "jev" }, { "id": "groq" }],
                })),
                ("POST", "/admin/api/profiles") => json_response(200, json!({ "id": "jev", "overview": {} })),
                _ => json_response(404, json!({})),
            }
        });
        let ui = core.connect();
        let params = json!({ "station": "ws1/st1", "form": "add-test" });
        let r = call(&host, &core, ui, 1, "profile.flow.open", params.clone()).await; assert!(r.is_ok(), "open: {r:?}");
        let edit = |input: Value| json!({ "station": "ws1/st1", "form": "add-test", "input": input });
        let r = call(&host, &core, ui, 2, "profile.flow.edit", edit(json!({ "provider": "jev" }))).await; assert!(r.is_ok(), "edit provider: {r:?}");
        call(&host, &core, ui, 3, "profile.flow.edit", edit(json!({ "key": "k" }))).await.unwrap();
        let added = call(&host, &core, ui, 4, "profile.flow.submit", params.clone()).await;
        assert!(added.is_ok(), "{added:?}");
        let sent = posted(&host, "/profiles");
        assert_eq!(sent.len(), 1, "the add reaches the station");
        assert_eq!(sent[0]["access"]["provider"], "jev");
    });
}

#[test]
fn token_forms_publish_core_validation_and_keep_the_legacy_call_working() {
    run(async {
        let host = FakeHost::new();
        sign_in(&host);
        station_answers(&host, |req| match req.url.trim_start_matches("https://stillfail.test") {
            "/admin/api/slack/verify" => json_response(200, json!({"identity": {"team":"T", "teamId":"T1", "url":"https://t.slack.com", "botUserId":"B1", "botName":"bot"}, "errors":[]})),
            _ => json_response(200, json!({})),
        });
        let core = over_fetch(&host, 0.0).await;
        let ui = core.connect();
        let topic = Topic::SlackTokens { station: "ws/st".into(), form: "f".into() };
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: topic.clone() });
        let edit = json!({"station":"ws/st", "form":"f", "input":{"appToken":"app", "botToken":"bot"}});
        assert_eq!(call(&host, &core, ui, 10, "slack.tokens.edit", edit).await.unwrap()["ready"], true);
        let form = json!({"station":"ws/st", "form":"f"});
        assert_eq!(call(&host, &core, ui, 11, "slack.tokens.verify", form.clone()).await.unwrap(), true);
        let mut values = HashMap::new();
        apply(&host, &mut values);
        assert_eq!(values[&1]["verified"]["botName"], "bot");
        assert_eq!(posted(&host, "/slack/verify").len(), 1);
        assert_eq!(call(&host, &core, ui, 12, "slack.tokens.verify", form.clone()).await.unwrap(), true);
        assert_eq!(posted(&host, "/slack/verify").len(), 1, "a verified draft need not be checked again");
        // Existing pages still call the original operation.
        assert!(call(&host, &core, ui, 13, "slack.verify", json!({"station":"ws/st", "appToken":"app", "botToken":"bot"})).await.is_ok());
        assert_eq!(posted(&host, "/slack/verify").len(), 2);
        call(&host, &core, ui, 14, "slack.tokens.drop", form.clone()).await.unwrap();
        assert_eq!(core.inner.slack_tokens.value(&topic)["appToken"], "");
        assert!(call(&host, &core, ui, 15, "slack.tokens.verify", form).await.is_err());
    });
}

#[test]
fn new_chat_combos_are_local_to_a_workspace_persist_and_pick_model_and_depth_together() {
    run(async {
        let (host, core) = choosing_core().await;
        let ui = core.connect();
        let topic = Topic::NewChat { scope: "ws".into() };
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: topic.clone() });
        host.settle().await;
        let mut values = HashMap::new();
        apply(&host, &mut values);
        assert_eq!(values[&1]["frequent"], json!([]));
        call(&host, &core, ui, 2, "newChat.pick", json!({"scope": "ws", "model": "gpt-6-astra", "runtime": "codex", "effort": "medium"})).await.unwrap();
        apply(&host, &mut values);
        assert_eq!(values[&1]["frequent"], json!([]), "picking alone is not usage");
        core.inner.choose.used("other/st", &json!({"model": "claude-opus-5-5", "runtime": "claude", "effort": "high"}));
        call(&host, &core, ui, 3, "newChat.create", json!({"station": "ws/st"})).await.unwrap();
        apply(&host, &mut values);
        let combos = values[&1]["frequent"].as_array().unwrap();
        assert_eq!(combos.len(), 1, "another workspace's history must not appear");
        assert_eq!(combos[0]["effort"], "medium");
        drop(core);
        host.take_emitted();
        let core = over_fetch(&host, 0.0).await;
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: topic });
        host.settle().await;
        let mut values = HashMap::new();
        apply(&host, &mut values);
        let combo = values[&1]["frequent"][0].clone();
        assert_eq!(combo["model"], "gpt-6-astra");
        call(&host, &core, ui, 2, "newChat.pick", json!({"scope": "ws", "model": "claude-opus-5-5", "effort": "low"})).await.unwrap();
        call(&host, &core, ui, 3, "newChat.pick", json!({"scope": "ws", "model": combo["model"], "runtime": combo["runtime"], "effort": combo["effort"]})).await.unwrap();
        apply(&host, &mut values);
        assert_eq!(values[&1]["model"]["model"], "gpt-6-astra");
        assert_eq!(values[&1]["effort"], "medium");
        assert_eq!(values[&1]["frequent"][0]["selected"], true);
    });
}

#[test]
fn a_new_chat_runs_on_what_was_last_picked_there_as_far_as_the_station_still_has_it() {
    run(async {
        let (host, core) = choosing_core().await;
        let ui = core.connect();
        // What the page kept before the core did comes in once.
        call(&host, &core, ui, 1, "newChat.migrate", json!({ "choices": { "st": { "runtime": "claude", "model": "claude-sonnet-5", "effort": "low", "profile": "" } }, "last": "st" })).await.unwrap();
        let topic = Topic::NewChat { scope: "ws".into() };
        core.receive(ui, ClientMessage::Subscribe { id: 2, subscribe: topic.clone() });
        host.settle().await;
        let mut values = HashMap::new();
        apply(&host, &mut values);
        let v = &values[&2];
        assert_eq!((v["kept"].as_str(), v["station"]["id"].as_str()), (Some("st"), Some("st")));
        assert_eq!((v["model"]["model"].as_str(), v["runtime"].as_str(), v["effort"].as_str()), (Some("claude-sonnet-5"), Some("claude"), Some("low")));
        assert_eq!((v["waiting"].clone(), v["blocked"].clone(), v["pickAccount"].clone()), (json!(false), Value::Null, json!(false)));
        // Its unchecked profile is checked, once.
        assert_eq!(posted(&host, "/profiles/p1/check").len(), 1);
        assert!(posted(&host, "/profiles/p2/check").is_empty());
        // An account kept to that does not run the model gives way to the station's pick.
        call(&host, &core, ui, 3, "newChat.pick", json!({ "scope": "ws", "model": "claude-opus-5-5", "profile": "p3" })).await.unwrap();
        apply(&host, &mut values);
        let v = &values[&2];
        assert_eq!((v["model"]["model"].as_str(), v["effort"].as_str(), v["profile"].clone()), (Some("claude-opus-5-5"), Some("low"), Value::Null));
        assert_eq!(v["accounts"].as_array().map(Vec::len), Some(2));
        assert_eq!(v["pickAccount"], true);
        assert_eq!(v["accounts"][0]["quotaLine"], json!({ "text": "5 小时 90%" }));
        assert_eq!(v["accounts"][1]["quotaLine"], json!({ "text": "5 小时只剩 20%", "level": "amber" }));
        // A model on another runtime takes it, and its default depth.
        call(&host, &core, ui, 4, "newChat.pick", json!({ "scope": "ws", "model": "gpt-6-astra" })).await.unwrap();
        apply(&host, &mut values);
        assert_eq!((values[&2]["runtime"].as_str(), values[&2]["effort"].clone()), (Some("codex"), Value::Null));
        // Kept across a restart; what an older page kept does not come in over it.
        drop(core);
        host.take_emitted();
        let core = over_fetch(&host, 0.0).await;
        let ui = core.connect();
        call(&host, &core, ui, 1, "newChat.migrate", json!({ "choices": { "st": { "runtime": "claude", "model": "claude-sonnet-5", "effort": "", "profile": "" } } })).await.unwrap();
        core.receive(ui, ClientMessage::Subscribe { id: 2, subscribe: topic });
        host.settle().await;
        let mut values = HashMap::new();
        apply(&host, &mut values);
        assert_eq!(values[&2]["model"]["model"], "gpt-6-astra");
        // The model control of a new chat there: picked in its panel, then saved as what it runs on.
        let pick = Topic::Pick { station: "ws/st".into(), of: "new".into() };
        core.receive(ui, ClientMessage::Subscribe { id: 5, subscribe: pick });
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!((values[&5]["changed"].clone(), values[&5]["value"]["runtime"].clone(), values[&5]["account"].clone()), (json!(false), json!("codex"), Value::Null));
        call(&host, &core, ui, 6, "pick.set", json!({ "station": "ws/st", "of": "new", "model": "claude-opus-5-5", "profile": "p2" })).await.unwrap();
        apply(&host, &mut values);
        let p = &values[&5];
        assert_eq!((p["changed"].clone(), p["draft"]["runtime"].clone(), p["draft"]["profile"].clone(), p["who"].clone()), (json!(true), json!("claude"), json!("p2"), json!("p2")));
        assert_eq!(values[&2]["model"]["model"], "gpt-6-astra", "only a draft until saved");
        assert_eq!(call(&host, &core, ui, 7, "pick.save", json!({ "station": "ws/st", "of": "new" })).await.unwrap()["saved"], true);
        apply(&host, &mut values);
        assert_eq!((values[&2]["model"]["model"].as_str(), values[&2]["profile"].as_str()), (Some("claude-opus-5-5"), Some("p2")));
        // Kept to an account running low: the control names it, amber.
        assert_eq!(values[&5]["account"], json!({ "text": "p2@x.com", "auto": false, "level": "amber" }));
        // A chat made there is asked for with it, and the scope's next new chat starts there too.
        let made = call(&host, &core, ui, 8, "newChat.create", json!({ "station": "ws/st" })).await.unwrap();
        assert!(made["key"].as_str().is_some_and(|k| k.starts_with(crate::views::PENDING_PREFIX)));
        assert_eq!(posted(&host, "/sessions").last().map(|b| (b["model"].clone(), b["profile"].clone())), Some((json!("claude-opus-5-5"), json!("p2"))));
        // Refused: no scope, no station.
        assert!(call(&host, &core, ui, 9, "newChat.pick", json!({ "model": "x" })).await.is_err());
        assert!(call(&host, &core, ui, 10, "pick.set", json!({ "station": "ws/st", "of": "nothing" })).await.is_err());
    });
}

#[test]
fn a_sessions_model_control_says_what_changes_and_saves_it_on_the_station() {
    run(async {
        let (host, core) = choosing_core().await;
        let ui = core.connect();
        let pick = Topic::Pick { station: "ws/st".into(), of: "session:k1".into() };
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: pick });
        host.settle().await;
        let mut values = HashMap::new();
        apply(&host, &mut values);
        let p = &values[&1];
        // It runs on p1, the station's pick, with no model set.
        assert_eq!((p["runtimeFixed"].clone(), p["value"]["model"].clone(), p["account"]["text"].clone()), (json!(true), Value::Null, json!("自动 · p1@x.com")));
        assert_eq!(p["saveText"], "不变");
        // Kept to p2 and moved to Sonnet, which p2 does not run: back to the station's pick, said so.
        call(&host, &core, ui, 2, "pick.set", json!({ "station": "ws/st", "of": "session:k1", "profile": "p2" })).await.unwrap();
        call(&host, &core, ui, 3, "pick.set", json!({ "station": "ws/st", "of": "session:k1", "model": "claude-sonnet-5", "effort": "high" })).await.unwrap();
        apply(&host, &mut values);
        let p = &values[&1];
        assert_eq!(p["draft"]["profile"], Value::Null);
        assert!(p["dropped"].as_str().is_some_and(|d| d.contains("改成了自动分配")), "{p}");
        assert!(p["force"].as_str().is_some_and(|f| f.starts_with("指定的账号「p2」没有启用")), "{p}");
        assert_eq!(p["whoLevel"], "amber");
        assert_eq!(p["becomes"][1], "high");
        assert_eq!(p["changed"], true);
        call(&host, &core, ui, 4, "pick.save", json!({ "station": "ws/st", "of": "session:k1" })).await.unwrap();
        assert_eq!(posted(&host, "/sessions/k1/settings"), [json!({ "model": "claude-sonnet-5", "effort": "high", "profile": null })]);
        // Opened again: from what it runs on.
        call(&host, &core, ui, 5, "pick.set", json!({ "station": "ws/st", "of": "session:k1", "open": true })).await.unwrap();
        apply(&host, &mut values);
        assert_eq!(values[&1]["draft"]["effort"], Value::Null);
        // The machine's own sessions come each with its line.
        let listed = call(&host, &core, ui, 6, "machineSessions.list", json!({ "station": "ws/st" })).await.unwrap();
        assert!(listed["sessions"][0]["meta"].as_str().is_some_and(|m| m.starts_with("Codex · ~/src/x · ")), "{listed}");
    });
}

#[test]
fn a_draft_written_as_it_is_typed_is_one_write_and_read_by_its_key() {
    run(async {
        let (host, core) = station_core(0.0).await;
        let ui = core.connect();
        let put = |id, text: &str| ClientMessage::Call { id, call: "draft.put".into(), params: json!({ "key": "ws/st:thread:7", "text": text, "quotes": [], "files": [] }) };
        for (id, text) in [(1, "修"), (2, "修一"), (3, "修一下")] {
            core.receive(ui, put(id, text));
        }
        host.settle().await;
        let kept = |host: &FakeHost| host.db.borrow().iter().filter(|((t, _), _)| t == "draft").map(|(_, v)| serde_json::from_slice::<Value>(v).unwrap()["text"].clone()).collect::<Vec<_>>();
        // There at once; on the device a moment after the last change, as it is then.
        assert!(kept(&host).is_empty());
        core.receive(ui, ClientMessage::Call { id: 4, call: "draft.get".into(), params: json!({ "key": "ws/st:thread:7" }) });
        host.settle().await;
        let answer = |host: &FakeHost, want| host.take_emitted().into_iter().find_map(|(_, m)| match m { CoreMessage::Ok { id, ok } if id == want => Some(ok), _ => None });
        assert_eq!(answer(&host, 4).unwrap()["text"], "修一下");
        host.sleep(crate::data::SOON_MS + 50).await;
        host.settle().await;
        assert_eq!(kept(&host), [json!("修一下")]);
        // Emptied before it was written: nothing is written after all.
        core.receive(ui, ClientMessage::Call { id: 5, call: "draft.put".into(), params: json!({ "key": "new:ws/st", "text": "新的" }) });
        core.receive(ui, ClientMessage::Call { id: 6, call: "draft.put".into(), params: json!({ "key": "new:ws/st", "text": "" }) });
        host.sleep(crate::data::SOON_MS + 50).await;
        host.settle().await;
        assert_eq!(kept(&host), [json!("修一下")]);
        core.receive(ui, ClientMessage::Call { id: 7, call: "draft.get".into(), params: json!({ "key": "new:ws/st" }) });
        host.settle().await;
        assert_eq!(answer(&host, 7).unwrap(), json!({ "text": "", "quotes": [], "files": [] }));
    });
}

#[test]
fn a_chat_referred_to_goes_out_as_a_link_to_it() {
    run(async {
        let (host, core) = station_core(0.0).await;
        let ui = core.connect();
        core.receive(ui, ClientMessage::Call { id: 1, call: "chat.ref".into(), params: json!({ "station": "ws/st", "id": "ember:c 1", "title": "排查 [登录]", "base": "https://x" }) });
        core.receive(ui, ClientMessage::Call { id: 2, call: "chat.ref".into(), params: json!({ "station": "w2/st", "id": "k2", "title": "云上的", "base": "https://x" }) });
        // Kept by a page before the core kept them: one to a station's own page (gone) is no workspace's.
        core.receive(ui, ClientMessage::Call { id: 3, call: "chat.refs".into(), params: json!({ "links": [["旧的", "https://x/w/ws/s/st/chats/a"], ["本机", "/admin/chats/b"]] }) });
        host.settle().await;
        let answers: HashMap<RequestId, Value> = host.take_emitted().into_iter().filter_map(|(_, m)| match m { CoreMessage::Ok { id, ok } => Some((id, ok)), _ => None }).collect();
        assert_eq!(answers[&1], json!({ "mark": "@[排查 登录]" }));
        assert_eq!(answers[&2], json!({ "mark": "@[云上的]" }));
        core.receive(ui, ClientMessage::Call { id: 4, call: "chat.send".into(), params: json!({ "station": "ws/st", "thread": 7, "text": "看 @[排查 登录]、@[云上的]、@[旧的]、@[本机] 和 @[不知道]" }) });
        host.settle().await;
        let sent = host.requests.borrow().iter().rev().find(|r| r.method == "POST" && r.url.ends_with("/admin/api/threads/7/messages")).map(|r| serde_json::from_slice::<Value>(r.body.as_deref().unwrap()).unwrap()).expect("sent");
        // Another workspace's chat is none of this one's: its mark stays as written.
        assert_eq!(sent["text"], "看 [排查 登录](https://x/w/ws/s/st/chats/ember%3Ac%201)、@[云上的]、[旧的](https://x/w/ws/s/st/chats/a)、@[本机] 和 @[不知道]");
    });
}

#[test]
fn an_address_of_a_stations_own_page_kept_from_before_is_said_gone() {
    run(async {
        let (host, core) = station_core(0.0).await;
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Chat { station: "local".into(), thread: Some(7), session: None } });
        core.receive(ui, ClientMessage::Subscribe { id: 2, subscribe: Topic::Overview { station: "local".into() } });
        core.receive(ui, ClientMessage::Call { id: 3, call: "chat.send".into(), params: json!({ "station": "local", "thread": 7, "text": "hi" }) });
        host.settle().await;
        let errors: HashMap<RequestId, String> = host.take_emitted().into_iter().filter_map(|(_, m)| match m { CoreMessage::Error { id, error } => Some((id, error.code)), _ => None }).collect();
        assert_eq!((errors.get(&1).map(String::as_str), errors.get(&2).map(String::as_str), errors.get(&3).map(String::as_str)), (Some("gone"), Some("gone"), Some("gone")), "{errors:?}");
    });
}

#[test]
fn the_chats_a_few_words_find_are_a_view_of_the_list() {
    run(async {
        let (host, core) = station_core(0.0).await;
        station_answers(&host, |req| {
            let path = req.url.trim_start_matches("https://stillfail.test");
            let row = |id: &str, title: &str, at: i64| json!({
                "id": id, "session": id, "thread": null, "title": title, "agents": [], "last": null, "unread": false, "mine": true,
                "lastActiveAt": at, "connect": null, "origin": null,
            });
            match path.split('?').next().unwrap() {
                "/admin/api/chats" => json_response(200, json!([row("a", "别的", 3), row("b", "登录页", 2), row("c", "修登录", 1)])),
                "/admin/api/overview" => json_response(200, json!({
                    "viewer": { "via": "local" }, "connects": [], "profiles": [], "processes": [], "counts": { "sessions": 0, "running": 0, "warm": 0 },
                    "mesh": null, "slackUsers": [], "slackTeams": [], "slackApps": [], "disk": null, "logins": [],
                })),
                _ => json_response(404, json!({})),
            }
        });
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: serde_json::from_value(json!({ "topic": "chatSearch", "scope": "ws", "query": "登录", "exclude": "c" })).unwrap() });
        host.settle().await;
        let mut values = HashMap::new();
        apply(&host, &mut values);
        let ids: Vec<&str> = values[&1]["items"].as_array().unwrap().iter().map(|i| i["id"].as_str().unwrap()).collect();
        assert_eq!(ids, ["b"]);
        assert_eq!(values[&1]["items"][0]["station"], "ws/st");
    });
}

#[test]
fn a_chat_shown_has_its_unread_line_and_is_read_while_its_end_is_in_view() {
    run(async {
        let (host, core) = station_core(0.0).await;
        station_answers(&host, |req| {
            let path = req.url.trim_start_matches("https://stillfail.test");
            let said = |n: u64| json!({ "thread": 7, "n": n, "kind": "message", "ts": format!("{n}.0"), "authorKind": "agent", "author": "k1", "authorName": null, "text": "好", "at": n });
            match (req.method.as_str(), path.split('?').next().unwrap()) {
                ("GET", "/admin/api/threads") => json_response(200, json!([{
                    "id": 7, "surface": "ember", "channel": "EMBER", "channelName": null, "threadTs": "7.0", "title": null, "createdBy": null,
                    "creator": null, "createdAt": 1, "sessions": [{ "thread": 7, "session": "k1", "connect": "ember", "joinedAt": 1 }],
                    "last": 3, "lastMessage": null, "read": 1, "unread": 2, "people": [], "firstText": null,
                }])),
                ("GET", "/admin/api/threads/7/entries") => json_response(200, json!({ "first": 1, "last": 3, "entries": [said(1), said(2), said(3)] })),
                ("PUT", "/admin/api/threads/7/read") => json_response(200, json!({ "n": 3 })),
                ("GET", "/admin/api/sessions") => json_response(200, json!([session("k1")])),
                ("GET", "/admin/api/sessions/k1") => json_response(200, json!({ "session": session("k1"), "threads": [], "turns": [] })),
                _ => json_response(404, json!({})),
            }
        });
        let ui = core.connect();
        let mut values = HashMap::new();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Chat { station: "ws/st".into(), thread: Some(7), session: None } });
        host.settle().await;
        apply(&host, &mut values);
        // Not shown by any page yet: the line as it will be (its first value opens there).
        assert_eq!(values[&1]["messages"].as_array().unwrap().len(), 3);
        assert_eq!(values[&1]["unreadLine"], 2);
        // Shown: the line over the first not read when it was opened; not read while its end is out of view.
        core.receive(ui, ClientMessage::Call { id: 2, call: "client.focus".into(), params: json!({ "visible": true, "focused": true, "chat": { "station": "ws/st", "thread": 7, "end": false } }) });
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!(values[&1]["unreadLine"], 2);
        let reads = |host: &FakeHost| host.requests.borrow().iter().filter(|r| r.method == "PUT" && r.url.ends_with("/threads/7/read")).count();
        assert_eq!(reads(&host), 0);
        // Its end in view: read up to the newest, once; the line stays for the visit.
        core.receive(ui, ClientMessage::Call { id: 3, call: "client.focus".into(), params: json!({ "chat": { "station": "ws/st", "thread": 7, "end": true } }) });
        host.settle().await;
        core.receive(ui, ClientMessage::Call { id: 4, call: "client.focus".into(), params: json!({ "visible": true }) });
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!(reads(&host), 1);
        assert_eq!(values[&1]["unreadLine"], 2);
        // The page gone: the visit ends with it; opened again, nothing unread.
        core.disconnect(ui);
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Chat { station: "ws/st".into(), thread: Some(7), session: None } });
        core.receive(ui, ClientMessage::Call { id: 2, call: "client.focus".into(), params: json!({ "visible": true, "chat": { "station": "ws/st", "thread": 7 } }) });
        host.settle().await;
        let mut values = HashMap::new();
        apply(&host, &mut values);
        assert_eq!(values[&1]["unreadLine"], Value::Null);
    });
}

#[test]
fn notifications_are_on_until_turned_off_and_kept_so_with_no_pushes() {
    run(async {
        let (host, core) = station_core(0.0).await;
        let ui = core.connect();
        let mut values = HashMap::new();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Notify { workspace: None } });
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!(values[&1], json!({ "on": true, "asked": false, "push": true, "show": [] }));
        // Off (and asked, as Android moves its old settings over): pushes go, and are not taken while off.
        core.receive(ui, ClientMessage::Call { id: 2, call: "notify.set".into(), params: json!({ "on": false, "asked": true }) });
        core.receive(ui, ClientMessage::Call { id: 3, call: "push.register".into(), params: json!({ "kind": "fcm", "token": "t" }) });
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!(values[&1], json!({ "on": false, "asked": true, "push": false, "show": [] }));
        assert_eq!(host.stored(PUSH_KEY), None);
        // Kept across a restart.
        drop(core);
        let core = Core::new(host.clone()).await;
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Notify { workspace: None } });
        core.receive(ui, ClientMessage::Call { id: 2, call: "notice.pushed".into(), params: json!({}) });
        core.receive(ui, ClientMessage::Call { id: 3, call: "notice.claim".into(), params: json!({ "id": "n1" }) });
        host.settle().await;
        let emitted = host.take_emitted();
        let ok = |id| emitted.iter().find_map(|(_, m)| match m { CoreMessage::Ok { id: i, ok } if *i == id => Some(ok.clone()), _ => None }).unwrap();
        assert_eq!((ok(2), ok(3)), (json!({ "show": false }), json!({ "show": false })));
        let value = emitted.iter().find_map(|(_, m)| match m { CoreMessage::Value { id: 1, value } => Some(value.clone()), _ => None }).unwrap();
        assert_eq!(value["on"], false);
    });
}

#[test]
fn a_chats_jobs_are_shown_as_the_core_puts_them_and_a_jobs_output_says_when_it_last_grew() {
    run(async {
        let host = FakeHost::new();
        host.speed_up(SPEEDUP);
        sign_in(&host);
        let now = (now_s() * 1000.0) as i64;
        let reads = Rc::new(std::cell::Cell::new(0));
        let counted = reads.clone();
        station_answers(&host, move |req| {
            let path = req.url.trim_start_matches("https://stillfail.test");
            let job = |id: &str, patch: Value| {
                let mut j = json!({ "id": id, "session": "k1", "name": id, "state": "running", "port": null, "startedAt": now - 60_000, "command": "watch" });
                j.as_object_mut().unwrap().extend(patch.as_object().unwrap().clone());
                j
            };
            match path.split('?').next().unwrap() {
                "/admin/api/threads" => json_response(200, json!([{
                    "id": 7, "surface": "ember", "channel": "EMBER", "channelName": null, "threadTs": "7.0", "title": null, "createdBy": null,
                    "creator": null, "createdAt": 1, "sessions": [{ "thread": 7, "session": "k1", "connect": "ember", "joinedAt": 1 }],
                    "last": 0, "lastMessage": null, "read": 0, "unread": 0, "people": [], "firstText": null,
                }])),
                "/admin/api/threads/7/entries" => json_response(200, json!({ "last": 0, "entries": [] })),
                "/admin/api/sessions" => json_response(200, json!([session("k1")])),
                "/admin/api/sessions/k1" => json_response(200, json!({ "session": session("k1"), "threads": [], "turns": [], "jobs": [
                    job("w", json!({ "notices": [{ "at": now - 120_000, "text": "CI 还在跑" }] })),
                    job("s", json!({ "port": 4817, "state": "exited", "restarts": 1 })),
                    job("done", json!({ "state": "exited", "exitCode": 0, "endedAt": now - 30_000 })),
                ] })),
                "/admin/api/overview" => json_response(200, json!({
                    "viewer": { "via": "local" }, "connects": [], "profiles": [], "processes": [], "counts": { "sessions": 1, "running": 0, "warm": 0 },
                    "mesh": null, "slackUsers": [], "slackTeams": [], "slackApps": [], "disk": null, "logins": [],
                })),
                "/admin/api/jobs/w/log" => {
                    counted.set(counted.get() + 1);
                    json_response(200, json!({ "text": "step 3\n", "outputAt": now - 180_000, "follows": true }))
                }
                _ => json_response(404, json!({})),
            }
        });
        host.on_fetch_stream(|_| Ok(crate::host::StreamResponse { status: 200, headers: vec![], body: futures::stream::pending().boxed_local() }));
        let core = over_fetch(&host, 0.0).await;
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::ChatJobs { station: "ws/st".into(), thread: Some(7), session: None } });
        core.receive(ui, ClientMessage::Subscribe { id: 2, subscribe: Topic::JobLog { station: "ws/st".into(), job: "w".into(), lines: 1 } });
        host.settle().await;
        host.settle().await;
        let mut values = HashMap::new();
        apply(&host, &mut values);
        // Restarting first, then alive, then what is over; each with its dot and its line; the heads' notes.
        let jobs = &values[&1];
        let ids: Vec<&str> = jobs["jobs"].as_array().unwrap().iter().map(|j| j["id"].as_str().unwrap()).collect();
        assert_eq!(ids, ["s", "w", "done"]);
        assert_eq!((jobs["alarm"].as_str(), jobs["servicesNote"].as_str(), jobs["jobsNote"].as_str()), (Some("restart"), Some("1 个在重启"), Some("1 个在盯着")));
        assert_eq!((jobs["ended"].as_i64(), jobs["clear"].clone(), jobs["clearText"].as_str()), (Some(1), json!(["k1"]), Some("清掉 1 个已结束的")));
        let w = &jobs["jobs"][1];
        assert_eq!((w["tone"].as_str(), w["meta"][0]["text"].as_str(), w["meta"][1]["text"].as_str(), w["detail"].as_str()), (Some("live"), Some("CI 还在跑"), Some(" · 2 分钟前"), Some("在盯着 · 1 分钟 · 1 条通知")));
        assert_eq!((jobs["jobs"][0]["meta"][0]["text"].as_str(), jobs["jobs"][2]["tone"].as_str()), (Some("正在重启"), Some("off")));
        // Its output: the last line and when, in words; the station follows it, so it is not read again.
        assert_eq!((values[&2]["last"].as_str(), values[&2]["said"].as_str()), (Some("step 3"), Some("最后输出 · 3 分钟前")));
        let before = reads.get();
        pass(5_000).await;
        assert_eq!(reads.get(), before);
    });
}

#[test]
fn a_new_chat_is_there_at_once_and_what_is_sent_to_it_goes_in_once_the_station_has_made_it() {
    run(async {
        let (host, core) = station_core(0.0).await;
        let up = Rc::new(Cell::new(false));
        let station_up = up.clone();
        station_answers(&host, move |req| {
            let path = req.url.trim_start_matches("https://stillfail.test");
            match (req.method.as_str(), path) {
                ("POST", "/admin/api/sessions") if !station_up.get() => json_response(400, json!({"error": "no claude profile configured"})),
                ("POST", "/admin/api/sessions") => json_response(200, json!({"key": "ember:c-1", "thread": {
                    "id": 9, "surface": "ember", "channel": "EMBER", "channelName": null, "threadTs": "9.0", "title": null, "createdBy": "a@x.com",
                    "creator": null, "createdAt": 1, "sessions": [{ "thread": 9, "session": "ember:c-1", "connect": "ember", "joinedAt": 1 }],
                    "last": 0, "lastMessage": null, "read": 0, "unread": 0, "people": [], "firstText": null,
                }})),
                ("POST", "/admin/api/threads/9/messages") => json_response(200, json!({"n": 1})),
                _ => json_response(404, json!({})),
            }
        });
        let ui = core.connect();
        core.receive(ui, ClientMessage::Call { id: 1, call: "chat.create".into(), params: json!({"station": "ws/st", "runtime": "claude", "model": "opus"}) });
        host.settle().await;
        let answers = host.take_emitted();
        let key = answers.iter().find_map(|(_, m)| match m { CoreMessage::Ok { id: 1, ok } => ok["key"].as_str().map(str::to_string), _ => None }).expect("answered at once");
        assert!(key.starts_with(crate::views::PENDING_PREFIX), "{key}");
        // The station could not make it: what is sent waits, and has it tried again.
        core.receive(ui, ClientMessage::Subscribe { id: 2, subscribe: Topic::Chat { station: "ws/st".into(), thread: None, session: Some(key.clone()) } });
        host.settle().await;
        let mut values = HashMap::new();
        apply(&host, &mut values);
        assert_eq!(values[&2]["pending"], true);
        up.set(true);
        core.receive(ui, ClientMessage::Call { id: 3, call: "chat.send".into(), params: json!({"station": "ws/st", "session": key, "text": "修一下登录", "client": "android 0.1.1123"}) });
        host.settle().await;
        let asked: Vec<(String, String)> = host.requests.borrow().iter().filter(|r| r.method == "POST" && r.url.contains("/admin/api/"))
            .map(|r| (r.url.trim_start_matches("https://stillfail.test/admin/api").to_string(), String::from_utf8(r.body.clone().unwrap_or_default()).unwrap())).collect();
        assert_eq!(asked.iter().map(|(p, _)| p.as_str()).collect::<Vec<_>>(), ["/sessions", "/sessions", "/threads/9/messages"]);
        // It carries the key given here: the station's rows say it of the chat made.
        assert_eq!(serde_json::from_str::<Value>(&asked[0].1).unwrap(), json!({"runtime": "claude", "model": "opus", "clientKey": key}));
        // With the app it was sent from, which waited with it.
        let sent = serde_json::from_str::<Value>(&asked[2].1).unwrap();
        assert_eq!((sent["text"].clone(), sent["client"].clone()), (json!("修一下登录"), json!("android 0.1.1123")));
        // The page is the station's chat now, under the key it was opened with, and says the one the station gave it.
        apply(&host, &mut values);
        assert_eq!((values[&2]["pending"].clone(), values[&2]["key"].clone()), (json!(false), json!("ember:c-1")));
    });
}

/// What came out: subscription values (deltas applied) into `values`, and the calls' answers.
fn answers(host: &FakeHost, values: &mut HashMap<RequestId, Value>) -> HashMap<RequestId, std::result::Result<Value, String>> {
    let mut answers = HashMap::new();
    for (_, message) in host.take_emitted() {
        match message {
            CoreMessage::Value { id, value } => {
                values.insert(id, value);
            }
            CoreMessage::Delta { id, delta } => crate::delta::apply(values.get_mut(&id).expect("a delta needs a value"), &delta),
            CoreMessage::Ok { id, ok } => {
                answers.insert(id, Ok(ok));
            }
            CoreMessage::Error { id, error } => {
                answers.insert(id, Err(error.message));
            }
        }
    }
    answers
}

#[test]
fn a_chat_being_archived_leaves_the_list_at_once_and_comes_back_if_it_could_not_be() {
    run(async {
        let (host, core) = station_core(0.0).await;
        let (archived, refused) = (Rc::new(Cell::new(false)), Rc::new(Cell::new(true)));
        let (a, r) = (archived.clone(), refused.clone());
        station_answers(&host, move |req| {
            let row = |id: &str, thread: u64| json!({ "id": id, "session": id, "thread": thread, "title": id, "agents": [], "last": null,
                "unread": false, "mine": true, "lastActiveAt": 1, "connect": null, "origin": null });
            match (req.method.as_str(), req.url.trim_start_matches("https://stillfail.test/admin/api")) {
                ("GET", "/chats") => json_response(200, if a.get() { json!([row("k2", 8)]) } else { json!([row("k1", 7), row("k2", 8)]) }),
                ("POST", "/threads/7/archive") if r.get() => json_response(409, json!({ "error": "还在跑" })),
                ("POST", "/threads/7/archive") => {
                    a.set(true);
                    json_response(200, json!({ "ok": true }))
                }
                _ => json_response(404, json!({})),
            }
        });
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Chats { scope: "ws".into(), mine: false, watching: false } });
        host.settle().await;
        let mut values = HashMap::new();
        answers(&host, &mut values);
        let ids = |values: &HashMap<RequestId, Value>| -> Vec<String> {
            values[&1]["days"].as_array().unwrap().iter().flat_map(|d| d["items"].as_array().unwrap().iter().map(|i| i["id"].as_str().unwrap().to_string())).collect()
        };
        assert_eq!(ids(&values), ["k1", "k2"]);
        let archive = |id| ClientMessage::Call { id, call: "chat.archive".into(), params: json!({ "station": "ws/st", "thread": 7, "session": "k1", "archived": true }) };
        // Gone at once, while the station has not answered.
        let held = host.hold("/threads/7/archive");
        core.receive(ui, archive(2));
        host.settle().await;
        assert!(answers(&host, &mut values).is_empty());
        assert_eq!(ids(&values), ["k2"]);
        // It could not be: back, and the call says why.
        drop(held);
        host.settle().await;
        assert_eq!(answers(&host, &mut values)[&2], Err("还在跑".to_string()));
        assert_eq!(ids(&values), ["k1", "k2"]);
        // Archived: its station's rows, read again before the answer, no longer have it.
        refused.set(false);
        let held = host.hold("/threads/7/archive");
        core.receive(ui, archive(3));
        host.settle().await;
        answers(&host, &mut values);
        assert_eq!(ids(&values), ["k2"]);
        held.send(()).unwrap();
        host.settle().await;
        assert!(answers(&host, &mut values)[&3].is_ok());
        assert_eq!(ids(&values), ["k2"]);
        assert!(archived.get());
    });
}

#[test]
fn the_archive_is_its_stations_archived_chats_newest_first_by_day_and_one_restored_or_deleted_leaves_it() {
    run(async {
        let (host, core) = station_core(0.0).await;
        let now = host.now_ms().round();
        let gone = Rc::new(RefCell::new(Vec::<&str>::new()));
        let g = gone.clone();
        station_answers(&host, move |req| {
            let chat = |id: &str, thread: u64, archived: Value| json!({ "id": id, "session": id, "thread": thread, "title": format!("聊 {id}"),
                "last": { "text": "好了" }, "lastActiveAt": now - 9e8, "archived": archived });
            match (req.method.as_str(), req.url.trim_start_matches("https://stillfail.test/admin/api")) {
                ("GET", "/chats?archived=1") => {
                    let all = [
                        chat("k2", 8, json!({ "at": now - 3.0 * 86_400_000.0, "by": "auto", "alone": true })),
                        chat("k1", 7, json!({ "at": now, "by": "manual", "alone": false })),
                        // A station from before the archive answers the chats it shows: not archived ones.
                        chat("k3", 9, Value::Null),
                    ];
                    json_response(200, Value::Array(all.into_iter().filter(|c| !g.borrow().contains(&c["id"].as_str().unwrap())).collect()))
                }
                ("DELETE", "/threads/7/archive") => {
                    g.borrow_mut().push("k1");
                    json_response(200, json!({ "ok": true }))
                }
                ("DELETE", "/sessions/k2") => {
                    g.borrow_mut().push("k2");
                    json_response(200, json!({ "ok": true }))
                }
                _ => json_response(404, json!({})),
            }
        });
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Archive { scope: "ws".into() } });
        host.settle().await;
        let mut values = HashMap::new();
        answers(&host, &mut values);
        let v = &values[&1];
        assert_eq!((v["loading"].clone(), v.get("note"), v["errors"].clone()), (json!(false), None, json!([])));
        let days = v["days"].as_array().unwrap();
        assert_eq!(days.len(), 2);
        assert_eq!(days[0]["label"], "今天");
        let first = &days[0]["items"][0];
        assert_eq!(
            (first["station"].clone(), first["session"].clone(), first["thread"].clone(), first["title"].clone(), first["last"].clone(), first["how"].clone(), first["deletable"].clone()),
            (json!("ws/st"), json!("k1"), json!(7), json!("聊 k1"), json!("好了"), json!("手动归档"), json!(true))
        );
        assert_eq!(first["clock"].as_str().unwrap().len(), 5);
        // One station: which one is not said.
        assert!(first.get("place").is_none());
        assert_eq!((days[1]["items"][0]["how"].clone(), days[1]["items"][0]["deletable"].clone()), (json!("空闲后自动归档"), json!(false)));
        // Put back in the list: it leaves the archive before the call answers.
        core.receive(ui, ClientMessage::Call { id: 2, call: "chat.archive".into(), params: json!({ "station": "ws/st", "thread": 7, "session": "k1", "archived": false }) });
        host.settle().await;
        assert!(answers(&host, &mut values)[&2].is_ok());
        let sessions = |v: &Value| -> Vec<String> { v["days"].as_array().unwrap().iter().flat_map(|d| d["items"].as_array().unwrap().iter().map(|i| i["session"].as_str().unwrap().to_string())).collect() };
        assert_eq!(sessions(&values[&1]), ["k2"]);
        // Deleted: the same, and with nothing left the page says so.
        core.receive(ui, ClientMessage::Call { id: 3, call: "session.delete".into(), params: json!({ "station": "ws/st", "key": "k2" }) });
        host.settle().await;
        assert!(answers(&host, &mut values)[&3].is_ok());
        assert_eq!((values[&1]["days"].clone(), values[&1]["note"].clone()), (json!([]), json!("没有归档的对话。")));
    });
}

#[test]
fn encodes_path_segments_like_encode_uri_component() {
    assert_eq!(encode("ws_01-a.b~"), "ws_01-a.b~");
    assert_eq!(encode("a/b c?"), "a%2Fb%20c%3F");
    assert_eq!(encode("工"), "%E5%B7%A5");
}

#[test]
fn the_changelog_says_what_this_app_has_and_what_an_update_brought_until_seen() {
    run(async {
        let host = FakeHost::new();
        let now = (host.now_ms() / 1000.0).round();
        host.on_fetch(move |req| {
            if !req.url.ends_with("/v1/changelog") {
                return json_response(404, json!({}));
            }
            let entry = |version: i64, parts: Value, text: &str| json!({ "version": version, "commit": "c", "at": now, "text": [text], "fixes": [], "parts": parts });
            json_response(200, json!({
                "entries": [
                    entry(1340, json!(["android"]), "修复：还没发布的"),
                    entry(1330, json!(["android", "web"]), "修复：列表跳动"),
                    entry(1325, json!(["station"]), "修复：station 的"),
                    entry(1310, json!(["android"]), "新功能：更早的"),
                ],
                "released": { "android": 1335, "web": 1335, "station": 1320, "desktop": null },
            }))
        });
        let core = Core::new(host.clone()).await;
        let ui = core.connect();
        call(&host, &core, ui, 1, "client.device", json!({ "app": "android", "build": "0.1.1320" })).await.unwrap();
        core.receive(ui, ClientMessage::Subscribe { id: 2, subscribe: Topic::Changelog });
        host.settle().await;
        let mut values = HashMap::new();
        answers(&host, &mut values);
        let v = &values[&2];
        assert_eq!((v["app"].clone(), v["build"].clone(), v["loading"].clone()), (json!("android"), json!(1320), json!(false)));
        let entries = v["days"][0]["entries"].as_array().unwrap();
        assert_eq!(v["days"][0]["label"], "今天");
        let notes: Vec<&str> = entries.iter().map(|e| e["note"].as_str().unwrap()).collect();
        assert_eq!(notes, ["还没发布", "更新到 0.1.1330 后就有", "还没发布", "你的版本已包含"]);
        // The first build seen here: nothing is news.
        assert!(v.get("news").is_none(), "{v}");

        // Updated, the app started again: what it brought, until seen.
        drop(core);
        let core = Core::new(host.clone()).await;
        let ui = core.connect();
        call(&host, &core, ui, 3, "client.device", json!({ "app": "android", "build": "0.1.1335" })).await.unwrap();
        core.receive(ui, ClientMessage::Subscribe { id: 2, subscribe: Topic::Changelog });
        host.settle().await;
        answers(&host, &mut values);
        let news = &values[&2]["news"];
        assert_eq!(news["build"], "0.1.1335");
        assert_eq!(news["entries"].as_array().unwrap().iter().map(|e| e["text"][0].clone()).collect::<Vec<_>>(), [json!("修复：列表跳动")]);
        call(&host, &core, ui, 4, "changelog.seen", json!({})).await.unwrap();
        answers(&host, &mut values);
        assert!(values[&2].get("news").is_none());
        // Read when shown, once in the hour for each start.
        assert_eq!(host.requests.borrow().iter().filter(|r| r.url.ends_with("/v1/changelog")).count(), 2);
    });
}

#[test]
fn connect_wizard_owns_steps_tokens_and_submission_on_all_clients() {
    run(async {
        let (host, core) = choosing_core().await;
        let ui = core.connect();
        let topic = Topic::ConnectFlow { station:"ws/st".into(), form:"wizard".into() };
        let form = json!({"station":"ws/st","form":"wizard"});
        call(&host,&core,ui,1,"connect.flow.open",form.clone()).await.unwrap();
        let flow = &core.inner.connect_flow;
        let view = flow.value(&topic).unwrap();
        assert_eq!(view["gettingToken"],true,"desktop has the config form on its first step");
        assert_eq!(view["total"],4);
        let mut shaped = view;
        crate::present::decorate(&topic, &mut shaped, crate::present::Clock {now:0.0,offset_min:0});
        stillfail_shapes::conform::<stillfail_shapes::ConnectFlowView>(shaped).unwrap();
        assert!(flow.go(&topic,ui,"bind").is_err(),"cannot skip token verification");
        flow.go(&topic,ui,"manual").unwrap();
        assert_eq!(flow.value(&topic).unwrap()["total"],2);
        call(&host,&core,ui,2,"slack.tokens.edit",json!({"station":"ws/st","form":"wizard","input":{"appToken":"app","botToken":"bot"}})).await.unwrap();
        let overview=core.inner.store.get(&Topic::Overview{station:"ws/st".into()}).unwrap();
        station_answers(&host,move |req| match req.url.trim_start_matches("https://stillfail.test") {
            "/admin/api/slack/verify"=>json_response(200,json!({"identity":{"team":"Team","teamId":"T","url":"https://t.slack.com","botUserId":"B","botName":"bot"},"errors":[]})),
            "/admin/api/connects"=>json_response(200,json!({"id":"new"})),
            "/admin/api/overview"=>json_response(200,overview.clone()),
            _=>json_response(200,json!({})),
        });
        call(&host,&core,ui,3,"connect.flow.verify",form.clone()).await.unwrap();
        assert_eq!(flow.value(&topic).unwrap()["step"],"bind");
        call(&host,&core,ui,4,"pick.set",json!({"station":"ws/st","of":"connect-new:wizard","model":"gpt-6-astra","runtime":"codex"})).await.unwrap();
        call(&host,&core,ui,5,"pick.save",json!({"station":"ws/st","of":"connect-new:wizard"})).await.unwrap();
        let created=call(&host,&core,ui,6,"connect.flow.create",form.clone()).await.unwrap();
        assert_eq!(created["id"],"new");
        let sent=posted(&host,"/connects");
        assert_eq!(sent.len(),1);
        assert_eq!(sent[0]["bind"]["model"],"gpt-6-astra");
        assert_eq!(sent[0]["bind"]["runtime"],"codex");
        assert_eq!(sent[0]["bind"]["effort"],"");
        assert_eq!(sent[0]["slack"]["appToken"],"app");
        assert!(call(&host,&core,ui,7,"connect.flow.create",form.clone()).await.is_err(),"a completed form cannot create twice");
        call(&host,&core,ui,8,"connect.flow.drop",form).await.unwrap();
        assert!(flow.value(&topic).is_err());
        assert_eq!(core.inner.slack_tokens.value(&crate::connect_flow::tokens("ws/st","wizard"))["appToken"],"");
    });
}

#[test]
fn connect_wizard_isolates_forms_handles_resume_and_discards_closed_results() {
    run(async {
        let (host,core)=choosing_core().await;let ui=core.connect();let other=core.connect();
        for (id,form) in [(1,"one"),(2,"two")] {
            call(&host,&core,ui,id,"connect.flow.open",json!({"station":"ws/st","form":form,"input":{"mobile":true}})).await.unwrap();
        }
        let flow=&core.inner.connect_flow;
        let one=Topic::ConnectFlow{station:"ws/st".into(),form:"one".into()};
        let two=Topic::ConnectFlow{station:"ws/st".into(),form:"two".into()};
        assert_eq!(flow.value(&one).unwrap()["gettingToken"],false,"mobile shows a token page, not the desktop inline form");
        assert!(flow.edit(&one,other,&json!({"config":"secret"})).is_err());
        assert!(flow.edit(&one,ui,&json!({"requireMention":"false"})).is_err());
        flow.go(&one,ui,"token").unwrap();
        flow.edit(&one,ui,&json!({"config":"xoxe.xoxp-wrong"})).unwrap();
        assert!(flow.value(&one).unwrap()["configError"].is_string());
        assert!(flow.begin(&one,ui,"config",&json!({}),false).is_err());
        flow.edit(&one,ui,&json!({"config":" xoxe-1-long-enough-refresh-token "})).unwrap();
        let (generation,name,params)=flow.begin(&one,ui,"config",&json!({}),false).unwrap();
        assert_eq!(name,"slack.addConfigToken");assert_eq!(params["refreshToken"],"xoxe-1-long-enough-refresh-token");
        assert!(flow.go(&one,ui,"back").is_err());
        assert!(flow.begin(&one,ui,"config",&json!({}),false).is_err());
        flow.drop(&one,ui);flow.open(&one,ui,&json!({"mobile":true,"resume":"existing"})).unwrap();
        assert!(!flow.finish(&one,generation,"config",&Ok(json!({"teamId":"late"}))));
        assert_eq!(flow.value(&one).unwrap()["step"],"install");assert_eq!(flow.value(&one).unwrap()["back"],"close");
        call(&host,&core,ui,3,"pick.set",json!({"station":"ws/st","of":"connect-new:one","model":"gpt-6-astra","runtime":"codex"})).await.unwrap();
        call(&host,&core,ui,4,"pick.save",json!({"station":"ws/st","of":"connect-new:one"})).await.unwrap();
        assert_eq!(flow.value(&one).unwrap()["pick"]["value"]["model"],"gpt-6-astra");
        assert_ne!(flow.value(&two).unwrap()["pick"]["value"]["model"],"gpt-6-astra");
        core.disconnect(ui);
        assert!(flow.value(&one).is_err());assert!(flow.value(&two).is_err());
    });
}

#[test]
fn connect_wizard_configuration_and_oauth_install_keep_one_draft() {
    run(async {
        let (host, core) = choosing_core().await;
        let ui = core.connect();
        let topic = Topic::ConnectFlow { station: "ws/st".into(), form: "oauth".into() };
        let flow = &core.inner.connect_flow;
        flow.open(&topic, ui, &json!({"mobile":true})).unwrap();
        host.settle().await;
        flow.go(&topic, ui, "token").unwrap();
        flow.edit(&topic, ui, &json!({"config":"xoxe-1-a-refresh-token-for-test"})).unwrap();
        let (generation, _, _) = flow.begin(&topic, ui, "config", &json!({}), false).unwrap();
        flow.finish(&topic, generation, "config", &Ok(json!({"teamId":"T"})));
        let overview_topic = Topic::Overview { station: "ws/st".into() };
        let mut overview = core.inner.store.get(&overview_topic).unwrap();
        overview["slackTeams"] = json!([{"teamId":"T","teamName":"Team"}]);
        core.inner.data.set(&overview_topic, overview.clone());
        assert_eq!(flow.value(&topic).unwrap()["config"], "");
        let (generation, name, params) = flow.begin(&topic, ui, "make", &json!({}), false).unwrap();
        assert_eq!(name, "slack.makeApp");
        assert_eq!(params["team"], "T");
        assert_eq!(params["settings"]["groups"].as_object().unwrap().len(), 16);
        flow.finish(&topic, generation, "make", &Err(CoreError::invalid("try again")));
        assert_eq!(flow.value(&topic).unwrap()["step"], "app");
        let (generation, _, _) = flow.begin(&topic, ui, "make", &json!({}), false).unwrap();
        flow.finish(&topic, generation, "make", &Ok(json!({"appId":"A"})));
        overview["slackApps"] = json!([{"appId":"A","state":"oauth-state","installed":true}]);
        core.inner.data.set(&overview_topic, overview);
        let tokens = json!({"appToken":"app-token","botToken":""});
        let (generation, name, params) = flow.begin(&topic, ui, "verify", &tokens, false).unwrap();
        assert_eq!(name, "slack.verify");
        assert_eq!(params["install"], "oauth-state");
        flow.finish(&topic, generation, "verify", &Ok(json!({"identity":null,"errors":["invalid token"]})));
        assert_eq!(flow.value(&topic).unwrap()["step"], "install");
        let (generation, _, _) = flow.begin(&topic, ui, "verify", &tokens, false).unwrap();
        flow.finish(&topic, generation, "verify", &Ok(json!({"identity":{"teamId":"T"},"errors":[]})));
        assert!(flow.begin(&topic, ui, "create", &tokens, false).is_err());
        let (_, name, params) = flow.begin(&topic, ui, "create", &tokens, true).unwrap();
        assert_eq!(name, "connect.create");
        assert_eq!(params["input"]["slack"], json!({"appToken":"app-token","install":"oauth-state"}));
        assert!(host.requests.borrow().iter().all(|r| !r.url.contains("slack.com")));
    });
}

#[test]
fn an_agent_provided_close_option_never_posts_a_chat_message() {
    run(async {
        let (host, core) = station_core(0.0).await;
        let ui = core.connect();
        let card = json!({"seq":4,"card":{"type":"options","options":[{"label":"不需要部署","action":"close"},{"label":"部署"}]},
            "message":{"seq":4,"ts":"9.000004","text":"部署吗？","authorName":"Claude"}});
        core.inner.data.set(&Topic::ChatRows { station: "ws/st".into() }, json!([{"id":"k1","session":"k1","thread":7,"card":card}]));
        core.receive(ui, ClientMessage::Call { id: 71, call: "decision.answer".into(), params: json!({"station":"ws/st","thread":7,"seq":4,"option":"不需要部署"}) });
        host.settle().await;
        let requests = host.requests.borrow();
        let closed: Vec<Value> = requests.iter().filter(|r| r.method == "PUT" && r.url.ends_with("/threads/7/closed-card"))
            .map(|r| serde_json::from_slice(r.body.as_deref().unwrap_or_default()).unwrap()).collect();
        assert_eq!(closed, vec![json!({"n":4,"option":"不需要部署"})]);
        assert!(!requests.iter().any(|r| r.method == "POST" && r.url.ends_with("/threads/7/messages")));
    });
}

#[test]
fn preview_load_topic_reports_pending_finished_and_cancelled_resources() {
    run(async {
        let (host, core) = station_core(0.0).await;
        host.on_fetch_stream(|_| Ok(crate::host::StreamResponse {
            status: 200, headers: vec![("content-type".into(), "image/png".into())],
            body: futures::stream::pending().boxed_local(),
        }));
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 90, subscribe: Topic::PreviewLoad { station: "ws/st".into(), port: 5180 } });
        host.settle().await;
        let values = |host: &FakeHost| host.take_emitted().into_iter().filter_map(|(_, m)| match m { CoreMessage::Value { id: 90, value } => Some(value), _ => None }).collect::<Vec<_>>();
        assert_eq!(values(&host).last().unwrap()["total"], 0);
        core.receive(ui, ClientMessage::Call { id: 1, call: "station.preview".into(), params: json!({ "station": "ws/st", "port": 5180, "method": "GET", "path": "/slow.png", "stream": true }) });
        host.settle().await;
        let loading = values(&host).pop().unwrap();
        assert_eq!(loading["percent"], 0);
        assert_eq!(loading["resources"][0]["status"], 200);
        core.receive(ui, ClientMessage::Cancel { id: 1, cancel: true });
        host.settle().await;
        let cancelled = values(&host).pop().unwrap();
        assert_eq!(cancelled["percent"], 100);
        assert_eq!(cancelled["failed"], 1);
        assert_eq!(cancelled["resources"][0]["error"], "已取消");
    });
}

#[test]
fn session_speed_pick_sends_true_false_and_null_and_new_chats_keep_it() {
    run(async {
        let (host, core) = choosing_core_speed(true).await;
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 9, subscribe: Topic::NewChat { scope: "ws".into() } });
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Pick { station: "ws/st".into(), of: "session:k1".into() } });
        host.settle().await;
        let mut values = HashMap::new();
        apply(&host, &mut values);
        assert_eq!(values[&1]["fastAvailable"], true);
        for fast in [json!(true), json!(false)] {
            call(&host, &core, ui, 2, "pick.set", json!({"station":"ws/st", "of":"session:k1", "fast":fast})).await.unwrap();
            apply(&host, &mut values);
            assert_eq!(values[&1]["draft"]["fast"], fast);
            assert_eq!(values[&1]["changed"], true);
            call(&host, &core, ui, 3, "pick.save", json!({"station":"ws/st", "of":"session:k1"})).await.unwrap();
            assert_eq!(posted(&host, "/sessions/k1/settings").last().unwrap()["fast"], fast);
        }
        call(&host, &core, ui, 4, "newChat.pick", json!({"scope":"ws", "station":"st", "model":"gpt-6-astra", "fast":false})).await.unwrap();
        call(&host, &core, ui, 5, "newChat.create", json!({"station":"ws/st"})).await.unwrap();
        assert_eq!(posted(&host, "/sessions").last().unwrap()["fast"], false);
        call(&host, &core, ui, 6, "newChat.pick", json!({"scope":"ws", "fast":null})).await.unwrap();
        call(&host, &core, ui, 7, "newChat.create", json!({"station":"ws/st"})).await.unwrap();
        assert!(posted(&host, "/sessions").last().unwrap().get("fast").is_none());
    });
}

#[test]
fn speed_summary_only_shows_effective_fast_and_ignores_unsaved_drafts() {
    run(async {
        for profile_fast in [false, true] {
            for session_fast in [None, Some(false), Some(true)] {
                let (host, core) = choosing_core_speed_defaults(true, profile_fast, session_fast).await;
                let ui = core.connect();
                core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Pick { station: "ws/st".into(), of: "session:k1".into() } });
                host.settle().await;
                let mut values = HashMap::new();
                apply(&host, &mut values);
                let expected = if session_fast.unwrap_or(profile_fast) { json!("Fast") } else { Value::Null };
                assert_eq!(values[&1]["fastText"], expected);
                assert_eq!(values[&1]["fastAvailable"], true);
                call(&host, &core, ui, 2, "pick.set", json!({"station":"ws/st", "of":"session:k1", "fast": !session_fast.unwrap_or(profile_fast)})).await.unwrap();
                apply(&host, &mut values);
                assert_eq!(values[&1]["fastText"], expected, "drafts do not change the summary");

                core.receive(ui, ClientMessage::Subscribe { id: 9, subscribe: Topic::NewChat { scope: "ws".into() } });
                core.receive(ui, ClientMessage::Subscribe { id: 3, subscribe: Topic::Pick { station: "ws/st".into(), of: "new".into() } });
                host.settle().await;
                for pinned in [false, true] {
                    call(&host, &core, ui, 4, "newChat.pick", json!({"scope":"ws", "station":"st", "model":"gpt-6-astra", "profile":if pinned { "p3" } else { "" }, "fast": session_fast})).await.unwrap();
                    apply(&host, &mut values);
                    assert_eq!(values[&3]["fastText"], if session_fast.unwrap_or(pinned && profile_fast) { json!("Fast") } else { Value::Null });
                }
            }
        }
    });
}

#[test]
fn lends_the_phone_s_adb_through_its_calls_and_topic() {
    run(async {
        let (host, core) = station_core(0.0).await;
        let ui = core.connect();
        core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::AdbShare });
        host.settle().await;
        let mut values = HashMap::new();
        apply(&host, &mut values);
        assert_eq!((values[&1]["sharing"].clone(), values[&1]["phase"].clone()), (json!(false), json!("off")));
        core.receive(ui, ClientMessage::Call { id: 2, call: "adb.share".into(), params: json!({ "station": "ws1/st1", "connect": 41234, "device": "Pixel" }) });
        host.settle().await;
        apply(&host, &mut values);
        assert_eq!((values[&1]["sharing"].clone(), values[&1]["station"].clone(), values[&1]["connectPort"].clone()), (json!(true), json!("ws1/st1"), json!(41234)));
        assert!(values[&1]["until"].is_number());
        core.receive(ui, ClientMessage::Call { id: 3, call: "adb.stop".into(), params: json!({}) });
        host.settle().await;
        apply(&host, &mut values);
        // Off again, every field of the offer gone (the clients' shape takes their absence).
        assert_eq!(values[&1], json!({ "sharing": false, "phase": "off", "tunnels": 0 }));
    });
}

#[test]
fn automatic_decision_drafts_require_a_model_and_preserve_failed_saves() {
    run(async {
        let (host,core)=choosing_core().await;
        let ui=core.connect();let other=core.connect();
        let params=json!({"station":"ws/st","form":"automatic-test"});
        let topic=Topic::DecisionForm{station:"ws/st".into(),form:"automatic-test".into()};
        call(&host,&core,ui,1,"automaticDecisions.form.open",params.clone()).await.unwrap();
        let forms=&core.inner.decision_form;
        stillfail_shapes::conform::<stillfail_shapes::AutomaticDecisionDraft>(forms.value(&topic).unwrap()).unwrap();
        assert!(forms.change(&topic,other,"edit",&json!({"enabled":true})).is_err());
        forms.change(&topic,ui,"edit",&json!({"enabled":true})).unwrap();
        assert!(forms.begin(&topic,ui).is_err());
        forms.change(&topic,ui,"edit",&json!({"model":"gpt-6-luna"})).unwrap();
        assert_eq!(forms.begin(&topic,ui).unwrap(),json!({"completion":{"enabled":true,"model":"gpt-6-luna"}}));
        assert!(forms.change(&topic,ui,"edit",&json!({"enabled":false})).is_err());
        forms.finish(&topic,ui,&Err(CoreError::invalid("save failed")));
        assert_eq!(forms.value(&topic).unwrap()["dirty"],true);
        forms.begin(&topic,ui).unwrap();forms.finish(&topic,ui,&Ok(json!({})));
        assert_eq!(forms.value(&topic).unwrap()["dirty"],false);
        forms.change(&topic,ui,"drop",&json!({})).unwrap();assert!(forms.value(&topic).unwrap().is_null());
    });
}
