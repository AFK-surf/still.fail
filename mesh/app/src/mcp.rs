//! The station's MCP endpoint (streamable HTTP, JSON responses only). Every request carries the session's bearer token;
//! tools run on behalf of that session. The HTTP wiring is the server's: this takes a request's method,
//! authorization and body, and gives its status and body.

use std::collections::HashMap;
use std::sync::Arc;

use anyhow::Result;
use futures_util::future::BoxFuture;
use serde_json::{Map, Value, json};
use tracing::warn;

/// The tools that reach out of the station, refused while it is in no workspace (`McpEndpoint::gated`): what posts or
/// sends to people (chat_post, into still.fail chats and Slack, with its files), slack_api (as the workspace's Slack
/// bot: writes, uploads, and reads too, since the station is not connected to Slack meanwhile and one method name does
/// not reliably say which it is) and job_start (jobs and services do not run then). The rest only read the station's
/// own records (chat_history, chat_list, chat_read, session_history, job_list, job_log), record the turn's state
/// (chat_state: nothing is sent), or stop something (job_stop), and stay open.
pub const OUTWARD: &[&str] = &["chat_post", "slack_api", "job_start", "station_list", "station_task", "station_file"];

/// What a refused outward call says.
pub const UNBOUND_REFUSAL: &str = "Refused: this station is not in a still.fail workspace right now (it was removed from it, or has not joined one), so it does not post to chats or Slack, call Slack, or start jobs. Nothing was sent. Stop here and do not retry: when the station is back in its workspace, the interrupted work resumes and you can post then.";

type Gate = Arc<dyn Fn() -> Option<String> + Send + Sync>;

pub type Run = Arc<dyn Fn(String, Map<String, Value>) -> BoxFuture<'static, Result<String>> + Send + Sync>;

#[derive(Clone)]
pub struct Tool {
    pub name: String,
    pub description: String,
    pub input_schema: Value,
    /// Returns the text the agent sees. An error returns its message as a tool error.
    pub run: Run,
}

pub struct McpEndpoint {
    tools: Vec<Tool>,
    by_name: HashMap<String, usize>,
    /// Maps a bearer token to a session key.
    resolve: Arc<dyn Fn(&str) -> Option<String> + Send + Sync>,
    /// Why OUTWARD tools are refused now, if they are.
    gate: Option<Gate>,
}

/// What the HTTP layer sends back: a status, and a JSON body (none for 202 and 405).
pub struct Reply {
    pub status: u16,
    pub body: Option<Value>,
}

impl McpEndpoint {
    pub fn new(resolve: impl Fn(&str) -> Option<String> + Send + Sync + 'static, tools: Vec<Tool>) -> McpEndpoint {
        let by_name = tools.iter().enumerate().map(|(i, t)| (t.name.clone(), i)).collect();
        McpEndpoint { tools, by_name, resolve: Arc::new(resolve), gate: None }
    }

    /// Refuses the OUTWARD tools, with what `closed` says, while it says anything (the station is in no workspace).
    pub fn gated(mut self, closed: impl Fn() -> Option<String> + Send + Sync + 'static) -> McpEndpoint {
        self.gate = Some(Arc::new(closed));
        self
    }

