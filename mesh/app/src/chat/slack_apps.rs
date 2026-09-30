//! Managing a connect's Slack app from still.fail: its name, description, colour, icon and permissions live in the app's
//! manifest, which Slack lets a workspace member change with an app configuration token. The token lasts 12 hours; its
//! refresh token (single use) yields the next pair, so the station keeps both and rotates as needed. Permission changes still
//! need a person to approve them in Slack; the station hands them the link. Also the manifest a new app starts from, and the
//! link that opens Slack's "create app" page with it filled in.

use std::collections::{BTreeMap, HashMap};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use anyhow::{Result, anyhow, bail};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};
use tracing::info;

use crate::config::{ConfigToken, ConfigTokenOwner};
use crate::store::now_ms;

/// A permission group in plain words: the scopes and events it adds to the app.
pub struct SlackGroup {
    pub id: &'static str,
    pub label: &'static str,
    pub description: &'static str,
    pub scopes: &'static [&'static str],
    pub events: &'static [&'static str],
}

/// Permissions in plain words. Each group adds its scopes and events to the app; "base" is always on.
pub const SLACK_GROUPS: &[SlackGroup] = &[
    SlackGroup {
        id: "base",
        label: "读取和回复消息",
        description: "被 @ 时收到消息，读取所在频道、私信和群聊的消息并回复，干活时在 thread 里显示进度。",
        scopes: &[
            "app_mentions:read",
            "chat:write",
            "channels:history",
            "groups:history",
            "im:history",
            "mpim:history",
            "channels:read",
            "groups:read",
            "im:read",
            "mpim:read",
            "users:read",
            "assistant:write",
        ],
        events: &["app_mention", "message.channels", "message.groups", "message.im", "message.mpim"],
    },
    SlackGroup {
        id: "public",
        label: "在没加入的公开频道发言",
        description: "不用先邀请，也能在公开频道回复。",
        scopes: &["chat:write.public", "channels:join"],
        events: &[],
    },
    SlackGroup { id: "dm", label: "主动发私信", description: "给人或多人开启私信对话。", scopes: &["im:write", "mpim:write"], events: &[] },
    SlackGroup {
        id: "customize",
        label: "用别的名字和头像发消息",
        description: "每条消息可以换显示名和头像。",
        scopes: &["chat:write.customize"],
        events: &[],
    },
    SlackGroup {
        id: "files",
        label: "读写文件",
        description: "读取消息里的附件，上传截图、日志等文件。",
        scopes: &["files:read", "files:write", "remote_files:read", "remote_files:write", "remote_files:share"],
        events: &["file_shared"],
    },
    SlackGroup {
        id: "reactions",
        label: "表情回应、置顶和书签",
        description: "用表情标记进度，置顶消息，管理频道书签。",
        scopes: &["reactions:read", "reactions:write", "pins:read", "pins:write", "bookmarks:read", "bookmarks:write"],
        events: &["reaction_added", "reaction_removed"],
    },
    SlackGroup {
        id: "channels",
        label: "创建和管理频道",
        description: "建频道、邀请成员，知道有人加入或新建频道。",
        scopes: &["channels:manage", "groups:write"],
        events: &["member_joined_channel", "channel_created"],
    },
    SlackGroup {
        id: "people",
        label: "查看成员资料",
        description: "读取邮箱、个人资料、用户组、工作区信息和自定义表情。",
        scopes: &["users:read.email", "users.profile:read", "usergroups:read", "team:read", "emoji:read"],
        events: &[],
    },
    SlackGroup {
        id: "extras",
        label: "链接预览、提醒和状态",
        description: "展开链接、设置提醒、读取勿扰和通话状态。",
        scopes: &["links:read", "links:write", "reminders:read", "reminders:write", "dnd:read", "calls:read"],
        events: &[],
    },
    SlackGroup {
        id: "canvases",
        label: "读写 canvas",
        description: "新建、编辑和读取 canvas 文档，比如把方案、报告写成频道里的 canvas。",
        scopes: &["canvases:read", "canvases:write"],
        events: &[],
    },
    SlackGroup { id: "lists", label: "读写列表", description: "新建、编辑和读取 Slack 列表（Lists），比如维护任务清单。", scopes: &["lists:read", "lists:write"], events: &[] },
    SlackGroup {
        id: "topics",
        label: "改频道话题和邀请成员",
        description: "设置频道和私信的话题、用途，把人邀请进频道。",
        scopes: &["channels:write.invites", "channels:write.topic", "groups:write.invites", "groups:write.topic", "im:write.topic", "mpim:write.topic"],
        events: &[],
    },
    SlackGroup {
        id: "usergroups",
        label: "管理用户组和发起通话",
        description: "建用户组、改成员，发起和更新 Slack 通话。",
        scopes: &["usergroups:write", "calls:write"],
        events: &[],
    },
    // Real-time search: of its kinds only these three take a bot token (private channels and DMs need a person's).
    SlackGroup {
        id: "search",
        label: "搜索消息、文件和成员",
        description: "在公开频道里搜消息和文件、按名字找人，回答问题时自己找上下文。",
        scopes: &["search:read.public", "search:read.files", "search:read.users"],
        events: &[],
    },
    SlackGroup {
        id: "connect",
        label: "Slack Connect 跨组织频道",
        description: "查看、发出和接受和别的公司共享频道的邀请。",
        scopes: &["conversations.connect:read", "conversations.connect:write", "conversations.connect:manage"],
        events: &[],
    },
    SlackGroup {
        id: "more",
        label: "状态、元数据和斜杠命令",
        description: "设置自己的在线状态，读取消息元数据和工作区设置，嵌入视频链接，响应斜杠命令。",
        scopes: &["users:write", "metadata.message:read", "team.preferences:read", "links.embed:write", "commands"],
        events: &[],
    },
];

