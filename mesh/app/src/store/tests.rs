//! test/store.test.ts, ported.

use super::*;

fn archive_file(store: &Store, thread: i64) -> std::path::PathBuf {
    store.archive_dir().join("threads").join(format!("{thread}.jsonl.zst"))
}

fn memory() -> Store {
    Store::open(":memory:", None).unwrap()
}

fn session(store: &Store, key: &str) {
    store
        .insert_session(&NewSession {
            key: key.into(),
            connect: "ds".into(),
            runtime: "claude".into(),
            profile: "cc".into(),
            workspace: format!("/w/{key}"),
            token: key.into(),
            created_at: 1,
            last_active_at: 1,
            ..NewSession::default()
        })
        .unwrap();
}

fn say(store: &Store, thread: i64, ts: &str, kind: AuthorKind, author: &str, text: &str) -> (i64, bool) {
    store.insert_message(NewMessage::new(thread, ts, kind, author, text)).unwrap()
}

fn drain(rx: &mut broadcast::Receiver<StoreChange>) -> Vec<StoreChange> {
    let mut out = Vec::new();
    while let Ok(change) = rx.try_recv() {
        out.push(change);
    }
    out
}

#[test]
fn a_database_of_another_schema_version_is_refused() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("ember.db");
    let db = Connection::open(&path).unwrap();
    db.execute_batch("CREATE TABLE sessions (key TEXT); PRAGMA user_version = 8;").unwrap();
    drop(db);
    let error = Store::open(path.to_str().unwrap(), None).err().unwrap().to_string();
    assert!(error.contains("schema version 8; this station uses 12"), "{error}");
}

#[test]
fn a_message_is_recorded_once_and_delivered_to_every_session_in_its_thread() {
    let store = memory();
    session(&store, "a");
    session(&store, "b");
    let thread = store.open_thread("slack:T1", "C1", "1.1", None, None).unwrap();
    assert_eq!(store.open_thread("slack:T1", "C1", "1.1", None, None).unwrap().id, thread.id);
    store.join_thread(thread.id, "a", "ds").unwrap();
    assert!(!store.join_thread(thread.id, "a", "ds").unwrap());
    store.join_thread(thread.id, "b", "gpt").unwrap();
    let first = say(&store, thread.id, "1.1", AuthorKind::Person, "U1", "hi");
    assert_eq!(first, (1, true));
    assert_eq!(say(&store, thread.id, "1.1", AuthorKind::Person, "U1", "hi"), (1, false));
    let both = vec!["a".to_string(), "b".to_string()];
    assert_eq!(store.deliver(thread.id, first.0, &both).unwrap(), both);
    assert!(store.deliver(thread.id, first.0, &both).unwrap().is_empty());
    let pending: Vec<_> = store.pending_messages("b").unwrap().into_iter().map(|m| (m.message.text, m.connect)).collect();
    assert_eq!(pending, vec![("hi".to_string(), "gpt".to_string())]);
    store.mark_delivered("a", &[(thread.id, first.0)]).unwrap();
    assert_eq!(store.sessions_with_pending().unwrap(), vec!["b".to_string()]);
    assert_eq!(store.latest_thread("a").unwrap().unwrap().thread.id, thread.id);
    assert_eq!(store.session_thread("b", "C1", "1.1").unwrap().unwrap().connect, "gpt");
    assert_eq!(store.session_thread("b", "C9", "1.1").unwrap(), None);
}

fn plain(entries: &[EntryRow]) -> Vec<(i64, EntryKind, String, String)> {
    entries
        .iter()
        .map(|e| (e.n, e.kind, e.target.map(|t| t.to_string()).or(e.ts.clone()).unwrap_or_default(), e.text.clone().unwrap_or_default()))
        .collect()
}

