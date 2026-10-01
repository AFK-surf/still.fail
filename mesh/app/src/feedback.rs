//! Bug reports about still.fail itself (docs/feedback.md): the `feedback_send` tool, with which an agent passes a
//! report on to the still.fail team once the person it works for agreed to it (the stillfail-feedback skill says when
//! and how). The station process (stillfail-station) posts it to still.fail cloud signed with the station's key
//! (`register`); this side adds what the station knows of the session. Stations on the test channel (youdid.wtf,
//! where the team runs its own) neither have the tool nor the skill.
//!
//! Once a report is fixed and the fix is out on the station's channel (cloud/src/changelog.ts), the session it was
//! reported from is told (`tell_fixed`), for its agent to tell the person who reported it in the thread they did.

use std::sync::{Arc, OnceLock};

use anyhow::{Result, anyhow};
use futures_util::future::BoxFuture;
use serde_json::{Map, Value, json};
use sha2::{Digest, Sha256};

use crate::mcp::{Run, Tool};
use crate::store::{SessionRow, Store};

/// Posts a report to still.fail cloud and gives back its answer ({ id, number, duplicate }).
pub type Sender = Arc<dyn Fn(Value) -> BoxFuture<'static, Result<Value>> + Send + Sync>;

static SENDER: OnceLock<Sender> = OnceLock::new();

/// Who posts reports: the station process, once it is in still.fail cloud. Until then the tool says it cannot.
pub fn register(sender: Sender) {
    let _ = SENDER.set(sender);
}

/// Asks still.fail cloud which of this station's reports are fixed and out, saying which of them it has told of (their
/// ids): { fixed: [{ id, number, title, version, parts, released, session, thread }], station: its own version }.
pub type Fixed = Arc<dyn Fn(Vec<String>) -> BoxFuture<'static, Result<Value>> + Send + Sync>;

static FIXED: OnceLock<Fixed> = OnceLock::new();

/// Who asks: the station process, once it is in still.fail cloud.
pub fn register_fixed(fixed: Fixed) {
    let _ = FIXED.set(fixed);
}

/// How often the station asks.
pub const FIXED_EVERY: std::time::Duration = std::time::Duration::from_secs(3600);

/// The names people know the parts by.
fn part_name(part: &str) -> &str {
    match part {
        "station" => "the station",
        "web" => "the web app (app.still.fail; the desktop app from its next update)",
        "android" => "the Android app",
        "desktop" => "the desktop app",
        "cloud" => "still.fail cloud",
        other => other,
    }
}

/// What a session's agent is told of a fixed report: what it was, where the fix is and whether this station has it, and
/// to tell the person in the thread it was reported in.
pub fn fixed_notice(report: &Value, station: Option<&str>) -> String {
    let number = report.get("number").and_then(Value::as_u64).unwrap_or(0);
    let title = report.get("title").and_then(Value::as_str).unwrap_or("");
    let version = report.get("version").and_then(Value::as_u64).unwrap_or(0);
    let parts: Vec<&str> = report.get("parts").and_then(Value::as_array).map(|p| p.iter().filter_map(Value::as_str).collect()).unwrap_or_default();
    let mut text = format!("The still.fail team fixed a bug reported from this session: FB-{number} \"{title}\". ");
    if parts.is_empty() || parts == ["cloud"] {
        text.push_str("The fix is live now.");
    } else {
        let names: Vec<String> = parts.iter().map(|p| if *p == "cloud" { part_name(p).to_string() } else { format!("{} 0.1.{version}", part_name(p)) }).collect();
        text.push_str(&format!("The fix is released in {} and later.", names.join(", ")));
    }
    if parts.contains(&"station") {
        let own = station.and_then(|s| s.rsplit('.').next()?.parse::<u64>().ok());
        match own {
            Some(own) if own >= version => text.push_str(&format!(" This station runs {}: it has the fix.", station.unwrap_or_default())),
            Some(_) => text.push_str(&format!(" This station runs {}: the fix applies once it is updated (in still.fail, the station's page).", station.unwrap_or_default())),
            None => {}
        }
    }
    if parts.iter().any(|p| matches!(*p, "web" | "android" | "desktop")) {
        text.push_str(" An app gets it once it is updated to that version or later.");
    }
    match report.get("thread").and_then(Value::as_str) {
        Some(thread) => text.push_str(&format!(" Tell the person who reported it, in the thread it was reported in ({thread}), briefly and in their language; nothing else needs doing.")),
        None => text.push_str(" Tell the person who reported it, where they reported it, briefly and in their language; nothing else needs doing."),
    }
    text
}

