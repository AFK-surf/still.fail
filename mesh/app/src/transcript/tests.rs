//! test/transcript.test.ts (and the transcript tests of live.test.ts and profiles.test.ts), ported.

use super::*;
use serde_json::json;
use std::io::Write;

fn file(lines: &[Value]) -> (tempfile::TempDir, PathBuf) {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("t.jsonl");
    let text: Vec<String> = lines.iter().map(|l| l.to_string()).collect();
    std::fs::write(&path, format!("{}\n{{\"partial", text.join("\n"))).unwrap();
    (dir, path)
}

fn read(runtime: RuntimeKind, path: &Path) -> Vec<TimelineEntry> {
    TranscriptTail::new(runtime, path.to_path_buf()).read().1
}

#[test]
fn claude_transcripts_become_a_timeline_subagent_work_marked() {
    let (_dir, path) = file(&[
        json!({ "type": "user", "timestamp": "t1", "message": { "content": "fix it" } }),
        json!({ "type": "assistant", "message": { "content": [{ "type": "thinking", "thinking": "hmm" }, { "type": "text", "text": "on it" }, { "type": "tool_use", "id": "tu1", "name": "Bash", "input": { "command": "ls" } }] } }),
        json!({ "type": "user", "message": { "content": [{ "type": "tool_result", "tool_use_id": "tu1", "is_error": true, "content": [{ "type": "text", "text": "boom" }] }] } }),
        json!({ "type": "assistant", "isSidechain": true, "message": { "content": [{ "type": "text", "text": "sub" }] } }),
        json!({ "type": "user", "isMeta": true, "message": { "content": "injected" } }),
        json!({ "type": "attachment" }),
    ]);
    let timeline = read(RuntimeKind::Claude, &path);
    assert_eq!(timeline[3].call_id.as_deref(), Some("tu1"));
    assert_eq!(timeline[4].call_id.as_deref(), Some("tu1"));
    let plain: Vec<(&str, &str, Option<bool>, Option<bool>)> = timeline.iter().map(|e| (e.kind.as_str(), e.text.as_str(), e.ok, e.subagent)).collect();
    assert_eq!(
        plain,
        vec![
            ("user", "fix it", None, None),
            ("thinking", "hmm", None, None),
            ("assistant", "on it", None, None),
            ("tool_call", "{\n  \"command\": \"ls\"\n}", None, None),
            ("tool_result", "boom", Some(false), None),
            ("assistant", "sub", None, Some(true)),
        ]
    );
}

#[test]
fn codex_rollouts_become_a_timeline_without_injected_context() {
    let (_dir, path) = file(&[
        json!({ "type": "session_meta", "payload": {} }),
        json!({ "type": "response_item", "payload": { "type": "message", "role": "developer", "content": [{ "type": "input_text", "text": "rules" }] } }),
        json!({ "type": "response_item", "payload": { "type": "message", "role": "user", "content": [{ "type": "input_text", "text": "<environment_context>…" }] } }),
        json!({ "type": "response_item", "timestamp": "t2", "payload": { "type": "message", "role": "user", "content": [{ "type": "input_text", "text": "# AGENTS.md instructions\n\n<INSTRUCTIONS>…</INSTRUCTIONS>" }, { "type": "input_text", "text": "<recommended_plugins>…</recommended_plugins>" }, { "type": "input_text", "text": "count files" }] } }),
        json!({ "type": "response_item", "payload": { "type": "reasoning", "summary": [], "content": [{ "type": "reasoning_text", "text": "easy" }] } }),
        json!({ "type": "response_item", "payload": { "type": "function_call", "name": "exec_command", "call_id": "c1", "arguments": "{\"cmd\":\"ls\"}" } }),
        json!({ "type": "response_item", "payload": { "type": "function_call_output", "call_id": "c1", "output": "Process exited with code 2\nOutput:\nnope" } }),
        json!({ "type": "response_item", "payload": { "type": "message", "role": "assistant", "content": [{ "type": "output_text", "text": "5" }] } }),
    ]);
    let timeline = read(RuntimeKind::Codex, &path);
    let plain: Vec<(&str, Option<&str>, Option<bool>)> = timeline.iter().map(|e| (e.kind.as_str(), e.tool.as_deref(), e.ok)).collect();
    assert_eq!(
        plain,
        vec![("user", None, None), ("thinking", None, None), ("tool_call", Some("exec_command"), None), ("tool_result", None, Some(false)), ("assistant", None, None)]
    );
    assert_eq!((timeline[0].at.as_deref(), timeline[0].text.as_str()), (Some("t2"), "count files"));
    assert_eq!((timeline[2].call_id.as_deref(), timeline[3].call_id.as_deref()), (Some("c1"), Some("c1")));
}