/// The app as the settings form shows it.
#[derive(Serialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SlackAppSettings {
    pub name: String,
    pub display_name: String,
    pub description: String,
    pub long_description: String,
    pub background_color: String,
    pub groups: BTreeMap<String, bool>,
}

/// The form's edits: what is given changes, the rest stays.
#[derive(Deserialize, Debug, Clone, Default, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SlackAppEdit {
    pub name: Option<String>,
    pub display_name: Option<String>,
    pub description: Option<String>,
    pub long_description: Option<String>,
    pub background_color: Option<String>,
    pub groups: Option<BTreeMap<String, bool>>,
}

fn at<'a>(value: &'a Value, path: &[&str]) -> Option<&'a Value> {
    path.iter().try_fold(value, |v, key| v.get(key))
}

fn strings(value: Option<&Value>) -> Vec<String> {
    value.and_then(Value::as_array).map(|a| a.iter().filter_map(Value::as_str).map(String::from).collect()).unwrap_or_default()
}

/// A value as JavaScript's String() writes it: absent is "".
fn text(value: Option<&Value>) -> String {
    match value {
        None | Some(Value::Null) => String::new(),
        Some(Value::String(s)) => s.clone(),
        Some(other) => other.to_string(),
    }
}

/// The object at `key` of `parent`, made an empty one when missing (`??=`).
fn object<'a>(parent: &'a mut Value, key: &str) -> &'a mut Value {
    if !parent.is_object() {
        *parent = json!({});
    }
    let map = parent.as_object_mut().expect("an object");
    let slot = map.entry(key.to_string()).or_insert_with(|| json!({}));
    if slot.is_null() {
        *slot = json!({});
    }
    slot
}

fn unique(values: impl IntoIterator<Item = String>) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for v in values {
        if !out.contains(&v) {
            out.push(v);
        }
    }
    out
}

fn known_scopes() -> Vec<&'static str> {
    SLACK_GROUPS.iter().flat_map(|g| g.scopes.iter().copied()).collect()
}

fn known_events() -> Vec<&'static str> {
    SLACK_GROUPS.iter().flat_map(|g| g.events.iter().copied()).collect()
}

/// Reads the form's view of a manifest. A group counts as on when all its scopes are there.
pub fn settings_of(manifest: &Value) -> SlackAppSettings {
    let scopes = strings(at(manifest, &["oauth_config", "scopes", "bot"]));
    let groups = SLACK_GROUPS.iter().map(|g| (g.id.to_string(), g.scopes.iter().all(|s| scopes.iter().any(|x| x == s)))).collect();
    SlackAppSettings {
        name: text(at(manifest, &["display_information", "name"])),
        display_name: text(at(manifest, &["features", "bot_user", "display_name"])),
        description: text(at(manifest, &["display_information", "description"])),
        long_description: text(at(manifest, &["display_information", "long_description"])),
        background_color: text(at(manifest, &["display_information", "background_color"])),
        groups,
    }
}

