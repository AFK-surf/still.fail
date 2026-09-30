//! test/slack-apps.test.ts, ported, and Slack's app API against a stand-in for Slack.

use std::sync::Mutex;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;

use super::*;

#[test]
fn a_new_app_has_every_permission_group_on() {
    let settings = settings_of(&slack_manifest("ember", None, None));
    assert_eq!(settings.name, "ember");
    assert_eq!(settings.groups.len(), SLACK_GROUPS.len());
    assert!(settings.groups.values().all(|on| *on));
}

#[test]
fn turning_a_group_off_removes_its_scopes_and_events_but_keeps_unknown_ones() {
    let mut manifest = slack_manifest("ember", None, None);
    manifest["oauth_config"]["scopes"]["bot"].as_array_mut().unwrap().push(json!("workflow.steps:execute"));
    let edit = SlackAppEdit {
        groups: Some(BTreeMap::from([("files".to_string(), false)])),
        description: Some(String::new()),
        background_color: Some("#112233".into()),
        ..SlackAppEdit::default()
    };
    let next = apply_settings(&manifest, &edit);
    let scopes = strings(at(&next, &["oauth_config", "scopes", "bot"]));
    let files = SLACK_GROUPS.iter().find(|g| g.id == "files").unwrap();
    for s in files.scopes {
        assert!(!scopes.iter().any(|x| x == s), "{s}");
    }
    assert!(scopes.iter().any(|x| x == "workflow.steps:execute"));
    assert!(!strings(at(&next, &["settings", "event_subscriptions", "bot_events"])).iter().any(|e| e == "file_shared"));
    assert_eq!(next["display_information"].get("description"), None);
    assert_eq!(next["display_information"]["background_color"], "#112233");
    assert!(!settings_of(&next).groups["files"]);
    assert!(settings_of(&next).groups["reactions"]);
    let back = apply_settings(&next, &SlackAppEdit { groups: Some(BTreeMap::from([("files".to_string(), true)])), ..SlackAppEdit::default() });
    assert!(settings_of(&back).groups["files"]);
}

#[test]
fn the_base_group_cannot_be_turned_off() {
    let next = apply_settings(&slack_manifest("ember", None, None), &SlackAppEdit { groups: Some(BTreeMap::from([("base".to_string(), false)])), ..SlackAppEdit::default() });
    assert!(settings_of(&next).groups["base"]);
}

#[test]
fn an_old_app_gets_a_bot_user_and_its_messages_tab_on_any_change() {
    let next = apply_settings(&json!({ "display_information": { "name": "old" }, "features": { "app_home": { "home_tab_enabled": true } } }), &SlackAppEdit { name: Some(" new ".into()), ..SlackAppEdit::default() });
    assert_eq!(next["display_information"]["name"], "new");
    assert_eq!(next["features"]["bot_user"], json!({ "display_name": " new ", "always_online": true }));
    assert_eq!(next["features"]["app_home"], json!({ "home_tab_enabled": true, "messages_tab_enabled": true, "messages_tab_read_only_enabled": false }));
}

#[test]
fn socket_mode_off_drops_the_events_and_on_brings_back_those_of_the_groups_on() {
    let mut manifest = apply_settings(&slack_manifest("ember", None, None), &SlackAppEdit { groups: Some(BTreeMap::from([("files".to_string(), false)])), ..SlackAppEdit::default() });
    manifest["settings"]["event_subscriptions"]["bot_events"].as_array_mut().unwrap().insert(0, json!("custom_event"));
    let off = with_socket_mode(&manifest, false);
    assert_eq!(off["settings"]["socket_mode_enabled"], false);
    assert_eq!(off["settings"].get("event_subscriptions"), None);
    let on = with_socket_mode(&manifest, true);
    let events = strings(at(&on, &["settings", "event_subscriptions", "bot_events"]));
    assert_eq!(events[0], "custom_event", "events ember does not know stay");
    assert!(events.iter().any(|e| e == "app_mention") && events.iter().any(|e| e == "reaction_added"));
    assert!(!events.iter().any(|e| e == "file_shared"), "a group off has no events");
    // Off first (as an app is made), then on: the groups' events come back.
    let again = with_socket_mode(&off, true);
    assert!(strings(at(&again, &["settings", "event_subscriptions", "bot_events"])).iter().any(|e| e == "message.im"));
}

