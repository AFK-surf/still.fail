//! Slack through the pages: apps made and edited with a person's configuration token, their installs, new connects
//! from tokens, the token check, and the people of the connected Slack workspaces. (src/admin/api.ts, Slack apps)

use std::collections::HashSet;
use std::sync::Arc;

use anyhow::Result;
use base64::Engine;
use serde_json::{Map, Value, json};
use tracing::{info, warn};

use super::{AdminApi, Input, http_error};
use crate::access::Viewer;
use crate::chat::slack_apps::{
    SLACK_GROUPS, SlackApiError, SlackAppEdit, apply_settings, app_id_of, exchange_install_code, owner_of_config_token, rotate_config_token, settings_of, slack_app_links,
    slack_error, slack_manifest, with_socket_mode,
};
use crate::config::{ConfigToken, RawPlace, SlackAppMade, SlackAppOauth};
use crate::connections::ConnectState;

/// The tokens with this one in, in place of its person's old one for the workspace.
pub fn upsert_token(mut tokens: Vec<ConfigToken>, token: ConfigToken) -> Vec<ConfigToken> {
    match tokens.iter_mut().find(|t| t.by == token.by && t.team_id == token.team_id) {
        Some(slot) => {
            let owner = token.owner.clone().or(slot.owner.clone());
            *slot = ConfigToken { owner, ..token };
        }
        None => tokens.push(token),
    }
    tokens
}

fn group_ids() -> Vec<&'static str> {
    SLACK_GROUPS.iter().map(|g| g.id).collect()
}

fn url_encode(s: &str) -> String {
    s.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => (b as char).to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect()
}

fn random_hex(n: usize) -> String {
    let mut b = vec![0u8; n];
    let _ = getrandom::fill(&mut b);
    hex::encode(b)
}

fn color_ok(color: &str) -> bool {
    let c = color.trim();
    c.len() == 7 && c.starts_with('#') && c[1..].chars().all(|x| x.is_ascii_hexdigit())
}

/// A connect id from its bot's name: lower case, runs of anything else as one dash.
fn connect_slug(name: &str) -> String {
    let mut out = String::new();
    for c in name.to_lowercase().chars() {
        if c.is_ascii_alphanumeric() {
            out.push(c);
        } else if !out.ends_with('-') {
            out.push('-');
        }
    }
    let slug: String = out.trim_matches('-').chars().take(32).collect();
    let slug = slug.trim_end_matches('-').to_string();
    if slug.is_empty() { "slack".into() } else { slug }
}

impl AdminApi {
    /// Keeps what each connected connect is known by, its Slack workspace and its bot's name there, as Slack says
    /// now: a connect shows by them while it is not connected too.
    pub(super) fn remember_identities(&self) {
        let config = self.config();
        let changed: Vec<(String, RawPlace, String, Option<String>)> = config
            .connects
            .iter()
            .filter_map(|c| {
                let seen = match self.deps.connections.state(c) {
                    ConnectState::Connected { workspace, .. } | ConnectState::Reconnecting { workspace, .. } => workspace?,
                    _ => return None,
                };
                if seen.team_id.is_empty() {
                    return None;
                }
                let same = c.slack.team.as_ref().is_some_and(|t| t.id == seen.team_id && t.name == seen.team)
                    && c.slack.bot_name.as_deref() == Some(seen.bot_name.as_str())
                    && c.slack.bot_image == seen.bot_image;
                (!same).then(|| (c.id.clone(), RawPlace { id: seen.team_id, name: Some(seen.team) }, seen.bot_name, seen.bot_image))
            })
            .collect();
        if changed.is_empty() {
            return;
        }
        let saved = self.deps.settings.update(|raw| {
            for connect in raw.connects.iter_mut().flatten() {
                let Some((_, team, bot_name, bot_image)) = changed.iter().find(|(id, ..)| *id == connect.id) else { continue };
                let slack = connect.slack.get_or_insert_with(Default::default);
                slack.team = Some(team.clone());
                slack.bot_name = Some(bot_name.clone());
                slack.bot_image = bot_image.clone();
            }
            Ok(())
        });
        if let Err(e) = saved {
            warn!(error = %e, "slack identities not kept");
        }
    }