fn set_or_delete(target: &mut Value, key: &str, value: &str) {
    let map = target.as_object_mut().expect("an object");
    if value.is_empty() {
        map.remove(key);
    } else {
        map.insert(key.into(), json!(value));
    }
}

/// What a Slack app the station makes is called when nobody named it.
pub const DEFAULT_APP_NAME: &str = "still.fail";

/// Applies form edits to a manifest. Turning a group off removes only what no group that stays on needs; scopes the
/// station does not know about are kept.
pub fn apply_settings(manifest: &Value, edit: &SlackAppEdit) -> Value {
    let mut next = manifest.clone();
    object(&mut next, "display_information");
    let features = object(&mut next, "features");
    if features.get("bot_user").is_none_or(Value::is_null) {
        let name = edit.display_name.as_deref().or(edit.name.as_deref()).unwrap_or(DEFAULT_APP_NAME);
        features["bot_user"] = json!({ "display_name": name, "always_online": true });
    }
    // People can always message the bot directly (an app made before this is fixed by any change to it).
    let home = object(features, "app_home");
    home["messages_tab_enabled"] = json!(true);
    home["messages_tab_read_only_enabled"] = json!(false);
    if let Some(name) = &edit.name {
        next["display_information"]["name"] = json!(name.trim());
    }
    if let Some(display_name) = &edit.display_name {
        next["features"]["bot_user"]["display_name"] = json!(display_name.trim());
    }
    let info = &mut next["display_information"];
    if let Some(v) = &edit.description {
        set_or_delete(info, "description", v.trim());
    }
    if let Some(v) = &edit.long_description {
        set_or_delete(info, "long_description", v.trim());
    }
    if let Some(v) = &edit.background_color {
        set_or_delete(info, "background_color", v.trim());
    }
    // Every save puts in what "base" has now (an app made before a scope joined it gets it), and the groups as edited.
    {
        let now = settings_of(manifest).groups;
        let given = edit.groups.clone().unwrap_or_default();
        let on: Vec<&SlackGroup> = SLACK_GROUPS.iter().filter(|g| g.id == "base" || given.get(g.id).copied().unwrap_or(now[g.id])).collect();
        let keep_scopes: Vec<String> = unique(on.iter().flat_map(|g| g.scopes.iter().map(|s| s.to_string())));
        let keep_events: Vec<String> = unique(on.iter().flat_map(|g| g.events.iter().map(|s| s.to_string())));
        let (known, known_events) = (known_scopes(), known_events());
        let scopes = strings(at(&next, &["oauth_config", "scopes", "bot"]));
        let events = strings(at(&next, &["settings", "event_subscriptions", "bot_events"]));
        let scopes = unique(scopes.into_iter().filter(|s| !known.contains(&s.as_str()) || keep_scopes.contains(s)).chain(keep_scopes.clone()));
        let events = unique(events.into_iter().filter(|e| !known_events.contains(&e.as_str()) || keep_events.contains(e)).chain(keep_events.clone()));
        object(object(&mut next, "oauth_config"), "scopes")["bot"] = json!(scopes);
        object(object(&mut next, "settings"), "event_subscriptions")["bot_events"] = json!(events);
    }
    next
}

/// A manifest with Socket Mode off or on. Off, it has no events either (Slack asks events of an app without Socket Mode
/// to go to a URL): an app made so lets its maker turn Socket Mode on in Slack, which is where Slack makes the app-level
/// token with its scope already picked. On, its events are those of the groups it has on.
pub fn with_socket_mode(manifest: &Value, on: bool) -> Value {
    let mut next = manifest.clone();
    let settings = object(&mut next, "settings");
    settings["socket_mode_enabled"] = json!(on);
    if !on {
        settings.as_object_mut().expect("an object").remove("event_subscriptions");
        return next;
    }
    let groups = settings_of(manifest).groups;
    let events = events_on(&groups);
    let known = known_events();
    let others: Vec<String> = strings(at(settings, &["event_subscriptions", "bot_events"])).into_iter().filter(|e| !known.contains(&e.as_str())).collect();
    object(settings, "event_subscriptions")["bot_events"] = json!(unique(others.into_iter().chain(events)));
    next
}