#[test]
fn the_create_app_link_carries_the_manifest() {
    let url = create_app_url("ember 机器人");
    let encoded = url.strip_prefix("https://api.slack.com/apps?new_app=1&manifest_json=").unwrap();
    assert!(!encoded.contains(' ') && !encoded.contains('{') && !encoded.contains('"'));
    let bytes = encoded.as_bytes();
    let (mut decoded, mut i) = (Vec::new(), 0);
    while i < bytes.len() {
        if bytes[i] == b'%' {
            decoded.push(u8::from_str_radix(&encoded[i + 1..i + 3], 16).unwrap());
            i += 3;
        } else {
            decoded.push(bytes[i]);
            i += 1;
        }
    }
    let manifest: Value = serde_json::from_slice(&decoded).unwrap();
    assert_eq!(manifest, slack_manifest("ember 机器人", None, None));
    assert_eq!(manifest["settings"]["socket_mode_enabled"], true);
    assert_eq!(slack_manifest("x", None, Some("https://e/cb"))["oauth_config"]["redirect_urls"], json!(["https://e/cb"]));
}

#[test]
fn shapes_show_token_kinds_and_never_values() {
    let shape = shape_of(&json!({ "app_id": "A1", "credentials": { "client_secret": "s3cret", "token": "xapp-1-abc" }, "n": 1, "on": true }));
    assert_eq!(shape, json!({ "app_id": "string", "credentials": { "client_secret": "string", "token": "xapp-…" }, "n": "number", "on": "boolean" }));
}

/// A request Slack's stand-in saw: method (the path), its bearer token, its body.
#[derive(Debug, Clone)]
struct Seen {
    method: String,
    auth: String,
    body: String,
    content_type: String,
}

/// A stand-in for Slack's Web API on a local port: each request answered by `answer`, one per connection.
async fn fake_slack(answer: impl Fn(&Seen) -> Value + Send + Sync + 'static) -> (String, Arc<Mutex<Vec<Seen>>>) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let seen = Arc::new(Mutex::new(Vec::new()));
    let (log, answer) = (seen.clone(), Arc::new(answer));
    tokio::spawn(async move {
        loop {
            let Ok((mut socket, _)) = listener.accept().await else { return };
            let (log, answer) = (log.clone(), answer.clone());
            tokio::spawn(async move {
                let mut buf = Vec::new();
                let mut chunk = [0u8; 8192];
                let head_end = loop {
                    let n = socket.read(&mut chunk).await.unwrap();
                    if n == 0 {
                        return;
                    }
                    buf.extend_from_slice(&chunk[..n]);
                    if let Some(at) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
                        break at + 4;
                    }
                };
                let head = String::from_utf8_lossy(&buf[..head_end]).to_string();
                let header = |name: &str| {
                    head.lines().find_map(|l| l.split_once(':').filter(|(k, _)| k.eq_ignore_ascii_case(name)).map(|(_, v)| v.trim().to_string())).unwrap_or_default()
                };
                let length: usize = header("content-length").parse().unwrap_or(0);
                while buf.len() < head_end + length {
                    let n = socket.read(&mut chunk).await.unwrap();
                    if n == 0 {
                        break;
                    }
                    buf.extend_from_slice(&chunk[..n]);
                }
                let path = head.split_whitespace().nth(1).unwrap_or("").trim_start_matches('/').to_string();
                let seen = Seen {
                    method: path,
                    auth: header("authorization").trim_start_matches("Bearer ").to_string(),
                    body: String::from_utf8_lossy(&buf[head_end..]).to_string(),
                    content_type: header("content-type"),
                };
                let reply = answer(&seen).to_string();
                log.lock().unwrap().push(seen);
                let response = format!("HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{reply}", reply.len());
                let _ = socket.write_all(response.as_bytes()).await;
            });
        }
    });
    (base, seen)
}

fn token(by: &str, team: &str, access: &str, expires_at: i64) -> ConfigToken {
    ConfigToken { access_token: access.into(), refresh_token: format!("refresh-{access}"), expires_at, team_id: team.into(), by: by.into(), owner: None }
}