    /// The workspace an app is made in: the one asked for, or the only one the viewer has.
    fn team_for(&self, input: &Input, viewer: &Viewer) -> Result<String> {
        let by = viewer.id();
        let config = self.config();
        let teams: Vec<&ConfigToken> = config.slack_config_tokens.iter().filter(|t| t.by == by).collect();
        if teams.is_empty() {
            return Err(http_error(400, "你还没有加 Slack 的 App 配置 token"));
        }
        let team = input.str("team").map(String::from).or_else(|| (teams.len() == 1).then(|| teams[0].team_id.clone()));
        match team {
            Some(team) if teams.iter().any(|t| t.team_id == team) => Ok(team),
            _ => Err(http_error(400, "选一个 Slack 工作区")),
        }
    }

    /// The Slack workspace a connect's app is in, as last seen.
    fn team_of(&self, connect: &str) -> Option<String> {
        self.config().connects.iter().find(|c| c.id == connect).and_then(|c| c.slack.team.as_ref().map(|t| t.id.clone()))
    }

    async fn app_id(&self, connect_id: &str) -> Result<Option<String>> {
        let connect = self.config().connects.iter().find(|c| c.id == connect_id).cloned().ok_or_else(|| http_error(404, format!("unknown connect {connect_id}")))?;
        if let Some(app) = connect.slack.app_id.clone() {
            return Ok(Some(app));
        }
        if let Some(app) = self.app_ids.lock().unwrap().get(connect_id).cloned() {
            return Ok(Some(app));
        }
        if connect.slack.bot_token.is_empty() {
            return Ok(None);
        }
        let app = app_id_of(&connect.slack.bot_token).await?;
        self.app_ids.lock().unwrap().insert(connect_id.to_string(), app.clone());
        Ok(Some(app))
    }

    pub(super) async fn slack_app(&self, connect_id: &str, viewer: &Viewer) -> Result<Value> {
        let groups = group_ids();
        let app = match self.app_id(connect_id).await {
            Ok(app) => app,
            Err(e) if e.downcast_ref::<super::HttpError>().is_some() => return Err(e),
            // The bot token no longer works, so the app cannot be looked up; the Slack section says why.
            Err(e) => return Ok(json!({ "state": "no_app", "appId": null, "links": null, "settings": null, "groups": groups, "error": slack_error(&e) })),
        };
        let Some(app) = app else { return Ok(json!({ "state": "no_app", "appId": null, "links": null, "settings": null, "groups": groups })) };
        let links = slack_app_links(&app, self.team_of(connect_id).as_deref());
        if !self.apps.configured(&viewer.id()) {
            return Ok(json!({ "state": "no_config_token", "appId": app, "links": links, "settings": null, "groups": groups }));
        }
        Ok(match self.apps.export_manifest(&viewer.id(), &app).await {
            Ok(manifest) => json!({ "state": "ok", "appId": app, "links": links, "settings": settings_of(&manifest), "groups": groups }),
            Err(e) => json!({ "state": "error", "appId": app, "links": links, "settings": null, "groups": groups, "error": slack_error(&e) }),
        })
    }

    pub(super) async fn put_slack_app(self: &Arc<Self>, connect_id: &str, input: &Input, viewer: &Viewer) -> Result<Value> {
        let app = self.app_id(connect_id).await?.ok_or_else(|| http_error(400, "这个连接还没有 Slack app"))?;
        let text = |k: &str| input.str(k).map(String::from);
        let edit = SlackAppEdit {
            name: text("name"),
            display_name: text("displayName"),
            description: text("description"),
            long_description: text("longDescription"),
            background_color: text("backgroundColor"),
            groups: input.get("groups").and_then(|g| serde_json::from_value(g.clone()).ok()),
        };
        if edit.name.as_deref().is_some_and(|n| n.trim().is_empty()) {
            return Err(http_error(400, "名字不能为空"));
        }
        if edit.background_color.as_deref().is_some_and(|c| !c.is_empty() && !color_ok(c)) {
            return Err(http_error(400, "背景色要写成 #RRGGBB"));
        }
        let by = viewer.id();
        let updated = async {
            let current = self.apps.export_manifest(&by, &app).await?;
            self.apps.update_manifest(&by, &app, &apply_settings(&current, &edit)).await
        };
        let permissions_updated = updated.await.map_err(|e| http_error(400, format!("Slack 没接受这次修改：{}", slack_error(&e))))?;
        let icon_error = match input.str("icon").filter(|i| !i.is_empty()) {
            Some(icon) => self.set_icon(&by, &app, icon).await,
            None => None,
        };
        // Its name here is its bot's in Slack: read again now, and once more when Slack has surely taken the change.
        if edit.name.is_some() || edit.display_name.is_some() {
            let (connections, id) = (self.deps.connections.clone(), connect_id.to_string());
            tokio::spawn(async move {
                for wait in [0, 8] {
                    tokio::time::sleep(std::time::Duration::from_secs(wait)).await;
                    if let Err(e) = connections.refresh_identity(&id).await {
                        warn!(connect = id, error = %e, "slack identity refresh failed");
                    }
                }
            });
        }
        info!(connect = connect_id, app, permissions_updated, by, "slack app updated from the admin page");
        Ok(json!({ "permissionsUpdated": permissions_updated, "iconError": icon_error, "links": slack_app_links(&app, self.team_of(connect_id).as_deref()) }))
    }