/// The events of the groups on (base always).
fn events_on(groups: &BTreeMap<String, bool>) -> Vec<String> {
    SLACK_GROUPS
        .iter()
        .filter(|g| g.id == "base" || groups.get(g.id).copied().unwrap_or(false))
        .flat_map(|g| g.events.iter().map(|e| e.to_string()))
        .collect()
}

// ── the manifest a new app starts from ────────

/// Every bot scope of every permission group.
pub fn bot_scopes() -> Vec<String> {
    unique(known_scopes().into_iter().map(String::from))
}

/// The Slack app manifest for a still.fail connect. Every permission group is on, so later features (file upload, reactions
/// as status, co-author lookup) do not need a reinstall; people can turn groups off on the connect page.
/// `redirect_url`: where Slack sends a person who installed it (still.fail cloud's page that hands the code to the station),
/// so the bot token is not copied by hand.
pub fn slack_manifest(name: &str, description: Option<&str>, redirect_url: Option<&str>) -> Value {
    let mut oauth = json!({ "scopes": { "bot": bot_scopes() } });
    if let Some(url) = redirect_url {
        oauth["redirect_urls"] = json!([url]);
    }
    json!({
        "display_information": { "name": name, "description": description.unwrap_or("Coding agent in your threads (still.fail)"), "background_color": "#7a2e0e" },
        // The Messages tab lets people message the bot directly; without it Slack says messaging the app is turned off.
        "features": {
            "bot_user": { "display_name": name, "always_online": true },
            "app_home": { "home_tab_enabled": false, "messages_tab_enabled": true, "messages_tab_read_only_enabled": false },
        },
        "oauth_config": oauth,
        "settings": {
            "event_subscriptions": { "bot_events": unique(known_events().into_iter().map(String::from)) },
            "interactivity": { "is_enabled": false },
            "org_deploy_enabled": false,
            "socket_mode_enabled": true,
            "token_rotation_enabled": false,
        },
    })
}

/// As JavaScript's encodeURIComponent.
fn encode_uri_component(text: &str) -> String {
    let mut out = String::new();
    for b in text.bytes() {
        if b.is_ascii_alphanumeric() || b"-_.!~*'()".contains(&b) {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

pub fn create_app_url(name: &str) -> String {
    format!("https://api.slack.com/apps?new_app=1&manifest_json={}", encode_uri_component(&slack_manifest(name, None, None).to_string()))
}

// ── Slack's app API ─────────────────────────────────────────────────────────

/// Slack said no: its error code, and the details it gave (a manifest's problems, say).
#[derive(Debug, Clone, PartialEq)]
pub struct SlackApiError {
    pub method: String,
    pub code: String,
    pub details: Option<Value>,
}

impl std::fmt::Display for SlackApiError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}: {}", self.method, self.code)?;
        if let Some(details) = &self.details {
            write!(f, " {details}")?;
        }
        Ok(())
    }
}

impl std::error::Error for SlackApiError {}

/// Slack's error codes in words people can act on; other errors as they are.
pub fn slack_error(error: &anyhow::Error) -> String {
    let Some(error) = error.downcast_ref::<SlackApiError>() else { return error.to_string() };
    let known = match error.code.as_str() {
        "invalid_auth" => "配置 token 无效，请重新填写",
        "token_expired" => "配置 token 过期了，请重新填写",
        "invalid_refresh_token" => "refresh token 已失效，请重新生成配置 token",
        "not_allowed_token_type" => "这不是 App 配置 token",
        "app_not_found" => "Slack 找不到这个 app；配置 token 可能属于别的工作区",
        "invalid_manifest" => "manifest 不合法",
        other => other,
    };
    let details = match &error.details {
        Some(Value::Array(list)) => list
            .iter()
            .map(|d| format!("{} {}", text(d.get("pointer")), text(d.get("message"))).trim().to_string())
            .collect::<Vec<_>>()
            .join("；"),
        _ => String::new(),
    };
    [known.to_string(), details].into_iter().filter(|s| !s.is_empty()).collect::<Vec<_>>().join("：")
}

fn api_base() -> String {
    crate::former::var("SLACK_API").unwrap_or_else(|| "https://slack.com/api".into())
}

fn client() -> &'static reqwest::Client {
    static CLIENT: OnceLock<reqwest::Client> = OnceLock::new();
    CLIENT.get_or_init(|| reqwest::Client::builder().timeout(Duration::from_secs(30)).build().expect("http client"))
}

