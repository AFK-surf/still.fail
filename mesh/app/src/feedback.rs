//! Bug reports about still.fail itself (docs/feedback.md): the `feedback_send` tool, with which an agent passes a
//! report on to the still.fail team once the person it works for agreed to it (the stillfail-feedback skill says when
//! and how). The station process (stillfail-station) posts it to still.fail cloud signed with the station's key
//! (`register`); this side adds what the station knows of the session. Stations on the test channel (youdid.wtf,
//! where the team runs its own) neither have the tool nor the skill.

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
    fn a_report_needs_a_title_and_a_body() {
        assert!(report(&session(), &args(json!({ "title": " ", "body": "x" })), None).is_err());
        assert!(report(&session(), &args(json!({ "title": "x" })), None).is_err());
    }
}
