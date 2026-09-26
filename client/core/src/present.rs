//! What the clients show of sessions and sidebar rows, decided here once:
//! where a session stands, a row's state, and who said a row's last thing
//! (with that agent's state on its picture). Clients draw these; they do not
//! work them out.

use serde_json::{Value, json};

/// Where a session stands: running, queued, final, block, failed, aborted, unexpected (a turn that ended without
/// saying final or block, or was left open by a crash), or idle.
pub fn session_status(s: &Value) -> &'static str {
    if s.get("process").and_then(Value::as_str) == Some("running") {
        return "running";
    }
    if s.get("pending").and_then(Value::as_u64).unwrap_or(0) > 0 {
        return "queued";
    }
    let Some(turn) = s.get("lastTurn").filter(|t| t.is_object()) else { return "idle" };
    match turn.get("declared").and_then(Value::as_str) {
        Some("final") => return "final",
        Some("block") => return "block",
        _ => {}
    }
    match turn.get("outcome").and_then(Value::as_str) {
        Some("failed") => "failed",
        Some("aborted") => "aborted",
        // Still open with no process: a crash left it so.
        _ => "unexpected",
    }
}

/// A status as a client's small mark: run (at work), block, failed; none for the rest.
pub fn badge(status: &str) -> Option<&'static str> {
    match status {
        "running" | "queued" => Some("run"),
        "block" => Some("block"),
        "failed" | "unexpected" => Some("failed"),
        _ => None,
    }
}

/// A row's state, from its agents': one that is blocked comes first, then one at work, then one that failed.
pub fn row_state(agents: &[Value]) -> Option<&'static str> {
    let marks: Vec<&str> = agents.iter().filter_map(|a| badge(session_status(a))).collect();
    ["block", "run", "failed"].into_iter().find(|b| marks.contains(b))
}

/// Whether a person (an email, "local", a Slack user id) is the viewer: by id, by email, or as a Slack user the
/// viewer said is them.
pub fn is_viewer(me: &Value, person: &str, slack_users: &[String]) -> bool {
    let id = me.get("id").and_then(Value::as_str);
    let email = me.get("email").and_then(Value::as_str);
    id == Some(person) || email.is_some_and(|e| e.eq_ignore_ascii_case(person)) || slack_users.iter().any(|u| u == person)
}

/// Who said a row's last thing, as its line shows them: `{ kind, name, model?, runtime?, picture?, mine, state? }`,
/// the agent's state riding on its picture when it is an agent of the row.
pub fn last_by(row: &Value, me: &Value, slack_users: &[String], members: &[Value]) -> Option<Value> {
    let last = row.get("last").filter(|l| l.is_object())?;
    let kind = last.get("authorKind").and_then(Value::as_str).unwrap_or("person");
    let author = last.get("author").and_then(Value::as_str).unwrap_or("");
    let said_name = last.get("authorName").and_then(Value::as_str).filter(|n| !n.is_empty());
    Some(match kind {
        "agent" => {
            let agent = row.get("agents").and_then(Value::as_array).and_then(|a| a.iter().find(|a| a.get("key").and_then(Value::as_str) == Some(author)));
            let model = agent.and_then(|a| a.get("model")).and_then(Value::as_str);
            json!({
                "kind": "agent",
                "name": model.or(said_name).unwrap_or("agent"),
                "model": model,
                "runtime": agent.and_then(|a| a.get("runtime")).cloned().unwrap_or(json!("claude")),
                "mine": false,
                "state": agent.and_then(|a| badge(session_status(a))),
            })
        }
        "ember" => json!({ "kind": "ember", "name": "ember", "mine": false }),
        _ => {
            let mine = is_viewer(me, author, slack_users);
            let member = members.iter().find(|m| m.get("email").and_then(Value::as_str).is_some_and(|e| e.eq_ignore_ascii_case(author)));
            let name = if mine { "你".to_string() } else {
                member.and_then(|m| m.get("name")).and_then(Value::as_str).filter(|n| !n.is_empty()).or(said_name).unwrap_or(author).to_string()
            };
            json!({
                "kind": "person",
                "id": author,
                "name": name,
                "picture": member.and_then(|m| m.get("picture")).filter(|p| p.as_str().is_some_and(|p| !p.is_empty())),
                "mine": mine,
            })
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_session_stands_where_its_process_and_last_turn_say() {
        assert_eq!(session_status(&json!({"process": "running"})), "running");
        assert_eq!(session_status(&json!({"process": "warm", "pending": 1})), "queued");
        assert_eq!(session_status(&json!({"lastTurn": {"declared": "block", "outcome": "completed"}})), "block");
        assert_eq!(session_status(&json!({"lastTurn": {"outcome": "completed"}})), "unexpected");
        assert_eq!(session_status(&json!({})), "idle");
    }

    #[test]
    fn a_rows_state_puts_block_first() {
        let agents = [json!({"lastTurn": {"outcome": "failed"}}), json!({"process": "running"}), json!({"lastTurn": {"declared": "block"}})];
        assert_eq!(row_state(&agents), Some("block"));
        assert_eq!(row_state(&agents[..2]), Some("run"));
        assert_eq!(row_state(&[json!({"lastTurn": {"declared": "final"}})]), None);
    }

    #[test]
    fn the_last_speaker_is_named_and_an_agents_state_rides_on_it() {
        let me = json!({"id": "a@x.com", "email": "a@x.com"});
        let members = [json!({"email": "b@x.com", "name": "阿二", "picture": "https://p/b"})];
        let row = |kind: &str, author: &str| json!({
            "agents": [{"key": "k", "model": "deepseek-flash", "runtime": "claude", "lastTurn": {"declared": "block"}}],
            "last": {"authorKind": kind, "author": author, "authorName": null, "text": "hi"},
        });
        let agent = last_by(&row("agent", "k"), &me, &[], &members).unwrap();
        assert_eq!((agent["name"].as_str(), agent["state"].as_str()), (Some("deepseek-flash"), Some("block")));
        let other = last_by(&row("person", "b@x.com"), &me, &[], &members).unwrap();
        assert_eq!((other["name"].as_str(), other["picture"].as_str(), other["mine"].as_bool()), (Some("阿二"), Some("https://p/b"), Some(false)));
        assert_eq!(last_by(&row("person", "A@x.com"), &me, &[], &members).unwrap()["name"], "你");
        assert_eq!(last_by(&row("person", "U7"), &me, &["U7".into()], &members).unwrap()["mine"], true, "a Slack user who is the viewer");
    }
}
