//! The admin's console (web/src/admin): still.fail cloud's operator lists (`Topic::Admin`) as its pages show them, so
//! the page only draws. `adminList`: one list found, filtered and sorted, with how many each filter holds;
//! `adminItem`: one user's or workspace's page; `adminOverview`: the counts and what wants a look. Times stay in
//! seconds, as still.fail cloud gives them: what goes out has them in words beside (present.rs `times`).

use std::cmp::Ordering;
use std::collections::HashMap;

use serde_json::{Value, json};

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
            _ => vec![of(account, "workspaces"), of(account, "users")],
        },
        Topic::AdminOverview { account } => vec![of(account, "users"), of(account, "workspaces"), of(account, "invite-codes")],
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

fn role_label(role: &str) -> &'static str {
    match role {
        "owner" => "Owner",
        "admin" => "管理员",
        _ => "成员",
    }
}

fn admission_label(admission: &str) -> &'static str {
    match admission {
        "admin" => "still.fail 管理员",
        "code" => "用邀请码加入",
        "granted" => "管理员开通",
        "invitation" => "被邀请加入",
        "early" => "邀请码之前加入",
        _ => "还没进来",
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

fn code_state(c: &Value, now: f64) -> (&'static str, &'static str, &'static str) {
    if num(c, "used_at").is_some() || c.get("used_by").is_some_and(Value::is_object) {
        ("used", "已使用", "neutral")
    } else if num(c, "revoked_at").is_some() {
        ("revoked", "已撤回", "red")
    } else if num(c, "expires_at").is_some_and(|at| at <= now) {
        ("expired", "已过期", "amber")
    } else {
        ("open", "可用", "green")
    }
}

/// One kind of list: its filters (id, label, whether a row is in it), its sorts, and how a row is found and shown.
struct Kind {
    filters: Vec<(&'static str, &'static str, Box<dyn Fn(&Value) -> bool>)>,
    sorts: Vec<(&'static str, &'static str)>,
}

fn user_kind(now: f64) -> Kind {
    let seen = |u: &Value| num(u, "last_seen");
    Kind {
        filters: vec![
            ("all", "全部", Box::new(|_| true)),
            ("active", "7 天内来过", Box::new(move |u| seen(u).is_some_and(|at| now - at < 7.0 * DAY))),
            ("new", "7 天内新来", Box::new(move |u| num(u, "created_at").is_some_and(|at| now - at < 7.0 * DAY))),
            ("stuck", "还没进来", Box::new(|u| u.get("admission").is_none_or(Value::is_null))),
            ("dormant", "30 天没来", Box::new(move |u| seen(u).is_none_or(|at| now - at > 30.0 * DAY))),
            ("creators", "能建 workspace", Box::new(|u| u.get("may_create").and_then(Value::as_bool) == Some(true))),
            ("beta", "测试版", Box::new(|u| u.get("beta").and_then(Value::as_bool) == Some(true))),
            ("blocked", "已封禁", Box::new(|u| u.get("blocked").and_then(Value::as_bool) == Some(true))),
        ],
        sorts: vec![("seen", "最近来访"), ("created", "首次登录"), ("workspaces", "workspace 数"), ("name", "名字")],
    }
}

fn workspace_kind(now: f64, newest: Option<String>) -> Kind {
    Kind {
        filters: vec![
            ("all", "全部", Box::new(|_| true)),
            ("bare", "没有 station", Box::new(|w| items(w, "stations").is_empty())),
            ("stale", "station 7 天没连", Box::new(move |w| !items(w, "stations").is_empty() && latest_station(w).is_none_or(|at| now - at > 7.0 * DAY))),
            ("outdated", "有旧版 station", Box::new(move |w| {
                let Some(newest) = &newest else { return false };
                items(w, "stations").iter().any(|s| s.get("version").and_then(Value::as_str).is_some_and(|v| version_key(v) < version_key(newest)))
            })),
            ("invited", "有待接受的邀请", Box::new(|w| !items(w, "invitations").is_empty())),
            ("full", "人满了", Box::new(|w| w.get("seats").and_then(Value::as_u64).is_some_and(|n| items(w, "members").len() as u64 >= n))),
        ],
        sorts: vec![("active", "station 最近连"), ("created", "创建时间"), ("members", "人数"), ("name", "名字")],
    }
}

fn code_kind(now: f64) -> Kind {
    let is = move |state: &'static str| -> Box<dyn Fn(&Value) -> bool> { Box::new(move |c| code_state(c, now).0 == state) };
    Kind {
        filters: vec![("all", "全部", Box::new(|_| true)), ("open", "可用", is("open")), ("used", "已使用", is("used")), ("expired", "已过期", is("expired")), ("revoked", "已撤回", is("revoked"))],
        sorts: vec![("created", "生成时间")],
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
                marks.push(mark("已封禁", "red"));
            }
            match v.get("admission").and_then(Value::as_str) {
                None => marks.push(mark("还没进来", "amber")),
                Some("admin") => marks.push(mark("管理员", "accent")),
                _ => {}
            }
            if v.get("beta").and_then(Value::as_bool) == Some(true) {
                marks.push(mark("测试版", "accent"));
            }
            let workspaces: Vec<&str> = items(v, "workspaces").iter().map(|w| str_of(w, "name")).collect();
            let mut line = str_of(v, "email").to_string();
            if !workspaces.is_empty() {
                line = format!("{line} · {}", workspaces.join("、"));
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
            }).unwrap_or_else(|| "已不在的人".into());
            let mut marks = Vec::new();
            if stations.is_empty() {
                marks.push(mark("没有 station", "amber"));
            }
            let latest = latest_station(v);
            json!({
                "id": str_of(v, "id"),
                "title": str_of(v, "name"),
                "line": format!("{creator} 创建 · {} 人 · {} 台 station", items(v, "members").len(), stations.len()),
                "marks": marks,
                // When a station of it last came to still.fail cloud, and how that stands.
                "last_seen": latest,
                "state": (!stations.is_empty()).then(|| station_state(latest, now)),
                "created_at": v.get("created_at").cloned().unwrap_or(Value::Null),
            })
        }
        _ => {
            let (state, label, tone) = code_state(v, now);
            let user = v.get("used_by").filter(|u| u.is_object());
            let line = match (state, user) {
                ("used", Some(u)) => {
                    let n = str_of(u, "name");
                    let workspace = v.get("workspace").filter(|w| w.is_object()).map(|w| format!("「{}」", str_of(w, "name"))).unwrap_or_else(|| " workspace（已删除）".into());
                    format!("{} 用它建了{workspace}", if n.is_empty() { str_of(u, "email") } else { n })
                }
                ("used", None) => "已不在的人用过".into(),
                _ => str_of(v, "note").to_string(),
            };
            json!({
                "id": str_of(v, "code"),
                "title": str_of(v, "code"),
                "note": str_of(v, "note"),
                "line": line,
                "state": state,
                "marks": [mark(label, tone)],
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
        _ => return Err(CoreError::invalid("没有这个列表")),
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
    let u = rows_of("users", users).into_iter().find(|u| str_of(u, "sub") == id).ok_or_else(|| CoreError::new("http_404", "没有这个用户").with_status(404))?;
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
            "line": format!("{} · {people} 人 · {stations} 台 station", role_label(str_of(m, "role"))),
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
            "管理员不受限制"
        } else if creator {
            "自己建过 workspace，一直可以再建（最多 5 个）"
        } else if may_create == Some(true) {
            "可以新建 workspace，最多 5 个"
        } else {
            "只能被邀请加入别人的 workspace"
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
    let w = all.iter().find(|w| str_of(w, "id") == id).ok_or_else(|| CoreError::new("http_404", "没有这个 workspace").with_status(404))?;
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
        "email": i.get("email").and_then(Value::as_str).unwrap_or("任何拿到链接的人"),
        "line": format!("{}{}", role_label(str_of(i, "role")), match str_of(i, "inviter") { "" => String::new(), by => format!(" · {by} 邀请") }),
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

/// The console's first page: counts, new people by week, and what wants a look, each with the list and filter that
/// show it.
pub fn overview(users: &Value, workspaces: &Value, codes: &Value, now: f64, offset_min: i32) -> Value {
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
        let label = if ago == 0 { "本周".to_string() } else { crate::format::day_label(start * 1000.0, now * 1000.0, offset_min) };
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
    want(stuck, format!("{stuck} 人登录了但还没进来"), "开通资格，或者看看卡在哪", "amber", "users", "stuck");
    want(bare, format!("{bare} 个 workspace 还没有 station"), "建了但没装起来", "amber", "workspaces", "bare");
    want(stale, format!("{stale} 台 station 7 天没连 still.fail cloud"), "可能关机或卸载了", "neutral", "workspaces", "stale");
    want(outdated, format!("{outdated} 台 station 不是最新版"), newest.as_deref().map(|n| format!("最新是 {n}")).as_deref().unwrap_or(""), "neutral", "workspaces", "outdated");
    want(expiring, format!("{expiring} 个邀请码 3 天内过期"), "还没人用", "neutral", "invite-codes", "open");
    let pct = if users.is_empty() { 0 } else { active * 100 / users.len() };
    let used_ws = count(&workspaces, &|w| latest_station(w).is_some_and(|at| now - at < 7.0 * DAY));
    let today = stations.iter().filter(|s| num(s, "last_seen").is_some_and(|at| now - at < DAY)).count();
    json!({
        "stats": [
            { "label": "用户", "value": users.len(), "note": format!("7 天新增 {}", count(&users, &|u| within(u, "created_at", 7.0))), "list": "users", "filter": "all" },
            { "label": "7 天活跃", "value": active, "note": format!("占 {pct}%"), "list": "users", "filter": "active" },
            { "label": "Workspace", "value": workspaces.len(), "note": format!("{used_ws} 个这周有 station 连过"), "list": "workspaces", "filter": "all" },
            { "label": "Station", "value": stations.len(), "note": format!("{today} 台今天连过"), "list": "workspaces", "filter": "all" },
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
            Topic::AdminItem { account, id, .. } => {
                let workspaces = read(account, "workspaces")?;
                let users = read(account, "users").and_then(Result::ok);
                Some(workspaces.and_then(|w| workspace(id, &w, users.as_ref(), now)))
            }
            Topic::AdminOverview { account } => {
                let (users, workspaces, codes) = (read(account, "users")?, read(account, "workspaces")?, read(account, "invite-codes")?);
                Some(users.and_then(|u| workspaces.and_then(|w| codes.map(|c| overview(&u, &w, &c, now, clock.offset_min)))))
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
        let v = overview(&users(), &workspaces(), &json!({ "codes": [] }), NOW, 480);
        assert_eq!(v["stats"][0]["value"], 3);
        assert_eq!(v["weeks"].as_array().unwrap().len(), 12);
        assert_eq!(v["weeks"][11]["count"], 1);
        let todo: Vec<(&str, &str)> = v["todo"].as_array().unwrap().iter().map(|t| (t["list"].as_str().unwrap(), t["filter"].as_str().unwrap())).collect();
        assert_eq!(todo, [("users", "stuck"), ("workspaces", "bare"), ("workspaces", "stale"), ("workspaces", "outdated")]);
    }
}
