//! test/instructions.test.ts, ported; and the texts checked word for word (session.txt, inbound.txt, history.txt: made
//! by src/instructions.ts from the same inputs, then kept here as the Rust station's own grew: session.txt's line on
//! messages via="ember", from background jobs).

use super::*;
use crate::store::{Attachment, AuthorKind, Quote};

fn message(n: i64, ts: &str, author: &str, rich: bool, kind: AuthorKind) -> MessageRow {
    MessageRow {
        thread: 1,
        n,
        ts: ts.into(),
        author_kind: kind,
        author: author.into(),
        text: "hi \"there\" & you".into(),
        attachments: if rich { vec![Attachment { name: "a.png".into(), path: "/w/uploads/a.png".into(), size: 3, width: None, height: None }] } else { vec![] },
        quotes: if rich { vec![Quote { author: "U2".into(), text: "line1\nline2".into(), comment: "see".into(), ts: Some("99.0".into()), role: Some("person".into()) }] } else { vec![] },
        declared: None,
        created_at: 1,
        edited_at: None,
    }
}

fn pending(m: MessageRow, surface: &str, channel: &str, thread_ts: &str) -> PendingMessage {
    PendingMessage { message: m, surface: surface.into(), channel: channel.into(), thread_ts: thread_ts.into(), connect: "cl".into() }
}

#[test]
fn the_texts_are_the_ts_stations_word_for_word() {
    assert_eq!(session_instructions("/w/s", "/d/repos", "/d/agent/MEMORY.md"), include_str!("session.txt"));
    let names = HashMap::from([("U1".to_string(), "Ada".to_string()), ("gpt-key".to_string(), "GPT (<@UGPT>)".to_string())]);
    let selves = HashMap::from([("cl".to_string(), "ember (<@UBOT>)".to_string())]);
    let inbound = format_inbound(
        &[
            pending(message(2, "101.0", "U1", true, AuthorKind::Person), "slack:T1", "C1", "100.0"),
            pending(message(3, "102.0", "U3", false, AuthorKind::Person), "slack:T1", "C1", "100.0"),
            pending(message(4, "103.0", "gpt-key", false, AuthorKind::Agent), "slack:T1", "C1", "100.0"),
        ],
        &HashSet::from([1]),
        &names,
        &selves,
    );
    assert_eq!(inbound, include_str!("inbound.txt"));
    let history = format_history(
        &[
            message(2, "101.0", "U1", true, AuthorKind::Person),
            message(2, "101.0", "me", false, AuthorKind::Agent),
            message(2, "101.0", "other", false, AuthorKind::Agent),
            message(2, "101.0", "ember", false, AuthorKind::Ember),
        ],
        "ember",
        "EMBER/1.0",
        "me",
        &names,
    );
    assert_eq!(history, include_str!("history.txt"));
}

fn hinted(n: i64, ts: &str, surface: &str, channel: &str, thread_ts: &str) -> bool {
    let m = pending(message(n, ts, "a@x.com", false, AuthorKind::Person), surface, channel, thread_ts);
    format_inbound(&[m], &HashSet::from([1]), &HashMap::new(), &HashMap::new()).contains("had messages before you were brought in")
}

#[test]
fn a_thread_new_to_the_session_is_said_to_have_earlier_messages_only_when_it_has_them() {
    // A chat on the station's page: its id is its own, apart from its first message's; its first message has none.
    assert!(!hinted(1, "100.2", EMBER_SURFACE, "EMBER", "99.5"));
    assert!(hinted(3, "100.2", EMBER_SURFACE, "EMBER", "99.5"));
    // Slack: a thread's first message has none; a reply does, whether the station saw them or not.
    assert!(!hinted(1, "100.0", "slack:T1", "C1", "100.0"));
    assert!(hinted(1, "101.0", "slack:T1", "C1", "100.0"));
}

#[test]
fn addresses_are_channel_slash_ts() {
    assert_eq!(parse_thread_address(" C1/1790434911.559000 "), Some(("C1".into(), "1790434911.559000".into())));
    assert_eq!(parse_thread_address("EMBER/1.0"), Some(("EMBER".into(), "1.0".into())));
    assert_eq!(parse_thread_address("c1/1.0"), None);
    assert_eq!(parse_thread_address("C1/1"), None);
}