/// What a call sends: form fields, or a multipart form (a file).
enum Params {
    Form(Vec<(String, String)>),
    Multipart(Vec<(String, String)>, (Vec<u8>, &'static str, &'static str)),
}

fn form(list: &[(&str, &str)]) -> Params {
    Params::Form(list.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect())
}

async fn call(method: &str, token: Option<&str>, params: Params) -> Result<Value> {
    let mut request = client().post(format!("{}/{method}", api_base()));
    if let Some(token) = token {
        request = request.bearer_auth(token);
    }
    request = match params {
        Params::Form(fields) => request.form(&fields),
        Params::Multipart(fields, (bytes, name, mime)) => {
            let mut body = reqwest::multipart::Form::new();
            for (k, v) in fields {
                body = body.text(k, v);
            }
            body = body.part("file", reqwest::multipart::Part::bytes(bytes).file_name(name).mime_str(mime)?);
            request.multipart(body)
        }
    };
    let response = request.send().await?;
    let status = response.status().as_u16();
    let data: Value = response.json().await?;
    if data.get("ok") != Some(&Value::Bool(true)) {
        let code = match data.get("error") {
            Some(Value::String(code)) => code.clone(),
            Some(other) if !other.is_null() => other.to_string(),
            _ => format!("HTTP {status}"),
        };
        let details = data.get("errors").filter(|e| !e.is_null()).cloned();
        return Err(SlackApiError { method: method.into(), code, details }.into());
    }
    Ok(data)
}

/// An installation's code (from Slack's redirect) exchanged for its bot token, with the workspace it went into.
pub async fn exchange_install_code(client_id: &str, client_secret: &str, code: &str, redirect_uri: &str) -> Result<(String, Option<String>)> {
    let data = call(
        "oauth.v2.access",
        None,
        form(&[("client_id", client_id), ("client_secret", client_secret), ("code", code), ("redirect_uri", redirect_uri)]),
    )
    .await?;
    let team = at(&data, &["team", "name"]).and_then(Value::as_str).filter(|n| !n.is_empty()).map(String::from);
    Ok((text(data.get("access_token")), team))
}

/// A configuration token's next pair, not yet anyone's.
#[derive(Debug, Clone, PartialEq)]
pub struct RotatedToken {
    pub access_token: String,
    pub refresh_token: String,
    /// Epoch ms.
    pub expires_at: i64,
    pub team_id: String,
}

/// Exchanges a refresh token for a fresh pair. The old refresh token stops working.
pub async fn rotate_config_token(refresh_token: &str) -> Result<RotatedToken> {
    let data = call("tooling.tokens.rotate", None, form(&[("refresh_token", refresh_token.trim())])).await?;
    Ok(RotatedToken {
        access_token: text(data.get("token")),
        refresh_token: text(data.get("refresh_token")),
        expires_at: data.get("exp").and_then(Value::as_i64).unwrap_or(0) * 1000,
        team_id: text(data.get("team_id")),
    })
}

/// Which app a bot token belongs to.
pub async fn app_id_of(bot_token: &str) -> Result<String> {
    let auth = call("auth.test", Some(bot_token), form(&[])).await?;
    let bot = call("bots.info", Some(bot_token), form(&[("bot", &text(auth.get("bot_id")))])).await?;
    Ok(text(at(&bot, &["bot", "app_id"])))
}

/// Pages in Slack's app settings a person may need.
#[derive(Serialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SlackAppLinks {
    pub settings: String,
    pub install: String,
    pub app_token: String,
    pub oauth: String,
}

pub fn slack_app_links(app_id: &str, team_id: Option<&str>) -> SlackAppLinks {
    // Slack keeps an app's settings under its workspace (app.slack.com/app-settings/<team>/<app>/<page>); without the
    // workspace, its list of apps is where to find it.
    let Some(team_id) = team_id else {
        let apps = "https://api.slack.com/apps".to_string();
        return SlackAppLinks { settings: apps.clone(), install: apps.clone(), app_token: apps.clone(), oauth: apps };
    };
    let base = format!("https://app.slack.com/app-settings/{team_id}/{app_id}");
    // An app-level token is made from the Socket Mode page: there Slack has its scope (connections:write) already picked.
    SlackAppLinks { settings: base.clone(), install: format!("{base}/install-on-team"), app_token: format!("{base}/socket-mode"), oauth: format!("{base}/oauth") }
}