#[test]
fn a_thread_is_a_log_edits_are_entries_of_their_own() {
    let store = memory();
    let thread = store.open_thread("slack:T1", "C1", "1.1", None, None).unwrap();
    let other = store.open_thread("slack:T1", "C1", "2.1", None, None).unwrap();
    for ts in ["1.1", "1.2", "1.3"] {
        say(&store, thread.id, ts, AuthorKind::Person, "U1", ts);
    }
    say(&store, other.id, "2.1", AuthorKind::Person, "U1", "elsewhere");
    assert_eq!(store.last_entry(thread.id).unwrap(), 3);
    assert!(store.entries_after(thread.id, 3).unwrap().is_empty());
    assert_eq!(store.edit_message("slack:T1", "C1", "1.1", "1.1", "1.1 edited").unwrap(), Some(thread.id));
    assert_eq!(store.edit_message("slack:T1", "C1", "1.1", "1.1", "1.1 edited").unwrap(), None, "the same words are no change");
    assert_eq!(store.edit_message("slack:T1", "C1", "1.1", "1.2", "1.2 edited").unwrap(), Some(thread.id));
    assert_eq!(store.edit_message("slack:T1", "C1", "1.1", "9.9", "never seen").unwrap(), None);
    let mut new = NewMessage::new(thread.id, "1.4", AuthorKind::Agent, "a", "new");
    new.declared = Some("final".into());
    store.insert_message(new).unwrap();
    let s = |x: &str| x.to_string();
    assert_eq!(
        plain(&store.entries_after(thread.id, 3).unwrap()),
        vec![(4, EntryKind::Edit, s("1"), s("1.1 edited")), (5, EntryKind::Edit, s("2"), s("1.2 edited")), (6, EntryKind::Message, s("1.4"), s("new"))]
    );
    // What was read stays true: the message entries are as they were said.
    assert_eq!(plain(&store.entries_between(thread.id, 1, 2).unwrap()), vec![(1, EntryKind::Message, s("1.1"), s("1.1")), (2, EntryKind::Message, s("1.2"), s("1.2"))]);
    assert_eq!(store.entries_between(thread.id, 5, 9).unwrap().iter().map(|e| e.n).collect::<Vec<_>>(), vec![5, 6]);
    assert_eq!(store.entries_before(thread.id, Some(4), 2).unwrap().iter().map(|e| e.n).collect::<Vec<_>>(), vec![2, 3]);
    assert_eq!(store.entries_before(thread.id, None, 2).unwrap().iter().map(|e| e.n).collect::<Vec<_>>(), vec![5, 6]);
    assert_eq!(store.entries_after(other.id, 0).unwrap().iter().map(|e| e.n).collect::<Vec<_>>(), vec![1], "each thread counts from 1");
    // Merged: the latest edit's words.
    let merged: Vec<_> = store.messages_before(thread.id, None, 10).unwrap().into_iter().map(|m| (m.n, m.text, m.edited_at.is_some())).collect();
    assert_eq!(merged, vec![(1, s("1.1 edited"), true), (2, s("1.2 edited"), true), (3, s("1.3"), false), (6, s("new"), false)]);
    assert_eq!(store.messages_before(thread.id, Some(3), 1).unwrap().into_iter().map(|m| m.ts).collect::<Vec<_>>(), vec![s("1.2")]);
    assert_eq!(store.last_message(thread.id).unwrap().unwrap().declared.as_deref(), Some("final"));
}

#[test]
fn a_message_still_pending_reaches_the_agent_as_it_reads_at_delivery() {
    let store = memory();
    session(&store, "a");
    let thread = store.open_thread("slack:T1", "C1", "1.1", None, None).unwrap();
    store.join_thread(thread.id, "a", "ds").unwrap();
    for ts in ["1.1", "1.2"] {
        let (n, _) = say(&store, thread.id, ts, AuthorKind::Person, "U1", ts);
        store.deliver(thread.id, n, &["a".to_string()]).unwrap();
    }
    store.edit_message("slack:T1", "C1", "1.1", "1.1", "edited").unwrap();
    let pending: Vec<_> = store.pending_messages("a").unwrap().into_iter().map(|m| (m.message.n, m.message.text)).collect();
    assert_eq!(pending, vec![(1, "edited".to_string()), (2, "1.2".to_string())]);
    assert_eq!(store.session_stats(Some("a")).unwrap()["a"].first_text.as_deref(), Some("edited"));
}