    /// Sets an app's icon (a PNG data URL); what went wrong, in words, or None.
    async fn set_icon(&self, by: &str, app: &str, icon: &str) -> Option<String> {
        let (head, data) = icon.split_once(";base64,").unwrap_or(("data:image/png", ""));
        let mime = head.strip_prefix("data:").filter(|m| m.starts_with("image/")).unwrap_or("image/png");
        let bytes = base64::engine::general_purpose::STANDARD.decode(data).unwrap_or_default();
        match self.apps.set_icon(by, app, bytes, mime).await {
            Ok(()) => None,
            Err(e) if e.downcast_ref::<SlackApiError>().is_some_and(|s| s.code == "app_not_owned_by_manager_app") => {
                Some("Slack 只允许给用 API 创建的 app 换图标。这个 app 是在 Slack 网页上建的，请在 Slack 的 app 设置页上传图标。".into())
            }
            Err(e) => Some(slack_error(&e)),
        }
    }

    /// Makes a Slack app for a connect to come. On a station in ember cloud it is made to be installed through Slack's
    /// OAuth: `install` is the link, and Slack sends the person back to ember cloud's page, which hands the code to this
    /// station (POST /slack/installs), which takes the bot token for it. Elsewhere the token is copied.
    pub(super) async fn make_slack_app(&self, input: &Input, viewer: &Viewer) -> Result<Value> {
        let by = viewer.id();
        let team = self.team_for(input, viewer)?;
        let mut edit: SlackAppEdit = input.get("settings").filter(|s| s.is_object()).and_then(|s| serde_json::from_value(s.clone()).ok()).unwrap_or_default();
        let name = edit.name.as_deref().map(str::trim).filter(|n| !n.is_empty()).unwrap_or("ember").to_string();
        if edit.background_color.as_deref().is_some_and(|c| !c.is_empty() && !color_ok(c)) {
            return Err(http_error(400, "背景色要写成 #RRGGBB"));
        }
        edit.name = Some(name.clone());
        let mesh = self.deps.mesh.as_ref().map(|m| m.status());
        let redirect = mesh.as_ref().filter(|m| m.workspace_id.is_some() && m.station.is_some()).and_then(|m| m.origin.as_ref()).map(|o| format!("{o}/slack/installed"));
        let manifest = apply_settings(&slack_manifest(&name, None, redirect.as_deref()), &edit);
        // Made without Socket Mode: its maker turns it on in Slack, which makes the app-level token with its scope
        // picked; the connect that takes it puts Socket Mode and its events in (socket_mode_on).
        let app = self.apps.create_app(&by, &team, &with_socket_mode(&manifest, false)).await.map_err(|e| http_error(400, format!("Slack 没能创建 app：{}", slack_error(&e))))?;
        let icon_error = match input.str("icon").filter(|i| !i.is_empty()) {
            Some(icon) => self.set_icon(&by, &app.app_id, icon).await,
            None => None,
        };
        // Kept here until a connect takes it: the pages show it, and it can be installed and finished any time later.
        let shown = manifest["display_information"]["name"].as_str().map(String::from).unwrap_or(name);
        let mut made = SlackAppMade { app_id: app.app_id.clone(), name: shown, team_id: team, by, created: crate::store::now_ms(), oauth: None };
        if let (Some(redirect), Some(mesh)) = (&redirect, &mesh) {
            if !app.client_id.is_empty() && !app.client_secret.is_empty() {
                // Which station it is for goes with it, so ember cloud's page knows where to hand the code.
                let state = format!("{}/{}~{}", mesh.workspace_id.clone().unwrap_or_default(), mesh.station.clone().unwrap_or_default(), random_hex(16));
                let scopes: Vec<String> = manifest["oauth_config"]["scopes"]["bot"].as_array().into_iter().flatten().filter_map(Value::as_str).map(String::from).collect();
                let install = format!(
                    "https://slack.com/oauth/v2/authorize?client_id={}&scope={}&redirect_uri={}&state={}",
                    url_encode(&app.client_id),
                    url_encode(&scopes.join(",")),
                    url_encode(redirect),
                    url_encode(&state)
                );
                made.oauth = Some(SlackAppOauth { state, client_id: app.client_id.clone(), client_secret: app.client_secret.clone(), redirect_uri: redirect.clone(), install, bot_token: None, installed_team: None });
            }
        }
        self.save(viewer, &format!("slack app {}", app.app_id), |raw| {
            raw.slack_apps.get_or_insert_with(Vec::new).push(made);
            Ok(())
        })?;
        Ok(json!({ "appId": app.app_id, "iconError": icon_error }))
    }