    pub async fn handle(&self, method: &str, authorization: Option<&str>, body: &[u8]) -> Reply {
        if method != "POST" {
            return Reply { status: 405, body: None };
        }
        let token = authorization.map(|a| a.strip_prefix("Bearer ").or_else(|| a.strip_prefix("bearer ")).unwrap_or(a).trim()).unwrap_or("");
        let Some(session) = (!token.is_empty()).then(|| (self.resolve)(token)).flatten() else {
            return Reply { status: 401, body: Some(json!({ "error": "unknown session token" })) };
        };
        let Ok(message) = serde_json::from_slice::<Value>(body) else {
            return Reply { status: 400, body: Some(json!({ "jsonrpc": "2.0", "id": null, "error": { "code": -32700, "message": "parse error" } })) };
        };
        let Some(id) = message.get("id").cloned() else {
            return Reply { status: 202, body: None }; // a notification
        };
        let params = message.get("params").cloned().unwrap_or(Value::Null);
        let reply = |body: Value| {
            let mut out = json!({ "jsonrpc": "2.0", "id": id });
            for (k, v) in body.as_object().cloned().unwrap_or_default() {
                out[k] = v;
            }
            Reply { status: 200, body: Some(out) }
        };
        match message.get("method").and_then(Value::as_str).unwrap_or("") {
            "initialize" => reply(json!({ "result": {
                "protocolVersion": params.get("protocolVersion").and_then(Value::as_str).unwrap_or("2025-06-18"),
                "capabilities": { "tools": {} },
                "serverInfo": { "name": "still.fail", "version": "0.0.0" },
            } })),
            "ping" => reply(json!({ "result": {} })),
            "tools/list" => reply(json!({ "result": { "tools": self.tools.iter().map(|t| json!({ "name": t.name, "description": t.description, "inputSchema": t.input_schema })).collect::<Vec<_>>() } })),
            "tools/call" => {
                let name = params.get("name").and_then(Value::as_str).unwrap_or("").to_string();
                let Some(tool) = self.by_name.get(&name).map(|i| &self.tools[*i]) else {
                    return reply(json!({ "error": { "code": -32602, "message": format!("unknown tool {name}") } }));
                };
                if OUTWARD.contains(&name.as_str()) {
                    if let Some(why) = self.gate.as_ref().and_then(|closed| closed()) {
                        warn!(session, tool = name, "outward tool refused: the station is in no workspace");
                        return reply(json!({ "result": { "content": [{ "type": "text", "text": why }], "isError": true } }));
                    }
                }
                let args = params.get("arguments").and_then(Value::as_object).cloned().unwrap_or_default();
                match (tool.run)(session.clone(), args).await {
                    Ok(text) => reply(json!({ "result": { "content": [{ "type": "text", "text": text }] } })),
                    Err(error) => {
                        warn!(session, tool = name, error = %error, "tool call failed");
                        reply(json!({ "result": { "content": [{ "type": "text", "text": error.to_string() }], "isError": true } }))
                    }
                }
            }
            other => reply(json!({ "error": { "code": -32601, "message": format!("method not found: {other}") } })),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn endpoint() -> McpEndpoint {
        let echo = Tool {
            name: "echo".into(),
            description: "echo".into(),
            input_schema: json!({ "type": "object" }),
            run: Arc::new(|key, args| {
                Box::pin(async move {
                    if args.get("fail").is_some() {
                        anyhow::bail!("nope");
                    }
                    Ok(format!("{key}:{}", args.get("text").and_then(Value::as_str).unwrap_or("")))
                })
            }),
        };
        McpEndpoint::new(|token| (token == "good").then(|| "session-1".to_string()), vec![echo])
    }

    /// The station's tools by name, each answering "<name> ran".
    fn tools(names: &[&str]) -> Vec<Tool> {
        names
            .iter()
            .map(|name| {
                let said = format!("{name} ran");
                Tool {
                    name: name.to_string(),
                    description: String::new(),
                    input_schema: json!({ "type": "object" }),
                    run: Arc::new(move |_, _| {
                        let said = said.clone();
                        Box::pin(async move { Ok(said) })
                    }),
                }
            })
            .collect()
    }

    async fn rpc(e: &McpEndpoint, token: Option<&str>, body: Value) -> Reply {
        let auth = token.map(|t| format!("Bearer {t}"));
        e.handle("POST", auth.as_deref(), body.to_string().as_bytes()).await
    }

    #[tokio::test]
    async fn requests_without_a_known_token_are_refused() {
        let e = endpoint();
        assert_eq!(rpc(&e, None, json!({ "jsonrpc": "2.0", "id": 1, "method": "tools/list" })).await.status, 401);
        assert_eq!(rpc(&e, Some("bad"), json!({ "jsonrpc": "2.0", "id": 1, "method": "tools/list" })).await.status, 401);
    }

    #[tokio::test]
    async fn initialize_list_and_call_run_on_behalf_of_the_tokens_session() {
        let e = endpoint();
        let init = rpc(&e, Some("good"), json!({ "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": { "protocolVersion": "2025-06-18" } })).await;
        let initialized = init.body.unwrap();
        assert_eq!(initialized["result"]["protocolVersion"], "2025-06-18");
        assert_eq!(initialized["result"]["serverInfo"]["name"], "still.fail");
        assert_eq!(rpc(&e, Some("good"), json!({ "jsonrpc": "2.0", "method": "notifications/initialized" })).await.status, 202);
        let list = rpc(&e, Some("good"), json!({ "jsonrpc": "2.0", "id": 2, "method": "tools/list" })).await.body.unwrap();
        assert_eq!(list["result"]["tools"][0]["name"], "echo");
        let call = rpc(&e, Some("good"), json!({ "jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": { "name": "echo", "arguments": { "text": "hi" } } })).await.body.unwrap();
        assert_eq!(call["result"], json!({ "content": [{ "type": "text", "text": "session-1:hi" }] }));
        let failed = rpc(&e, Some("good"), json!({ "jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": { "name": "echo", "arguments": { "fail": true } } })).await.body.unwrap();
        assert_eq!((failed["result"]["isError"].clone(), failed["result"]["content"][0]["text"].clone()), (json!(true), json!("nope")));
    }

    #[tokio::test]
    async fn while_the_station_is_in_no_workspace_outward_tools_are_refused_and_the_rest_run() {
        let names = ["chat_post", "slack_api", "job_start", "station_list", "station_task", "station_file", "chat_state", "chat_history", "chat_list", "chat_read", "session_history", "job_list", "job_log", "job_stop"];
        let out = Arc::new(std::sync::atomic::AtomicBool::new(true));
        let closed = out.clone();
        let e = McpEndpoint::new(|_| Some("s".to_string()), tools(&names))
            .gated(move || closed.load(std::sync::atomic::Ordering::SeqCst).then(|| UNBOUND_REFUSAL.to_string()));
        let call = |name: &'static str| {
            let e = &e;
            async move { rpc(e, Some("t"), json!({ "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": { "name": name, "arguments": {} } })).await.body.unwrap()["result"].clone() }
        };
        for name in names {
            let result = call(name).await;
            if OUTWARD.contains(&name) {
                assert_eq!((result["isError"].clone(), result["content"][0]["text"].clone()), (json!(true), json!(UNBOUND_REFUSAL)), "{name}");
            } else {
                assert_eq!(result, json!({ "content": [{ "type": "text", "text": format!("{name} ran") }] }), "{name}");
            }
        }
        assert_eq!(OUTWARD, ["chat_post", "slack_api", "job_start", "station_list", "station_task", "station_file"]);
        // Listed all the same: an agent that read the list before keeps the same tools.
        let list = rpc(&e, Some("t"), json!({ "jsonrpc": "2.0", "id": 2, "method": "tools/list" })).await.body.unwrap();
        assert_eq!(list["result"]["tools"].as_array().unwrap().len(), names.len());
        // Back in a workspace: they run.
        out.store(false, std::sync::atomic::Ordering::SeqCst);
        for name in OUTWARD.iter().copied() {
            assert_eq!(call(name).await["content"][0]["text"], json!(format!("{name} ran")));
        }
    }
}