/// Asks still.fail cloud for this station's fixed reports and tells each one's session (`notify`); then says which
/// were told, so they are not again. A report whose session is gone is taken as told: there is no one to tell.
pub async fn tell_fixed(notify: &(dyn Fn(&str, String) -> Result<()> + Send + Sync)) -> Result<usize> {
    let Some(fixed) = FIXED.get().cloned() else { return Ok(0) };
    let answer = fixed(Vec::new()).await?;
    let station = answer.get("station").and_then(Value::as_str);
    let mut told = Vec::new();
    for report in answer.get("fixed").and_then(Value::as_array).into_iter().flatten() {
        let Some(id) = report.get("id").and_then(Value::as_str) else { continue };
        if let Some(session) = report.get("session").and_then(Value::as_str) {
            if let Err(e) = notify(session, fixed_notice(report, station)) {
                tracing::warn!(session, error = %e, "a fixed report's session not told");
            }
        }
        told.push(id.to_string());
    }
    let count = told.len();
    if count > 0 {
        fixed(told).await?;
    }
    Ok(count)
}

/// What a report is about, as still.fail cloud takes it (cloud/src/feedback.ts).
const AREAS: &[&str] = &["station", "web", "android", "desktop", "slack", "cloud", "unknown"];

/// The report still.fail cloud is sent: the agent's words, and what the station adds of the session. `key` is the same
/// for the same report from the same session, so a call tried again is not a second report.
pub fn report(session: &SessionRow, args: &Map<String, Value>, link: Option<String>) -> Result<Value> {
    let text = |k: &str| args.get(k).and_then(Value::as_str).unwrap_or("").trim().to_string();
    let (title, body) = (text("title"), text("body"));
    if title.is_empty() || body.is_empty() {
        return Err(anyhow!("title and body are required"));
    }
    let area = text("area");
    let area = if AREAS.contains(&area.as_str()) { area } else { "unknown".into() };
    let key = hex::encode(&Sha256::digest(format!("{}\n{title}\n{body}", session.key).as_bytes())[..16]);
    let mut context = json!({
        "session": session.key,
        "connect": session.connect,
        "runtime": session.runtime,
        "profile": session.profile,
        "os": std::env::consts::OS,
        "arch": std::env::consts::ARCH,
    });
    for (name, value) in [("model", session.model.clone()), ("thread", Some(text("to")).filter(|t| !t.is_empty())), ("link", link)] {
        if let Some(value) = value {
            context[name] = Value::String(value);
        }
    }
    let mut report = json!({ "key": key, "title": title, "body": body, "area": area, "reporter": text("reporter"), "context": context });
    if let Some(logs) = Some(text("logs")).filter(|l| !l.is_empty()) {
        report["logs"] = Value::String(logs);
    }
    Ok(report)
}

/// The tool, for a station on the stable channel. `session` finds a session's row and `link` its page on still.fail
/// cloud.
pub fn tools(store: Arc<Store>, link: Arc<dyn Fn(&str) -> Option<String> + Send + Sync>) -> Vec<Tool> {
    let run: Run = Arc::new(move |key, args| {
        let (store, link) = (store.clone(), link.clone());
        Box::pin(async move {
            let session = store.get_session(&key)?.ok_or_else(|| anyhow!("unknown session"))?;
            let report = report(&session, &args, link(&key))?;
            let sender = SENDER.get().cloned().ok_or_else(|| anyhow!("this station is not connected to still.fail cloud, so the report cannot be sent; give the person the report to pass on themselves"))?;
            let answer = sender(report).await.map_err(|e| anyhow!("the report was not sent ({e}); give the person the report to pass on themselves"))?;
            let number = answer.get("number").and_then(Value::as_u64).ok_or_else(|| anyhow!("still.fail cloud answered without a number: {answer}"))?;
            Ok(if answer.get("duplicate").and_then(Value::as_bool) == Some(true) {
                format!("This report was already sent as FB-{number}.")
            } else {
                format!("Sent to the still.fail team as FB-{number}.")
            })
        })
    });
    vec![Tool {
        name: "feedback_send".into(),
        description: "Send a bug report about still.fail itself (the station, its tools, the still.fail apps, web or cloud, its Slack side) to the still.fail team. Only after the person you work for agreed to it and saw what is sent; the stillfail-feedback skill says when and how. Not for bugs in their own code or other services.".into(),
        input_schema: json!({
            "type": "object",
            "properties": {
                "to": { "type": "string", "description": "CHANNEL/THREAD_TS of the conversation the problem came up in." },
                "title": { "type": "string", "description": "One line: what goes wrong (at most 200 characters)." },
                "body": { "type": "string", "description": "Markdown: what happened, what was expected, how to get there, when, and anything else the team needs to find it. Only what the person agreed to send." },
                "area": { "type": "string", "enum": AREAS, "description": "The part of still.fail it is in, as far as you can tell." },
                "reporter": { "type": "string", "description": "Who reports it: their name and where they said it (e.g. \"Ada, Slack #ops\")." },
                "logs": { "type": "string", "description": "Optional: the lines of the station's own logs or tool errors that show the problem (at most 64 KB). No secrets, no people's content." },
            },
            "required": ["to", "title", "body"],
            "additionalProperties": false,
        }),
        run,
    }]
}

