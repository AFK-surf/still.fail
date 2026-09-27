//! This station's errors, reported to ember's PostHog project (docs/telemetry.md). (src/telemetry.ts) Off unless the
//! station's operator turns it on in config.json (`"telemetry": { "errors": true }`). Only errors leave: error-level
//! log lines, each with its error's message, the station's id and the build. Never a log line's fields, which may hold
//! what people wrote; paths under home directories lose the home, and quoted text in error messages (a JSON parser's,
//! for one, quotes its input) is cut. The station's traces are ember-station's (mesh/station/src/telemetry.rs); what
//! turns a log line into a report is the station's logging (it calls `report` for its error events).

use std::path::Path;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde::Deserialize;
use serde_json::{Value, json};
use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use tracing::warn;

use crate::runtime::uuid;
use crate::store::now_ms;
use crate::transcript::iso;

/// The project key and build, written next to the admin page by its build (web/vite.config.ts).
#[derive(Deserialize, Debug, Clone, PartialEq)]
pub struct ProjectKey {
    pub host: String,
    pub key: String,
    pub release: String,
}

/// The key the admin page was built with; None for a build without one (then nothing can be reported).
pub fn built_key(ui_dir: &Path) -> Option<ProjectKey> {
    serde_json::from_str(&std::fs::read_to_string(ui_dir.join("posthog.json")).ok()?).ok()
}

/// Home directories (this user's and anyone's) in a path or stack, as ~.
pub fn scrub_paths(text: &str, home: &str) -> String {
    let own = if !home.is_empty() && home != "/" { text.replace(home, "~") } else { text.to_string() };
    let mut out = String::with_capacity(own.len());
    let mut rest = own.as_str();
    'scan: while !rest.is_empty() {
        for root in ["/Users/", "/home/"] {
            if let Some(after) = rest.strip_prefix(root) {
                let name = after.find(|c: char| c == '/' || c.is_whitespace() || ":'\"()".contains(c)).unwrap_or(after.len());
                if name > 0 {
                    out.push('~');
                    rest = &after[name..];
                    continue 'scan;
                }
            }
        }
        let c = rest.chars().next().unwrap();
        out.push(c);
        rest = &rest[c.len_utf8()..];
    }
    out
}

/// An error message without the text it quoted.
pub fn scrub_message(text: &str, home: &str) -> String {
    let text = scrub_paths(text, home);
    let pairs = [('"', '"'), ('\'', '\''), ('`', '`'), ('“', '”'), ('「', '」')];
    let chars: Vec<char> = text.chars().collect();
    let mut out = String::with_capacity(text.len());
    let mut i = 0;
    while i < chars.len() {
        if let Some((open, close)) = pairs.iter().find(|(open, _)| *open == chars[i]) {
            if let Some(end) = chars[i + 1..].iter().position(|c| c == close) {
                out.push(*open);
                out.push('…');
                out.push(*close);
                i += end + 2;
                continue;
            }
        }
        out.push(chars[i]);
        i += 1;
    }
    out
}

pub struct ErrorReportsOptions {
    pub key: Option<ProjectKey>,
    /// Read on every report, so turning it off in the config stops them at once.
    pub enabled: Arc<dyn Fn() -> bool + Send + Sync>,
    /// The station's id from its mesh enrollment; None before it is enrolled.
    pub station: Arc<dyn Fn() -> Option<String> + Send + Sync>,
    /// Whose home paths lose their home (default: this user's).
    pub home: Option<String>,
}

pub struct ErrorReports {
    options: ErrorReportsOptions,
    home: String,
    /// One per process when the station has no id yet.
    anonymous: String,
    sender: Mutex<Option<(mpsc::UnboundedSender<Value>, JoinHandle<()>)>>,
}

impl ErrorReports {
    pub fn new(options: ErrorReportsOptions) -> Arc<ErrorReports> {
        let home = options.home.clone().or_else(|| std::env::var("HOME").ok()).unwrap_or_default();
        let sender = options.key.clone().map(|key| {
            let (tx, rx) = mpsc::unbounded_channel();
            (tx, tokio::spawn(send(key, rx)))
        });
        Arc::new(ErrorReports { options, home, anonymous: uuid(), sender: Mutex::new(sender) })
    }

