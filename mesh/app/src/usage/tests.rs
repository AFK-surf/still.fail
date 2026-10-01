use std::io::Write;

use serde_json::json;

use super::*;
use crate::store::{AuthorKind, NewMessage, NewSession, TurnFor};
use crate::transcript::iso;

fn claude_line(id: &str, at: i64, model: &str, usage: Value) -> String {
    json!({ "type": "assistant", "timestamp": iso(at), "isSidechain": false, "message": { "id": id, "model": model, "usage": usage } }).to_string()
}

fn usage(input: i64, read: i64, short: i64, long: i64, output: i64) -> Value {
    json!({
        "input_tokens": input,
        "cache_read_input_tokens": read,
        "cache_creation_input_tokens": short + long,
        "cache_creation": { "ephemeral_5m_input_tokens": short, "ephemeral_1h_input_tokens": long },
        "output_tokens": output,
    })
}

#[test]
fn a_claude_response_written_as_several_lines_counts_once_with_its_cache_split_by_how_long() {
    let text = [
        claude_line("m1", 1000, "claude-opus-5-5", usage(2, 100, 0, 50, 10)),
        claude_line("m1", 1001, "claude-opus-5-5", usage(2, 100, 0, 50, 30)),
        json!({ "type": "user", "message": { "content": "usage" } }).to_string(),
        claude_line("m2", 2000, "<synthetic>", usage(0, 0, 0, 0, 0)),
        claude_line("m3", 3000, "claude-sonnet-5-5", json!({ "input_tokens": 5, "cache_creation_input_tokens": 7, "output_tokens": 1, "speed": "fast" })),
    ]
    .join("\n");
    let calls = calls_of(RuntimeKind::Claude, &text, false, &mut None, &mut None);
    assert_eq!(calls.len(), 2);
    assert_eq!(
        calls[0],
        UsageCall { id: "m1".into(), at: 1000, model: Some("claude-opus-5-5".into()), subagent: false, fast: false, input: 2, cache_read: 100, cache_write: 0, cache_write_long: 50, output: 30 }
    );
    // Without the split, what was written to the cache is taken as written for five minutes.
    assert_eq!((calls[1].cache_write, calls[1].cache_write_long, calls[1].fast), (7, 0, true));
}

#[test]
fn codex_calls_are_its_token_counts_told_once_each_with_the_model_its_turn_named() {
    let count = |total: i64, input: i64, cached: i64, output: i64| {
        json!({ "timestamp": iso(5000), "type": "event_msg", "payload": { "type": "token_count", "info": {
            "total_token_usage": { "total_tokens": total },
            "last_token_usage": { "input_tokens": input, "cached_input_tokens": cached, "output_tokens": output },
        } } })
        .to_string()
    };
    let text = [
        json!({ "timestamp": iso(4000), "type": "session_meta", "payload": { "id": "th1", "cwd": "/w" } }).to_string(),
        json!({ "timestamp": iso(4000), "type": "turn_context", "payload": { "model": "gpt-6" } }).to_string(),
        count(120, 100, 60, 20),
        // The same count again, told with the rate limits.
        count(120, 100, 60, 20),
        json!({ "timestamp": iso(5000), "type": "event_msg", "payload": { "type": "token_count", "info": null } }).to_string(),
        count(200, 70, 10, 10),
    ]
    .join("\n");
    let (mut model, mut id) = (None, None);
    let calls = calls_of(RuntimeKind::Codex, &text, false, &mut model, &mut id);
    let ids: Vec<&str> = calls.iter().map(|c| c.id.as_str()).collect();
    assert_eq!(ids, ["codex:th1:120", "codex:th1:120", "codex:th1:200"], "repeats are left to the store, which keeps one");
    assert_eq!((calls[0].input, calls[0].cache_read, calls[0].output, calls[0].model.as_deref()), (40, 60, 20, Some("gpt-6")));
    assert_eq!(model.as_deref(), Some("gpt-6"));
}

