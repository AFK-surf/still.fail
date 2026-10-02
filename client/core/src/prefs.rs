//! What this device keeps of how its person likes it (the `prefs` topic): the lists' 只看我的 (the chat list's 监控中,
//! one or the other), the appearance, whose
//! pictures led a row (no longer read; clients from before still set it), times as dates, keys changed, the workspace
//! and the chat last open (each workspace's, as `client.focus` says: `openChat`), each chat's history tabs, a new connect to go on with, the invite code carried through
//! signing in. One record in the data center (data.rs, table `prefs`), written by `prefs.set`. With it, what the device
//! is (`client.device`: its host says so once at start) and what follows from that: phone or computer, the name it signs in as, the app a message is sent from.

use serde_json::{Map, Value, json};

use crate::data::Data;
use crate::error::{CoreError, Result};
use crate::protocol::Topic;

/// The fields `prefs.set` takes; the rest of a patch is refused.
const FIELDS: &[&str] = &["onlyMine", "onlyWatching", "appearance", "rowPicture", "absoluteTime", "language", "keys", "workspace", "lastChat", "chatTabs", "resume", "invite"];
/// Fields that are maps: a patch changes them entry by entry.
const MAPS: &[&str] = &["keys", "lastChat", "chatTabs", "resume"];
/// How many chats keep their tabs: the latest used.
const TABS_KEPT: usize = 200;
/// How many decisions set aside are kept: the latest.
const DEFERRED_KEPT: usize = 200;

/// What is kept, as kept (no defaults filled in).
fn kept(data: &Data) -> Map<String, Value> {
    match data.get(&Topic::Prefs) {
        Some(Value::Object(map)) => map,
        _ => Map::new(),
    }
}

/// Puts `patch` into what is kept: a field given replaces it and null removes it; a map's entries are each put so (an
/// entry null removes it). `fill`: only what is not kept yet (a device's values from before, moved in once).
pub fn set(data: &Data, patch: Value, fill: bool, now: f64) -> Result<()> {
    let Value::Object(patch) = patch else { return Err(CoreError::invalid("参数不对：要是一个对象")) };
    let mut prefs = kept(data);
    for (field, value) in patch {
        if !FIELDS.contains(&field.as_str()) {
            return Err(CoreError::invalid(format!("参数不对：没有 {field} 这一项")));
        }
        match value {
            Value::Object(entries) if MAPS.contains(&field.as_str()) => {
                let map = prefs.entry(field.clone()).or_insert_with(|| json!({}));
                let Some(map) = map.as_object_mut() else { continue };
                for (key, mut entry) in entries {
                    if fill && map.contains_key(&key) {
                        continue;
                    }
                    if entry.is_null() {
                        map.remove(&key);
                        continue;
                    }
                    // When it was used, for keeping the latest (after every other, the clock however it goes).
                    if field == "chatTabs" && entry.is_object() {
                        let last = map.values().filter_map(|v| v.get("at")?.as_f64()).fold(0.0, f64::max);
                        entry["at"] = json!(now.max(last + 1.0));
                    }
                    map.insert(key, entry);
                }
            }
            _ if fill && prefs.contains_key(&field) => {}
            Value::Null => {
                prefs.remove(&field);
            }
            value => {
                // The chat list shows one: 我参与的 or 监控中, not both.
                let other = match field.as_str() {
                    "onlyMine" => Some("onlyWatching"),
                    "onlyWatching" => Some("onlyMine"),
                    _ => None,
                };
                if let Some(other) = other.filter(|_| value == Value::Bool(true) && !fill) {
                    prefs.remove(other);
                }
                prefs.insert(field, value);
            }
        }
    }
    if let Some(Value::Object(tabs)) = prefs.get_mut("chatTabs")
        && tabs.len() > TABS_KEPT
    {
        let mut by_use: Vec<(f64, String)> = tabs.iter().map(|(k, v)| (v.get("at").and_then(Value::as_f64).unwrap_or(0.0), k.clone())).collect();
        by_use.sort_by(|a, b| a.0.total_cmp(&b.0));
        for (_, key) in by_use.into_iter().take(tabs.len() - TABS_KEPT) {
            tabs.remove(&key);
        }
    }
    if prefs.get("language").is_some_and(|l| !matches!(l.as_str(), Some("zh" | "en"))) {
        return Err(CoreError::invalid("参数不对：language 要是 zh 或 en"));
    }
    with_lang(&mut prefs);
    let prefs = Value::Object(prefs);
    stillfail_shapes::conform::<stillfail_shapes::PrefsView>(prefs.clone()).map_err(|e| CoreError::invalid(format!("参数不对：{e}")))?;
    data.set(&Topic::Prefs, prefs);
    Ok(())
}

/// A chat opened (`client.focus`): kept as the one last open in its workspace (`openChat`), to go back to.
pub fn chat_opened(data: &Data, station: &str, key: &str) {
    let workspace = crate::workspace::of_address(station);
    let chat = json!({ "station": station, "key": key });
    let mut prefs = kept(data);
    if prefs.get("openChat").and_then(|m| m.get(workspace)) == Some(&chat) {
        return;
    }
    let map = prefs.entry("openChat").or_insert_with(|| json!({}));
    if !map.is_object() {
        *map = json!({});
    }
    map[workspace] = chat;
    data.set(&Topic::Prefs, Value::Object(prefs));
}