    /// Whether a report would go out now.
    pub fn active(&self) -> bool {
        self.sender.lock().unwrap().is_some() && (self.options.enabled)()
    }

    /// An error-level log line: its message, and the error's own when it has one.
    pub fn report(&self, log: &str, error: Option<&str>) {
        if !self.active() {
            return;
        }
        let station = (self.options.station)();
        let value = scrub_message(error.unwrap_or(log), &self.home);
        let event = json!({
            "event": "$exception",
            "distinct_id": station.as_ref().map(|s| format!("station:{s}")).unwrap_or_else(|| self.anonymous.clone()),
            "timestamp": iso(now_ms()),
            "properties": {
                "$exception_list": [{ "type": "Error", "value": value, "mechanism": { "handled": true, "synthetic": false } }],
                "log": scrub_paths(log, &self.home),
                "station": station,
                "release": self.options.key.as_ref().map(|k| k.release.clone()),
                "$process_person_profile": false,
                "$lib": "ember-station",
            },
        });
        if let Some((tx, _)) = self.sender.lock().unwrap().as_ref() {
            let _ = tx.send(event);
        }
    }

    /// Sends what is queued, then nothing more.
    pub async fn shutdown(&self) {
        let sender = self.sender.lock().unwrap().take();
        if let Some((tx, worker)) = sender {
            drop(tx);
            let _ = tokio::time::timeout(Duration::from_secs(5), worker).await;
        }
    }
}

