//! The admin's console (web/src/admin): still.fail cloud's operator lists (`Topic::Admin`) as its pages show them, so
//! the page only draws. `adminList`: one list found, filtered and sorted, with how many each filter holds;
//! `adminItem`: one user's, workspace's or bug report's page; `adminOverview`: the counts and what wants a look. Times stay in
//! seconds, as still.fail cloud gives them: what goes out has them in words beside (present.rs `times`).

use std::cmp::Ordering;
use std::collections::HashMap;

use serde_json::{Value, json};
use stillfail_i18n::t;

use super::Views;
use crate::error::{CoreError, Result};
use crate::protocol::Topic;

const DAY: f64 = 86_400.0;
/// Rows a list gives at first, and more as the page asks for them (`limit`).
const LIMIT: u32 = 50;

/// The operator lists a view of `list` is built from.
pub(super) fn sources(view: &Topic) -> Vec<Topic> {
    let of = |account: &str, list: &str| Topic::Admin { account: account.to_string(), list: list.to_string() };
    match view {
        Topic::AdminList { account, list, .. } => vec![of(account, list)],
        // A user's page counts their workspaces' people and stations; a workspace's, its people's last visits.
        Topic::AdminItem { account, list, .. } => match list.as_str() {
            "users" => vec![of(account, "users"), of(account, "workspaces"), of(account, "invite-codes")],
            "feedback" => vec![of(account, "feedback")],
            _ => vec![of(account, "workspaces"), of(account, "users")],
        },
        // The bug reports only add what wants a look: a cloud from before has none (404), and the rest stands.
        Topic::AdminOverview { account } => vec![of(account, "users"), of(account, "workspaces"), of(account, "invite-codes"), of(account, "feedback")],
        _ => Vec::new(),
    }
}

fn str_of<'a>(v: &'a Value, key: &str) -> &'a str {
    v.get(key).and_then(Value::as_str).unwrap_or("")
}

fn num(v: &Value, key: &str) -> Option<f64> {
    v.get(key).and_then(Value::as_f64).filter(|n| *n > 0.0)
}

fn items<'a>(v: &'a Value, key: &str) -> &'a [Value] {
    v.get(key).and_then(Value::as_array).map(Vec::as_slice).unwrap_or(&[])
}

fn role_label(role: &str) -> String {
    match role {
        "owner" => t!("core-views.admin.role.owner"),
        "admin" => t!("core-views.admin.role.admin"),
        _ => t!("core-views.admin.role.member"),
    }
}

fn admission_label(admission: &str) -> String {
    match admission {
        "admin" => t!("core-views.admin.admission.admin"),
        "code" => t!("core-views.admin.admission.code"),
        "granted" => t!("core-views.admin.admission.granted"),
        "invitation" => t!("core-views.admin.admission.invitation"),
        "early" => t!("core-views.admin.admission.early"),
        _ => t!("core-views.admin.not_in"),
    }
}

fn mark(label: &str, tone: &str) -> Value {
    json!({ "label": label, "tone": tone })
}

/// A version's numbers, to compare (`0.1.1212` → [0, 1, 1212]).
fn version_key(v: &str) -> Vec<u64> {
    v.split(['.', '-', '+']).map_while(|p| p.parse().ok()).collect()
}

/// The newest station version any workspace runs: the one the others are behind.
fn newest_version(workspaces: &[Value]) -> Option<String> {
    workspaces.iter().flat_map(|w| items(w, "stations")).filter_map(|s| s.get("version").and_then(Value::as_str))
        .max_by(|a, b| version_key(a).cmp(&version_key(b))).map(str::to_string)
}

/// How a station last stood with still.fail cloud (it does not know whether one is up: the devices find that out
/// over the mesh): `online` came today, `offline` this week, `busy` (amber) not for a week, `error` never.
fn station_state(last_seen: Option<f64>, now: f64) -> &'static str {
    match last_seen {
        None => "error",
        Some(at) if now - at < DAY => "online",
        Some(at) if now - at < 7.0 * DAY => "offline",
        Some(_) => "busy",
    }
}

fn latest_station(w: &Value) -> Option<f64> {
    items(w, "stations").iter().filter_map(|s| num(s, "last_seen")).reduce(f64::max)
}

/// Whether every word of `query` is somewhere in `text` (both in lower case).
fn found(text: &str, words: &[String]) -> bool {
    words.iter().all(|w| text.contains(w.as_str()))
}

fn code_state(c: &Value, now: f64) -> (&'static str, &'static str) {
    if num(c, "used_at").is_some() || c.get("used_by").is_some_and(Value::is_object) {
        ("used", "neutral")
    } else if num(c, "revoked_at").is_some() {
        ("revoked", "red")
    } else if num(c, "expires_at").is_some_and(|at| at <= now) {
        ("expired", "amber")
    } else {
        ("open", "green")
    }
}

/// An invite code's state (`code_state`) in words.
fn code_label(state: &str) -> String {
    match state {
        "used" => t!("core-views.admin.code.used"),
        "revoked" => t!("core-views.admin.code.revoked"),
        "expired" => t!("core-views.admin.code.expired"),
        _ => t!("core-views.admin.code.open"),
    }
}

/// Where a bug report stands: its label and tone.
fn feedback_status(status: &str) -> (String, &'static str) {
    match status {
        "triaged" => (t!("core-views.admin.feedback.triaged"), "blue"),
        "fixed" => (t!("core-views.admin.feedback.fixed"), "green"),
        "wontfix" => (t!("core-views.admin.feedback.wontfix"), "neutral"),
        _ => (t!("core-views.admin.feedback.new"), "amber"),
    }
}

/// The statuses a bug report can be set to, in order.
const FEEDBACK_STATUSES: [&str; 4] = ["new", "triaged", "fixed", "wontfix"];

fn channel_label(channel: &str) -> String {
    if channel == "beta" { t!("core-views.admin.channel.beta") } else { t!("core-views.admin.channel.stable") }
}

fn area_label(area: &str) -> String {
    match area {
        "station" => "Station".into(),
        "web" => "Web".into(),
        "android" => "Android".into(),
        "desktop" => t!("core-views.admin.area.desktop"),
        "slack" => "Slack".into(),
        "cloud" => "still.fail cloud".into(),
        _ => t!("core-views.admin.area.unsure"),
    }
}