#[test]
fn reads_move_forward_only_and_unread_counts_skip_the_viewers_own() {
    let store = memory();
    session(&store, "a");
    let thread = store.open_thread("slack:T1", "C1", "1.1", None, None).unwrap();
    store.join_thread(thread.id, "a", "ds").unwrap();
    let (mine, _) = say(&store, thread.id, "1.2", AuthorKind::Person, "me@x", "q");
    say(&store, thread.id, "1.3", AuthorKind::Agent, "a", "answer");
    say(&store, thread.id, "1.4", AuthorKind::Person, "you@x", "also");
    store.edit_message("slack:T1", "C1", "1.1", "1.3", "answer, edited").unwrap();
    let view = |viewer: &str| store.list_threads(viewer, Some("a"), None).unwrap().remove(0);
    let me = view("me@x");
    assert_eq!((me.unread, me.read, me.last), (2, 0, 4));
    assert_eq!(store.unread_count("me@x", thread.id).unwrap(), 2, "an edit is no message of its own");
    assert_eq!(view("you@x").unread, 2);
    assert_eq!(store.set_read("me@x", thread.id, mine + 1).unwrap(), mine + 1);
    assert_eq!(store.set_read("me@x", thread.id, mine).unwrap(), mine + 1, "never back");
    let me = view("me@x");
    assert_eq!((me.unread, me.read), (1, mine + 1));
    assert_eq!(view("you@x").unread, 2, "each viewer reads for themselves");
    assert_eq!((view("me@x").last_message.unwrap().ts, view("you@x").last_message.unwrap().text), ("1.4".to_string(), "also".to_string()));
    // Its people, and the first thing one of them said.
    assert_eq!((view("me@x").people, view("me@x").first_text), (vec!["slack:ds:me@x".to_string(), "slack:ds:you@x".to_string()], Some("q".to_string())));
    let slack = store.open_thread("slack:T1", "C1", "2.1", None, None).unwrap();
    store.join_thread(slack.id, "a", "ds").unwrap();
    say(&store, slack.id, "2.1", AuthorKind::Agent, "a", "hello");
    say(&store, slack.id, "2.2", AuthorKind::Person, "U2", "<@UBOT> 看看");
    say(&store, slack.id, "2.3", AuthorKind::Person, "U1", "嗯");
    say(&store, slack.id, "2.4", AuthorKind::Person, "U2", "再看");
    let slack_view = store.list_threads("me@x", None, Some(slack.id)).unwrap().remove(0);
    assert_eq!((slack_view.people, slack_view.first_text), (vec!["slack:ds:U2".to_string(), "slack:ds:U1".to_string()], Some("<@UBOT> 看看".to_string())));
    assert_eq!(store.list_threads("me@x", None, None).unwrap().iter().map(|t| t.thread.id).collect::<Vec<_>>(), vec![slack.id, thread.id], "the latest said first");
}