#[tokio::test]
async fn apps_are_reached_with_the_persons_token_that_owns_them_rotating_one_about_to_expire() {
    let (base, seen) = fake_slack(|s| match s.method.as_str() {
        "tooling.tokens.rotate" => json!({ "ok": true, "token": "fake-t1-next", "refresh_token": "fake-r1-next", "exp": 2_000_000_000, "team_id": "T1" }),
        // The app is T2's: T1's token is refused.
        "apps.manifest.export" if s.auth == "fake-t2" => json!({ "ok": true, "manifest": { "display_information": { "name": "bot" } } }),
        "apps.manifest.export" => json!({ "ok": false, "error": "app_not_found" }),
        "apps.manifest.validate" => json!({ "ok": false, "error": "invalid_manifest", "errors": [{ "pointer": "/display_information/name", "message": "too long" }] }),
        "apps.icon.set" => json!({ "ok": true }),
        "apps.manifest.create" => json!({ "ok": true, "app_id": "A9", "credentials": { "client_id": "c1", "client_secret": "fake-secret" } }),
        other => json!({ "ok": false, "error": format!("unexpected {other}") }),
    })
    .await;
    // SAFETY: the only test in this crate that sets it.
    unsafe { std::env::set_var("EMBER_SLACK_API", &base) };
    let tokens = Arc::new(Mutex::new(vec![
        token("me", "T1", "fake-t1", now_ms() + 60_000),
        token("me", "T2", "fake-t2", now_ms() + 3_600_000),
        token("someone", "T3", "fake-t3", now_ms() + 3_600_000),
    ]));
    let (load, save) = (tokens.clone(), tokens.clone());
    let apps = SlackApps::new(
        Arc::new(move || load.lock().unwrap().clone()),
        Arc::new(move |next: ConfigToken| {
            let mut all = save.lock().unwrap();
            all.retain(|t| !(t.by == next.by && t.team_id == next.team_id));
            all.push(next);
        }),
    );
    assert!(apps.configured("me") && !apps.configured("stranger"));

    let manifest = apps.export_manifest("me", "A2").await.unwrap();
    assert_eq!(manifest["display_information"]["name"], "bot");
    let calls: Vec<(String, String)> = seen.lock().unwrap().iter().map(|s| (s.method.clone(), s.auth.clone())).collect();
    assert_eq!(
        calls,
        [
            ("tooling.tokens.rotate".to_string(), String::new()),
            ("apps.manifest.export".into(), "fake-t1-next".into()),
            ("apps.manifest.export".into(), "fake-t2".into()),
        ],
        "T1's token was about to expire: rotated first, then tried; T2's owns the app"
    );
    assert!(seen.lock().unwrap()[0].body.contains("refresh_token=refresh-fake-t1"));
    let rotated = tokens.lock().unwrap().iter().find(|t| t.team_id == "T1").cloned().unwrap();
    assert_eq!((rotated.access_token.as_str(), rotated.refresh_token.as_str(), rotated.expires_at, rotated.by.as_str()), ("fake-t1-next", "fake-r1-next", 2_000_000_000_000, "me"));

    // Its owner is known now: one call.
    seen.lock().unwrap().clear();
    apps.export_manifest("me", "A2").await.unwrap();
    assert_eq!(seen.lock().unwrap().iter().map(|s| s.auth.clone()).collect::<Vec<_>>(), ["fake-t2"]);

    // Slack's refusals come with their code and details, in words people can act on.
    let refused = apps.update_manifest("me", "A2", &json!({})).await.unwrap_err();
    assert_eq!(refused.downcast_ref::<SlackApiError>().unwrap().code, "invalid_manifest");
    assert_eq!(slack_error(&refused), "manifest 不合法：/display_information/name too long");

    seen.lock().unwrap().clear();
    apps.set_icon("me", "A2", vec![0x89, b'P', b'N', b'G'], "image/png").await.unwrap();
    let icon = seen.lock().unwrap()[0].clone();
    assert!(icon.content_type.starts_with("multipart/form-data"), "{}", icon.content_type);
    assert!(icon.body.contains("filename=\"icon.png\"") && icon.body.contains("name=\"app_id\""));

    let made = apps.create_app("me", "T2", &slack_manifest("ember", None, None)).await.unwrap();
    assert_eq!(made, CreatedApp { app_id: "A9".into(), client_id: "c1".into(), client_secret: "fake-secret".into() });

    let none = apps.export_manifest("stranger", "A2").await.unwrap_err();
    assert_eq!(none.to_string(), "你还没有加 Slack App 配置 token");
    assert_eq!(apps.create_app("me", "T9", &json!({})).await.unwrap_err().to_string(), "你在这个 Slack 工作区没有配置 token");
}