/// The name of what a report has under `key` (`station`, `workspace`), when it has one.
fn named<'a>(v: &'a Value, key: &str) -> Option<&'a Value> {
    v.get(key).filter(|x| x.is_object())
}

fn account_title(a: &Value) -> &str {
    match str_of(a, "name") {
        "" => str_of(a, "email"),
        n => n,
    }
}

/// One kind of list: its filters (id, label, whether a row is in it), its sorts, and how a row is found and shown.
struct Kind {
    filters: Vec<(&'static str, String, Box<dyn Fn(&Value) -> bool>)>,
    sorts: Vec<(&'static str, String)>,
}

fn user_kind(now: f64) -> Kind {
    let seen = |u: &Value| num(u, "last_seen");
    Kind {
        filters: vec![
            ("all", t!("core-views.admin.filter.all"), Box::new(|_| true)),
            ("active", t!("core-views.admin.filter.active"), Box::new(move |u| seen(u).is_some_and(|at| now - at < 7.0 * DAY))),
            ("new", t!("core-views.admin.filter.new_users"), Box::new(move |u| num(u, "created_at").is_some_and(|at| now - at < 7.0 * DAY))),
            ("stuck", t!("core-views.admin.not_in"), Box::new(|u| u.get("admission").is_none_or(Value::is_null))),
            ("dormant", t!("core-views.admin.filter.dormant"), Box::new(move |u| seen(u).is_none_or(|at| now - at > 30.0 * DAY))),
            ("creators", t!("core-views.admin.filter.creators"), Box::new(|u| u.get("may_create").and_then(Value::as_bool) == Some(true))),
            ("beta", channel_label("beta"), Box::new(|u| u.get("beta").and_then(Value::as_bool) == Some(true))),
            ("blocked", t!("core-views.admin.blocked"), Box::new(|u| u.get("blocked").and_then(Value::as_bool) == Some(true))),
        ],
        sorts: vec![("seen", t!("core-views.admin.sort.seen")), ("created", t!("core-views.admin.sort.first_sign_in")), ("workspaces", t!("core-views.admin.sort.workspaces")), ("name", t!("core-views.admin.sort.name"))],
    }
}

fn workspace_kind(now: f64, newest: Option<String>) -> Kind {
    Kind {
        filters: vec![
            ("all", t!("core-views.admin.filter.all"), Box::new(|_| true)),
            ("bare", t!("core-views.admin.no_station"), Box::new(|w| items(w, "stations").is_empty())),
            ("stale", t!("core-views.admin.filter.stale"), Box::new(move |w| !items(w, "stations").is_empty() && latest_station(w).is_none_or(|at| now - at > 7.0 * DAY))),
            ("outdated", t!("core-views.admin.filter.outdated"), Box::new(move |w| {
                let Some(newest) = &newest else { return false };
                items(w, "stations").iter().any(|s| s.get("version").and_then(Value::as_str).is_some_and(|v| version_key(v) < version_key(newest)))
            })),
            ("invited", t!("core-views.admin.filter.invited"), Box::new(|w| !items(w, "invitations").is_empty())),
            ("full", t!("core-views.admin.filter.full"), Box::new(|w| w.get("seats").and_then(Value::as_u64).is_some_and(|n| items(w, "members").len() as u64 >= n))),
        ],
        sorts: vec![("active", t!("core-views.admin.sort.station_seen")), ("created", t!("core-views.admin.sort.created")), ("members", t!("core-views.admin.sort.members")), ("name", t!("core-views.admin.sort.name"))],
    }
}

fn code_kind(now: f64) -> Kind {
    let is = move |state: &'static str| -> Box<dyn Fn(&Value) -> bool> { Box::new(move |c| code_state(c, now).0 == state) };
    Kind {
        filters: vec![("all", t!("core-views.admin.filter.all"), Box::new(|_| true)), ("open", code_label("open"), is("open")), ("used", code_label("used"), is("used")), ("expired", code_label("expired"), is("expired")), ("revoked", code_label("revoked"), is("revoked"))],
        sorts: vec![("created", t!("core-views.admin.sort.generated"))],
    }
}

fn feedback_kind() -> Kind {
    let is = |status: &'static str| -> Box<dyn Fn(&Value) -> bool> { Box::new(move |f| str_of(f, "status") == status || (status == "new" && f.get("status").is_none_or(Value::is_null))) };
    Kind {
        filters: vec![
            ("all", t!("core-views.admin.filter.all"), Box::new(|_| true)),
            ("new", feedback_status("new").0, is("new")),
            ("triaged", feedback_status("triaged").0, is("triaged")),
            ("fixed", feedback_status("fixed").0, is("fixed")),
            ("wontfix", feedback_status("wontfix").0, is("wontfix")),
            ("beta", channel_label("beta"), Box::new(|f| str_of(f, "channel") == "beta")),
            ("stable", channel_label("stable"), Box::new(|f| str_of(f, "channel") != "beta")),
        ],
        sorts: vec![("created", t!("core-views.admin.sort.submitted"))],
    }
}

/// What a row is found by, in lower case.
fn haystack(list: &str, v: &Value) -> String {
    let mut text = match list {
        "users" => format!("{} {} {}", str_of(v, "name"), str_of(v, "email"), str_of(v, "sub")),
        "workspaces" => {
            let creator = v.get("created_by").map(|c| format!("{} {}", str_of(c, "name"), str_of(c, "email"))).unwrap_or_default();
            format!("{} {} {creator}", str_of(v, "name"), str_of(v, "id"))
        }
        "feedback" => {
            let name = |key: &str| named(v, key).map(|x| format!("{} {}", str_of(x, "name"), str_of(x, "id"))).unwrap_or_default();
            let account = named(v, "account").map(|a| format!("{} {}", str_of(a, "name"), str_of(a, "email"))).unwrap_or_default();
            let number = v.get("number").and_then(Value::as_u64).map(|n| format!("fb-{n}")).unwrap_or_default();
            format!("{number} {} {} {} {} {} {account}", str_of(v, "title"), str_of(v, "body"), str_of(v, "reporter"), name("station"), name("workspace"))
        }
        _ => {
            let user = v.get("used_by").map(|c| format!("{} {}", str_of(c, "name"), str_of(c, "email"))).unwrap_or_default();
            let workspace = v.get("workspace").map(|w| str_of(w, "name").to_string()).unwrap_or_default();
            format!("{} {} {user} {workspace}", str_of(v, "code"), str_of(v, "note"))
        }
    };
    for (key, fields) in [("workspaces", &["name"][..]), ("members", &["name", "email"][..]), ("stations", &["name", "id"][..])] {
        for item in items(v, key) {
            for field in fields {
                text.push(' ');
                text.push_str(str_of(item, field));
            }
        }
    }
    text.to_lowercase()
}

fn order(list: &str, sort: &str, a: &Value, b: &Value) -> Ordering {
    let desc = |x: Option<f64>, y: Option<f64>| y.unwrap_or(0.0).total_cmp(&x.unwrap_or(0.0));
    let name = |v: &Value| {
        let n = str_of(v, "name");
        (if n.is_empty() { str_of(v, "email") } else { n }).to_lowercase()
    };
    match (list, sort) {
        (_, "created") => desc(num(a, "created_at"), num(b, "created_at")),
        ("users", "workspaces") => items(b, "workspaces").len().cmp(&items(a, "workspaces").len()),
        ("workspaces", "members") => items(b, "members").len().cmp(&items(a, "members").len()),
        ("workspaces", "active") => desc(latest_station(a), latest_station(b)),
        (_, "name") => name(a).cmp(&name(b)),
        _ => desc(num(a, "last_seen"), num(b, "last_seen")),
    }
    .then_with(|| desc(num(a, "created_at"), num(b, "created_at")))
}

/// A row as the list draws it: a title, a line under it, marks for what is off, and a time at its end.
fn row(list: &str, v: &Value, now: f64) -> Value {
    match list {
        "users" => {
            let mut marks = Vec::new();
            if v.get("blocked").and_then(Value::as_bool) == Some(true) {
                marks.push(mark(&t!("core-views.admin.blocked"), "red"));
            }
            match v.get("admission").and_then(Value::as_str) {
                None => marks.push(mark(&t!("core-views.admin.not_in"), "amber")),
                Some("admin") => marks.push(mark(&role_label("admin"), "accent")),
                _ => {}
            }
            if v.get("beta").and_then(Value::as_bool) == Some(true) {
                marks.push(mark(&channel_label("beta"), "accent"));
            }
            let workspaces: Vec<&str> = items(v, "workspaces").iter().map(|w| str_of(w, "name")).collect();
            let mut line = str_of(v, "email").to_string();
            if !workspaces.is_empty() {
                line = format!("{line} · {}", workspaces.join(&t!("core-views.list_separator")));
            }
            let name = str_of(v, "name");
            json!({
                "id": str_of(v, "sub"),
                "title": if name.is_empty() { str_of(v, "email") } else { name },
                "line": line,
                "person": { "name": name, "email": str_of(v, "email"), "picture": str_of(v, "picture") },
                "marks": marks,
                "last_seen": v.get("last_seen").cloned().unwrap_or(Value::Null),
                "created_at": v.get("created_at").cloned().unwrap_or(Value::Null),
            })
        }
        "workspaces" => {
            let stations = items(v, "stations");
            let creator = v.get("created_by").filter(|c| c.is_object()).map(|c| {
                let n = str_of(c, "name");
                (if n.is_empty() { str_of(c, "email") } else { n }).to_string()
            }).unwrap_or_else(|| t!("core-views.admin.someone_gone"));
            let mut marks = Vec::new();
            if stations.is_empty() {
                marks.push(mark(&t!("core-views.admin.no_station"), "amber"));
            }
            let latest = latest_station(v);
            json!({
                "id": str_of(v, "id"),
                "title": str_of(v, "name"),
                "line": ([t!("core-views.admin.created_by", name = creator), t!("core-views.admin.people", n = items(v, "members").len()), t!("core-views.admin.stations", n = stations.len())].join(" · ")),
                "marks": marks,
                // When a station of it last came to still.fail cloud, and how that stands.
                "last_seen": latest,
                "state": (!stations.is_empty()).then(|| station_state(latest, now)),
                "created_at": v.get("created_at").cloned().unwrap_or(Value::Null),
            })
        }
        "feedback" => {
            let (label, tone) = feedback_status(str_of(v, "status"));
            let mut marks = vec![mark(&label, tone)];
            if str_of(v, "channel") == "beta" {
                marks.push(mark(&channel_label("beta"), "accent"));
            }
            let mut line = vec![area_label(str_of(v, "area"))];
            line.extend(named(v, "workspace").map(|w| str_of(w, "name").to_string()).filter(|n| !n.is_empty()));
            line.extend(named(v, "station").map(|s| str_of(s, "name").to_string()).filter(|n| !n.is_empty()));
            match str_of(v, "reporter") {
                "" => line.extend(named(v, "account").map(|a| account_title(a).to_string())),
                by => line.push(by.to_string()),
            }
            json!({
                "id": str_of(v, "id"),
                "number": feedback_ref(v),
                "title": str_of(v, "title"),
                "line": line.join(" · "),
                "state": str_of(v, "status"),
                "marks": marks,
                "created_at": v.get("created_at").cloned().unwrap_or(Value::Null),
            })
        }
        _ => {
            let (state, tone) = code_state(v, now);
            let user = v.get("used_by").filter(|u| u.is_object());
            let line = match (state, user) {
                ("used", Some(u)) => {
                    let n = str_of(u, "name");
                    let name = if n.is_empty() { str_of(u, "email") } else { n };
                    match v.get("workspace").filter(|w| w.is_object()) {
                        Some(w) => t!("core-views.admin.code.made", name = name, workspace = str_of(w, "name")),
                        None => t!("core-views.admin.code.made_deleted", name = name),
                    }
                }
                ("used", None) => t!("core-views.admin.code.used_by_gone"),
                _ => str_of(v, "note").to_string(),
            };
            json!({
                "id": str_of(v, "code"),
                "title": str_of(v, "code"),
                "note": str_of(v, "note"),
                "line": line,
                "state": state,
                "marks": [mark(&code_label(state), tone)],
                "url": v.get("url").cloned().unwrap_or(Value::Null),
                "user": user.map(|u| str_of(u, "sub")),
                "created_at": v.get("created_at").cloned().unwrap_or(Value::Null),
                "expires_at": v.get("expires_at").cloned().unwrap_or(Value::Null),
                "used_at": v.get("used_at").cloned().unwrap_or(Value::Null),
                "revoked_at": v.get("revoked_at").cloned().unwrap_or(Value::Null),
            })
        }
    }
}

/// The rows of an operator list, as still.fail cloud gives them.
fn rows_of(list: &str, value: &Value) -> Vec<Value> {
    let key = match list {
        "users" => "users",
        "workspaces" => "workspaces",
        "feedback" => "feedback",
        _ => "codes",
    };
    items(value, key).to_vec()
}

/// One list found by `query`, in `filter`, by `sort`: its first `limit` rows, and how many each filter holds (of what
/// `query` finds).
pub fn list(list: &str, value: &Value, query: &str, filter: Option<&str>, sort: Option<&str>, limit: Option<u32>, now: f64) -> Result<Value> {
    let all = rows_of(list, value);
    let kind = match list {
        "users" => user_kind(now),
        "workspaces" => workspace_kind(now, newest_version(&all)),
        "invite-codes" => code_kind(now),
        "feedback" => feedback_kind(),
        _ => return Err(CoreError::invalid(t!("core-views.admin.error.no_list"))),
    };
    let words: Vec<String> = query.to_lowercase().split_whitespace().map(str::to_string).collect();
    let matched: Vec<&Value> = all.iter().filter(|v| words.is_empty() || found(&haystack(list, v), &words)).collect();
    let filter = kind.filters.iter().find(|f| Some(f.0) == filter).unwrap_or(&kind.filters[0]);
    let sort = kind.sorts.iter().find(|s| Some(s.0) == sort).unwrap_or(&kind.sorts[0]).0;
    let mut shown: Vec<&Value> = matched.iter().copied().filter(|v| (filter.2)(v)).collect();
    shown.sort_by(|a, b| order(list, sort, a, b));
    let limit = limit.unwrap_or(LIMIT).max(1) as usize;
    Ok(json!({
        "total": all.len(),
        "found": shown.len(),
        "filter": filter.0,
        "filters": kind.filters.iter().map(|(id, label, keep)| json!({ "id": id, "label": label, "count": matched.iter().filter(|v| keep(v)).count() })).collect::<Vec<_>>(),
        "sort": sort,
        "sorts": kind.sorts.iter().map(|(id, label)| json!({ "id": id, "label": label })).collect::<Vec<_>>(),
        "rows": shown.iter().take(limit).map(|v| row(list, v, now)).collect::<Vec<_>>(),
        "more": shown.len() > limit,
    }))
}

/// A user's page: who they are, how they got in and what they may do, their workspaces, the code they used.
pub fn user(id: &str, users: &Value, workspaces: &Value, codes: Option<&Value>, now: f64) -> Result<Value> {
    let u = rows_of("users", users).into_iter().find(|u| str_of(u, "sub") == id).ok_or_else(|| CoreError::new("http_404", t!("core-views.admin.error.no_user")).with_status(404))?;
    let all = rows_of("workspaces", workspaces);
    let by_id: HashMap<&str, &Value> = all.iter().map(|w| (str_of(w, "id"), w)).collect();
    let theirs: Vec<Value> = items(&u, "workspaces").iter().map(|m| {
        let w = by_id.get(str_of(m, "id"));
        let stations = w.map(|w| items(w, "stations").len()).unwrap_or(0);
        let people = w.map(|w| items(w, "members").len()).unwrap_or(0);
        json!({
            "id": str_of(m, "id"),
            "name": str_of(m, "name"),
            "role": role_label(str_of(m, "role")),
            "line": ([role_label(str_of(m, "role")), t!("core-views.admin.people", n = people), t!("core-views.admin.stations", n = stations)].join(" · ")),
        })
    }).collect();
    let admission = u.get("admission").and_then(Value::as_str);
    let code = codes.map(|c| rows_of("invite-codes", c)).unwrap_or_default().into_iter()
        .find(|c| c.get("used_by").is_some_and(|by| str_of(by, "sub") == id)).map(|c| str_of(&c, "code").to_string());
    let may_create = u.get("may_create").and_then(Value::as_bool);
    let creator = u.get("creator").and_then(Value::as_bool) == Some(true);
    let name = str_of(&u, "name");
    Ok(json!({
        "id": id,
        "title": if name.is_empty() { str_of(&u, "email") } else { name },
        "person": { "name": name, "email": str_of(&u, "email"), "picture": str_of(&u, "picture") },
        "email": str_of(&u, "email"),
        "admin": admission == Some("admin"),
        "admission": admission_label(admission.unwrap_or("")),
        "code": code,
        "created_at": u.get("created_at").cloned().unwrap_or(Value::Null),
        "last_seen": u.get("last_seen").cloned().unwrap_or(Value::Null),
        // Whether they may create workspaces, and whether that can be taken back here (null: a cloud from before).
        "mayCreate": may_create,
        "mayCreateHint": if admission == Some("admin") {
            t!("core-views.admin.may_create.admin")
        } else if creator {
            t!("core-views.admin.may_create.creator")
        } else if may_create == Some(true) {
            t!("core-views.admin.may_create.yes")
        } else {
            t!("core-views.admin.may_create.no")
        },
        "mayCreateFixed": admission == Some("admin") || creator,
        "beta": u.get("beta").and_then(Value::as_bool),
        "blocked": u.get("blocked").and_then(Value::as_bool),
        "workspaces": theirs,
        "seen": num(&u, "last_seen").map(|at| now - at),
    }))
}

/// A workspace's page: who made it, its people with when they last came, its stations and how each last stood, its
/// open invitations.
pub fn workspace(id: &str, workspaces: &Value, users: Option<&Value>, now: f64) -> Result<Value> {
    let all = rows_of("workspaces", workspaces);
    let newest = newest_version(&all);
    let w = all.iter().find(|w| str_of(w, "id") == id).ok_or_else(|| CoreError::new("http_404", t!("core-views.admin.error.no_workspace")).with_status(404))?;
    // A cloud from before gives members no last visit: the users list has it.
    let seen: HashMap<String, Value> = users.map(|u| rows_of("users", u)).unwrap_or_default().into_iter()
        .map(|u| (str_of(&u, "sub").to_string(), u.get("last_seen").cloned().unwrap_or(Value::Null))).collect();
    let members: Vec<Value> = items(w, "members").iter().map(|m| {
        let sub = str_of(m, "sub");
        let name = str_of(m, "name");
        json!({
            "id": sub,
            "title": if name.is_empty() { str_of(m, "email") } else { name },
            "person": { "name": name, "email": str_of(m, "email"), "picture": str_of(m, "picture") },
            "role": role_label(str_of(m, "role")),
            "last_seen": m.get("last_seen").filter(|v| !v.is_null()).or_else(|| seen.get(sub)).cloned().unwrap_or(Value::Null),
        })
    }).collect();
    let stations: Vec<Value> = items(w, "stations").iter().map(|s| {
        let version = s.get("version").and_then(Value::as_str);
        let outdated = matches!((version, &newest), (Some(v), Some(n)) if version_key(v) < version_key(n));
        json!({
            "id": str_of(s, "id"),
            "name": str_of(s, "name"),
            "version": version,
            "outdated": outdated,
            "state": station_state(num(s, "last_seen"), now),
            "last_seen": s.get("last_seen").cloned().unwrap_or(Value::Null),
        })
    }).collect();
    let invitations: Vec<Value> = items(w, "invitations").iter().map(|i| json!({
        "id": str_of(i, "id"),
        "email": i.get("email").and_then(Value::as_str).map(str::to_string).unwrap_or_else(|| t!("core-views.admin.invitation.anyone")),
        "line": format!("{}{}", role_label(str_of(i, "role")), match str_of(i, "inviter") { "" => String::new(), by => format!(" · {}", t!("core-views.admin.invitation.by", name = by)) }),
        "expires_at": i.get("expires_at").cloned().unwrap_or(Value::Null),
    })).collect();
    let creator = w.get("created_by").filter(|c| c.is_object());
    Ok(json!({
        "id": id,
        "title": str_of(w, "name"),
        "creator": creator.map(|c| json!({ "id": str_of(c, "sub"), "title": match str_of(c, "name") { "" => str_of(c, "email"), n => n } })),
        "created_at": w.get("created_at").cloned().unwrap_or(Value::Null),
        "people": match w.get("seats").and_then(Value::as_u64) { Some(n) => format!("{} / {n}", members.len()), None => members.len().to_string() },
        "members": members,
        "stations": stations,
        "invitations": invitations,
    }))
}

/// How a bug report is named to people: `FB-<number>`.
fn feedback_ref(v: &Value) -> String {
    v.get("number").and_then(Value::as_u64).map(|n| format!("FB-{n}")).unwrap_or_default()
}

/// A value of a report's context as a line: text as it is, the rest as JSON.
fn context_text(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        other => other.to_string(),
    }
}

/// A bug report's page: all of it, where it came from, where it stands, and the whole of it as plain text (`text`) to
/// hand to an agent.
pub fn feedback(id: &str, value: &Value) -> Result<Value> {
    let f = rows_of("feedback", value).into_iter().find(|f| str_of(f, "id") == id).ok_or_else(|| CoreError::new("http_404", t!("core-views.admin.error.no_feedback")).with_status(404))?;
    let status = match str_of(&f, "status") {
        "" => "new",
        s => s,
    };
    let context: Vec<(String, String)> = match f.get("context") {
        Some(Value::Object(map)) => map.iter().filter(|(_, v)| !v.is_null()).map(|(k, v)| (k.clone(), context_text(v))).collect(),
        Some(Value::Null) | None => Vec::new(),
        Some(other) => vec![("context".into(), context_text(other))],
    };
    let logs = f.get("logs").and_then(Value::as_str).filter(|l| !l.trim().is_empty());
    let station = named(&f, "station");
    let workspace = named(&f, "workspace");
    let account = named(&f, "account");
    let place = |x: Option<&Value>| x.map(|x| match str_of(x, "name") { "" => str_of(x, "id").to_string(), n => format!("{n} ({})", str_of(x, "id")) });
    let number = feedback_ref(&f);
    // The whole report, as an agent is to read it.
    let mut text = format!("{number} {}\n\n", str_of(&f, "title"));
    let mut fact = |label: &str, value: Option<String>| {
        if let Some(value) = value.filter(|v| !v.is_empty()) {
            text.push_str(&format!("{label}: {value}\n"));
        }
    };
    // Fixed by a commit's `Fixes: FB-<n>` (docs/changelog.md): in which version, and whether its reporter was told.
    let fixed_in = f.get("fixed_in").and_then(Value::as_i64);
    let told = f.get("told_at").is_some_and(|t| !t.is_null());
    let state = match fixed_in {
        Some(n) if status == "fixed" => format!("{} · 0.1.{n}{}", feedback_status(status).0, if told { format!(" · {}", t!("core-views.admin.feedback.told")) } else { String::new() }),
        _ => feedback_status(status).0,
    };
    fact(&t!("core-views.admin.feedback.fact.status"), Some(state.clone()));
    fact(&t!("core-views.admin.feedback.fact.channel"), Some(format!("{} ({})", channel_label(str_of(&f, "channel")), str_of(&f, "channel"))));
    fact(&t!("core-views.admin.feedback.fact.area"), Some(area_label(str_of(&f, "area"))));
    fact("Workspace", place(workspace));
    fact("Station", place(station));
    fact(&t!("core-views.admin.feedback.fact.reporter"), Some(str_of(&f, "reporter").to_string()));
    fact(&t!("core-views.admin.feedback.fact.account"), account.map(|a| match (str_of(a, "name"), str_of(a, "email")) { ("", e) => e.to_string(), (n, e) => format!("{n} <{e}>") }));
    fact("ID", Some(id.to_string()));
    text.push_str(&format!("\n## {}\n\n{}\n", t!("core-views.admin.feedback.body"), str_of(&f, "body").trim_end()));
    if !context.is_empty() {
        text.push_str(&format!("\n## {}\n\n", t!("core-views.admin.feedback.context")));
        for (k, v) in &context {
            text.push_str(&format!("{k}: {v}\n"));
        }
    }
    if let Some(logs) = logs {
        text.push_str(&format!("\n## {}\n\n```\n{}\n```\n", t!("core-views.admin.feedback.logs"), logs.trim_end()));
    }
    Ok(json!({
        "id": id,
        "number": number,
        "title": str_of(&f, "title"),
        "body": str_of(&f, "body"),
        "status": status,
        "statuses": FEEDBACK_STATUSES.iter().map(|s| json!({ "id": s, "label": feedback_status(s).0 })).collect::<Vec<_>>(),
        "marks": [mark(&state, feedback_status(status).1)],
        "channel": str_of(&f, "channel"),
        "channelLabel": channel_label(str_of(&f, "channel")),
        "area": area_label(str_of(&f, "area")),
        "reporter": str_of(&f, "reporter"),
        "station": station.map(|s| json!({ "id": str_of(s, "id"), "name": str_of(s, "name") })),
        "workspace": workspace.map(|w| json!({ "id": str_of(w, "id"), "title": match str_of(w, "name") { "" => str_of(w, "id"), n => n } })),
        "account": account.map(|a| json!({ "id": str_of(a, "sub"), "title": account_title(a) })),
        "context": context.iter().map(|(k, v)| json!({ "key": k, "value": v })).collect::<Vec<_>>(),
        "logs": logs,
        "created_at": f.get("created_at").cloned().unwrap_or(Value::Null),
        "text": text,
    }))
}

/// The console's first page: counts, new people by week, and what wants a look, each with the list and filter that
/// show it.
/// `feedback`: the bug reports, when still.fail cloud has them (one from before has none).
pub fn overview(users: &Value, workspaces: &Value, codes: &Value, feedback: Option<&Value>, now: f64, offset_min: i32) -> Value {
    let users = rows_of("users", users);
    let workspaces = rows_of("workspaces", workspaces);
    let codes = rows_of("invite-codes", codes);
    let within = |v: &Value, key: &str, days: f64| num(v, key).is_some_and(|at| now - at < days * DAY);
    let count = |list: &[Value], keep: &dyn Fn(&Value) -> bool| list.iter().filter(|v| keep(v)).count();
    let active = count(&users, &|u| within(u, "last_seen", 7.0));
    let stations: Vec<&Value> = workspaces.iter().flat_map(|w| items(w, "stations")).collect();
    let newest = newest_version(&workspaces);
    let outdated = stations.iter().filter(|s| matches!((s.get("version").and_then(Value::as_str), &newest), (Some(v), Some(n)) if version_key(v) < version_key(n))).count();
    let stale = stations.iter().filter(|s| num(s, "last_seen").is_none_or(|at| now - at > 7.0 * DAY)).count();
    // Weeks end now: the last is the seven days up to now.
    let weeks: Vec<Value> = (0..12).rev().map(|ago| {
        let end = now - ago as f64 * 7.0 * DAY;
        let start = end - 7.0 * DAY;
        let n = users.iter().filter(|u| num(u, "created_at").is_some_and(|at| at > start && at <= end)).count();
        let label = if ago == 0 { t!("core-views.admin.overview.this_week") } else { crate::format::day_label(start * 1000.0, now * 1000.0, offset_min) };
        json!({ "count": n, "label": label })
    }).collect();
    let stuck = count(&users, &|u| u.get("admission").is_none_or(Value::is_null));
    let bare = count(&workspaces, &|w| items(w, "stations").is_empty());
    let expiring = count(&codes, &|c| code_state(c, now).0 == "open" && num(c, "expires_at").is_some_and(|at| at - now < 3.0 * DAY));
    let mut todo = Vec::new();
    let mut want = |n: usize, text: String, hint: &str, tone: &str, list: &str, filter: &str| {
        if n > 0 {
            todo.push(json!({ "text": text, "hint": hint, "tone": tone, "list": list, "filter": filter }));
        }
    };
    let reports = feedback.map(|f| rows_of("feedback", f)).unwrap_or_default();
    let fresh = count(&reports, &|f| matches!(f.get("status").and_then(Value::as_str), Some("new") | None));
    want(fresh, t!("core-views.admin.todo.fresh", n = fresh), &t!("core-views.admin.todo.fresh_hint"), "amber", "feedback", "new");
    want(stuck, t!("core-views.admin.todo.stuck", n = stuck), &t!("core-views.admin.todo.stuck_hint"), "amber", "users", "stuck");
    want(bare, t!("core-views.admin.todo.bare", n = bare), &t!("core-views.admin.todo.bare_hint"), "amber", "workspaces", "bare");
    want(stale, t!("core-views.admin.todo.stale", n = stale), &t!("core-views.admin.todo.stale_hint"), "neutral", "workspaces", "stale");
    want(outdated, t!("core-views.admin.todo.outdated", n = outdated), &newest.as_deref().map(|n| t!("core-views.admin.todo.outdated_hint", version = n)).unwrap_or_default(), "neutral", "workspaces", "outdated");
    want(expiring, t!("core-views.admin.todo.expiring", n = expiring), &t!("core-views.admin.todo.expiring_hint"), "neutral", "invite-codes", "open");
    let pct = if users.is_empty() { 0 } else { active * 100 / users.len() };
    let used_ws = count(&workspaces, &|w| latest_station(w).is_some_and(|at| now - at < 7.0 * DAY));
    let today = stations.iter().filter(|s| num(s, "last_seen").is_some_and(|at| now - at < DAY)).count();
    json!({
        "stats": [
            { "label": t!("core-views.admin.stat.users"), "value": users.len(), "note": t!("core-views.admin.stat.users_note", n = count(&users, &|u| within(u, "created_at", 7.0))), "list": "users", "filter": "all" },
            { "label": t!("core-views.admin.stat.active"), "value": active, "note": t!("core-views.admin.stat.active_note", percent = pct), "list": "users", "filter": "active" },
            { "label": "Workspace", "value": workspaces.len(), "note": t!("core-views.admin.stat.workspaces_note", n = used_ws), "list": "workspaces", "filter": "all" },
            { "label": "Station", "value": stations.len(), "note": t!("core-views.admin.stat.stations_note", n = today), "list": "workspaces", "filter": "all" },
        ],
        "weeks": weeks,
        "todo": todo,
    })
}

impl Views {
    /// The console's views, from the operator lists they rest on; an error of one (not the admin: 404) is theirs.
    pub(super) fn admin(&self, view: &Topic) -> Option<Result<Value>> {
        let clock = self.clock();
        let now = clock.now / 1000.0;
        let read = |account: &str, list: &str| self.store.value(&Topic::Admin { account: account.to_string(), list: list.to_string() });
        match view {
            Topic::AdminList { account, list: name, query, filter, sort, limit } => Some(read(account, name)?.and_then(|v| list(name, &v, query, filter.as_deref(), sort.as_deref(), *limit, now))),
            Topic::AdminItem { account, list, id } if list == "users" => {
                let users = read(account, "users")?;
                let workspaces = read(account, "workspaces")?;
                let codes = read(account, "invite-codes").and_then(Result::ok);
                Some(users.and_then(|u| workspaces.and_then(|w| user(id, &u, &w, codes.as_ref(), now))))
            }
            Topic::AdminItem { account, list, id } if list == "feedback" => Some(read(account, "feedback")?.and_then(|f| feedback(id, &f))),
            Topic::AdminItem { account, id, .. } => {
                let workspaces = read(account, "workspaces")?;
                let users = read(account, "users").and_then(Result::ok);
                Some(workspaces.and_then(|w| workspace(id, &w, users.as_ref(), now)))
            }
            Topic::AdminOverview { account } => {
                let (users, workspaces, codes) = (read(account, "users")?, read(account, "workspaces")?, read(account, "invite-codes")?);
                // Not there yet, or a cloud from before (404): the page stands without them.
                let feedback = read(account, "feedback").and_then(Result::ok);
                Some(users.and_then(|u| workspaces.and_then(|w| codes.map(|c| overview(&u, &w, &c, feedback.as_ref(), now, clock.offset_min)))))
            }
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const NOW: f64 = 1_790_000_000.0;

    fn users() -> Value {
        json!({ "users": [
            { "sub": "a", "email": "ann@x.io", "name": "Ann", "picture": "", "created_at": NOW - 2.0 * DAY, "last_seen": NOW - 3600.0, "admission": "code", "workspaces": [{ "id": "w1", "name": "产品", "role": "owner" }], "beta": false, "may_create": true, "creator": true },
            { "sub": "b", "email": "bob@y.io", "name": "", "picture": "", "created_at": NOW - 40.0 * DAY, "last_seen": NOW - 35.0 * DAY, "admission": null, "workspaces": [], "beta": true, "may_create": false, "blocked": true },
            { "sub": "c", "email": "cat@x.io", "name": "Cat", "picture": "", "created_at": NOW - 10.0 * DAY, "last_seen": null, "admission": "invitation", "workspaces": [{ "id": "w1", "name": "产品", "role": "member" }] },
        ] })
    }

    fn workspaces() -> Value {
        json!({ "workspaces": [
            { "id": "w1", "name": "产品", "created_at": NOW - 2.0 * DAY, "created_by": { "sub": "a", "email": "ann@x.io", "name": "Ann", "picture": "" }, "seats": 2,
              "members": [{ "sub": "a", "email": "ann@x.io", "name": "Ann", "picture": "", "role": "owner", "added_at": 1, "last_seen": NOW - 3600.0 }, { "sub": "c", "email": "cat@x.io", "name": "Cat", "picture": "", "role": "member", "added_at": 2 }],
              "stations": [{ "id": "s1", "name": "studio", "version": "0.1.1212", "last_seen": NOW - 60.0 }, { "id": "s2", "name": "nas", "version": "0.1.1104", "last_seen": null }], "invitations": [] },
            { "id": "w2", "name": "设计", "created_at": NOW - 5.0 * DAY, "created_by": null, "members": [], "stations": [], "invitations": [{ "id": "i", "role": "member", "email": null, "inviter": "Ann", "expires_at": NOW + DAY }] },
        ] })
    }

    fn reports() -> Value {
        json!({ "feedback": [
            { "id": "F2", "number": 2, "channel": "beta", "station": { "id": "s1", "name": "studio" }, "workspace": { "id": "w1", "name": "产品" }, "account": null,
              "title": "发送后消息消失", "body": "## 步骤\n1. 发一条", "area": "web", "reporter": "Ann (Slack)", "context": { "version": "0.1.1212", "session": "ember:c-1", "extra": { "a": 1 } },
              "logs": "line 1\nline 2", "status": "new", "created_at": NOW - 60.0, "updated_at": NOW - 60.0 },
            { "id": "F1", "number": 1, "channel": "stable", "station": null, "workspace": null, "account": { "sub": "a", "email": "ann@x.io", "name": "" },
              "title": "图标糊了", "body": "看着糊", "area": "android", "reporter": "", "context": null, "logs": null, "status": "fixed", "created_at": NOW - DAY, "updated_at": NOW },
        ] })
    }

    fn ids(v: &Value) -> Vec<&str> {
        v["rows"].as_array().unwrap().iter().map(|r| r["id"].as_str().unwrap()).collect()
    }

    fn count(v: &Value, filter: &str) -> u64 {
        v["filters"].as_array().unwrap().iter().find(|f| f["id"] == filter).unwrap()["count"].as_u64().unwrap()
    }

    #[test]
    fn users_are_found_filtered_and_sorted() {
        let all = list("users", &users(), "", None, None, None, NOW).unwrap();
        assert_eq!(ids(&all), ["a", "b", "c"], "last visit first, never last");
        assert_eq!((count(&all, "stuck"), count(&all, "blocked"), count(&all, "dormant"), count(&all, "new")), (1, 1, 2, 1));
        assert_eq!(all["rows"][1]["title"], "bob@y.io");
        let labels: Vec<&str> = all["rows"][1]["marks"].as_array().unwrap().iter().map(|m| m["label"].as_str().unwrap()).collect();
        assert_eq!(labels, ["已封禁", "还没进来", "测试版"]);
        assert_eq!(all["rows"][0]["line"], "ann@x.io · 产品");
        // Words are all to be found, in any case; the counts are of what they find.
        let found = list("users", &users(), "X.IO 产品", Some("all"), Some("name"), None, NOW).unwrap();
        assert_eq!((ids(&found), count(&found, "stuck")), (vec!["a", "c"], 0));
        let page = list("users", &users(), "", Some("dormant"), Some("created"), Some(1), NOW).unwrap();
        assert_eq!((ids(&page), page["more"].as_bool(), page["found"].as_u64()), (vec!["c"], Some(true), Some(2)));
    }

    #[test]
    fn workspaces_say_what_is_off() {
        let all = list("workspaces", &workspaces(), "", None, None, None, NOW).unwrap();
        assert_eq!(ids(&all), ["w1", "w2"]);
        assert_eq!((count(&all, "bare"), count(&all, "outdated"), count(&all, "full"), count(&all, "invited")), (1, 1, 1, 1));
        assert_eq!(all["rows"][0]["state"], "online");
        assert_eq!(all["rows"][1]["line"], "已不在的人 创建 · 0 人 · 0 台 station");
        assert_eq!(ids(&list("workspaces", &workspaces(), "nas", None, None, None, NOW).unwrap()), ["w1"], "found by a station's name");
    }

    #[test]
    fn a_users_page_counts_their_workspaces() {
        let page = user("a", &users(), &workspaces(), None, NOW).unwrap();
        assert_eq!(page["workspaces"][0]["line"], "Owner · 2 人 · 2 台 station");
        assert_eq!((page["mayCreate"].as_bool(), page["mayCreateFixed"].as_bool()), (Some(true), Some(true)));
        let page = user("b", &users(), &workspaces(), None, NOW).unwrap();
        assert_eq!((page["admission"].as_str(), page["mayCreateFixed"].as_bool(), page["blocked"].as_bool()), (Some("还没进来"), Some(false), Some(true)));
        assert!(user("z", &users(), &workspaces(), None, NOW).is_err());
    }

    #[test]
    fn a_workspaces_page_has_its_people_and_stations() {
        let page = workspace("w1", &workspaces(), Some(&users()), NOW).unwrap();
        assert_eq!(page["people"], "2 / 2");
        assert_eq!((page["stations"][1]["state"].as_str(), page["stations"][1]["outdated"].as_bool()), (Some("error"), Some(true)));
        assert_eq!(page["members"][1]["last_seen"], Value::Null);
        assert_eq!(page["members"][0]["role"], "Owner");
    }

    #[test]
    fn the_overview_points_at_lists() {
        let v = overview(&users(), &workspaces(), &json!({ "codes": [] }), None, NOW, 480);
        assert_eq!(v["stats"][0]["value"], 3);
        assert_eq!(v["weeks"].as_array().unwrap().len(), 12);
        assert_eq!(v["weeks"][11]["count"], 1);
        let todo: Vec<(&str, &str)> = v["todo"].as_array().unwrap().iter().map(|t| (t["list"].as_str().unwrap(), t["filter"].as_str().unwrap())).collect();
        assert_eq!(todo, [("users", "stuck"), ("workspaces", "bare"), ("workspaces", "stale"), ("workspaces", "outdated")]);
        let v = overview(&users(), &workspaces(), &json!({ "codes": [] }), Some(&reports()), NOW, 480);
        assert_eq!((v["todo"][0]["text"].as_str(), v["todo"][0]["list"].as_str(), v["todo"][0]["filter"].as_str()), (Some("1 个新反馈"), Some("feedback"), Some("new")));
    }

    #[test]
    fn bug_reports_are_listed_by_status_and_channel() {
        let all = list("feedback", &reports(), "", None, None, None, NOW).unwrap();
        assert_eq!(ids(&all), ["F2", "F1"], "newest first");
        assert_eq!((count(&all, "new"), count(&all, "fixed"), count(&all, "beta"), count(&all, "stable")), (1, 1, 1, 1));
        assert_eq!(all["rows"][0]["number"], "FB-2");
        assert_eq!(all["rows"][0]["line"], "Web · 产品 · studio · Ann (Slack)");
        assert_eq!(all["rows"][1]["line"], "Android · ann@x.io");
        let labels: Vec<&str> = all["rows"][0]["marks"].as_array().unwrap().iter().map(|m| m["label"].as_str().unwrap()).collect();
        assert_eq!(labels, ["新反馈", "测试版"]);
        // Found by its number, its words, where it came from.
        assert_eq!(ids(&list("feedback", &reports(), "fb-1", None, None, None, NOW).unwrap()), ["F1"]);
        assert_eq!(ids(&list("feedback", &reports(), "STUDIO 步骤", None, None, None, NOW).unwrap()), ["F2"]);
        assert_eq!(ids(&list("feedback", &reports(), "", Some("fixed"), None, None, NOW).unwrap()), ["F1"]);
    }

    #[test]
    fn a_bug_reports_page_has_all_of_it_in_text_too() {
        let page = feedback("F2", &reports()).unwrap();
        assert_eq!((page["number"].as_str(), page["status"].as_str(), page["channelLabel"].as_str()), (Some("FB-2"), Some("new"), Some("测试版")));
        assert_eq!(page["statuses"].as_array().unwrap().len(), 4);
        let context: Vec<(&str, &str)> = page["context"].as_array().unwrap().iter().map(|c| (c["key"].as_str().unwrap(), c["value"].as_str().unwrap())).collect();
        assert!(context.contains(&("version", "0.1.1212")) && context.contains(&("extra", "{\"a\":1}")), "{context:?}");
        let text = page["text"].as_str().unwrap();
        assert!(text.starts_with("FB-2 发送后消息消失\n"), "{text}");
        for part in ["渠道: 测试版 (beta)", "Station: studio (s1)", "Workspace: 产品 (w1)", "反馈人: Ann (Slack)", "## 步骤", "session: ember:c-1", "```\nline 1\nline 2\n```"] {
            assert!(text.contains(part), "{part} in {text}");
        }
        let page = feedback("F1", &reports()).unwrap();
        assert_eq!((page["logs"].clone(), page["context"].as_array().unwrap().len(), page["account"]["title"].as_str()), (Value::Null, 0, Some("ann@x.io")));
        assert!(!page["text"].as_str().unwrap().contains("## 日志"));
        assert!(feedback("F9", &reports()).is_err());
        // A cloud from before: no list, so no page and no overview item, and the rest stands.
        assert!(list("feedback", &json!({}), "", None, None, None, NOW).unwrap()["rows"].as_array().unwrap().is_empty());
    }
}
