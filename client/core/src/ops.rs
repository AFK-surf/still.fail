//! What the UIs can have done on a station or on still.fail cloud, each by its name (`session.stop`, `profile.put`,
//! `workspace.rename`…). A UI never makes a request itself: it names what it wants done and with what, and the core
//! knows the request that does it and what it changes (the effects declared beside each operation), so every
//! topic that shows it is current when the call answers. See docs/client-core.md, Calls.

use serde_json::{Map, Value, json};

use crate::error::{CoreError, Result};
use crate::station::encode;

/// Where an operation goes: a station (its address), or still.fail cloud as a signed-in account.
#[derive(Debug, Clone, PartialEq)]
pub enum Target {
    Station(String),
    Cloud(String),
}

/// How a successful station operation updates its live topics. Declared with the request, never inferred from a URL.
#[derive(Debug, Clone, PartialEq)]
pub enum Effect {
    None,
    Session(Option<String>),
    Thread { archived: bool },
    Connect(Option<String>),
    Overview,
    Footprint,
    Slack,
    Job,
    Identity,
}

/// The request an operation makes.
#[derive(Debug, Clone, PartialEq)]
pub struct Request {
    pub target: Target,
    pub method: &'static str,
    pub path: String,
    pub body: Option<Value>,
    /// Made instead when the first one is a 404: what a station from before the first one knew.
    pub fallback: Option<Box<Request>>,
    pub effect: Effect,
}

/// The request of the operation `name`, with its params; `None` when there is no such operation.
pub fn request(name: &str, params: &Value) -> Option<Result<Request>> {
    let (service, _) = name.split_once('.')?;
    let cloud = matches!(service, "workspace" | "invitation" | "loginSession" | "admin");
    if cloud { cloud_op(name, params) } else { station_op(name, params) }
}

/// The params of one call, read as it goes.
struct P<'a>(&'a Value);

impl P<'_> {
    fn str(&self, name: &str) -> Result<String> {
        self.0.get(name).and_then(Value::as_str).map(str::to_string).ok_or_else(|| CoreError::invalid(format!("参数不对：缺少 {name}")))
    }
    fn word(&self, name: &str) -> Option<String> {
        self.0.get(name).and_then(Value::as_str).map(str::to_string)
    }
    fn at(&self, name: &str) -> Result<String> {
        self.str(name).map(|s| encode(&s))
    }
    fn u64(&self, name: &str) -> Result<u64> {
        self.0.get(name).and_then(Value::as_u64).ok_or_else(|| CoreError::invalid(format!("参数不对：缺少 {name}")))
    }
    fn bool(&self, name: &str) -> bool {
        self.0.get(name).and_then(Value::as_bool).unwrap_or(false)
    }
    fn value(&self, name: &str) -> Result<Value> {
        self.0.get(name).cloned().ok_or_else(|| CoreError::invalid(format!("参数不对：缺少 {name}")))
    }
    /// Those of `names` that are given (null included), as a body.
    fn pick(&self, names: &[&str]) -> Value {
        let mut body = Map::new();
        for name in names {
            if let Some(v) = self.0.get(*name) {
                body.insert((*name).to_string(), v.clone());
            }
        }
        Value::Object(body)
    }
}