#[test]
fn transcripts_are_found_where_each_runtime_keeps_them() {
    let home = tempfile::tempdir().unwrap();
    let h = home.path();
    std::fs::create_dir_all(h.join("projects/-some-cwd")).unwrap();
    std::fs::write(h.join("projects/-some-cwd/abc.jsonl"), "").unwrap();
    std::fs::create_dir_all(h.join("sessions/2026/09/26")).unwrap();
    std::fs::write(h.join("sessions/2026/09/26/rollout-2026-09-26T00-00-00-xyz.jsonl"), "").unwrap();
    assert_eq!(transcript_path(RuntimeKind::Claude, h, "abc"), Some(h.join("projects/-some-cwd/abc.jsonl")));
    assert_eq!(transcript_path(RuntimeKind::Codex, h, "xyz"), Some(h.join("sessions/2026/09/26/rollout-2026-09-26T00-00-00-xyz.jsonl")));
    assert_eq!(transcript_path(RuntimeKind::Claude, h, "missing"), None);
}

#[test]
fn codex_code_mode_the_tool_calls_in_an_exec_script_are_its_steps_read_as_data() {
    let post = script_calls("text(await tools.mcp__ember__chat_post({to:\"EMBER/1790434911.559000\",text:\"你好，我在。\\n有什么\\\"事\\\"？\",kind:\"final\"}));\n");
    assert_eq!(post, (vec![("mcp__ember__chat_post".to_string(), json!({ "to": "EMBER/1790434911.559000", "text": "你好，我在。\n有什么\"事\"？", "kind": "final" }))], true));
    // More than calls: the script stays, the calls in it too.
    let mixed = script_calls("text(ALL_TOOLS.filter(x=>/chat_post/.test(x.name)));\ntext(await tools.exec_command({cmd:\"cat SKILL.md\",max_output_tokens:3000}));\n");
    assert_eq!(mixed, (vec![("exec_command".to_string(), json!({ "cmd": "cat SKILL.md", "max_output_tokens": 3000 }))], false));
    // An argument that is not a literal is not read (nothing is run).
    assert_eq!(script_calls("await tools.mcp__ember__chat_post(build())"), (vec![], false));
    assert!(script_calls("await tools.x({a:`${secret}`})").0.is_empty());
}

#[test]
fn a_transcript_leaves_out_its_agents_posts_and_weaves_them_back_by_time() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("rollout.jsonl");
    let line = |payload: Value, timestamp: &str| json!({ "type": "response_item", "timestamp": timestamp, "payload": payload }).to_string();
    let lines = [
        line(json!({ "type": "message", "role": "user", "content": [{ "type": "input_text", "text": "hi" }] }), "2026-09-27T00:00:00.000Z"),
        line(json!({ "type": "custom_tool_call", "name": "exec", "call_id": "c1", "input": "text(await tools.mcp__ember__chat_post({to:\"EMBER/1\",text:\"hello\",kind:\"final\"}));" }), "2026-09-27T00:00:02.000Z"),
        line(json!({ "type": "custom_tool_call_output", "call_id": "c1", "output": [{ "type": "input_text", "text": "Script completed" }] }), "2026-09-27T00:00:03.000Z"),
        line(json!({ "type": "function_call", "name": "mcp__ember__chat_post", "call_id": "c2", "arguments": "{}" }), "2026-09-27T00:00:04.000Z"),
        line(json!({ "type": "function_call_output", "call_id": "c2", "output": "Posted" }), "2026-09-27T00:00:05.000Z"),
        line(json!({ "type": "message", "role": "assistant", "content": [{ "type": "output_text", "text": "done" }] }), "2026-09-27T00:00:06.000Z"),
    ];
    std::fs::write(&path, format!("{}\n", lines.join("\n"))).unwrap();
    let mut tail = TranscriptTail::new(RuntimeKind::Codex, path);
    tail.read();
    assert_eq!(tail.entries.iter().map(|e| e.kind.as_str()).collect::<Vec<_>>(), vec!["user", "assistant"], "the posting calls and their outputs are left out");
    let mut woven = TimelineEntry::new(Some("2026-09-27T00:00:02.500Z".into()), "tool_call", "{}".into());
    woven.tool = Some("mcp__ember__chat_post".into());
    tail.weave(vec![woven]);
    assert_eq!(tail.entries.iter().map(|e| e.kind.as_str()).collect::<Vec<_>>(), vec!["user", "tool_call", "assistant"], "woven in by time");
}

fn claude_line(text: &str, id: &str) -> String {
    format!(
        "{}\n",
        json!({ "type": "assistant", "timestamp": "2026-09-26T00:00:00Z", "message": { "id": id, "content": [{ "type": "text", "text": text }], "usage": { "input_tokens": 10, "output_tokens": 2 } } })
    )
}