#[test]
fn prices_are_found_however_a_profile_spells_the_model_and_cost_counts_each_kind_of_token() {
    assert_eq!(price("claude-opus-5-5").map(|p| p.input), Some(4.0));
    assert_eq!(price("anthropic/claude-opus-5-5[1m]").map(|p| p.cache_read), Some(0.2));
    assert_eq!(price("claude-opus-5").map(|p| p.input), Some(5.0));
    assert_eq!(price("claude-fable-5-1").map(|p| p.cache_read), Some(0.25));
    assert_eq!(price("gpt-6"), None);
    let g = UsageGroup { model: Some("claude-opus-5-5".into()), input: 1_000_000, cache_read: 1_000_000, cache_write: 1_000_000, cache_write_long: 1_000_000, output: 1_000_000, ..Default::default() };
    // 4 + 0.2 + 5 + 8 + 20
    assert!((cost(&g).unwrap() - 37.2).abs() < 1e-9);
    assert!((cost(&UsageGroup { fast: true, ..g.clone() }).unwrap() - 74.4).abs() < 1e-9);
    assert_eq!(cost(&UsageGroup { model: Some("gpt-6".into()), ..g }), None);
}

struct Rig {
    _dir: tempfile::TempDir,
    data: PathBuf,
    store: Arc<Store>,
    usage: Arc<Usage>,
}

fn rig() -> Rig {
    let dir = tempfile::tempdir().unwrap();
    let data = dir.path().to_path_buf();
    let path = data.join("config.json");
    std::fs::write(&path, json!({ "profiles": [{ "id": "cc", "runtime": "claude", "home": "homes/cc" }] }).to_string()).unwrap();
    let settings = Settings::open(&path, &data).unwrap();
    let store = Arc::new(Store::open(":memory:", None).unwrap());
    let usage = Usage::new(store.clone(), settings);
    Rig { _dir: dir, data, store, usage }
}

fn session(store: &Store, key: &str, workspace: &Path, created_at: i64) {
    store
        .insert_session(&NewSession {
            key: key.into(),
            connect: "ember".into(),
            created_by: Some("creator@x".into()),
            runtime: "claude".into(),
            profile: "cc".into(),
            workspace: workspace.to_string_lossy().into(),
            token: format!("t-{key}"),
            created_at,
            last_active_at: created_at,
            ..Default::default()
        })
        .unwrap();
}

fn append(path: &Path, lines: &[String]) {
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    let mut f = std::fs::OpenOptions::new().create(true).append(true).open(path).unwrap();
    for l in lines {
        writeln!(f, "{l}").unwrap();
    }
}

fn pause() {
    std::thread::sleep(Duration::from_millis(15));
}

