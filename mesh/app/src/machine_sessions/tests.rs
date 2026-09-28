use serde_json::json;

use super::*;

fn lines(records: &[Value]) -> String {
    records.iter().map(|r| format!("{r}\n")).collect()
}

/// A machine with one Claude Code session and one Codex session, the Codex one written later.
pub(crate) fn machine(root: &Path, project: &Path) -> MachineRoots {
    let roots = MachineRoots { claude: root.join(".claude/projects"), codex: root.join(".codex/sessions") };
    let cwd = project.to_string_lossy();
    let claude_dir = roots.claude.join(cwd.replace('/', "-"));
    std::fs::create_dir_all(&claude_dir).unwrap();
    std::fs::write(
        claude_dir.join("11111111-aaaa-bbbb-cccc-000000000001.jsonl"),
        lines(&[
            json!({ "type": "ai-title", "aiTitle": "Old name" }),
            json!({ "type": "user", "cwd": cwd, "isMeta": true, "timestamp": "2026-09-01T00:00:00.000Z", "message": { "content": "meta" } }),
            json!({ "type": "user", "cwd": cwd, "timestamp": "2026-09-01T00:00:01.000Z", "message": { "content": "<command-name>/model</command-name>" } }),
            json!({ "type": "user", "cwd": cwd, "timestamp": "2026-09-01T00:00:02.000Z", "message": { "content": "fix   the\nbuild" } }),
            json!({ "type": "assistant", "cwd": cwd, "timestamp": "2026-09-01T00:00:03.000Z", "message": { "content": [{ "type": "thinking", "thinking": "hm" }, { "type": "text", "text": "Looking." }] } }),
            json!({ "type": "assistant", "cwd": cwd, "timestamp": "2026-09-01T00:00:04.000Z", "message": { "content": [{ "type": "tool_use", "id": "t1", "name": "Bash", "input": {} }] } }),
            json!({ "type": "user", "cwd": cwd, "timestamp": "2026-09-01T00:00:05.000Z", "message": { "content": [{ "type": "tool_result", "tool_use_id": "t1", "content": "ok" }] } }),
            json!({ "type": "assistant", "cwd": cwd, "isSidechain": true, "timestamp": "2026-09-01T00:00:05.500Z", "message": { "content": [{ "type": "text", "text": "a subagent" }] } }),
            json!({ "type": "assistant", "cwd": cwd, "timestamp": "2026-09-01T00:00:06.000Z", "message": { "model": "claude-opus-5-5", "content": [{ "type": "text", "text": "Fixed." }] } }),
            json!({ "type": "assistant", "cwd": cwd, "isApiErrorMessage": true, "timestamp": "2026-09-01T00:00:06.500Z", "message": { "content": [{ "type": "text", "text": "Not logged in · Please run /login" }] } }),
            json!({ "type": "user", "cwd": cwd, "isCompactSummary": true, "timestamp": "2026-09-01T00:00:07.000Z", "message": { "content": "This session is being continued…" } }),
            json!({ "type": "user", "cwd": cwd, "timestamp": "2026-09-01T00:00:08.000Z", "message": { "content": [{ "type": "text", "text": "thanks" }] } }),
            json!({ "type": "ai-title", "aiTitle": "Fix the build" }),
        ]),
    )
    .unwrap();
    // Nothing asked: not listed.
    std::fs::write(claude_dir.join("11111111-aaaa-bbbb-cccc-000000000002.jsonl"), lines(&[json!({ "type": "user", "cwd": cwd, "isMeta": true, "message": { "content": "x" } })])).unwrap();
    let codex_dir = roots.codex.join("2026/09/02");
    std::fs::create_dir_all(&codex_dir).unwrap();
    std::fs::write(
        codex_dir.join("rollout-2026-09-02T00-00-00-22222222-aaaa-bbbb-cccc-000000000001.jsonl"),
        lines(&[
            json!({ "type": "session_meta", "payload": { "id": "22222222-aaaa-bbbb-cccc-000000000001", "cwd": cwd } }),
            json!({ "type": "response_item", "timestamp": "2026-09-02T00:00:00.000Z", "payload": { "type": "message", "role": "user", "content": [{ "type": "input_text", "text": "<environment_context>…</environment_context>" }] } }),
            json!({ "type": "response_item", "timestamp": "2026-09-02T00:00:00.500Z", "payload": { "type": "message", "role": "user", "content": [{ "type": "input_text", "text": "<recommended_plugins>\nHere is a list…\n</recommended_plugins>" }] } }),
            json!({ "type": "response_item", "timestamp": "2026-09-02T00:00:01.000Z", "payload": { "type": "message", "role": "user", "content": [{ "type": "input_text", "text": "<skills_instructions>…</skills_instructions>" }, { "type": "input_text", "text": "<recommended_plugins>…</recommended_plugins>" }, { "type": "input_text", "text": "add a test" }] } }),
            json!({ "type": "turn_context", "payload": { "model": "gpt-5.5" } }),
            json!({ "type": "response_item", "timestamp": "2026-09-02T00:00:02.000Z", "payload": { "type": "reasoning", "summary": [] } }),
            json!({ "type": "response_item", "timestamp": "2026-09-02T00:00:03.000Z", "payload": { "type": "message", "role": "assistant", "content": [{ "type": "output_text", "text": "Added." }] } }),
        ]),
    )
    .unwrap();
    std::fs::write(root.join(".codex/session_index.jsonl"), lines(&[
        json!({ "id": "22222222-aaaa-bbbb-cccc-000000000001", "thread_name": "Old" }),
        json!({ "id": "22222222-aaaa-bbbb-cccc-000000000001", "thread_name": "Add a test" }),
    ]))
    .unwrap();
    let older = std::time::SystemTime::now() - std::time::Duration::from_secs(60);
    std::fs::File::options().append(true).open(claude_dir.join("11111111-aaaa-bbbb-cccc-000000000001.jsonl")).unwrap().set_modified(older).unwrap();
    roots
}