fn station_op(name: &str, params: &Value) -> Option<Result<Request>> {
    let p = P(params);
    let op = |method: &'static str, path: Result<String>, body: Option<Value>, effect: Effect| -> Result<Request> {
        Ok(Request { target: Target::Station(p.str("station")?), method, path: path?, body, fallback: None, effect })
    };
    let r = match name {
        // ── sessions and chats ──
        // @params key:string
        "session.stop" => op("POST", p.at("key").map(|k| format!("/sessions/{k}/stop")), None, Effect::Session(p.word("key"))),
        // @params key:string
        "session.warm" => op("POST", p.at("key").map(|k| format!("/sessions/{k}/warm")), None, Effect::Session(p.word("key"))),
        // @params key:string
        "session.evict" => op("POST", p.at("key").map(|k| format!("/sessions/{k}/evict")), None, Effect::Session(p.word("key"))),
        // @params key:string
        "session.delete" => op("DELETE", p.at("key").map(|k| format!("/sessions/{k}")), None, Effect::Session(p.word("key"))),
        // How it runs from its next turn on: any of profile, model, effort (null: the default).
        // @params key:string profile?:string model?:string effort?:string fast?:boolean
        "session.settings" => op("POST", p.at("key").map(|k| format!("/sessions/{k}/settings")), Some(p.pick(&["profile", "model", "effort", "fast"])), Effect::Session(p.word("key"))),
        // A chat into the archive or back: its thread (with its session when it is that session's own), or an agent
        // with no chat yet. A station from before chats were archived by themselves archives its session instead.
        // @params archived?:boolean session:string thread?:number
        "chat.archive" => (|| {
            let method = if p.bool("archived") { "POST" } else { "DELETE" };
            let fallback = op(method, p.at("session").map(|key| format!("/sessions/{key}/archive")), None, Effect::Session(p.word("session")))?;
            match p.0.get("thread").and_then(Value::as_u64) {
                Some(thread) => {
                    let mut request = op(method, Ok(format!("/threads/{thread}/archive")), None, Effect::Thread { archived: true })?;
                    request.fallback = Some(Box::new(fallback));
                    Ok(request)
                }
                None => Ok(fallback),
            }
        })(),
        // Keep this chat and stop offering to archive it, on every device of this viewer.
        // @params thread:number
        "chat.keep" => (|| op("PUT", Ok(format!("/threads/{}/keep", p.u64("thread")?)), None, Effect::Thread { archived: false }))(),
        // A chat named by hand (an empty name: named by its first message again): its thread, or an agent with no chat yet.
        // @params session?:string title?:string thread?:number
        "chat.rename" => (|| match p.0.get("thread").and_then(Value::as_u64) {
            Some(thread) => op("PUT", Ok(format!("/threads/{thread}/title")), Some(p.pick(&["title"])), Effect::Thread { archived: false }),
            None => op("POST", p.at("session").map(|k| format!("/sessions/{k}/title")), Some(p.pick(&["title"])), Effect::Session(p.word("session"))),
        })(),
        // A chat kept at the top of the viewer's list, or let go: by its item's id, its session's key.
        // @params pinned?:boolean session:string
        "chat.pin" => op(if p.bool("pinned") { "PUT" } else { "DELETE" }, p.at("session").map(|k| format!("/sessions/{k}/pin")), None, Effect::Session(p.word("session"))),
        // A decision the viewer will not take up (decisions.rs): off their list on every device, pending for the rest.
        // @params thread:number seq:number
        "decision.dismiss" => (|| op("PUT", Ok(format!("/threads/{}/dismissed", p.u64("thread")?)), Some(json!({ "n": p.u64("seq")? })), Effect::Thread { archived: false }))(),
        // An agent-provided close option ends this question without sending a reply or waking an agent.
        // @params thread:number seq:number option:string
        "decision.close" => (|| op("PUT", Ok(format!("/threads/{}/closed-card", p.u64("thread")?)), Some(json!({ "n": p.u64("seq")?, "option": p.str("option")? })), Effect::Session(None)))(),
        // A new chat: its session and its thread, made before its first message (`chat.create` makes one behind the page).
        // @params runtime?:string profile?:string model?:string effort?:string fast?:boolean
        "session.new" => op("POST", Ok("/sessions".into()), Some(p.pick(&["runtime", "profile", "model", "effort", "fast"])), Effect::Session(None)),
        // @params
        "chats.archived" => op("GET", Ok("/chats?archived=1".into()), None, Effect::None),
        // The chat of an agent that has none yet, bound to its session: answers the thread.
        // @params session?:string
        "chat.forSession" => op("POST", Ok("/threads".into()), Some(p.pick(&["session"])), Effect::Thread { archived: false }),
        // What an inline visualization kept, by the session that sent its file and the file's path.
        // @params key:string path:string
        "widget.state" => op("GET", (|| Ok(format!("/sessions/{}/widget-state?path={}", p.at("key")?, p.at("path")?)))(), None, Effect::None),
        // @params key:string path?:string state?:json
        "widget.setState" => op("PUT", p.at("key").map(|k| format!("/sessions/{k}/widget-state")), Some(p.pick(&["path", "state"])), Effect::Session(p.word("key"))),
        // ── the machine's own sessions (Claude Code, Codex in a terminal) ──
        // @params
        "machineSessions.list" => op("GET", Ok("/machine-sessions".into()), None, Effect::None),
        // @params runtime:string id:string limit?:number
        "machineSessions.read" => op(
            "GET",
            (|| Ok(format!("/machine-sessions/{}/{}?limit={}", p.at("runtime")?, p.at("id")?, p.0.get("limit").and_then(Value::as_u64).unwrap_or(200))))(),
            None,
            Effect::None,
        ),
        // @params runtime?:string id?:string
        "machineSessions.continue" => op("POST", Ok("/machine-sessions".into()), Some(p.pick(&["runtime", "id"])), Effect::None),
        // ── connects ──
        // @params input?:json id?:string
        "connect.create" => op("POST", Ok("/connects".into()), p.value("input").map(Some).unwrap_or(None), Effect::Connect(p.word("id"))),
        // @params id:string input?:json
        "connect.put" => op("PUT", p.at("id").map(|id| format!("/connects/{id}")), Some(p.value("input").unwrap_or(json!({}))), Effect::Connect(p.word("id"))),
        // @params id:string
        "connect.delete" => op("DELETE", p.at("id").map(|id| format!("/connects/{id}")), None, Effect::Connect(p.word("id"))),
        // @params id:string
        "connect.reconnect" => op("POST", p.at("id").map(|id| format!("/connects/{id}/reconnect")), None, Effect::Connect(p.word("id"))),
        // A single-session connect's session: `session` null makes a new one (named `title`).
        // @params connect:string session?:string title?:string
        "connect.bindSession" => op("POST", p.at("connect").map(|c| format!("/connects/{c}/session")), Some(p.pick(&["session", "title"])), Effect::Connect(p.word("connect"))),
        // @params connect:string input?:json
        "connect.putSlackApp" => op("PUT", p.at("connect").map(|c| format!("/connects/{c}/slack-app")), Some(p.value("input").unwrap_or(json!({}))), Effect::Connect(p.word("connect"))),
        // ── Slack ──
        // Verification reads Slack; it does not change the overview or any app settings.
        // @params connect?:string install?:string appToken?:string botToken?:string
        "slack.verify" => op("POST", Ok("/slack/verify".into()), Some(p.pick(&["connect", "install", "appToken", "botToken"])), Effect::None),
        // @params team?:string settings?:json icon?:string
        "slack.makeApp" => op("POST", Ok("/slack/apps".into()), Some(p.pick(&["team", "settings", "icon"])), Effect::Slack),
        // @params appId:string
        "slack.dropApp" => op("DELETE", p.at("appId").map(|a| format!("/slack/apps/{a}")), None, Effect::Slack),
        // @params code?:string state?:string
        "slack.installed" => op("POST", Ok("/slack/installs".into()), Some(p.pick(&["code", "state"])), Effect::Slack),
        // @params refreshToken?:string
        "slack.addConfigToken" => op("POST", Ok("/slack/config-tokens".into()), Some(p.pick(&["refreshToken"])), Effect::Slack),
        // @params team:string
        "slack.removeConfigToken" => op("DELETE", p.at("team").map(|t| format!("/slack/config-tokens/{t}")), None, Effect::Slack),
        // @params
        "slack.people" => op("GET", Ok("/slack/people".into()), None, Effect::None),
        // @params name:string
        "slack.createAppUrl" => op("GET", p.at("name").map(|n| format!("/slack/create-app-url?name={n}")), None, Effect::None),
        // "这是我" (bound) or "不是我" on a Slack user.
        // @params bound?:boolean user:string
        "slack.identity" => op(if p.bool("bound") { "PUT" } else { "DELETE" }, p.at("user").map(|u| format!("/me/slack/{u}")), None, Effect::Identity),
        // ── profiles and sign-ins ──
        // @params runtime?:string access?:json
        "profile.add" => op("POST", Ok("/profiles".into()), Some(p.pick(&["runtime", "access"])), Effect::Overview),
        // @params runtime?:string
        "profile.useMachineLogin" => op("POST", Ok("/profiles/machine".into()), Some(p.pick(&["runtime"])), Effect::Overview),
        // @params id:string input?:json
        "profile.put" => op("PUT", p.at("id").map(|id| format!("/profiles/{id}")), Some(p.value("input").unwrap_or(json!({}))), Effect::Overview),
        // @params id:string
        "profile.delete" => op("DELETE", p.at("id").map(|id| format!("/profiles/{id}")), None, Effect::Overview),
        // @params id:string
        "profile.resetQuota" => op("POST", p.at("id").map(|id| format!("/profiles/{id}/reset-quota")), None, Effect::Overview),
        // @params id:string
        "profile.quota" => op("POST", p.at("id").map(|id| format!("/profiles/{id}/quota")), None, Effect::Overview),
        // @params id:string
        "profile.check" => op("POST", p.at("id").map(|id| format!("/profiles/{id}/check")), None, Effect::Overview),
        // @params id:string
        "profile.login" => op("POST", p.at("id").map(|id| format!("/profiles/{id}/login")), None, Effect::Overview),
        // @params id:string
        "profile.cancelLogin" => op("DELETE", p.at("id").map(|id| format!("/profiles/{id}/login")), None, Effect::Overview),
        // @params id:string code?:string
        "profile.loginCode" => op("POST", p.at("id").map(|id| format!("/profiles/{id}/login-code")), Some(p.pick(&["code"])), Effect::Overview),
        // A subscription signed in before its profile exists: the station makes the profile when it succeeds.
        // @params runtime?:string
        "login.new" => op("POST", Ok("/logins".into()), Some(p.pick(&["runtime"])), Effect::None),
        // @params id:string code?:string
        "login.code" => op("POST", p.at("id").map(|id| format!("/logins/{id}/code")), Some(p.pick(&["code"])), Effect::None),
        // @params id:string
        "login.drop" => op("DELETE", p.at("id").map(|id| format!("/logins/{id}")), None, Effect::None),
        // ── background jobs and web services ──
        // @params id:string
        "job.get" => op("GET", p.at("id").map(|id| format!("/jobs/{id}")), None, Effect::None),
        // @params id:string lines:number
        "job.log" => op("GET", (|| Ok(format!("/jobs/{}/log?lines={}", p.at("id")?, p.u64("lines")?)))(), None, Effect::None),
        // @params id:string
        "job.stop" => op("POST", p.at("id").map(|id| format!("/jobs/{id}/stop")), None, Effect::Job),
        // A chat's jobs that are over, taken off its record (its session is read again).
        // @params session:string
        "job.clearEnded" => op("DELETE", p.at("session").map(|key| format!("/sessions/{key}/jobs")), None, Effect::Session(p.word("session"))),
        // ── the station itself ──
        // @params
        "memory.get" => op("GET", Ok("/memory".into()), None, Effect::None),
        // How much it takes (the `footprint` topic): measured again; what can be made again in chats' workspaces removed,
        // archived chats deleted, idle agents' processes ended; each for `keys` (the footprint page's choices say which).
        // @params
        "footprint.scan" => op("POST", Ok("/footprint/scan".into()), None, Effect::Footprint),
        // @params keys?:strings
        "footprint.rebuild" => op("POST", Ok("/footprint/rebuild".into()), Some(p.pick(&["keys"])), Effect::Footprint),
        // @params keys?:strings
        "footprint.delete" => op("POST", Ok("/footprint/delete".into()), Some(p.pick(&["keys"])), Effect::Footprint),
        // @params keys?:strings
        "footprint.evict" => op("POST", Ok("/footprint/evict".into()), Some(p.pick(&["keys"])), Effect::Footprint),
        // @params id?:string
        "software.update" => op("POST", Ok("/updates".into()), Some(p.pick(&["id"])), Effect::Overview),
        // @params
        "software.updateAll" => op("POST", Ok("/updates/all".into()), None, Effect::Overview),
        // @params
        "software.check" => op("POST", Ok("/updates/check".into()), None, Effect::Overview),
        // The station's update channel: { channel: "stable" | "beta" }. Back to stable from a beta, the stable release
        // is then offered to go back to (`downgrade`), older or not.
        // @params channel?:string
        "software.channel" => op("POST", Ok("/updates/channel".into()), Some(p.pick(&["channel"])), Effect::Overview),
        // The station updating itself when a newer release of its channel is out: { on }.
        // @params on?:boolean
        "software.auto" => op("POST", Ok("/updates/auto".into()), Some(json!({ "on": p.bool("on") })), Effect::Overview),
        _ => return None,
    };
    Some(r)
}