    /// An app made here, being connected: Socket Mode and its events on in its manifest (Slack has it off until then).
    async fn socket_mode_on(&self, made: &SlackAppMade) -> Result<()> {
        let turned = async {
            let current = self.apps.export_manifest(&made.by, &made.app_id).await?;
            self.apps.update_manifest(&made.by, &made.app_id, &with_socket_mode(&current, true)).await
        };
        turned.await.map(|_| ()).map_err(|e| http_error(400, format!("Slack 没能打开 app 的 Socket Mode 和事件：{}", slack_error(&e))))
    }

    /// A Slack app made here and not connected yet, by its app id or its install's state.
    fn made_app(&self, key: &str) -> Option<SlackAppMade> {
        self.config().slack_apps.iter().find(|a| a.app_id == key || a.oauth.as_ref().is_some_and(|o| o.state == key)).cloned()
    }

    /// Drops a made app from the waiting ones (it stays in Slack); only its maker's to drop.
    pub(super) fn drop_made_app(&self, app: &str, viewer: &Viewer) -> Result<Value> {
        let by = viewer.id();
        if !self.config().slack_apps.iter().any(|a| a.app_id == app && a.by == by) {
            return Err(http_error(404, "没有这个 app"));
        }
        self.save(viewer, &format!("slack app {app} dropped"), |raw| {
            raw.slack_apps.get_or_insert_with(Vec::new).retain(|a| a.app_id != app);
            Ok(())
        })
    }

    /// An app made here was installed: its code becomes its bot token, kept here for the connect that takes it.
    pub(super) async fn installed(&self, input: &Input) -> Result<Value> {
        let state = input.text("state");
        let oauth = self.made_app(&state).and_then(|a| a.oauth).filter(|o| !state.is_empty() && o.state == state);
        let Some(oauth) = oauth else { return Err(http_error(400, "这个安装不是这台 station 发起的，或者这个 app 已经连上或移除了")) };
        let (bot_token, team) = exchange_install_code(&oauth.client_id, &oauth.client_secret, &input.text("code"), &oauth.redirect_uri)
            .await
            .map_err(|e| http_error(400, format!("Slack 没能完成安装：{}", slack_error(&e))))?;
        self.deps.settings.update(|raw| {
            for app in raw.slack_apps.iter_mut().flatten() {
                if let Some(o) = app.oauth.as_mut().filter(|o| o.state == state) {
                    o.bot_token = Some(bot_token.clone());
                    o.installed_team = team.clone();
                }
            }
            Ok(())
        })?;
        info!(state, team = ?team, "slack app installed");
        self.events.overview_changed();
        Ok(json!({ "team": team }))
    }

