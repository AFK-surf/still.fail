//! The station's MCP endpoint (streamable HTTP, JSON responses only). Every request carries the session's bearer token;
//! tools run on behalf of that session. The HTTP wiring is the server's: this takes a request's method,
//! authorization and body, and gives its status and body.

use std::collections::HashMap;
use std::sync::Arc;

use anyhow::Result;
use futures_util::future::BoxFuture;
use serde_json::{Map, Value, json};
use tracing::warn;

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
}

/// What the HTTP layer sends back: a status, and a JSON body (none for 202 and 405).
pub struct Reply {
    pub status: u16,
    pub body: Option<Value>,
}

impl McpEndpoint {
    pub fn new(resolve: impl Fn(&str) -> Option<String> + Send + Sync + 'static, tools: Vec<Tool>) -> McpEndpoint {
        let by_name = tools.iter().enumerate().map(|(i, t)| (t.name.clone(), i)).collect();
        McpEndpoint { tools, by_name, resolve: Arc::new(resolve) }
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
                "serverInfo": { "name": "ember", "version": "0.0.0" },
            } })),
            "ping" => reply(json!({ "result": {} })),
            "tools/list" => reply(json!({ "result": { "tools": self.tools.iter().map(|t| json!({ "name": t.name, "description": t.description, "inputSchema": t.input_schema })).collect::<Vec<_>>() } })),
            "tools/call" => {
                let name = params.get("name").and_then(Value::as_str).unwrap_or("").to_string();
                let Some(tool) = self.by_name.get(&name).map(|i| &self.tools[*i]) else {
                    return reply(json!({ "error": { "code": -32602, "message": format!("unknown tool {name}") } }));
                };
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
        assert_eq!(init.body.unwrap()["result"]["protocolVersion"], "2025-06-18");
        assert_eq!(rpc(&e, Some("good"), json!({ "jsonrpc": "2.0", "method": "notifications/initialized" })).await.status, 202);
        let list = rpc(&e, Some("good"), json!({ "jsonrpc": "2.0", "id": 2, "method": "tools/list" })).await.body.unwrap();
        assert_eq!(list["result"]["tools"][0]["name"], "echo");
        let call = rpc(&e, Some("good"), json!({ "jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": { "name": "echo", "arguments": { "text": "hi" } } })).await.body.unwrap();
        assert_eq!(call["result"], json!({ "content": [{ "type": "text", "text": "session-1:hi" }] }));
        let failed = rpc(&e, Some("good"), json!({ "jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": { "name": "echo", "arguments": { "fail": true } } })).await.body.unwrap();
        assert_eq!((failed["result"]["isError"].clone(), failed["result"]["content"][0]["text"].clone()), (json!(true), json!("nope")));
    }
}
