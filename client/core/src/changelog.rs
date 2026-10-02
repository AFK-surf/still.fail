//! What changed in still.fail, for people (the `changelog` topic; docs/changelog.md): still.fail cloud's changelog
//! (`/v1/changelog`, made from main's history by scripts/changelog.ts) with what each part has out on this app's
//! channel, put together for this app: by day, newest first, each change saying where it is and whether this app has
//! it; and what this app got since the changelog was last shown here (`news`, until `changelog.seen`). Read when shown,
//! at most once an hour; kept on the device (data.rs, table `changelog`) for the next start and while offline.

use std::cell::Cell;
use std::rc::{Rc, Weak};

use futures::FutureExt;
use serde_json::{Value, json};
use stillfail_i18n::t;

use crate::data::Data;
use crate::host::{Host, HttpRequest};
use crate::protocol::Topic;
use crate::store::Store;

/// How often still.fail cloud is asked again while the changelog is shown.
const READ_EVERY_MS: f64 = 60.0 * 60.0 * 1000.0;
/// The changes shown, at most: the latest.
const SHOWN: usize = 200;
/// The changes `news` says, at most.
const NEWS: usize = 20;
const TABLE: &str = "changelog";

pub struct Changelog {
    host: Rc<dyn Host>,
    store: Weak<Store>,
    data: Rc<Data>,
    read_at: Cell<f64>,
    reading: Cell<bool>,
    failed: Cell<bool>,
}

/// The parts of still.fail an app runs: the web app is the desktop app's page too.
fn parts_of(app: &str) -> &'static [&'static str] {
    match app {
        "android" => &["android"],
        "desktop" => &["web", "desktop"],
        "web" => &["web"],
        _ => &[],
    }
}

fn part_name(part: &str) -> String {
    match part {
        "station" => "station".to_string(),
        "web" => t!("core-misc.changelog.part.web"),
        "android" => t!("core-misc.changelog.part.android"),
        "desktop" => t!("core-misc.changelog.part.desktop"),
        other => other.to_string(),
    }
}

impl Changelog {
    pub fn new(host: Rc<dyn Host>, store: Weak<Store>, data: Rc<Data>) -> Rc<Changelog> {
        Rc::new(Changelog { host, store, data, read_at: Cell::new(f64::NEG_INFINITY), reading: Cell::new(false), failed: Cell::new(false) })
    }

    pub fn owns(topic: &Topic) -> bool {
        matches!(topic, Topic::Changelog)
    }

    /// What the device's host said it is (`client.device`): its app, and its build's number.
    pub fn device(&self, facts: &Value) {
        let app = facts.get("app").and_then(Value::as_str).unwrap_or("");
        let build = facts.get("build").and_then(Value::as_str).and_then(|b| b.trim().rsplit('.').next()?.parse::<i64>().ok());
        self.data.put(TABLE, "device", json!({ "app": app, "build": build }));
        // The first build seen here: nothing is news before it.
        if let (Some(build), None) = (build, self.data.record(TABLE, "seen")) {
            self.data.put(TABLE, "seen", json!(build));
        }
        self.changed();
    }

    /// The changelog shown up to this build: `news` says nothing more until a later one.
    pub fn seen(&self) {
        if let Some(build) = self.build() {
            self.data.put(TABLE, "seen", json!(build));
        }
        self.changed();
    }

    fn build(&self) -> Option<i64> {
        self.data.record(TABLE, "device")?.get("build")?.as_i64()
    }

    fn changed(&self) {
        if let Some(store) = self.store.upgrade() {
            store.invalidate(&Topic::Changelog);
        }
    }

    /// Shown: read from still.fail cloud unless it was within the hour.
    pub fn start(self: &Rc<Self>) {
        self.changed();
        if self.reading.get() || self.host.now_ms() - self.read_at.get() < READ_EVERY_MS {
            return;
        }
        self.reading.set(true);
        let me = Rc::downgrade(self);
        let request = HttpRequest {
            method: "GET".into(),
            url: format!("{}/v1/changelog", self.host.cloud_origin()),
            headers: crate::cloud::channel_header(&*self.host).into_iter().collect(),
            body: None,
        };
        let fetch = self.host.fetch(request);
        self.host.spawn(
            async move {
                let response = fetch.await;
                let Some(me) = me.upgrade() else { return };
                me.reading.set(false);
                let feed = response.ok().filter(|r| r.status == 200).and_then(|r| serde_json::from_slice::<Value>(&r.body).ok()).filter(|v| v.get("entries").is_some_and(Value::is_array));
                match feed {
                    Some(feed) => {
                        me.read_at.set(me.host.now_ms());
                        me.failed.set(false);
                        me.data.put(TABLE, "feed", feed);
                    }
                    // Not reached (or a cloud from before): what was kept stays, and it is asked again when next shown.
                    None => me.failed.set(true),
                }
                me.changed();
            }
            .boxed_local(),
        );
    }