    /// A new Slack connect from its tokens: named as its bot is in Slack, with an id made from that name.
    pub(super) async fn new_slack_connect(self: &Arc<Self>, input: &Input, viewer: &Viewer) -> Result<Value> {
        let slack = input.get("slack");
        let text = |k: &str| slack.and_then(|s| s.get(k)).and_then(Value::as_str).map(str::trim).unwrap_or("").to_string();
        let app_token = text("appToken");
        // Installed through Slack's OAuth: its bot token is here already.
        let install = slack.and_then(|s| s.get("install")).and_then(Value::as_str).map(String::from);
        let installed = install.as_deref().and_then(|i| self.made_app(i)).and_then(|a| a.oauth);
        if install.is_some() && installed.as_ref().and_then(|o| o.bot_token.as_ref()).is_none() {
            return Err(http_error(400, "app 还没装好：先在 Slack 里安装"));
        }
        let bot_token = installed.and_then(|o| o.bot_token).unwrap_or_else(|| text("botToken"));
        let (identity, errors) = crate::chat::slack::verify_slack_tokens(&app_token, &bot_token).await;
        let Some(identity) = identity.filter(|_| errors.is_empty()) else {
            return Err(http_error(400, if errors.is_empty() { "token 不对".to_string() } else { errors.join("；") }));
        };
        let given_app = slack.and_then(|s| s.get("appId")).and_then(Value::as_str).filter(|a| !a.is_empty()).map(String::from);
        let made = match (&install, &given_app) {
            (Some(i), _) => self.made_app(i),
            (None, Some(app)) => self.made_app(app),
            _ => None,
        };
        if let Some(made) = &made {
            self.socket_mode_on(made).await?;
        }
        let name = if identity.bot_name.is_empty() { "ember".to_string() } else { identity.bot_name.clone() };
        let taken: HashSet<String> = self.config().connects.iter().map(|c| c.id.clone()).collect();
        let base = connect_slug(&name);
        let mut id = base.clone();
        let mut n = 2;
        while taken.contains(&id) {
            id = format!("{base}-{n}");
            n += 1;
        }
        let app = made.as_ref().map(|m| m.app_id.clone()).or(given_app);
        let mut fields = input.0.clone();
        fields.insert("kind".into(), json!("slack"));
        let mut slack_fields = Map::new();
        slack_fields.insert("appToken".into(), json!(app_token));
        slack_fields.insert("botToken".into(), json!(bot_token));
        slack_fields.insert("team".into(), json!({ "id": identity.team_id, "name": identity.team }));
        slack_fields.insert("botName".into(), json!(identity.bot_name));
        if let Some(image) = &identity.bot_image {
            slack_fields.insert("botImage".into(), json!(image));
        }
        fields.insert("slack".into(), Value::Object(slack_fields));
        let overview = self.put_connect(&id, &Input(fields), viewer)?;
        // Its app is connected now: no longer one waiting.
        if let Some(made) = &made {
            self.deps.settings.update(|raw| {
                raw.slack_apps.get_or_insert_with(Vec::new).retain(|a| a.app_id != made.app_id);
                Ok(())
            })?;
        }
        let Some(app) = app else { return Ok(json!({ "id": id, "overview": overview })) };
        let overview = self.save(viewer, &format!("slack app of {id}"), |raw| {
            for c in raw.connects.iter_mut().flatten().filter(|c| c.id == id) {
                c.slack.get_or_insert_with(Default::default).app_id = Some(app.clone());
            }
            Ok(())
        })?;
        Ok(json!({ "id": id, "overview": overview }))
    }

    /// Creates the connect's Slack app with the configuration token, so only installing it is left to do in Slack.
    pub(super) async fn create_slack_app(&self, connect_id: &str, input: &Input, viewer: &Viewer) -> Result<Value> {
        let connect = self.config().connects.iter().find(|c| c.id == connect_id).cloned().ok_or_else(|| http_error(404, format!("unknown connect {connect_id}")))?;
        if self.app_id(connect_id).await?.is_some() {
            return Err(http_error(400, "这个连接已经有 Slack app 了"));
        }
        let name = input.str("name").map(str::trim).filter(|n| !n.is_empty()).map(String::from).unwrap_or_else(|| connect.name().to_string());
        let team = self.team_for(input, viewer)?;
        let app = self.apps.create_app(&viewer.id(), &team, &slack_manifest(&name, None, None)).await.map_err(|e| http_error(400, format!("Slack 没能创建 app：{}", slack_error(&e))))?;
        self.save(viewer, &format!("create slack app for {connect_id}"), |raw| {
            for c in raw.connects.iter_mut().flatten().filter(|c| c.id == connect_id) {
                c.slack.get_or_insert_with(Default::default).app_id = Some(app.app_id.clone());
            }
            Ok(())
        })?;
        Ok(json!({ "appId": app.app_id, "links": slack_app_links(&app.app_id, Some(&team)) }))
    }