/// A decision set aside on this device (待定, decisions.rs), kept as `decisionsDeferred` by where it is
/// (`decisions::deferral_key`) with when: last on the decisions page, still pending. The latest [`DEFERRED_KEPT`]. Not
/// in `prefs.set`'s fields: only the core sets it.
pub fn defer_decision(data: &Data, at: &str, now: f64) {
    let mut prefs = kept(data);
    let map = prefs.entry("decisionsDeferred").or_insert_with(|| json!({}));
    if !map.is_object() {
        *map = json!({});
    }
    let Some(map) = map.as_object_mut() else { return };
    // After every other, the clock however it goes: it goes last.
    let last = map.values().filter_map(Value::as_f64).fold(0.0, f64::max);
    map.insert(at.to_string(), json!(now.max(last + 1.0)));
    if map.len() > DEFERRED_KEPT {
        let mut by_age: Vec<(f64, String)> = map.iter().map(|(k, v)| (v.as_f64().unwrap_or(0.0), k.clone())).collect();
        by_age.sort_by(|a, b| a.0.total_cmp(&b.0));
        for (_, key) in by_age.into_iter().take(map.len() - DEFERRED_KEPT) {
            map.remove(&key);
        }
    }
    data.set(&Topic::Prefs, Value::Object(prefs));
}

/// A decision no longer set aside (answered, or dismissed).
pub fn undefer_decision(data: &Data, at: &str) {
    let mut prefs = kept(data);
    let Some(map) = prefs.get_mut("decisionsDeferred").and_then(Value::as_object_mut) else { return };
    if map.remove(at).is_some() {
        data.set(&Topic::Prefs, Value::Object(prefs));
    }
}

/// A workspace made: the invite code kept is done with (it was for that, or another was used).
pub fn invite_used(data: &Data) {
    if kept(data).contains_key("invite") {
        let _ = set(data, json!({ "invite": null }), false, 0.0);
    }
}

/// What the device is, from what its host says (`client.device`): `app` (web, desktop or android), its `build`, and a
/// browser's `userAgent` or an Android phone's `model`. Kept with the prefs, as they are shown, and what follows.
pub fn device(data: &Data, facts: &Value) -> Result<()> {
    let said = |k: &str| facts.get(k).and_then(Value::as_str).unwrap_or("").trim().to_string();
    let app = said("app");
    if !matches!(app.as_str(), "web" | "desktop" | "android") {
        return Err(CoreError::invalid("参数不对：app 要是 web、desktop 或 android"));
    }
    let (build, agent, model) = (said("build"), said("userAgent"), said("model"));
    let has = |words: &[&str]| words.iter().any(|w| agent.to_lowercase().contains(&w.to_lowercase()));
    let phone = app == "android" || (app == "web" && has(&["Android", "iPhone", "iPad"]));
    let os = if has(&["iPhone", "iPad"]) { "iOS" } else if agent.contains("Mac OS X") { "macOS" } else if agent.contains("Windows") { "Windows" } else if agent.contains("Android") { "Android" } else if agent.contains("Linux") { "Linux" } else { "" };
    let browser = if agent.contains("Edg/") { "Edge" } else if agent.contains("Chrome/") { "Chrome" } else if agent.contains("Firefox/") { "Firefox" } else if agent.contains("Safari/") { "Safari" } else { "浏览器" };
    let with = |s: &str| if s.is_empty() { String::new() } else { format!(" · {s}") };
    let name = match app.as_str() {
        "android" => format!("{} Android{}", crate::brand::name(), with(&model)),
        "desktop" => format!("{} 桌面版{}", crate::brand::name(), with(os)),
        _ => format!("{} 网页版 · {browser}{}", crate::brand::name(), with(os)),
    };
    let build = if build.is_empty() { String::new() } else { format!(" {build}") };
    let from = match app.as_str() {
        "web" => format!("web{build} ({})", if phone { "phone" } else { "pc" }),
        _ => format!("{app}{build}"),
    };
    let mut prefs = kept(data);
    let mut told = json!({ "app": app, "phone": phone, "handoff": app == "web" && !phone, "name": name, "sentFrom": from });
    let locale = said("locale");
    if !locale.is_empty() {
        told["locale"] = json!(locale);
    }
    prefs.insert("device".into(), told);
    with_lang(&mut prefs);
    data.set(&Topic::Prefs, Value::Object(prefs));
    Ok(())
}

/// The language things are said in (`lang`): as chosen, else as the device is; the core says its own words in it from now on.
fn with_lang(prefs: &mut Map<String, Value>) {
    let chosen = prefs.get("language").and_then(Value::as_str);
    let device = prefs.get("device").and_then(|d| d.get("locale")).and_then(Value::as_str);
    let lang = stillfail_i18n::Lang::from_locale(chosen.or(device).unwrap_or(""));
    prefs.insert("lang".into(), json!(lang.code()));
    stillfail_i18n::set_current(lang);
}

/// The core says its words in the language kept (at start, before anything is said).
pub fn follow_lang(data: &Data) {
    if let Some(lang) = kept(data).get("lang").and_then(Value::as_str) {
        stillfail_i18n::set_current(stillfail_i18n::Lang::from_locale(lang));
    }
}

fn device_said(data: &Data, field: &str) -> Option<String> {
    kept(data).get("device")?.get(field)?.as_str().filter(|s| !s.is_empty()).map(str::to_string)
}

/// The app a message is sent from ("web 0.1.1150 (phone)"), for the station to tell its agent; none until told.
pub fn sent_from(data: &Data) -> Option<String> {
    device_said(data, "sentFrom")
}

/// The name the device signs in as ("still.fail 网页版 · Chrome · macOS"), as its signed-in devices list it.
pub fn device_name(data: &Data) -> Option<String> {
    device_said(data, "name")
}