#[test]
fn archiving_writes_a_thread_out_to_a_zstd_file_and_back() {
    let archive = tempfile::tempdir().unwrap();
    let store = Store::open(":memory:", Some(archive.path())).unwrap();
    session(&store, "a");
    session(&store, "b");
    let shared = store.open_thread("slack:T1", "C1", "1.1", None, None).unwrap();
    let own = store.open_thread("ember", "EMBER", "2.1", None, None).unwrap();
    store.join_thread(shared.id, "a", "ds").unwrap();
    store.join_thread(shared.id, "b", "ds").unwrap();
    store.join_thread(own.id, "a", "ember").unwrap();
    let at = |mut m: NewMessage, at: i64| {
        m.at = Some(at);
        m
    };
    store.insert_message(at(NewMessage::new(own.id, "2.2", AuthorKind::Person, "local", "看看"), 1)).unwrap();
    store.insert_message(at(NewMessage::new(own.id, "2.3", AuthorKind::Agent, "a", "好"), 2)).unwrap();
    store.insert_message(at(NewMessage::new(shared.id, "1.1", AuthorKind::Person, "U1", "hi"), 3)).unwrap();
    let before = store.list_threads("local", None, Some(own.id)).unwrap().remove(0);
    let entries = store.entries_after(own.id, 0).unwrap();
    let file = archive.path().join("threads").join(format!("{}.jsonl.zst", own.id));

    store.set_archived("a", true, MANUAL).unwrap();
    assert!(file.exists(), "every session of it is archived");
    assert!(!archive.path().join("threads").join(format!("{}.jsonl.zst", shared.id)).exists(), "b still takes part");
    let text = String::from_utf8(zstd::decode_all(&std::fs::read(&file).unwrap()[..]).unwrap()).unwrap();
    let written: Vec<EntryRow> = text.trim().lines().map(|l| serde_json::from_str(l).unwrap()).collect();
    assert_eq!(written, entries);
    // The same shape the TypeScript station wrote: its archives read here, and back.
    assert!(text.lines().next().unwrap().starts_with(&format!("{{\"thread\":{},\"n\":1,\"kind\":\"message\",\"target\":null,\"ts\":\"2.2\",\"authorKind\":\"person\"", own.id)));
    // Out of the database, read from the file the same way.
    assert_eq!(store.entries_after(own.id, 0).unwrap(), entries);
    assert_eq!(store.entries_before(own.id, None, 1).unwrap(), entries[1..].to_vec());
    assert_eq!(store.entries_between(own.id, 2, 2).unwrap(), entries[1..].to_vec());
    assert_eq!(store.list_threads("local", None, Some(own.id)).unwrap().remove(0), before);
    assert_eq!(store.participants(Some("a")).unwrap()["a"], vec!["local".to_string(), "slack:ds:U1".to_string()]);

    store.set_archived("a", false, MANUAL).unwrap();
    assert!(!file.exists(), "shown again: back in the database");
    assert_eq!(store.entries_after(own.id, 0).unwrap(), entries);

    // Someone writing in an archived thread brings it back first.
    store.set_archived("a", true, MANUAL).unwrap();
    let mut heard = store.subscribe();
    assert_eq!(say(&store, own.id, "2.4", AuthorKind::Person, "local", "还在吗"), (3, true));
    assert!(!file.exists());
    assert_eq!(store.entries_after(own.id, 0).unwrap().iter().map(|e| e.n).collect::<Vec<_>>(), vec![1, 2, 3]);
    let appended: Vec<Vec<i64>> = drain(&mut heard)
        .into_iter()
        .filter_map(|c| match c {
            StoreChange::Thread { entries, .. } if !entries.is_empty() => Some(entries.iter().map(|e| e.n).collect()),
            _ => None,
        })
        .collect();
    assert_eq!(appended, vec![vec![3]]);

    // Deleting the session removes an archived thread's file with it.
    store.set_archived("a", true, MANUAL).unwrap();
    store.set_archived("b", true, MANUAL).unwrap();
    assert!(archive.path().join("threads").join(format!("{}.jsonl.zst", shared.id)).exists());
    let mut removed = store.subscribe();
    store.delete_session("a").unwrap();
    let gone: Vec<i64> = drain(&mut removed).into_iter().filter_map(|c| if let StoreChange::ThreadRemoved(id) = c { Some(id) } else { None }).collect();
    assert_eq!(gone, vec![own.id]);
    assert!(!file.exists());
    assert_eq!(store.entries_after(shared.id, 0).unwrap().into_iter().map(|e| e.text.unwrap()).collect::<Vec<_>>(), vec!["hi".to_string()], "b's archived thread stays");
}

#[test]
fn thread_ids_are_never_used_again() {
    let store = memory();
    session(&store, "a");
    let thread = store.open_thread("ember", "EMBER", "1.1", None, None).unwrap();
    store.join_thread(thread.id, "a", "ember").unwrap();
    store.delete_session("a").unwrap();
    assert!(store.open_thread("ember", "EMBER", "2.1", None, None).unwrap().id > thread.id);
}