    pub fn value(&self) -> Value {
        let device = self.data.record(TABLE, "device").unwrap_or(Value::Null);
        let app = device.get("app").and_then(Value::as_str).unwrap_or("").to_string();
        let build = device.get("build").and_then(Value::as_i64);
        let seen = self.data.record(TABLE, "seen").and_then(|v| v.as_i64());
        let Some(feed) = self.data.record(TABLE, "feed") else {
            return json!({
                "app": app, "build": build, "days": [],
                "loading": !self.failed.get(),
                "error": self.failed.get().then(|| t!("core-misc.changelog.unreadable")),
            });
        };
        let released = feed.get("released").cloned().unwrap_or(Value::Null);
        let (now, offset) = (self.host.now_ms(), self.host.utc_offset_min(self.host.now_ms()));
        let mut days: Vec<Value> = Vec::new();
        let mut news = Vec::new();
        for entry in feed["entries"].as_array().into_iter().flatten().take(SHOWN) {
            let Some(item) = item(entry, &app, build, &released) else { continue };
            let version = item["version"].as_i64().unwrap_or(0);
            let mine = item["mine"].as_bool().unwrap_or(false);
            if mine && build.is_some_and(|b| version <= b) && seen.is_some_and(|s| version > s) && news.len() < NEWS {
                news.push(item.clone());
            }
            let ms = entry.get("at").and_then(Value::as_f64).unwrap_or(0.0) * 1000.0;
            let label = crate::format::day_label(ms, now, offset);
            match days.last_mut() {
                Some(day) if day["label"] == label => day["entries"].as_array_mut().unwrap().push(item),
                _ => days.push(json!({ "label": label, "entries": [item] })),
            }
        }
        let news = (!news.is_empty()).then(|| json!({ "build": build.map(|b| format!("0.1.{b}")), "entries": news }));
        json!({ "app": app, "build": build, "days": days, "news": news, "loading": false })
    }
}

/// One change as this app shows it: its lines, where it is (`place`: the parts and the version), whether this app has
/// it (`has`: absent when it is not this app's), and what that means (`note`).
fn item(entry: &Value, app: &str, build: Option<i64>, released: &Value) -> Option<Value> {
    let version = entry.get("version")?.as_i64()?;
    let text: Vec<&str> = entry.get("text")?.as_array()?.iter().filter_map(Value::as_str).collect();
    if text.is_empty() {
        return None;
    }
    let parts: Vec<&str> = entry.get("parts").and_then(Value::as_array).map(|p| p.iter().filter_map(Value::as_str).collect()).unwrap_or_default();
    let ours = parts_of(app);
    let mine: Vec<&str> = parts.iter().copied().filter(|p| ours.contains(p)).collect();
    let out = |part: &str| part == "cloud" || released.get(part).and_then(Value::as_i64).is_some_and(|r| r >= version);
    let name = format!("0.1.{version}");
    // Where it is: the parts that are released (the cloud is not), and the version.
    let names: Vec<String> = parts.iter().filter(|p| **p != "cloud").map(|p| part_name(p)).collect();
    let place = if parts.is_empty() || parts == ["cloud"] { String::new() } else { t!("core-misc.changelog.place", parts = names.join(&t!("core-misc.changelog.and")), version = name) };
    let (has, note) = if parts.is_empty() || parts == ["cloud"] {
        (None, t!("core-misc.changelog.live"))
    } else if !mine.is_empty() {
        match build {
            Some(b) if b >= version => (Some(true), t!("core-misc.changelog.have")),
            _ if mine.iter().all(|p| out(p)) => (Some(false), if app == "web" { t!("core-misc.changelog.reload") } else { t!("core-misc.changelog.update", version = name) }),
            _ => (Some(false), t!("core-misc.changelog.unreleased")),
        }
    } else if parts.iter().all(|p| out(p)) {
        (None, t!("core-misc.changelog.released"))
    } else {
        (None, t!("core-misc.changelog.unreleased"))
    };
    Some(json!({ "version": version, "versionName": name, "text": text, "place": place, "has": has, "note": note, "mine": !mine.is_empty() }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(version: i64, parts: &[&str]) -> Value {
        json!({ "version": version, "commit": "c", "at": 1_790_000_000, "text": ["修复：一件事"], "fixes": [], "parts": parts })
    }

    #[test]
    fn a_change_says_whether_this_app_has_it() {
        let released = json!({ "android": 1340, "web": 1330, "station": null, "desktop": null });
        let had = item(&entry(1320, &["android"]), "android", Some(1323), &released).unwrap();
        assert_eq!((had["has"].as_bool(), had["note"].as_str(), had["place"].as_str()), (Some(true), Some("你的版本已包含"), Some("安卓 app 0.1.1320")));
        let update = item(&entry(1335, &["android", "web"]), "android", Some(1323), &released).unwrap();
        assert_eq!((update["has"].as_bool(), update["note"].as_str()), (Some(false), Some("更新到 0.1.1335 后就有")));
        let coming = item(&entry(1345, &["android"]), "android", Some(1323), &released).unwrap();
        assert_eq!(coming["note"], "还没发布");
        let web = item(&entry(1325, &["web"]), "web", Some(1323), &released).unwrap();
        assert_eq!(web["note"], "刷新页面后就有");
        let station = item(&entry(1320, &["station"]), "android", Some(1323), &released).unwrap();
        assert_eq!((station["has"].as_bool(), station["note"].as_str(), station["mine"].as_bool()), (None, Some("还没发布"), Some(false)));
        let cloud = item(&entry(1350, &["cloud"]), "web", Some(1), &released).unwrap();
        assert_eq!((cloud["note"].as_str(), cloud["place"].as_str()), (Some("已上线"), Some("")));
        // The desktop app runs the web app's page: a change to it is its.
        let desktop = item(&entry(1320, &["web"]), "desktop", Some(1323), &released).unwrap();
        assert_eq!(desktop["has"], true);
        assert!(item(&json!({ "version": 1, "text": [], "parts": [] }), "web", None, &released).is_none());
    }
}