/// Sends reports in batches as they come (whatever came meanwhile goes together).
async fn send(key: ProjectKey, mut events: mpsc::UnboundedReceiver<Value>) {
    let http = reqwest::Client::builder().timeout(Duration::from_secs(10)).build().unwrap_or_default();
    let url = format!("{}/batch/", key.host.trim_end_matches('/'));
    while let Some(first) = events.recv().await {
        let mut batch = vec![first];
        while let Ok(more) = events.try_recv() {
            batch.push(more);
        }
        let body = json!({ "api_key": key.key, "batch": batch });
        if let Err(e) = http.post(&url).json(&body).send().await.and_then(|r| r.error_for_status()) {
            warn!(error = %e, "error reports not sent");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    const HOME: &str = "/Users/alice";

    fn reports(key: Option<ProjectKey>, enabled: Arc<dyn Fn() -> bool + Send + Sync>) -> Arc<ErrorReports> {
        ErrorReports::new(ErrorReportsOptions { key, enabled, station: Arc::new(|| Some("st1".into())), home: Some(HOME.into()) })
    }

    #[test]
    fn paths_under_home_directories_lose_the_home_quoted_text_in_messages_is_cut() {
        assert_eq!(scrub_paths("at /Users/alice/ember/src/hub.ts:12:3", HOME), "at ~/ember/src/hub.ts:12:3");
        assert_eq!(scrub_paths("ENOENT: open '/home/bob/.ember/x.json'", HOME), "ENOENT: open '~/.ember/x.json'");
        assert_eq!(scrub_paths("file:///Users/carol/a.ts", HOME), "file://~/a.ts");
        assert_eq!(scrub_message(r#"Unexpected token 'h', "hello there" is not valid JSON"#, HOME), r#"Unexpected token '…', "…" is not valid JSON"#);
        assert_eq!(scrub_message("没有找到「周报草稿」", HOME), "没有找到「…」");
        assert_eq!(scrub_message("session task failed", HOME), "session task failed");
    }

    #[tokio::test]
    async fn station_error_reports_are_off_by_default() {
        let raw: crate::config::RawConfig = serde_json::from_value(json!({})).unwrap();
        let config = crate::config::parse_config(&raw, Path::new("/tmp/ember")).unwrap();
        assert!(!config.telemetry_errors && !config.telemetry_traces);
        let on: crate::config::RawConfig = serde_json::from_value(json!({ "telemetry": { "errors": true } })).unwrap();
        let config = crate::config::parse_config(&on, Path::new("/tmp/ember")).unwrap();
        assert!(config.telemetry_errors && !config.telemetry_traces);
        let key = ProjectKey { host: "http://127.0.0.1:9".into(), key: "phc_test".into(), release: "abc".into() };
        let off = reports(Some(key), Arc::new(|| false));
        off.report("something failed", Some("boom"));
        assert!(!off.active());
        off.shutdown().await;
    }

    #[tokio::test]
    async fn without_a_key_in_the_build_nothing_is_reported_whatever_the_config_says() {
        assert_eq!(built_key(tempfile::tempdir().unwrap().path()), None);
        let none = reports(None, Arc::new(|| true));
        assert!(!none.active());
        none.report("something failed", None);
        none.shutdown().await;
    }

    #[tokio::test]
    async fn reports_go_out_scrubbed_with_the_station_and_release_and_no_log_fields_turning_off_stops_them() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let bodies = Arc::new(Mutex::new(Vec::<Value>::new()));
        let seen = bodies.clone();
        tokio::spawn(async move {
            while let Ok((mut socket, _)) = listener.accept().await {
                let mut data = Vec::new();
                let mut buf = [0u8; 8192];
                // Read the head, then as much body as it says.
                loop {
                    let n = socket.read(&mut buf).await.unwrap_or(0);
                    if n == 0 {
                        break;
                    }
                    data.extend_from_slice(&buf[..n]);
                    let text = String::from_utf8_lossy(&data).to_string();
                    if let Some(split) = text.find("\r\n\r\n") {
                        let length: usize = text.to_lowercase().split("content-length:").nth(1).and_then(|r| r.lines().next()).and_then(|l| l.trim().parse().ok()).unwrap_or(0);
                        if data.len() >= split + 4 + length {
                            seen.lock().unwrap().push(serde_json::from_slice(&data[split + 4..split + 4 + length]).unwrap());
                            break;
                        }
                    }
                }
                let _ = socket.write_all(b"HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: 2\r\nconnection: close\r\n\r\n{}").await;
            }
        });
        let ui = tempfile::tempdir().unwrap();
        std::fs::write(ui.path().join("posthog.json"), json!({ "host": format!("http://127.0.0.1:{port}"), "key": "phc_test", "release": "abc123" }).to_string()).unwrap();
        let on = Arc::new(std::sync::atomic::AtomicBool::new(true));
        let flag = on.clone();
        let reports = reports(built_key(ui.path()), Arc::new(move || flag.load(std::sync::atomic::Ordering::SeqCst)));
        assert!(reports.active());
        reports.report("session task failed", Some(r#"cannot read /Users/alice/.ember/sessions/x: "the secret plan""#));
        on.store(false, std::sync::atomic::Ordering::SeqCst);
        reports.report("after turning off", Some("nope"));
        reports.shutdown().await;

        let events: Vec<Value> = bodies.lock().unwrap().iter().flat_map(|b| b["batch"].as_array().cloned().unwrap_or_default()).collect();
        assert_eq!(events.len(), 1);
        let event = &events[0];
        assert_eq!((event["event"].as_str(), event["distinct_id"].as_str()), (Some("$exception"), Some("station:st1")));
        let props = &event["properties"];
        assert_eq!((props["station"].as_str(), props["release"].as_str(), props["log"].as_str()), (Some("st1"), Some("abc123"), Some("session task failed")));
        assert_eq!(props["$process_person_profile"], json!(false));
        assert_eq!(props["$exception_list"][0]["value"].as_str(), Some(r#"cannot read ~/.ember/sessions/x: "…""#));
        let sent = event.to_string();
        assert!(!sent.contains("/Users/alice") && !sent.contains("secret plan"), "{sent}");
        assert_eq!(bodies.lock().unwrap()[0]["api_key"].as_str(), Some("phc_test"));
    }
}