#[test]
fn deleting_removes_the_sessions_rows_and_the_threads_only_it_was_in() {
    let store = memory();
    session(&store, "a");
    session(&store, "b");
    let shared = store.open_thread("slack:T1", "C1", "1.1", None, None).unwrap();
    let own = store.open_thread("ember", "EMBER", "2.1", None, None).unwrap();
    store.join_thread(shared.id, "a", "ds").unwrap();
    store.join_thread(shared.id, "b", "ds").unwrap();
    store.join_thread(own.id, "a", "ember").unwrap();
    let (said, _) = say(&store, shared.id, "1.1", AuthorKind::Person, "U1", "hi");
    store.deliver(shared.id, said, &["a".to_string(), "b".to_string()]).unwrap();
    say(&store, own.id, "2.2", AuthorKind::Person, "local", "mine");
    store.set_read("local", own.id, 99).unwrap();
    store.start_turn("t", "a", "input").unwrap();
    store.set_binding("team", Some("a")).unwrap();
    store.set_archived("a", true, MANUAL).unwrap();
    assert!(store.get_session("a").unwrap().unwrap().archived_at.unwrap() > 0);
    store.set_archived("a", false, MANUAL).unwrap();
    assert_eq!(store.get_session("a").unwrap().unwrap().archived_at, None);
    let mut events = store.subscribe();
    store.delete_session("a").unwrap();
    let said: Vec<String> = drain(&mut events)
        .into_iter()
        .filter_map(|c| match c {
            StoreChange::SessionRemoved(key) => Some(format!("removed {key}")),
            StoreChange::ThreadRemoved(id) => Some(format!("thread removed {id}")),
            StoreChange::Thread { id, .. } => Some(format!("thread {id}")),
            _ => None,
        })
        .collect();
    assert_eq!(said, vec!["removed a".to_string(), format!("thread removed {}", own.id), format!("thread {}", shared.id)]);
    assert_eq!(store.get_session("a").unwrap(), None);
    assert_eq!(store.get_thread(own.id).unwrap(), None);
    assert!(store.entries_after(own.id, 0).unwrap().is_empty());
    assert_eq!(store.thread_sessions(shared.id).unwrap().into_iter().map(|m| m.session).collect::<Vec<_>>(), vec!["b".to_string()]);
    assert_eq!(store.pending_messages("b").unwrap().len(), 1, "the other session keeps its delivery");
    assert!(store.list_turns("a").unwrap().is_empty());
    assert_eq!(store.binding("team").unwrap(), None);
}

#[test]
fn the_store_announces_what_changed() {
    let store = memory();
    let mut seen = store.subscribe();
    session(&store, "a");
    let thread = store.open_thread("ember", "EMBER", "1.1", None, None).unwrap();
    store.join_thread(thread.id, "a", "ember").unwrap();
    let (n, _) = say(&store, thread.id, "1.2", AuthorKind::Person, "local", "hi");
    store.deliver(thread.id, n, &["a".to_string()]).unwrap();
    store.set_read("local", thread.id, n).unwrap();
    store.record_process(42, 1, "claude", "x").unwrap();
    store.forget_process(42).unwrap();
    store.forget_process(42).unwrap();
    let changes = drain(&mut seen);
    let kinds: Vec<&str> = changes
        .iter()
        .map(|c| match c {
            StoreChange::Session(_) => "session",
            StoreChange::Thread { .. } => "thread",
            StoreChange::Read { .. } => "read",
            StoreChange::Processes => "processes",
            _ => "other",
        })
        .collect();
    assert_eq!(kinds, vec!["session", "session", "thread", "thread", "session", "read", "processes", "processes"]);
    assert_eq!(changes[2], StoreChange::Thread { id: thread.id, entries: vec![] });
    match &changes[3] {
        StoreChange::Thread { id, entries } => assert_eq!((*id, entries.iter().map(|e| (e.n, e.text.clone().unwrap())).collect::<Vec<_>>()), (thread.id, vec![(1, "hi".to_string())])),
        other => panic!("{other:?}"),
    }
    assert_eq!(changes[5], StoreChange::Read { viewer: "local".into(), thread: thread.id, n });
}

#[test]
fn a_sessions_own_chat_is_archived_with_it_a_chat_of_its_own_alone_anything_new_said_brings_them_back() {
    let store = memory();
    session(&store, "a");
    let own = store.open_thread_of("ember", "EMBER", "1.1", None, None, Some("a")).unwrap();
    let other = store.open_thread("ember", "EMBER", "2.1", None, None).unwrap();
    store.join_thread(own.id, "a", "ember").unwrap();
    store.join_thread(other.id, "a", "ember").unwrap();
    say(&store, other.id, "2.2", AuthorKind::Person, "local", "hi");
    assert_eq!(store.home_chat("a").unwrap().unwrap().id, own.id);
    assert_eq!(store.chats_of_their_own().unwrap().iter().map(|t| t.id).collect::<Vec<_>>(), vec![other.id]);
    let thread = |id: i64| store.get_thread(id).unwrap().unwrap();
    let row = || store.get_session("a").unwrap().unwrap();

    store.set_archived("a", true, AUTO).unwrap();
    assert_eq!((row().archived_by.as_deref(), thread(own.id).hidden_by.as_deref()), (Some(AUTO), Some(AUTO)));
    assert_eq!(thread(other.id).hidden_at, None, "a chat of its own stays");
    // Its agent says something there: the session comes back, with its own chat.
    say(&store, other.id, "2.3", AuthorKind::Agent, "a", "done");
    assert_eq!(row().archived_at, None);
    assert_eq!(row().shown_at, None, "brought back by what was said, not by hand");
    assert_eq!(thread(own.id).hidden_at, None);

    store.set_thread_hidden(other.id, true, MANUAL).unwrap();
    assert!(thread(other.id).hidden_at.is_some());
    assert_eq!(row().archived_at, None, "its sessions stay");
    assert!(archive_file(&store, other.id).exists(), "out of lists: in its archive file");
    assert_eq!(store.entries_after(other.id, 0).unwrap().iter().map(|e| e.text.clone().unwrap()).collect::<Vec<_>>(), vec!["hi", "done"]);
    // Someone writes in it: shown again.
    say(&store, other.id, "2.4", AuthorKind::Person, "local", "again");
    assert_eq!(thread(other.id).hidden_at, None);

    // Shown again by hand: the idle clock starts over.
    store.set_archived("a", true, MANUAL).unwrap();
    store.set_archived("a", false, MANUAL).unwrap();
    assert!(row().shown_at.is_some());
}

