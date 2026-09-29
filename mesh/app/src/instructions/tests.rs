//! The Node station's instructions tests, ported; and the texts checked word for word (session.txt, inbound.txt,
//! history.txt: made by the Node station from the same inputs, then kept here as the Rust station's own grew:
//! session.txt's line on messages via="ember", from background jobs).

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
        attachments: if rich { vec![Attachment { name: "a.png".into(), path: "/w/uploads/a.png".into(), size: 3, width: None, height: None, thumbhash: None }] } else { vec![] },
        quotes: if rich { vec![Quote { author: "U2".into(), text: "line1\nline2".into(), comment: "see".into(), ts: Some("99.0".into()), role: Some("person".into()), file: None }] } else { vec![] },
        declared: None,
        created_at: 1,
        edited_at: None,
    }
}

fn pending(m: MessageRow, surface: &str, channel: &str, thread_ts: &str) -> PendingMessage {
    PendingMessage { message: m, surface: surface.into(), channel: channel.into(), thread_ts: thread_ts.into(), connect: "cl".into() }
}

#[test]
fn a_session_continued_from_a_terminal_is_told_its_project_directory_before_its_workspace() {
    let text = session_instructions("/w/s", Some("/Users/me/app"), "/d/repos", "/d/agent/MEMORY.md");
    assert!(text.contains("Where you work:\n- Project directory: /Users/me/app. This session began outside ember"));
    assert!(text.contains("scratch files only.\n- Session workspace: /w/s."));
}

#[test]
fn the_texts_are_the_ts_stations_word_for_word() {
    assert_eq!(session_instructions("/w/s", None, "/d/repos", "/d/agent/MEMORY.md"), include_str!("session.txt"));
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

#[test]
fn a_mark_on_a_previewed_page_is_said_to_be_one_with_its_screenshot() {
    let mut m = message(2, "101.0", "U1", true, AuthorKind::Person);
    m.quotes = vec![Quote { author: "网页 demo 标注 1".into(), text: "button.btn「升级」\n选择器 main > button".into(), comment: "换个颜色".into(), ts: None, role: Some("page".into()), file: None }];
    assert!(message_for_agent(&m).starts_with(
        "[Quote] From a web page shown in the chat's preview (网页 demo 标注 1), marked with its number in the attached screenshot:\n> button.btn「升级」\n> 选择器 main > button\nTheir comment on it: 换个颜色"
    ));
}

#[test]
fn a_mark_with_a_screenshot_of_its_own_is_said_to_be_in_that_one() {
    let mut m = message(2, "101.0", "U1", false, AuthorKind::Person);
    let shot = |name: &str| Attachment { name: name.into(), path: format!("/files/x-{name}"), size: 3, width: None, height: None, thumbhash: None };
    m.attachments = vec![shot("demo-标注1.png"), shot("demo-标注2.png")];
    m.quotes = vec![Quote { author: "网页 demo 标注 2".into(), text: "按钮「升级」".into(), comment: String::new(), ts: None, role: Some("page".into()), file: Some("demo-标注2.png".into()) }];
    assert!(message_for_agent(&m).starts_with(
        "[Quote] From a web page shown in the chat's preview (网页 demo 标注 2), marked with its number in its own screenshot /files/x-demo-标注2.png:\n> 按钮「升级」"
    ));
}

#[test]
fn widget_models_are_one_section_each_with_where_it_was_posted() {
    assert_eq!(format_widget_models(&[]), "");
    let models = [
        WidgetModel { path: "/w/u/pick.html".into(), name: "pick.html".into(), thread: Some(("EMBER".into(), "1.0".into())), model: "chose red".into() },
        WidgetModel { path: "/x/y.html".into(), name: "y.html".into(), thread: None, model: "{\"n\":2}".into() },
    ];
    assert_eq!(
        format_widget_models(&models),
        "A widget you posted has state for you (the person's choices in it; not a message to answer by itself):\n- pick.html in EMBER/1.0: chose red\n- y.html: {\"n\":2}"
    );
}