#[test]
fn the_machines_sessions_are_listed_newest_first_with_where_they_ran_their_name_and_first_words() {
    let dir = tempfile::tempdir().unwrap();
    let project = dir.path().join("app");
    let roots = machine(dir.path(), &project);
    let found = list(&roots, 10);
    assert_eq!(found.iter().map(|s| (s.runtime, s.id.as_str())).collect::<Vec<_>>(), vec![
        (RuntimeKind::Codex, "22222222-aaaa-bbbb-cccc-000000000001"),
        (RuntimeKind::Claude, "11111111-aaaa-bbbb-cccc-000000000001"),
    ]);
    assert_eq!(found[0].first.as_deref(), Some("add a test"));
    assert_eq!(found[0].title.as_deref(), Some("Add a test"));
    assert_eq!(found[1].cwd, project.to_string_lossy());
    assert_eq!(found[1].title.as_deref(), Some("Fix the build"));
    assert_eq!(found[1].first.as_deref(), Some("fix the build"));
    assert_eq!((found[0].model.as_deref(), found[1].model.as_deref()), (Some("gpt-5.5"), Some("claude-opus-5-5")));
    assert_eq!(list(&roots, 1).len(), 1);
}

#[test]
fn a_session_is_found_by_its_runtime_and_id_only() {
    let dir = tempfile::tempdir().unwrap();
    let roots = machine(dir.path(), &dir.path().join("app"));
    assert!(find(&roots, RuntimeKind::Claude, "11111111-aaaa-bbbb-cccc-000000000001").is_some());
    assert!(find(&roots, RuntimeKind::Codex, "22222222-aaaa-bbbb-cccc-000000000001").is_some());
    assert!(find(&roots, RuntimeKind::Codex, "11111111-aaaa-bbbb-cccc-000000000001").is_none());
    assert!(find(&roots, RuntimeKind::Claude, "../x").is_none());
    assert!(find(&roots, RuntimeKind::Claude, "11111111-aaaa-bbbb-cccc-000000000002").is_none());
}

#[test]
fn the_conversation_is_what_people_said_and_each_turns_words_of_the_agent() {
    let dir = tempfile::tempdir().unwrap();
    let roots = machine(dir.path(), &dir.path().join("app"));
    let claude = find(&roots, RuntimeKind::Claude, "11111111-aaaa-bbbb-cccc-000000000001").unwrap();
    let said = conversation(RuntimeKind::Claude, &claude.path);
    let shown: Vec<(bool, &str)> = said.iter().map(|s| (s.person, s.text.as_str())).collect();
    assert_eq!(shown, vec![(true, "fix   the\nbuild"), (false, "Looking.\n\nFixed."), (true, "thanks")]);
    assert_eq!(said[0].at, parse_iso("2026-09-01T00:00:02.000Z"));
    let codex = find(&roots, RuntimeKind::Codex, "22222222-aaaa-bbbb-cccc-000000000001").unwrap();
    let said = conversation(RuntimeKind::Codex, &codex.path);
    assert_eq!(said.iter().map(|s| (s.person, s.text.as_str())).collect::<Vec<_>>(), vec![(true, "add a test"), (false, "Added.")]);
}