    /// The Slack workspaces ember makes apps in: a configuration token each, added by its refresh token.
    pub(super) async fn add_config_token(&self, input: &Input, viewer: &Viewer) -> Result<Value> {
        let refresh = input.text("refreshToken").trim().to_string();
        if !refresh.starts_with("xoxe-") {
            return Err(http_error(400, "Refresh token 应该以 xoxe- 开头（不是 xoxe.xoxp- 开头的那个）"));
        }
        let token = rotate_config_token(&refresh).await.map_err(|e| http_error(400, format!("Slack 没接受这个 token：{e}")))?;
        let owner = owner_of_config_token(&token.access_token).await;
        let team = token.team_id.clone();
        let made = ConfigToken { access_token: token.access_token, refresh_token: token.refresh_token, expires_at: token.expires_at, team_id: token.team_id, by: viewer.id(), owner };
        self.deps.settings.update(|raw| {
            raw.slack_config_tokens = Some(upsert_token(raw.slack_config_tokens.take().unwrap_or_default(), made));
            Ok(())
        })?;
        info!(team, by = viewer.id(), "slack configuration token added");
        Ok(json!({ "teamId": team, "overview": self.overview(viewer) }))
    }

    /// The tokens as given, blank ones falling back to the stored ones of `connect`, so replacing one token can be
    /// checked alone; an app installed through Slack's OAuth (`install`) checks with the bot token it got.
    pub(super) async fn verify_slack(&self, input: &Input) -> Value {
        let config = self.config();
        let stored = input.str("connect").and_then(|id| config.connects.iter().find(|c| c.id == id)).map(|c| c.slack.clone());
        let pick = |field: &str, stored: Option<String>| input.str(field).map(str::trim).filter(|t| !t.is_empty()).map(String::from).or(stored).unwrap_or_default();
        let app_token = pick("appToken", stored.as_ref().map(|s| s.app_token.clone()));
        let installed = input.str("install").and_then(|i| self.made_app(i)).and_then(|a| a.oauth).and_then(|o| o.bot_token);
        let bot_token = installed.unwrap_or_else(|| pick("botToken", stored.as_ref().map(|s| s.bot_token.clone())));
        let (identity, errors) = crate::chat::slack::verify_slack_tokens(&app_token, &bot_token).await;
        json!({ "identity": identity, "errors": errors })
    }

    /// The people of the Slack workspaces this station's connects are in, once each by email, for adding them to the
    /// ember workspace: bots and deactivated accounts left out; guests marked. Needs users:read.email to see emails.
    pub(super) async fn slack_people(&self) -> Value {
        let mut people: Vec<Value> = vec![];
        let mut seen = HashSet::new();
        let mut errors = vec![];
        for connect in self.config().connects.iter() {
            let Some(chat) = self.deps.connections.chat(&connect.id) else { continue };
            let mut cursor = String::new();
            loop {
                let mut params = Map::new();
                params.insert("limit".into(), json!(200));
                if !cursor.is_empty() {
                    params.insert("cursor".into(), json!(cursor));
                }
                let page = match chat.api("users.list", params).await {
                    Ok(page) => page,
                    Err(e) => {
                        errors.push(format!("{}：{e}", connect.name()));
                        break;
                    }
                };
                for m in page["members"].as_array().into_iter().flatten() {
                    let email = m["profile"]["email"].as_str().unwrap_or("").to_lowercase();
                    let skip = m["is_bot"] == true || m["deleted"] == true || m["id"] == "USLACKBOT" || email.is_empty();
                    if skip || !seen.insert(email.clone()) {
                        continue;
                    }
                    let name = [&m["profile"]["real_name"], &m["real_name"], &m["name"]].into_iter().filter_map(Value::as_str).find(|n| !n.is_empty()).unwrap_or(&email).to_string();
                    people.push(json!({
                        "email": email, "name": name, "image": m["profile"]["image_72"].as_str(),
                        "guest": m["is_restricted"] == true || m["is_ultra_restricted"] == true, "team": connect.slack.team.as_ref().map(|t| t.name.clone()),
                    }));
                }
                cursor = page["response_metadata"]["next_cursor"].as_str().unwrap_or("").to_string();
                if cursor.is_empty() {
                    break;
                }
            }
        }
        people.sort_by(|a, b| (a["guest"] == true).cmp(&(b["guest"] == true)).then_with(|| a["name"].as_str().cmp(&b["name"].as_str())));
        json!({ "people": people, "errors": errors })
    }
}