#[cfg(test)]
mod tests {
    use super::*;

    fn session() -> SessionRow {
        let store = Store::open(":memory:", None).unwrap();
        let new = crate::store::NewSession {
            key: "ember:C1:1.1".into(),
            connect: "ember".into(),
            runtime: "claude".into(),
            profile: "p1".into(),
            model: Some("opus".into()),
            workspace: "/w".into(),
            token: "t".into(),
            ..Default::default()
        };
        store.insert_session(&new).unwrap();
        store.get_session("ember:C1:1.1").unwrap().unwrap()
    }

    fn args(v: Value) -> Map<String, Value> {
        v.as_object().unwrap().clone()
    }

    #[test]
    fn a_report_carries_the_session_and_the_same_report_the_same_key() {
        let s = session();
        let a = report(&s, &args(json!({ "to": "EMBER/1.1", "title": "chat_post fails", "body": "it said 500", "area": "station", "reporter": "Ada" })), Some("https://x/o/1".into())).unwrap();
        assert_eq!(a["area"], "station");
        assert_eq!(a["context"]["session"], "ember:C1:1.1");
        assert_eq!(a["context"]["thread"], "EMBER/1.1");
        assert_eq!(a["context"]["model"], "opus");
        assert_eq!(a["context"]["link"], "https://x/o/1");
        assert!(a.get("logs").is_none());
        let again = report(&s, &args(json!({ "to": "EMBER/1.1", "title": "chat_post fails", "body": "it said 500" })), None).unwrap();
        assert_eq!(a["key"], again["key"]);
        let other = report(&s, &args(json!({ "to": "EMBER/1.1", "title": "chat_post fails", "body": "it said 502" })), None).unwrap();
        assert_ne!(a["key"], other["key"]);
        assert_eq!(other["area"], "unknown");
    }

    #[test]
    fn a_fixed_report_says_where_the_fix_is_and_whether_this_station_has_it() {
        let report = json!({ "id": "01", "number": 12, "title": "chat_post fails", "version": 1340, "parts": ["station"], "thread": "EMBER/1.1" });
        let had = fixed_notice(&report, Some("0.1.1342"));
        assert!(had.contains("FB-12 \"chat_post fails\""), "{had}");
        assert!(had.contains("the station 0.1.1340 and later"), "{had}");
        assert!(had.contains("This station runs 0.1.1342: it has the fix."), "{had}");
        assert!(had.contains("(EMBER/1.1)"), "{had}");
        let behind = fixed_notice(&report, Some("0.1.1300"));
        assert!(behind.contains("once it is updated"), "{behind}");
        let live = fixed_notice(&json!({ "number": 3, "title": "t", "version": 9, "parts": ["cloud"] }), None);
        assert!(live.contains("live now"), "{live}");
        assert!(!live.contains("This station"), "{live}");
        let app = fixed_notice(&json!({ "number": 4, "title": "t", "version": 9, "parts": ["android", "web"] }), Some("0.1.1"));
        assert!(app.contains("the Android app 0.1.9, the web app"), "{app}");
        assert!(app.contains("An app gets it once it is updated"), "{app}");
    }

    #[tokio::test]
    async fn fixed_reports_are_told_to_their_sessions_then_said_told() {
        use std::sync::Mutex;
        let asked: Arc<Mutex<Vec<Vec<String>>>> = Arc::default();
        let seen = asked.clone();
        register_fixed(Arc::new(move |told: Vec<String>| {
            let seen = seen.clone();
            Box::pin(async move {
                let first = told.is_empty();
                seen.lock().unwrap().push(told);
                Ok(if first {
                    json!({ "station": "0.1.1342", "fixed": [
                        { "id": "A", "number": 1, "title": "one", "version": 1340, "parts": ["station"], "session": "ember:C1:1.1", "thread": "C1/1.1" },
                        { "id": "B", "number": 2, "title": "two", "version": 1340, "parts": ["cloud"], "session": null },
                    ] })
                } else {
                    json!({ "fixed": [] })
                })
            })
        }));
        let notices: Arc<Mutex<Vec<(String, String)>>> = Arc::default();
        let kept = notices.clone();
        let count = tell_fixed(&move |session: &str, text: String| {
            kept.lock().unwrap().push((session.to_string(), text));
            Ok(())
        })
        .await
        .unwrap();
        assert_eq!(count, 2);
        let notices = notices.lock().unwrap();
        assert_eq!(notices.len(), 1);
        assert_eq!(notices[0].0, "ember:C1:1.1");
        assert!(notices[0].1.contains("FB-1"));
        assert_eq!(*asked.lock().unwrap(), vec![Vec::<String>::new(), vec!["A".to_string(), "B".to_string()]]);
    }

    #[test]
    fn a_report_needs_a_title_and_a_body() {
        assert!(report(&session(), &args(json!({ "title": " ", "body": "x" })), None).is_err());
        assert!(report(&session(), &args(json!({ "title": "x" })), None).is_err());
    }
}