/// Who a configuration token belongs to and in which workspace, as Slack shows them; None if Slack will not say.
pub async fn owner_of_config_token(access_token: &str) -> Option<ConfigTokenOwner> {
    let auth = call("auth.test", Some(access_token), form(&[])).await.ok()?;
    let user_id = text(auth.get("user_id"));
    let (user, team) = tokio::join!(
        call("users.info", Some(access_token), form(&[("user", &user_id)])),
        call("team.info", Some(access_token), form(&[])),
    );
    let user = user.ok().and_then(|d| d.get("user").cloned()).unwrap_or(Value::Null);
    let team = team.ok().and_then(|d| d.get("team").cloned()).unwrap_or(Value::Null);
    let some = |v: Option<&Value>| v.and_then(Value::as_str).filter(|s| !s.is_empty()).map(String::from);
    Some(ConfigTokenOwner {
        team: some(team.get("name")).unwrap_or_else(|| text(auth.get("team"))),
        team_domain: some(team.get("domain")),
        team_icon: some(at(&team, &["icon", "image_68"])),
        user: some(at(&user, &["profile", "display_name"])).or_else(|| some(user.get("real_name"))).unwrap_or_else(|| text(auth.get("user"))),
        email: some(at(&user, &["profile", "email"])),
        image: some(at(&user, &["profile", "image_48"])),
    })
}

/// A new app's id and its OAuth credentials (Slack gives them only when it is made).
#[derive(Debug, Clone, PartialEq)]
pub struct CreatedApp {
    pub app_id: String,
    pub client_id: String,
    pub client_secret: String,
}

pub type LoadTokens = Arc<dyn Fn() -> Vec<ConfigToken> + Send + Sync>;
pub type SaveToken = Arc<dyn Fn(ConfigToken) + Send + Sync>;

/// The Slack app API with the configuration tokens: a person's own (`by`), one per Slack workspace; nobody uses
/// another's. `load` and `save` keep them in the station's config, so a rotation survives restarts. An app is made with the
/// token of the workspace chosen; an app already made is read and changed with whichever of the person's tokens owns
/// it (found once, by asking).
pub struct SlackApps {
    load: LoadTokens,
    save: SaveToken,
    /// One rotation at a time per person and workspace: the refresh token works once.
    rotating: Mutex<HashMap<String, Arc<tokio::sync::Mutex<()>>>>,
    /// Which workspace's token owns an app, once known.
    owner: Mutex<HashMap<String, String>>,
}

impl SlackApps {
    pub fn new(load: LoadTokens, save: SaveToken) -> SlackApps {
        SlackApps { load, save, rotating: Mutex::default(), owner: Mutex::default() }
    }

    /// Whether this person has a token of their own.
    pub fn configured(&self, by: &str) -> bool {
        (self.load)().iter().any(|t| t.by == by)
    }

    pub async fn export_manifest(&self, by: &str, app_id: &str) -> Result<Value> {
        let data = self.for_app(by, app_id, "apps.manifest.export", &[("app_id", app_id)], None).await?;
        Ok(data.get("manifest").cloned().unwrap_or(Value::Null))
    }

    /// Validates, then updates. Returns whether Slack wants the permissions approved again.
    pub async fn update_manifest(&self, by: &str, app_id: &str, manifest: &Value) -> Result<bool> {
        let text = manifest.to_string();
        self.for_app(by, app_id, "apps.manifest.validate", &[("app_id", app_id), ("manifest", &text)], None).await?;
        let data = self.for_app(by, app_id, "apps.manifest.update", &[("app_id", app_id), ("manifest", &text)], None).await?;
        Ok(data.get("permissions_updated") == Some(&Value::Bool(true)))
    }

    /// Makes the app in one of this person's workspaces (`team`); its OAuth credentials come only now, once.
    pub async fn create_app(&self, by: &str, team: &str, manifest: &Value) -> Result<CreatedApp> {
        let token = self.token(by, team).await?;
        let data = call("apps.manifest.create", Some(&token), form(&[("manifest", &manifest.to_string())])).await?;
        // What Slack answers beyond what is read here, by shape only (never a value): whether an app-level token comes
        // with a Socket Mode app is not documented (its errors name one: failed_generating_app_token).
        info!(shape = %shape_of(&data), "slack app made");
        let app_id = text(data.get("app_id"));
        self.owner.lock().unwrap().insert(format!("{by}|{app_id}"), team.to_string());
        Ok(CreatedApp {
            app_id,
            client_id: text(at(&data, &["credentials", "client_id"])),
            client_secret: text(at(&data, &["credentials", "client_secret"])),
        })
    }