fn cloud_op(name: &str, params: &Value) -> Option<Result<Request>> {
    let p = P(params);
    let ws = || p.at("workspace").map(|w| format!("/v1/workspaces/{w}"));
    let op = |method: &'static str, path: Result<String>, body: Option<Value>| -> Result<Request> {
        Ok(Request { target: Target::Cloud(p.str("account")?), method, path: path?, body, fallback: None, effect: Effect::None })
    };
    let r = match name {
        // `invite_code`: for an account not let in yet (still.fail is invite-only).
        // @params name?:string invite_code?:string
        "workspace.create" => op("POST", Ok("/v1/workspaces".into()), Some(p.pick(&["name", "invite_code"]))),
        // @params workspace:string name?:string
        "workspace.rename" => op("PATCH", ws(), Some(p.pick(&["name"]))),
        // @params workspace:string
        "workspace.delete" => op("DELETE", ws(), None),
        // @params workspace:string role?:string email?:string
        "workspace.invite" => op("POST", ws().map(|w| format!("{w}/invitations")), Some(p.pick(&["role", "email"]))),
        // Adds people by email: members at once, or from their first sign-in.
        // @params workspace:string role?:string emails?:strings
        "workspace.addMembers" => op("POST", ws().map(|w| format!("{w}/members")), Some(p.pick(&["role", "emails"]))),
        // @params workspace:string email:string
        "workspace.removeAdded" => op("DELETE", (|| Ok(format!("{}/added/{}", ws()?, p.at("email")?)))(), None),
        // @params workspace:string invitation:string
        "workspace.revokeInvitation" => op("DELETE", (|| Ok(format!("{}/invitations/{}", ws()?, p.at("invitation")?)))(), None),
        // @params workspace:string member:string role?:string
        "workspace.setRole" => op("PATCH", (|| Ok(format!("{}/members/{}", ws()?, p.at("member")?)))(), Some(p.pick(&["role"]))),
        // @params workspace:string member:string
        "workspace.removeMember" => op("DELETE", (|| Ok(format!("{}/members/{}", ws()?, p.at("member")?)))(), None),
        // @params workspace:string name?:string
        "workspace.enroll" => op("POST", ws().map(|w| format!("{w}/enrollments")), Some(p.pick(&["name"]))),
        // @params workspace:string station:string name?:string
        "workspace.renameStation" => op("PATCH", (|| Ok(format!("{}/stations/{}", ws()?, p.at("station")?)))(), Some(p.pick(&["name"]))),
        // @params workspace:string station:string
        "workspace.removeStation" => op("DELETE", (|| Ok(format!("{}/stations/{}", ws()?, p.at("station")?)))(), None),
        // @params token?:string
        "invitation.preview" => op("POST", Ok("/v1/invitations/preview".into()), Some(p.pick(&["token"]))),
        // @params id?:string token?:string
        "invitation.accept" => match p.0.get("id") {
            Some(_) => op("POST", p.at("id").map(|id| format!("/v1/invitations/{id}/accept")), None),
            None => op("POST", Ok("/v1/invitations/accept".into()), Some(p.pick(&["token"]))),
        },
        // @params id:string
        "invitation.decline" => op("POST", p.at("id").map(|id| format!("/v1/invitations/{id}/decline")), None),
        // @params id:string
        "loginSession.revoke" => op("DELETE", p.at("id").map(|id| format!("/v1/auth/sessions/{id}")), None),
        // @params
        "admin.me" => op("GET", Ok("/v1/admin/me".into()), None),
        // @params note?:string days?:number
        "admin.createCode" => op("POST", Ok("/v1/admin/invite-codes".into()), Some(p.pick(&["note", "days"]))),
        // @params code:string
        "admin.revokeCode" => op("POST", p.at("code").map(|c| format!("/v1/admin/invite-codes/{c}/revoke")), None),
        // An account into the test channel (app.youdid.wtf) or out of it: { user, on }.
        // @params user:string on?:boolean
        "admin.setBeta" => op("POST", p.at("user").map(|u| format!("/v1/admin/users/{u}/beta")), Some(json!({ "on": p.bool("on") }))),
        // Gives an account the right to create workspaces, as an invite code would, or takes it back: { user, on }.
        // @params user:string on?:boolean
        "admin.setMayCreate" => op("POST", p.at("user").map(|u| format!("/v1/admin/users/{u}/may-create")), Some(json!({ "on": p.bool("on") }))),
        // Blocks an account (signed out everywhere, kept out) or lets it back: { user, on }.
        // @params user:string on?:boolean
        "admin.block" => op("POST", p.at("user").map(|u| format!("/v1/admin/users/{u}/block")), Some(json!({ "on": p.bool("on") }))),
        // @params workspace:string
        "admin.deleteWorkspace" => op("POST", p.at("workspace").map(|w| format!("/v1/admin/workspaces/{w}/delete")), None),
        // Where a bug report stands: { id, status } (new, triaged, fixed, wontfix).
        // @params id:string status?:string
        "admin.feedbackStatus" => op("POST", p.at("id").map(|id| format!("/v1/admin/feedback/{id}/status")), Some(p.pick(&["status"]))),
        _ => return None,
    };
    Some(r)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn req(name: &str, params: Value) -> Request {
        request(name, &params).expect("an operation").expect("its params")
    }

    #[test]
    fn operations_make_their_requests() {
        let r = req("job.stop", json!({ "station": "w/s", "id": "job 1" }));
        assert_eq!((r.target, r.method, r.path.as_str(), r.body), (Target::Station("w/s".into()), "POST", "/jobs/job%201/stop", None));
        let r = req("job.clearEnded", json!({ "station": "ws/st", "session": "ember:c-1" }));
        assert_eq!((r.method, r.path.as_str()), ("DELETE", "/sessions/ember%3Ac-1/jobs"));
        let r = req("session.settings", json!({ "station": "ws/st", "key": "k", "model": "m", "profile": null }));
        assert_eq!(r.body, Some(json!({ "model": "m", "profile": null })));
        let r = req("workspace.setRole", json!({ "account": "a", "workspace": "w1", "member": "x@y.z", "role": "admin" }));
        assert_eq!((r.target, r.method, r.path.as_str()), (Target::Cloud("a".into()), "PATCH", "/v1/workspaces/w1/members/x%40y.z"));
        assert_eq!(req("invitation.accept", json!({ "account": "a", "token": "t" })).path, "/v1/invitations/accept");
        let r = req("software.channel", json!({ "station": "w/s", "channel": "beta" }));
        assert_eq!((r.target, r.method, r.path.as_str(), r.body), (Target::Station("w/s".into()), "POST", "/updates/channel", Some(json!({ "channel": "beta" }))));
        let r = req("software.auto", json!({ "station": "w/s", "on": true }));
        assert_eq!((r.method, r.path.as_str(), r.body), ("POST", "/updates/auto", Some(json!({ "on": true }))));
        let r = req("admin.setBeta", json!({ "account": "a", "user": "sub-1", "on": true }));
        assert_eq!((r.method, r.path.as_str(), r.body), ("POST", "/v1/admin/users/sub-1/beta", Some(json!({ "on": true }))));
        let r = req("admin.feedbackStatus", json!({ "account": "a", "id": "01J0000000000000000000000A", "status": "fixed" }));
        assert_eq!((r.target, r.method, r.path.as_str(), r.body), (Target::Cloud("a".into()), "POST", "/v1/admin/feedback/01J0000000000000000000000A/status", Some(json!({ "status": "fixed" }))));
    }

    #[test]
    fn pinning_a_chat_goes_by_its_session() {
        let r = req("chat.pin", json!({ "station": "ws/st", "session": "ember:c-1", "pinned": true }));
        assert_eq!((r.method, r.path.as_str()), ("PUT", "/sessions/ember%3Ac-1/pin"));
        assert_eq!(req("chat.pin", json!({ "station": "ws/st", "session": "k", "pinned": false })).method, "DELETE");
    }

    #[test]
    fn a_decision_is_dismissed_on_its_chats_thread() {
        let r = req("decision.dismiss", json!({ "station": "ws/st", "thread": 7, "seq": 4 }));
        assert_eq!((r.target, r.method, r.path.as_str(), r.body), (Target::Station("ws/st".into()), "PUT", "/threads/7/dismissed", Some(json!({ "n": 4 }))));
        assert!(request("decision.dismiss", &json!({ "station": "ws/st", "thread": 7 })).unwrap().is_err());
    }

    #[test]
    fn archiving_a_chat_falls_back_to_its_session() {
        let r = req("chat.archive", json!({ "station": "ws/st", "thread": 7, "session": "k", "archived": true }));
        assert_eq!((r.method, r.path.as_str()), ("POST", "/threads/7/archive"));
        let fallback = r.fallback.unwrap();
        assert_eq!((fallback.method, fallback.path.as_str(), fallback.effect), ("POST", "/sessions/k/archive", Effect::Session(Some("k".into()))));
        let r = req("chat.archive", json!({ "station": "ws/st", "session": "k", "archived": false }));
        assert_eq!((r.method, r.path.as_str(), r.fallback), ("DELETE", "/sessions/k/archive", None));
    }

    #[test]
    fn renaming_a_chat_names_its_thread_or_its_session() {
        let r = req("chat.rename", json!({ "station": "ws/st", "thread": 7, "session": "k", "title": "值班" }));
        assert_eq!((r.method, r.path.as_str(), r.body), ("PUT", "/threads/7/title", Some(json!({ "title": "值班" }))));
        let r = req("chat.rename", json!({ "station": "ws/st", "session": "k", "title": "" }));
        assert_eq!((r.method, r.path.as_str(), r.body), ("POST", "/sessions/k/title", Some(json!({ "title": "" }))));
    }

    #[test]
    fn unknown_names_and_missing_params() {
        assert!(request("nothing.here", &json!({})).is_none());
        assert!(request("station.request", &json!({})).is_none());
        assert!(request("job.stop", &json!({ "station": "ws/st" })).unwrap().is_err());
    }
}