#[test]
fn a_newer_codex_rollout_is_read_from_its_events_of_what_was_said() {
    let dir = tempfile::tempdir().unwrap();
    let cwd = dir.path().to_string_lossy();
    let roots = MachineRoots { claude: dir.path().join("none"), codex: dir.path().join("sessions") };
    std::fs::create_dir_all(roots.codex.join("2026/09/03")).unwrap();
    let item = |kind: &str, text: &str| json!({ "type": "event_msg", "payload": { "type": "item_completed", "item": { "type": kind, "content": [{ "type": "text", "text": text }] } } });
    std::fs::write(
        roots.codex.join("2026/09/03/rollout-2026-09-03T00-00-00-33333333-aaaa-bbbb-cccc-000000000001.jsonl"),
        lines(&[
            json!({ "type": "session_meta", "payload": { "id": "33333333-aaaa-bbbb-cccc-000000000001", "cwd": cwd } }),
            json!({ "type": "response_item", "payload": { "type": "message", "role": "user", "content": [{ "type": "input_text", "text": "# AGENTS.md instructions\n\n<INSTRUCTIONS>…</INSTRUCTIONS>" }, { "type": "input_text", "text": "look at the vm" }] } }),
            item("UserMessage", "look at the vm\n"),
            item("AgentMessage", "Checking."),
            json!({ "type": "response_item", "payload": { "type": "message", "role": "assistant", "content": [{ "type": "output_text", "text": "Checking." }] } }),
            item("AgentMessage", "It runs."),
            json!({ "type": "event_msg", "payload": { "type": "user_message", "message": "<send_user_message_question_reply>[]</send_user_message_question_reply>" } }),
            item("UserMessage", "\n## Referenced chats with Codex:\n[…]\n## My request:\nthanks"),
        ]),
    )
    .unwrap();
    // An older file of the same thread, and an older rollout's editor context around a request.
    std::fs::write(
        roots.codex.join("2026/09/03/rollout-2026-09-02T00-00-00-33333333-aaaa-bbbb-cccc-000000000001_44444444-aaaa-bbbb-cccc-000000000001.jsonl"),
        lines(&[
            json!({ "type": "session_meta", "payload": { "id": "33333333-aaaa-bbbb-cccc-000000000001", "cwd": cwd } }),
            json!({ "type": "response_item", "payload": { "type": "message", "role": "user", "content": [{ "type": "input_text", "text": "# Files mentioned by the user:\n\n## a.png\n\n## My request for Codex:\nwhat is this" }] } }),
        ]),
    )
    .unwrap();
    let older = std::time::SystemTime::now() - std::time::Duration::from_secs(60);
    std::fs::File::options().append(true).open(roots.codex.join("2026/09/03/rollout-2026-09-02T00-00-00-33333333-aaaa-bbbb-cccc-000000000001_44444444-aaaa-bbbb-cccc-000000000001.jsonl")).unwrap().set_modified(older).unwrap();
    let listed = list(&roots, 10);
    assert_eq!(listed.len(), 1, "one thread, however many files");
    assert_eq!(listed[0].first.as_deref(), Some("look at the vm"));
    let older = read(RuntimeKind::Codex, &roots.codex.join("2026/09/03/rollout-2026-09-02T00-00-00-33333333-aaaa-bbbb-cccc-000000000001_44444444-aaaa-bbbb-cccc-000000000001.jsonl"), 0, 0).unwrap();
    assert_eq!(older.first.as_deref(), Some("what is this"));
    let found = find(&roots, RuntimeKind::Codex, "33333333-aaaa-bbbb-cccc-000000000001").unwrap();
    assert_eq!(found.first.as_deref(), Some("look at the vm"));
    let shared = dir.path().join("shared");
    copy_transcript(&roots, &found, &shared).unwrap();
    assert_eq!(std::fs::read_dir(shared.join("2026/09/03")).unwrap().count(), 2, "every file of the thread");
    let said = conversation(RuntimeKind::Codex, &found.path);
    assert_eq!(said.iter().map(|s| (s.person, s.text.as_str())).collect::<Vec<_>>(), vec![(true, "look at the vm"), (false, "Checking.\n\nIt runs."), (true, "thanks")]);
}

#[test]
fn a_transcript_is_copied_to_the_same_place_under_the_shared_one_and_the_original_left_as_it_was() {
    let dir = tempfile::tempdir().unwrap();
    let roots = machine(dir.path(), &dir.path().join("app"));
    let shared = dir.path().join("data/transcripts");
    let claude = find(&roots, RuntimeKind::Claude, "11111111-aaaa-bbbb-cccc-000000000001").unwrap();
    let to = copy_transcript(&roots, &claude, &shared.join("claude")).unwrap();
    assert_eq!(to, shared.join("claude").join(claude.path.strip_prefix(&roots.claude).unwrap()));
    assert_eq!(std::fs::read(&to).unwrap(), std::fs::read(&claude.path).unwrap());
    let codex = find(&roots, RuntimeKind::Codex, "22222222-aaaa-bbbb-cccc-000000000001").unwrap();
    let to = copy_transcript(&roots, &codex, &shared.join("codex")).unwrap();
    assert!(to.starts_with(shared.join("codex/2026/09/02")));
    assert!(codex.path.exists());
}