    /// `mime`: the picture's (image/png or image/jpeg).
    pub async fn set_icon(&self, by: &str, app_id: &str, picture: Vec<u8>, mime: &str) -> Result<()> {
        let (mime, name) = if mime == "image/jpeg" { ("image/jpeg", "icon.jpg") } else { ("image/png", "icon.png") };
        self.for_app(by, app_id, "apps.icon.set", &[("app_id", app_id)], Some((picture, name, mime))).await?;
        Ok(())
    }

    /// A call about an app, with the person's token that owns it: the one known, else each in turn until one is not
    /// refused.
    async fn for_app(&self, by: &str, app_id: &str, method: &str, fields: &[(&str, &str)], file: Option<(Vec<u8>, &'static str, &'static str)>) -> Result<Value> {
        let params = || {
            let fields = fields.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
            match &file {
                Some(file) => Params::Multipart(fields, file.clone()),
                None => Params::Form(fields),
            }
        };
        let key = format!("{by}|{app_id}");
        let known = self.owner.lock().unwrap().get(&key).cloned();
        if let Some(team) = known {
            return call(method, Some(&self.token(by, &team).await?), params()).await;
        }
        let tokens: Vec<ConfigToken> = (self.load)().into_iter().filter(|t| t.by == by).collect();
        if tokens.is_empty() {
            bail!("你还没有加 Slack App 配置 token");
        }
        let mut last = None;
        for token in tokens {
            let answer = match self.token(by, &token.team_id).await {
                Ok(access) => call(method, Some(&access), params()).await,
                Err(e) => Err(e),
            };
            match answer {
                Ok(data) => {
                    self.owner.lock().unwrap().insert(key, token.team_id);
                    return Ok(data);
                }
                Err(e) => last = Some(e),
            }
        }
        Err(last.expect("a token was tried"))
    }

    /// A working access token of a person's workspace, rotating first when the current one is about to expire.
    async fn token(&self, by: &str, team: &str) -> Result<String> {
        let current = || (self.load)().into_iter().find(|t| t.by == by && t.team_id == team);
        let fresh = |t: &ConfigToken| t.expires_at - now_ms() > 5 * 60_000;
        let token = current().ok_or_else(|| anyhow!("你在这个 Slack 工作区没有配置 token"))?;
        if fresh(&token) {
            return Ok(token.access_token);
        }
        let lock = self.rotating.lock().unwrap().entry(format!("{by}|{team}")).or_default().clone();
        let _one = lock.lock().await;
        // Another call may have rotated it meanwhile: its refresh token is spent, the pair it made is the one to use.
        let token = current().ok_or_else(|| anyhow!("你在这个 Slack 工作区没有配置 token"))?;
        if fresh(&token) {
            return Ok(token.access_token);
        }
        let next = rotate_config_token(&token.refresh_token).await?;
        let access = next.access_token.clone();
        info!(team = next.team_id, "slack configuration token rotated");
        (self.save)(ConfigToken {
            access_token: next.access_token,
            refresh_token: next.refresh_token,
            expires_at: next.expires_at,
            team_id: next.team_id,
            by: by.to_string(),
            owner: token.owner,
        });
        Ok(access)
    }
}

/// A JSON value's shape, for the log: its keys, and of each string only its kind (an xapp-/xoxb-/… token, or text).
fn shape_of(value: &Value) -> Value {
    match value {
        Value::Array(list) => Value::Array(list.iter().map(shape_of).collect()),
        Value::Object(map) => Value::Object(map.iter().map(|(k, v)| (k.clone(), shape_of(v))).collect::<Map<_, _>>()),
        Value::String(s) => {
            let b = s.as_bytes();
            let token = b.len() >= 5 && b[0] == b'x' && b[1..4].iter().all(u8::is_ascii_lowercase) && b[4] == b'-';
            json!(if token { format!("{}…", &s[..5]) } else { "string".into() })
        }
        Value::Number(_) => json!("number"),
        Value::Bool(_) => json!("boolean"),
        Value::Null => json!("object"),
    }
}

#[cfg(test)]
mod tests;