#[test]
fn each_call_is_counted_once_for_whom_its_turn_worked_where_and_on_what() {
    let r = rig();
    let workspace = r.data.join("sessions/ember/c-1/workspace");
    let created = now_ms();
    session(&r.store, "ember:c-1", &workspace, created);
    let chat = r.store.open_thread_of("ember", "ember", "1.0", None, Some("creator@x"), Some("ember:c-1")).unwrap();
    r.store.join_thread(chat.id, "ember:c-1", "ember").unwrap();
    pause();
    // A turn from before turns said whom they were for: its first person's message says.
    r.store.start_turn("t1", "ember:c-1", "input").unwrap();
    let (n, _) = r.store.insert_message(NewMessage::new(chat.id, "2.0", AuthorKind::Person, "b@x", "hi")).unwrap();
    r.store.deliver(chat.id, n, &["ember:c-1".into()]).unwrap();
    r.store.mark_delivered("ember:c-1", &[(chat.id, n)]).unwrap();
    r.store.end_turn("t1", "completed", None, None, None).unwrap();
    pause();
    r.store.start_turn_for("t2", "ember:c-1", "input", &TurnFor { profile: Some("cc2".into()), person: Some("a@x".into()), thread: Some(chat.id) }).unwrap();
    r.store.end_turn("t2", "completed", None, None, None).unwrap();
    pause();
    // A job's notice goes on with the work of the turn before.
    r.store.start_turn("t3", "ember:c-1", "job").unwrap();
    let starts: Vec<i64> = r.store.list_turns("ember:c-1").unwrap().iter().map(|t| t.summary.started_at).collect();

    let project = r.data.join("transcripts/claude").join(claude_project(&workspace));
    let main = project.join("r1.jsonl");
    append(
        &main,
        &[
            // From a terminal, before the station had it: not counted.
            claude_line("m0", created - 60_000, "claude-opus-5-5", usage(1, 0, 0, 0, 1)),
            claude_line("m1", starts[0] + 1, "claude-opus-5-5", usage(10, 0, 0, 0, 1)),
            claude_line("m2", starts[1] + 1, "claude-opus-5-5", usage(20, 0, 0, 0, 2)),
        ],
    );
    append(&project.join("r1/subagents/agent-a.jsonl"), &[claude_line("s1", starts[1] + 2, "claude-haiku-4-5", usage(5, 0, 0, 0, 5))]);
    assert_eq!(r.usage.read().unwrap(), 3);

    let mut rows = r.usage.summary(0, i64::MAX, 0).unwrap();
    rows.sort_by_key(|g| g.input);
    let who: Vec<(i64, Option<&str>, Option<&str>, Option<i64>)> = rows.iter().map(|g| (g.input, g.person.as_deref(), g.profile.as_deref(), g.thread)).collect();
    assert_eq!(who, [(5, Some("a@x"), Some("cc2"), Some(chat.id)), (10, Some("b@x"), Some("cc"), Some(chat.id)), (20, Some("a@x"), Some("cc2"), Some(chat.id))]);

    // Read again: only what was written since, and nothing twice (the last line of a response written again too).
    append(&main, &[claude_line("m2", starts[1] + 1, "claude-opus-5-5", usage(20, 0, 0, 0, 9)), claude_line("m3", starts[2] + 1, "claude-opus-5-5", usage(30, 0, 0, 0, 3))]);
    assert_eq!(r.usage.read().unwrap(), 1);
    let rows = r.usage.summary(0, i64::MAX, 0).unwrap();
    let total = |f: fn(&UsageRow) -> i64| rows.iter().map(f).sum::<i64>();
    assert_eq!((total(|g| g.calls), total(|g| g.input), total(|g| g.output)), (4, 65, 1 + 9 + 5 + 3));
    let job = rows.iter().find(|g| g.input == 30).unwrap();
    assert_eq!((job.person.as_deref(), job.thread), (Some("a@x"), Some(chat.id)));
    assert_eq!(r.store.usage_since().unwrap(), Some(starts[0] + 1));

    // Its session gone, what it spent stays.
    r.store.delete_session("ember:c-1").unwrap();
    assert_eq!(r.usage.summary(0, i64::MAX, 0).unwrap().iter().map(|g| g.calls).sum::<i64>(), 4);
}

#[test]
fn days_are_the_askers_own() {
    let r = rig();
    let workspace = r.data.join("w");
    session(&r.store, "k", &workspace, 0);
    // 2026-10-01T23:30Z: still the 1st in UTC, the 2nd in UTC+8.
    let at = parse_iso("2026-10-01T23:30:00.000Z").unwrap();
    append(&r.data.join("transcripts/claude").join(claude_project(&workspace)).join("r.jsonl"), &[claude_line("m", at, "claude-opus-5-5", usage(1, 0, 0, 0, 1))]);
    r.usage.read().unwrap();
    assert_eq!(r.usage.summary(0, i64::MAX, 0).unwrap()[0].day, "2026-10-01");
    assert_eq!(r.usage.summary(0, i64::MAX, 480).unwrap()[0].day, "2026-10-02");
    assert!(r.usage.summary(at + 1, i64::MAX, 0).unwrap().is_empty());
}