#[test]
fn a_transcript_read_as_it_grows_gives_what_a_full_read_gives() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("t.jsonl");
    std::fs::write(&path, claude_line("one", "m1")).unwrap();
    let mut tail = TranscriptTail::new(RuntimeKind::Claude, path.clone());
    assert_eq!(tail.read().1.iter().map(|e| e.text.as_str()).collect::<Vec<_>>(), vec!["one"]);
    let two = claude_line("two", "m2");
    let mut f = std::fs::OpenOptions::new().append(true).open(&path).unwrap();
    f.write_all(&two.as_bytes()[..20]).unwrap();
    assert_eq!(tail.read(), (1, vec![]));
    f.write_all(&two.as_bytes()[20..]).unwrap();
    let (start, entries) = tail.read();
    assert_eq!((start, entries.iter().map(|e| e.text.as_str()).collect::<Vec<_>>()), (1, vec!["two"]));
    assert_eq!(tail.entries.iter().map(|e| e.text.as_str()).collect::<Vec<_>>(), vec!["one", "two"]);
    assert_eq!(TranscriptTail::new(RuntimeKind::Claude, path).read().1, tail.entries, "read in pieces, the same as read at once");
    assert_eq!(tail.usage.model_calls, 2);
}

#[test]
fn usage_sums_model_requests_and_claudes_split_responses_count_once() {
    let usage = json!({ "input_tokens": 100, "cache_read_input_tokens": 900, "cache_creation_input_tokens": 0, "output_tokens": 50 });
    let (_d1, claude) = file(&[
        json!({ "type": "assistant", "message": { "id": "m1", "model": "deepseek-flash", "usage": usage } }),
        json!({ "type": "assistant", "message": { "id": "m1", "model": "deepseek-flash", "usage": usage } }),
        json!({ "type": "assistant", "message": { "id": "m2", "model": "deepseek-flash", "usage": usage } }),
    ]);
    let mut tail = TranscriptTail::new(RuntimeKind::Claude, claude);
    tail.read();
    assert_eq!(tail.usage, TranscriptUsage { model_calls: 2, input_tokens: 2000, cached_tokens: 1800, output_tokens: 100, model: Some("deepseek-flash".into()) });
    let (_d2, codex) = file(&[
        json!({ "type": "turn_context", "payload": { "model": "gpt-5" } }),
        json!({ "type": "event_msg", "payload": { "type": "token_count", "info": { "last_token_usage": { "input_tokens": 10, "cached_input_tokens": 4, "output_tokens": 2 } } } }),
        json!({ "type": "event_msg", "payload": { "type": "token_count", "info": null } }),
        json!({ "type": "event_msg", "payload": { "type": "token_count", "info": { "last_token_usage": { "input_tokens": 20, "cached_input_tokens": 0, "output_tokens": 3 } } } }),
    ]);
    let mut tail = TranscriptTail::new(RuntimeKind::Codex, codex);
    tail.read();
    assert_eq!(tail.usage, TranscriptUsage { model_calls: 2, input_tokens: 30, cached_tokens: 4, output_tokens: 5, model: Some("gpt-5".into()) });
}

#[test]
fn iso_times_are_read_to_the_millisecond() {
    assert_eq!(parse_iso("1970-01-01T00:00:00Z"), Some(0));
    assert_eq!(parse_iso("2026-09-27T00:00:02.500Z"), Some(1_790_467_202_500));
}

#[test]
fn iso_round_trips() {
    for at in ["2026-09-27T00:00:02.500Z", "2024-02-29T23:59:59.999Z", "1970-01-01T00:00:00.000Z"] {
        assert_eq!(iso(parse_iso(at).unwrap()), at);
    }
}

#[test]
fn posting_names_survive_the_namespace_migration() {
    assert!(super::is_posting("mcp__stillfail__chat_post"));
    assert!(super::is_posting("mcp__ember__chat_post"));
    assert!(!super::is_posting("mcp__stillfail__chat_history"));
}

#[test]
fn compressed_transcript_stays_discoverable_and_continues_after_restore() {
    let home = tempfile::tempdir().unwrap();
    let path = home.path().join("projects/x/archive-test.jsonl");
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    let line = |text: &str| format!("{}\n", serde_json::json!({"type":"user", "message":{"content":text}}));
    std::fs::write(&path, line("before")).unwrap();
    crate::archive::pack_file(&path).unwrap();
    assert_eq!(transcript_path(RuntimeKind::Claude, home.path(), "archive-test"), Some(path.clone()));
    let mut tail = TranscriptTail::new(RuntimeKind::Claude, path.clone());
    assert_eq!(tail.read().1[0].text, "before");
    assert!(tail.read().1.is_empty());
    crate::archive::restore_file(&path).unwrap();
    std::fs::write(&path, format!("{}{}", line("before"), line("after"))).unwrap();
    assert_eq!(tail.read().1[0].text, "after");
    assert_eq!(tail.entries.len(), 2);
}