#[test]
fn a_database_made_before_archiving_gains_its_columns_and_each_sessions_first_chat_is_its_own() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("ember.db");
    {
        let db = Connection::open(&path).unwrap();
        let old = SCHEMA
            .replace("  archived_at INTEGER,\n  archived_by TEXT,\n  shown_at INTEGER\n", "  archived_at INTEGER\n")
            .replace("  home TEXT,\n  hidden_at INTEGER,\n  hidden_by TEXT,\n  shown_at INTEGER,\n", "");
        assert!(!old.contains("hidden_at"));
        db.execute_batch(&old).unwrap();
        db.execute_batch(&format!("PRAGMA user_version = {SCHEMA_VERSION}")).unwrap();
        db.execute_batch(
            "INSERT INTO sessions (key, connect, scope, runtime, profile, workspace, token, created_at, last_active_at, archived_at)
               VALUES ('a', 'ember', 'all', 'claude', 'cc', '/w/a', 'a', 1, 1, 5);
             INSERT INTO threads (id, surface, channel, thread_ts, created_at) VALUES (1, 'ember', 'EMBER', '1.1', 1), (2, 'ember', 'EMBER', '2.1', 2);
             INSERT INTO thread_sessions (thread, session, connect, joined_at) VALUES (1, 'a', 'ember', 1), (2, 'a', 'ember', 2);",
        )
        .unwrap();
    }
    let store = Store::open(path.to_str().unwrap(), None).unwrap();
    let first = store.get_thread(1).unwrap().unwrap();
    assert_eq!((first.home.as_deref(), first.hidden_at, first.hidden_by.as_deref()), (Some("a"), Some(5), Some(MANUAL)));
    assert_eq!(store.get_thread(2).unwrap().unwrap().home, None);
    assert_eq!(store.get_session("a").unwrap().unwrap().archived_by.as_deref(), Some(MANUAL));
    drop(store);
    // Opened again: nothing more to add.
    Store::open(path.to_str().unwrap(), None).unwrap();
}

#[test]
fn a_database_made_before_clients_gains_the_column_and_a_message_keeps_its_app_through_archiving() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("ember.db");
    {
        let db = Connection::open(&path).unwrap();
        let old = SCHEMA.replace("  client TEXT,\n", "");
        assert!(!old.contains("client"));
        db.execute_batch(&old).unwrap();
        // The view as it was made before.
        db.execute_batch(&MERGED.replace("m.declared, m.client, m.agent_identity,", "m.declared,")).unwrap();
        db.execute_batch(&format!("PRAGMA user_version = {SCHEMA_VERSION}")).unwrap();
    }
    let store = Store::open(path.to_str().unwrap(), Some(&dir.path().join("archive"))).unwrap();
    session(&store, "a");
    let thread = store.open_thread("ember", "EMBER", "1.1", None, None).unwrap();
    store.join_thread(thread.id, "a", "ember").unwrap();
    say(&store, thread.id, "1.2", AuthorKind::Person, "local", "旧的");
    let (n, _) = store.insert_message(NewMessage { client: Some("android 0.1.1123".into()), ..NewMessage::new(thread.id, "1.3", AuthorKind::Person, "local", "新的") }).unwrap();
    store.deliver(thread.id, n, &["a".to_string()]).unwrap();
    let clients = |store: &Store| store.messages_before(thread.id, None, 10).unwrap().into_iter().map(|m| m.client).collect::<Vec<_>>();
    assert_eq!(clients(&store), vec![None, Some("android 0.1.1123".to_string())]);
    assert_eq!(store.pending_messages("a").unwrap()[0].message.client.as_deref(), Some("android 0.1.1123"));
    store.set_archived("a", true, MANUAL).unwrap();
    assert!(archive_file(&store, thread.id).exists());
    assert_eq!(clients(&store), vec![None, Some("android 0.1.1123".to_string())]);
    store.set_archived("a", false, MANUAL).unwrap();
    assert_eq!(clients(&store), vec![None, Some("android 0.1.1123".to_string())]);
    drop(store);
    // Opened again: nothing more to add.
    Store::open(path.to_str().unwrap(), None).unwrap();
}

#[test]
fn a_widgets_state_is_kept_by_session_and_path_its_model_told_once_until_it_changes() {
    let store = memory();
    session(&store, "a");
    session(&store, "b");
    let thread = store.open_thread("ember", "EMBER", "3.1", None, None).unwrap();
    store.join_thread(thread.id, "a", "ember").unwrap();
    let path = "/w/a/uploads/pick.html";
    let mut posted = NewMessage::new(thread.id, "3.2", AuthorKind::Agent, "a", "![](pick.html)");
    posted.attachments = vec![Attachment { name: "pick.html".into(), path: path.into(), size: 9, width: None, height: None, thumbhash: None }];
    store.insert_message(posted).unwrap();
    assert_eq!(store.widget_state("a", path).unwrap(), None);
    store.put_widget_state("a", path, r#"{"modelContent":"red"}"#, Some("red")).unwrap();
    store.put_widget_state("a", "/w/a/uploads/quiet.html", r#"{"privateContent":1}"#, None).unwrap();
    assert_eq!(store.widget_state("a", path).unwrap().as_deref(), Some(r#"{"modelContent":"red"}"#));
    assert_eq!(store.widget_state("b", path).unwrap(), None, "kept per session");
    let untold = store.untold_widget_models("a").unwrap();
    assert_eq!(untold, vec![WidgetModel { path: path.into(), name: "pick.html".into(), thread: Some(("EMBER".into(), "3.1".into())), model: "red".into() }]);
    store.mark_widget_models_told("a", &[(path.into(), "red".into())]).unwrap();
    assert!(store.untold_widget_models("a").unwrap().is_empty());
    // The same model again is not news; another is, and one changed after it was read is not marked told.
    store.put_widget_state("a", path, r#"{"modelContent":"red","privateContent":2}"#, Some("red")).unwrap();
    assert!(store.untold_widget_models("a").unwrap().is_empty());
    store.put_widget_state("a", path, r#"{"modelContent":"blue"}"#, Some("blue")).unwrap();
    store.mark_widget_models_told("a", &[(path.into(), "red".into())]).unwrap();
    assert_eq!(store.untold_widget_models("a").unwrap().into_iter().map(|w| w.model).collect::<Vec<_>>(), vec!["blue".to_string()]);
    // A file no message of the session's threads carries: its path's name, no thread.
    store.put_widget_state("a", "/elsewhere/x.html", "{}", Some("x")).unwrap();
    let elsewhere = store.untold_widget_models("a").unwrap().into_iter().find(|w| w.path == "/elsewhere/x.html").unwrap();
    assert_eq!((elsewhere.name.as_str(), elsewhere.thread), ("x.html", None));
    store.delete_session("a").unwrap();
    assert_eq!(store.widget_state("a", path).unwrap(), None);
}

#[test]
fn session_fast_migrates_old_databases_and_survives_restart() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("ember.db");
    let path = path.to_str().unwrap();
    let store = Store::open(path, None).unwrap();
    session(&store, "old");
    drop(store);
    let db = Connection::open(path).unwrap();
    db.execute_batch("ALTER TABLE sessions DROP COLUMN fast").unwrap();
    drop(db);
    let store = Store::open(path, None).unwrap();
    assert_eq!(store.get_session("old").unwrap().unwrap().fast, None);
    store.set_session_fast("old", Some(false)).unwrap();
    drop(store);
    let store = Store::open(path, None).unwrap();
    assert_eq!(store.get_session("old").unwrap().unwrap().fast, Some(false));
}

#[test]
fn the_latest_turn_is_the_last_inserted_when_start_times_tie() {
    let store = memory();
    session(&store, "same-ms");
    store.start_turn("first", "same-ms", "input").unwrap();
    store.end_turn("first", "failed", Some("rate_limit: quota"), None, None).unwrap();
    store.start_turn("second", "same-ms", "resume").unwrap();
    store.end_turn("second", "completed", None, None, None).unwrap();
    store.with(|inner, _| {
        inner.db.execute("UPDATE turns SET started_at = 123 WHERE session_key = 'same-ms'", [])?;
        Ok(())
    }).unwrap();
    let latest = store.last_turn("same-ms").unwrap().unwrap();
    assert_eq!(latest.kind, "resume");
    assert_eq!(latest.outcome.as_deref(), Some("completed"));
    assert_eq!(latest.detail, None);
}


#[test]
fn a_message_keeps_its_model_after_switching_editing_and_archiving() {
    let dir = tempfile::tempdir().unwrap();
    let store = Store::open(dir.path().join("ember.db").to_str().unwrap(), Some(&dir.path().join("archive"))).unwrap();
    session(&store, "a");
    let thread = store.open_thread("ember", "EMBER", "1.1", None, None).unwrap();
    store.join_thread(thread.id, "a", "ember").unwrap();
    store.set_session_model("a", Some("gpt-6-sol"), Some("high")).unwrap();
    say(&store, thread.id, "1.2", AuthorKind::Agent, "a", "first");
    store.set_session_model("a", Some("gpt-6-astra"), Some("medium")).unwrap();
    say(&store, thread.id, "1.3", AuthorKind::Agent, "a", "second");
    store.edit_message("ember", "EMBER", "1.1", "1.2", "edited").unwrap();
    let check = || {
        let messages = store.messages_before(thread.id, None, 10).unwrap();
        assert_eq!(messages[0].agent_identity.as_ref().unwrap()["model"], "gpt-6-sol");
        assert_eq!(messages[0].agent_identity.as_ref().unwrap()["effort"], "high");
        assert!(messages[0].agent_identity.as_ref().unwrap().get("runtime").is_none());
        assert_eq!(messages[1].agent_identity.as_ref().unwrap()["model"], "gpt-6-astra");
        assert_eq!(messages[0].text, "edited");
    };
    check();
    store.set_archived("a", true, MANUAL).unwrap();
    check();
    store.set_archived("a", false, MANUAL).unwrap();
    check();
}


#[test]
fn an_existing_client_view_gains_model_identity_even_after_a_partial_upgrade() {
    for already_added in [false, true] {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("ember.db");
        {
            let db = Connection::open(&path).unwrap();
            db.execute_batch(SCHEMA).unwrap();
            // The immediately previous release already had client, but no model snapshot.
            db.execute_batch(&MERGED.replace("m.agent_identity, ", "")).unwrap();
            if already_added {
                // The broken upgrade added the column while leaving this old view in place.
                db.execute_batch("ALTER TABLE entries ADD COLUMN agent_identity TEXT").unwrap();
            }
            db.execute_batch(&format!("PRAGMA user_version = {SCHEMA_VERSION}")).unwrap();
            db.execute(
                "INSERT INTO entries (thread, n, kind, ts, author_kind, author, text, client, at)
                 VALUES (1, 1, 'message', '1.1', 'person', 'local', 'kept', 'android old', 100)", [],
            ).unwrap();
            db.execute(
                "INSERT INTO entries (thread, n, kind, target, author_kind, author, text, at)
                 VALUES (1, 2, 'edit', 1, 'person', 'local', 'edited', 200)", [],
            ).unwrap();
        }
        // Both the first upgrade and subsequent opens must keep existing data readable.
        for _ in 0..2 {
            let store = Store::open(path.to_str().unwrap(), None).unwrap();
            let message = store.message_at(1, "1.1").unwrap().unwrap();
            assert_eq!(message.text, "edited");
            assert_eq!(message.client.as_deref(), Some("android old"));
            assert_eq!(message.edited_at, Some(200));
            assert!(message.agent_identity.is_none(), "do not backfill old messages");
            assert_eq!(store.messages_before(1, None, 10).unwrap(), vec![message.clone()]);
            assert_eq!(store.last_message(1).unwrap(), Some(message));
        }
    }
}
