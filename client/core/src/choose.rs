//! What a chat runs on, chosen. A new chat's page (`newChat`): the station it starts on and the model, runtime,
//! depth and account it runs there, as last picked on this device (kept per station, and the station per scope, in
//! the data center's `choice` table, each workspace's apart: `ws:<workspace>:station:<id>`, `ws:<workspace>:last`;
//! what was kept before that, `station:<id>`, `scope:<scope>` and `last`, is read where there is none yet), each given way to the first the station has once it no longer has it; its
//! profiles not checked since their station started are checked, once. A model control (`pick`): what a chat, a
//! connect or a new chat runs on now, what is picked in its panel until saved, and what that means (an account kept
//! to that does not run the model picked gives way to the station's pick, said so). Both screens and both phones
//! show these as they are; none of them decides anything.

use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::rc::Rc;

use serde_json::{Map, Value, json};

use crate::data::Data;
use crate::error::{CoreError, Result};
use crate::host::Host;
use crate::protocol::Topic;
use crate::store::{Store, Watch};
use crate::views::{Views, models};

const TABLE: &str = "choice";
const FIELDS: [&str; 4] = ["runtime", "model", "effort", "profile"];

/// Asks a station's profile to check itself (station address, profile id).
pub type Check = Rc<dyn Fn(&str, &str)>;

/// What a pick's save does: done here, or a request to the station.
pub enum Saved {
    Done(Value),
    Op(crate::ops::Request),
}

pub struct Choose {
    host: Rc<dyn Host>,
    store: Rc<Store>,
    data: Rc<Data>,
    views: Rc<Views>,
    check: Check,
    /// Per live topic, what it is put together from.
    watches: RefCell<HashMap<Topic, Vec<Watch>>>,
    /// Per pick topic, what its panel has picked and not saved (only the fields picked).
    drafts: RefCell<HashMap<Topic, Map<String, Value>>>,
    /// A connect being added, per station: what it will run on (until the page is left).
    adding: RefCell<HashMap<(String, String), Value>>,
    /// Profiles asked to check themselves this run, by station.
    checked: RefCell<HashSet<(String, String)>>,
}

/// What a pick is of.
enum Of<'a> {
    New,
    Session(&'a str),
    Connect(&'a str),
    ConnectNew(&'a str),
}

fn of(of: &str) -> Result<Of<'_>> {
    Ok(match of.split_once(':') {
        None if of == "new" => Of::New,
        None if of == "connect-new" => Of::ConnectNew(""),
        Some(("connect-new", form)) if !form.is_empty() => Of::ConnectNew(form),
        Some(("session", key)) if !key.is_empty() => Of::Session(key),
        Some(("connect", id)) if !id.is_empty() => Of::Connect(id),
        _ => return Err(CoreError::invalid(format!("没有这种选择：{of}"))),
    })
}

/// A station's id in its address (`"<workspace>/<station>"`).
fn station_id(address: &str) -> &str {
    address.rsplit('/').next().unwrap_or(address)
}

fn address(scope: &str, id: &str) -> String {
    format!("{scope}/{id}")
}

fn text(v: Option<&Value>) -> Option<String> {
    v.and_then(Value::as_str).filter(|s| !s.is_empty()).map(str::to_string)
}

/// The option a model is, however it is spelled (openai/gpt-6-astra is gpt-6-astra).
fn option_of<'a>(options: &'a [Value], model: Option<&str>) -> Option<&'a Value> {
    let model = model.filter(|m| !m.is_empty())?;
    options.iter().find(|o| o["model"] == model).or_else(|| options.iter().find(|o| o["ids"].as_array().is_some_and(|ids| ids.iter().any(|i| i == model))))
}

fn list(v: &Value) -> Vec<Value> {
    v.as_array().cloned().unwrap_or_default()
}

/// A choice (`{ runtime, model, effort, profile }`, "" for none) as the station has it now: a model or runtime it no
/// longer has gives way to the first it has; a depth the runtime has not, to its default; an account kept to that no
/// longer runs the model there, to the station's pick.
struct Resolved {
    entry: Option<Value>,
    runtime: Option<String>,
    effort: Option<String>,
    profile: Option<String>,
    efforts: Vec<Value>,
    accounts: Vec<Value>,
}

fn resolve(options: &[Value], choice: &Value) -> Resolved {
    let entry = option_of(options, choice["model"].as_str()).or(options.first()).cloned();
    let runtimes = entry.as_ref().map(|e| list(&e["runtimes"])).unwrap_or_default();
    let runtime = runtimes.iter().find(|r| **r == choice["runtime"]).or(runtimes.first()).and_then(Value::as_str).map(str::to_string);
    let at = |field: &str| entry.as_ref().zip(runtime.as_ref()).map(|(e, r)| list(&e[field][r])).unwrap_or_default();
    let (mut efforts, accounts) = (at("efforts"), at("accounts"));
    let profile = text(choice.get("profile")).filter(|p| accounts.iter().any(|a| a["id"] == p.as_str()));
    if let Some(levels) = profile.as_ref().and_then(|id| accounts.iter().find(|a| a["id"] == *id)).and_then(|a| a["efforts"].as_array()) {
        efforts = levels.clone();
    }
    let effort = text(choice.get("effort")).filter(|e| efforts.iter().any(|x| x == e.as_str()));
    Resolved { entry, runtime, effort, profile, efforts, accounts }
}

impl Resolved {
    fn picked(&self) -> Value {
        json!({ "model": self.entry.as_ref().map(|e| e["model"].clone()), "runtime": self.runtime.as_deref().unwrap_or("claude"), "effort": self.effort, "profile": self.profile })
    }
}

/// What is left of an account's allowance, in a few words (shapes: QuotaLine): every window, or only the one running
/// lowest, with its level; a quota that cannot be read says why.
pub fn quota_line(quota: Option<&Value>) -> Value {
    let Some(quota) = quota.filter(|q| q.is_object()) else { return Value::Null };
    let windows = list(&quota["windows"]);
    if quota["state"] != "ok" || windows.is_empty() {
        return text(quota.get("detail")).map_or(Value::Null, |d| json!({ "text": d }));
    }
    let mut windows: Vec<(String, i64, &str, u8)> = windows.iter().map(|w| {
        let label = w["label"].as_str().unwrap_or("").to_string();
        let (left, level) = crate::present::left_level(w["usedPercent"].as_f64().unwrap_or(0.0));
        let order = crate::format::window_mark(&label).1;
        (label, left, level, order)
    }).collect();
    windows.sort_by_key(|w| w.3);
    if let Some((label, left, level, _)) = windows.iter().filter(|w| w.2 != "ok").min_by_key(|w| w.1) {
        return json!({ "text": format!("{label}只剩 {left}%"), "level": level });
    }
    json!({ "text": windows.iter().map(|(label, left, ..)| format!("{label} {left}%")).collect::<Vec<_>>().join(" · ") })
}

/// A session the station's machine kept, in a line: its runtime, where it ran (the home directory as ~), how long ago.
pub fn machine_meta(session: &mut Value, now: f64) {
    let Some(s) = session.as_object_mut() else { return };
    let runtime = crate::format::runtime_label(s.get("runtime").and_then(Value::as_str).unwrap_or(""));
    let cwd = s.get("cwd").and_then(Value::as_str).unwrap_or("");
    // /Users/<name> or /home/<name>, and what follows it.
    let short = match cwd.strip_prefix("/Users/").or_else(|| cwd.strip_prefix("/home/")) {
        Some(rest) => match rest.find('/') {
            Some(at) if at > 0 => format!("~{}", &rest[at..]),
            None if !rest.is_empty() => "~".to_string(),
            _ => cwd.to_string(),
        },
        None => cwd.to_string(),
    };
    let ago = s.get("updatedAt").and_then(Value::as_f64).map(|at| {
        let secs = ((now - at) / 1000.0).round().max(0.0) as i64;
        match secs {
            s if s < 5 => "刚刚".to_string(),
            s if (86_400..2 * 86_400).contains(&s) => "昨天".to_string(),
            s if s < 60 => format!("{s} 秒前"),
            s if s < 3600 => format!("{} 分钟前", s / 60),
            s if s < 86_400 => format!("{} 小时前", s / 3600),
            s => format!("{} 天前", s / 86_400),
        }
    });
    s.insert("meta".into(), json!([Some(runtime.to_string()), Some(short), ago].into_iter().flatten().collect::<Vec<_>>().join(" · ")));
}

/// Usage stays bounded on the device; ties favour the most recently started chat.
fn record_combo(history: &mut Vec<Value>, choice: &Value, now: f64) {
    let same = |v: &Value| ["model", "runtime", "effort"].iter().all(|f| text(v.get(*f)) == text(choice.get(*f)));
    let count = history.iter().find(|v| same(v)).and_then(|v| v["count"].as_u64()).unwrap_or(0).saturating_add(1);
    history.retain(|v| !same(v));
    history.push(json!({ "model": choice["model"], "runtime": choice["runtime"], "effort": text(choice.get("effort")), "count": count, "last": now }));
    history.sort_by(|a, b| b["last"].as_f64().unwrap_or(0.0).total_cmp(&a["last"].as_f64().unwrap_or(0.0)));
    history.truncate(64);
}

/// Only exact, still runnable combinations are offered: never silently change a remembered depth or runtime.
fn frequent_combos(mut history: Vec<Value>, options: &[Value], current: &Resolved) -> Vec<Value> {
    history.sort_by(|a, b| b["count"].as_u64().cmp(&a["count"].as_u64())
        .then_with(|| b["last"].as_f64().unwrap_or(0.0).total_cmp(&a["last"].as_f64().unwrap_or(0.0))));
    let mut seen = HashSet::new();
    history.into_iter().filter_map(|v| {
        let entry = option_of(options, v["model"].as_str())?;
        let runtime = v["runtime"].as_str()?;
        if !list(&entry["runtimes"]).iter().any(|r| r == runtime) { return None; }
        let effort = text(v.get("effort"));
        // Preserve a currently pinned account if it supports the model, as newChat.pick does.
        let r = resolve(options, &json!({ "model": entry["model"], "runtime": runtime, "effort": effort, "profile": current.profile }));
        if r.effort != effort { return None; }
        let model = entry["model"].as_str()?;
        if !seen.insert((model.to_string(), runtime.to_string(), effort.clone())) { return None; }
        let depth = effort.as_deref().unwrap_or("默认深度");
        let name = entry["name"].as_str().unwrap_or(model);
        let label = if list(&entry["runtimes"]).len() > 1 {
            format!("{name} · {} · {depth}", crate::format::runtime_label(runtime))
        } else { format!("{name} · {depth}") };
        let selected = current.entry.as_ref().is_some_and(|e| e["model"] == model)
            && current.runtime.as_deref() == Some(runtime) && current.effort == effort;
        Some(json!({ "model": model, "runtime": runtime, "effort": effort, "label": label, "selected": selected }))
    }).take(4).collect()
}

impl Choose {
    pub fn new(host: Rc<dyn Host>, store: Rc<Store>, data: Rc<Data>, views: Rc<Views>, check: Check) -> Rc<Choose> {
        Rc::new(Choose { host, store, data, views, check, watches: RefCell::default(), drafts: RefCell::default(), adding: RefCell::default(), checked: RefCell::default() })
    }

    pub fn handles(topic: &Topic) -> bool {
        matches!(topic, Topic::NewChat { .. } | Topic::Pick { .. })
    }

    pub fn start(&self, topic: &Topic) {
        let sources = match topic {
            Topic::NewChat { scope } => vec![Topic::Stations { scope: scope.clone() }],
            Topic::Pick { station, of: o } => {
                let overview = Topic::Overview { station: station.clone() };
                match of(o) {
                    Ok(Of::Session(key)) => vec![
                        Topic::Session { station: station.clone(), key: key.to_string() },
                        Topic::Sessions { station: station.clone() },
                        Topic::ChatRows { station: station.clone() },
                        overview,
                    ],
                    _ => vec![overview],
                }
            }
            _ => return,
        };
        let watches = sources.iter().map(|source| {
            let (store, target) = (Rc::downgrade(&self.store), topic.clone());
            self.store.watch(source, Rc::new(move || {
                if let Some(store) = store.upgrade() {
                    store.invalidate(&target);
                }
            }))
        });
        let watches: Vec<Watch> = watches.collect();
        self.watches.borrow_mut().insert(topic.clone(), watches);
        self.store.invalidate(topic);
    }

    pub fn stop(&self, topic: &Topic) {
        let watches = self.watches.borrow_mut().remove(topic);
        self.drafts.borrow_mut().remove(topic);
        drop(watches);
    }

    pub fn compute(&self, topic: &Topic) -> Option<Result<Value>> {
        match topic {
            Topic::NewChat { scope } => Some(Ok(self.new_chat(scope))),
            Topic::Pick { station, of } => self.pick(topic, station, of),
            _ => None,
        }
    }

    /// Everything shown from the choices again (one changed).
    fn changed(&self) {
        let live: Vec<Topic> = self.watches.borrow().keys().cloned().collect();
        for topic in live {
            self.store.invalidate(&topic);
        }
    }

    // ── a new chat ──────────────────────────────────────────────────────────

    fn record(&self, key: &str) -> Option<Value> {
        self.data.record(TABLE, key)
    }

    /// What was last picked on a station of a workspace (by its id): `{ runtime, model, effort, profile }`, "" for
    /// none.
    fn choice(&self, scope: &str, id: &str) -> Value {
        self.record(&format!("ws:{scope}:station:{id}")).or_else(|| self.record(&format!("station:{id}"))).unwrap_or_else(|| json!({}))
    }

    fn keep_choice(&self, scope: &str, id: &str, choice: &Value) {
        let kept: Map<String, Value> = FIELDS.iter().map(|f| (f.to_string(), json!(choice[*f].as_str().unwrap_or("")))).collect();
        self.data.put(TABLE, &format!("ws:{scope}:station:{id}"), Value::Object(kept));
    }

    /// The station a scope's last chat was started on (or last picked there), its id. Before workspaces kept their
    /// own: the scope's, else the last in any scope (a station of another is none of this one's, and gives way to
    /// the first up).
    fn kept(&self, scope: &str) -> String {
        self.record(&format!("ws:{scope}:last")).or_else(|| self.record(&format!("scope:{scope}"))).or_else(|| self.record("last"))
            .and_then(|v| v.as_str().map(str::to_string)).unwrap_or_default()
    }

    fn keep_station(&self, scope: &str, id: &str) {
        self.data.put(TABLE, &format!("ws:{scope}:last"), json!(id));
    }

    /// The scope's stations up now (as the `stations` view has them); `Err` while not known, with why when it failed.
    fn online(&self, scope: &str) -> std::result::Result<(Vec<Value>, bool), Option<String>> {
        match self.store.value(&Topic::Stations { scope: scope.to_string() }) {
            None => Err(None),
            Some(Err(error)) => Err(Some(error.message)),
            Some(Ok(all)) => {
                let all = list(&all);
                let any = !all.is_empty();
                Ok((all.into_iter().filter(|s| s["online"] == true).collect(), any))
            }
        }
    }

    fn new_chat(&self, scope: &str) -> Value {
        let kept = self.kept(scope);
        let mut view = json!({ "kept": kept, "any": false, "efforts": [], "accounts": [], "pickAccount": false, "waiting": false, "frequent": [] });
        let (online, any) = match self.online(scope) {
            Ok(found) => found,
            Err(error) => {
                view["error"] = json!(error);
                return view;
            }
        };
        view["any"] = json!(any);
        let station = online.iter().find(|s| s["id"] == kept.as_str()).or(online.first()).cloned();
        view["stations"] = Value::Array(online);
        let Some(station) = station else { return view };
        let id = station["id"].as_str().unwrap_or("");
        let name = station["name"].as_str().unwrap_or("");
        let options = list(&station["models"]);
        let r = resolve(&options, &self.choice(scope, id));
        let history = self.record(&format!("ws:{scope}:frequent")).map(|v| list(&v)).unwrap_or_default();
        view["frequent"] = json!(frequent_combos(history, &options, &r));
        let overview = station.get("overview").filter(|o| o.is_object());
        let profiles = overview.map(|o| list(&o["profiles"])).unwrap_or_default();
        // The model list is what a profile's check found: those not checked since the station started are, now.
        for p in &profiles {
            let pid = p["id"].as_str().unwrap_or("");
            if p.get("check").is_none_or(Value::is_null) && !pid.is_empty() && self.checked.borrow_mut().insert((station["station"].as_str().unwrap_or("").to_string(), pid.to_string())) {
                (self.check)(station["station"].as_str().unwrap_or(""), pid);
            }
        }
        view["waiting"] = json!(overview.is_none());
        view["blocked"] = match overview {
            Some(_) if profiles.is_empty() => json!("profile"),
            Some(_) if options.is_empty() => json!("models"),
            _ => Value::Null,
        };
        view["problem"] = match overview {
            None => json!(format!("正在读取 {name} 的 Profile…")),
            Some(_) if !profiles.is_empty() && options.is_empty() => json!("这台 station 的 Profile 都还没有启用模型。点下面的「去勾选」，勾选可以用的模型。"),
            _ => Value::Null,
        };
        if let Some(entry) = &r.entry {
            if let Some(spent) = entry.get("spent").filter(|s| s.is_object()) {
                let back = text(spent.get("back")).map(|b| format!("，{b}")).unwrap_or_default();
                view["spent"] = json!(format!("{} 能用的账号额度都用完了{back}。现在发的消息要等额度恢复才会有回复；也可以换一个模型。", entry["name"].as_str().unwrap_or("")));
            }
        }
        view["pickAccount"] = json!(r.accounts.len() > 1);
        view["model"] = r.entry.clone().unwrap_or(Value::Null);
        view["runtime"] = json!(r.runtime);
        view["effort"] = json!(r.effort);
        view["profile"] = json!(r.profile);
        view["efforts"] = Value::Array(r.efforts);
        view["accounts"] = Value::Array(r.accounts);
        // Its model control, with the page (its panel's picks: `pick.set`, as the `pick` topic of `new` there).
        let address = station["station"].as_str().unwrap_or("").to_string();
        view["pick"] = self.pick(&Topic::Pick { station: address.clone(), of: "new".into() }, &address, "new").and_then(Result::ok).unwrap_or(Value::Null);
        view["station"] = station;
        view
    }

    /// The models a station offers and what was last picked there, resolved.
    fn on_station(&self, address: &str) -> (Vec<Value>, Resolved) {
        let overview = self.store.get(&Topic::Overview { station: address.to_string() });
        let options = list(&models(overview.as_ref(), self.host.now_ms()));
        let r = resolve(&options, &self.choice(crate::workspace::of_address(address), station_id(address)));
        (options, r)
    }

    /// `newChat.pick`: the station a scope's new chat starts on (`station`, its id), and what it runs there, each
    /// given one only changing it; a model picked keeps its runtime when it runs there (else the first it has), a
    /// runtime changed takes its default depth unless one is given.
    pub fn pick_new(&self, scope: &str, params: &Value) -> Result<()> {
        let station = text(params.get("station"));
        if let Some(id) = &station {
            self.keep_station(scope, id);
        }
        if FIELDS.iter().any(|f| params.get(*f).is_some()) {
            let id = match station {
                Some(id) => id,
                None => {
                    let kept = self.kept(scope);
                    let (online, _) = self.online(scope).map_err(|_| CoreError::invalid("还不知道有哪些 station"))?;
                    let current = online.iter().find(|s| s["id"] == kept.as_str()).or(online.first()).ok_or_else(|| CoreError::invalid("没有在线的 station"))?;
                    current["id"].as_str().unwrap_or("").to_string()
                }
            };
            let (options, now) = self.on_station(&address(scope, &id));
            let mut next = json!({ "runtime": now.runtime, "model": now.entry.as_ref().map(|e| e["model"].clone()), "effort": now.effort, "profile": now.profile });
            if let Some(model) = text(params.get("model")) {
                let runs = option_of(&options, Some(&model)).map(|o| list(&o["runtimes"])).unwrap_or_default();
                if params.get("runtime").is_none() && !runs.iter().any(|r| *r == next["runtime"]) {
                    next["runtime"] = runs.first().cloned().unwrap_or(Value::Null);
                    next["effort"] = Value::Null;
                }
                next["model"] = json!(model);
            }
            if let Some(runtime) = text(params.get("runtime")) {
                if next["runtime"] != runtime.as_str() {
                    next["effort"] = Value::Null;
                }
                next["runtime"] = json!(runtime);
            }
            for field in ["effort", "profile"] {
                if let Some(v) = params.get(field) {
                    next[field] = v.clone();
                }
            }
            self.keep_choice(scope, &id, &next);
        }
        self.changed();
        Ok(())
    }

    /// `newChat.create`: what a new chat on `station` is asked to be made with (`chat.create`), as picked there;
    /// the scope's next new chat starts on it too.
    pub fn create(&self, station: &str) -> Result<Value> {
        let (_, r) = self.on_station(station);
        let (Some(entry), Some(runtime)) = (&r.entry, &r.runtime) else { return Err(CoreError::invalid("先在 Profile 里启用模型")) };
        let mut ask = json!({ "runtime": runtime, "model": entry["model"] });
        if let Some(effort) = &r.effort {
            ask["effort"] = json!(effort);
        }
        if let Some(profile) = &r.profile {
            ask["profile"] = json!(profile);
        }
        let scope = crate::workspace::of_address(station);
        self.keep_station(scope, station_id(station));
        self.changed();
        Ok(ask)
    }

    /// A new chat accepted by the core, rather than merely clicking around its model picker.
    pub fn used(&self, station: &str, choice: &Value) {
        let key = format!("ws:{}:frequent", crate::workspace::of_address(station));
        let mut history = self.record(&key).map(|v| list(&v)).unwrap_or_default();
        record_combo(&mut history, choice, self.host.now_ms());
        self.data.put(TABLE, &key, json!(history));
        self.changed();
    }

    /// `newChat.migrate`: what a client kept before the core did (per station id, and the station per scope), each
    /// taken only where the core keeps nothing yet.
    pub fn migrate(&self, params: &Value) {
        for (id, choice) in params["choices"].as_object().into_iter().flatten() {
            if choice.is_object() && self.record(&format!("station:{id}")).is_none() {
                let kept: Map<String, Value> = FIELDS.iter().map(|f| (f.to_string(), json!(choice[*f].as_str().unwrap_or("")))).collect();
                self.data.put(TABLE, &format!("station:{id}"), Value::Object(kept));
            }
        }
        for (scope, id) in params["lastIn"].as_object().into_iter().flatten() {
            if let (Some(id), None) = (id.as_str(), self.record(&format!("scope:{scope}"))) {
                self.data.put(TABLE, &format!("scope:{scope}"), json!(id));
            }
        }
        if let (Some(id), None) = (text(params.get("last")), self.record("last")) {
            self.data.put(TABLE, "last", json!(id));
        }
        self.changed();
    }

    // ── a model control ─────────────────────────────────────────────────────

    /// What it is picked from, what it runs on now, the account it runs on now (a session's), and whether its runtime
    /// stays and its account is named only when it matters (a new chat's). `None` while not known.
    fn now(&self, station: &str, o: &Of) -> Option<Result<(Vec<Value>, Value, Option<Value>, bool, bool)>> {
        let overview = || self.store.get(&Topic::Overview { station: station.to_string() });
        let now = self.host.now_ms();
        Some(Ok(match o {
            Of::New => {
                let (options, r) = self.on_station(station);
                overview()?;
                (options, r.picked(), None, false, true)
            }
            Of::ConnectNew(form) => {
                let options = list(&models(Some(&overview()?), now));
                let r = resolve(&options, self.adding.borrow().get(&(station.into(), (*form).into())).unwrap_or(&json!({})));
                (options, r.picked(), None, false, false)
            }
            Of::Connect(id) => {
                let overview = overview()?;
                let Some(connect) = overview["connects"].as_array().and_then(|c| c.iter().find(|c| c["id"] == *id)) else {
                    return Some(Err(CoreError::new("http_404", "没有这个连接").with_status(404)));
                };
                let bind = &connect["bind"];
                let options = list(&models(Some(&overview), now)).into_iter().filter(|m| m["runtimes"].as_array().is_some_and(|r| r.contains(&bind["runtime"]))).collect();
                let value = json!({ "model": text(bind.get("model")), "runtime": bind["runtime"], "effort": text(bind.get("effort")), "profile": text(bind.get("profile")) });
                (options, value, None, true, false)
            }
            Of::Session(key) => {
                let agent = self.views.agent(station, key)?;
                let s = &agent["session"];
                let pinned = s["profilePinned"] == true;
                let value = json!({ "model": text(s.get("model")), "runtime": s["runtime"], "effort": text(s.get("effort")), "profile": if pinned { text(s.get("profile")) } else { None } });
                let current = Some(agent["account"].clone()).filter(Value::is_object);
                (list(&agent["choices"]), value, current, true, false)
            }
        }))
    }

    fn pick(&self, topic: &Topic, station: &str, o: &str) -> Option<Result<Value>> {
        let o = match of(o) {
            Ok(o) => o,
            Err(error) => return Some(Err(error)),
        };
        let (options, value, current, fixed, quiet) = match self.now(station, &o)? {
            Ok(now) => now,
            Err(error) => return Some(Err(error)),
        };
        let draft = self.drafts.borrow().get(topic).cloned().unwrap_or_default();
        let picked = |field: &str| text(draft.get(field).or(value.get(field)));
        let (model, runtime, profile_drafted) = (picked("model"), picked("runtime"), picked("profile"));
        let option = option_of(&options, model.as_deref());
        let value_option = option_of(&options, value["model"].as_str());
        let runtimes = option.map(|o| list(&o["runtimes"])).unwrap_or_default();
        let on = if fixed { value["runtime"].clone() } else { runtimes.iter().find(|r| r.as_str() == runtime.as_deref()).or(runtimes.first()).cloned().unwrap_or_else(|| value["runtime"].clone()) };
        let on_name = on.as_str().unwrap_or("");
        let accounts = option.map(|o| list(&o["accounts"][on_name])).unwrap_or_default();
        // With no model yet, a runtime that stays still says how hard it can think.
        let mut efforts = match option {
            Some(o) => list(&o["efforts"][on_name]),
            None if fixed => crate::format::efforts(on_name).iter().map(|e| json!(e)).collect(),
            None => Vec::new(),
        };
        let account = |id: Option<&str>| id.and_then(|id| accounts.iter().find(|a| a["id"] == id));
        let profile = account(profile_drafted.as_deref()).map(|a| a["id"].clone());
        if let Some(levels) = profile.as_ref().and_then(|id| accounts.iter().find(|a| a["id"] == *id)).and_then(|a| a["efforts"].as_array()) {
            efforts = levels.clone();
        }
        let dropped = profile_drafted.is_some() && profile.is_none();
        let effort = picked("effort").filter(|e| efforts.iter().any(|x| x == e.as_str()));
        // The model it has, as it spells it, stays: another spelling of it is not a change.
        let next_model = match option {
            Some(o) if value_option.is_none_or(|v| v["model"] != o["model"]) => o["model"].clone(),
            _ => value["model"].clone(),
        };
        let next = json!({ "model": next_model, "runtime": on, "effort": effort, "profile": profile });
        let changed = FIELDS.iter().any(|f| next[*f] != value[*f]);
        // The account the control names: the one kept to, else the one it runs on now.
        let kept = text(value.get("profile"));
        let shown = kept.as_deref()
            .and_then(|p| value_option.and_then(|o| o["accounts"][value["runtime"].as_str().unwrap_or("")].as_array()?.iter().find(|a| a["id"] == p).cloned()))
            .or_else(|| current.clone());
        let low = shown.as_ref().and_then(|s| quota_line(s.get("quota")).get("level").cloned());
        let names = !quiet || kept.is_some() || low.is_some();
        let account_view = names.then(|| {
            let text = match (&kept, &shown) {
                (Some(p), _) => shown.as_ref().map(|s| s["name"].as_str().unwrap_or(p).to_string()).unwrap_or_else(|| p.clone()),
                (None, Some(s)) => format!("自动 · {}", s["name"].as_str().unwrap_or("")),
                (None, None) => "自动分配".to_string(),
            };
            json!({ "text": text, "auto": kept.is_none(), "level": low, "profile": if quiet { None } else { shown.clone() } })
        });
        let drafted = account(profile.as_ref().and_then(Value::as_str));
        let who = drafted.and_then(|a| a["name"].as_str()).map_or("账号".to_string(), |n| n.split('@').next().unwrap_or(n).to_string());
        let who_level = if dropped { Some(json!("amber")) } else if profile.is_none() && kept.is_none() { low.clone() } else { None };
        let current_name = current.as_ref().and_then(|c| c["name"].as_str()).unwrap_or("").to_string();
        let auto_note = if current.is_some() && kept.is_none() { format!("现在是 {current_name}") } else { "额度用完或登录失效时换一个".to_string() };
        let option_name = option.and_then(|o| o["name"].as_str()).map(str::to_string);

        // Full screen: each property as it was and as it becomes.
        let name_of = |m: Option<&str>| -> Option<String> {
            let m = m?;
            Some(if Some(m) == value["model"].as_str() { stillfail_shapes::model::name(m) } else { option_of(&options, Some(m)).and_then(|o| o["name"].as_str()).unwrap_or(m).to_string() })
        };
        let account_text = |id: Option<&str>| id.map_or("自动分配".to_string(), |id| account(Some(id)).and_then(|a| a["name"].as_str()).unwrap_or(id).to_string());
        let on_current = current.as_ref().is_some_and(|c| accounts.iter().any(|a| a["id"] == c["id"]));
        let moves_off = profile.is_none() && kept.is_none() && model.is_some() && current.is_some() && !on_current;
        let model_name = name_of(model.as_deref());
        let effort_text = effort.clone().unwrap_or_else(|| "默认深度".into());
        let chosen_text = account_text(profile.as_ref().and_then(Value::as_str));
        let was = [
            name_of(value["model"].as_str()).unwrap_or_else(|| "默认模型".into()),
            text(value.get("effort")).unwrap_or_else(|| "默认深度".into()),
            if kept.is_some() { current_name.clone() } else { format!("自动 · {current_name}") },
        ];
        let becomes = [
            model_name.clone().unwrap_or_else(|| "默认模型".into()),
            effort_text.clone(),
            if profile.is_some() { chosen_text.clone() } else if moves_off { "自动（换账号）".into() } else if on_current { format!("自动 · {current_name}") } else { "自动分配".into() },
        ];
        let force = if dropped {
            Some(format!("指定的账号「{}」没有启用 {}，改成了自动分配", account_text(profile_drafted.as_deref()), model_name.clone().unwrap_or_default()))
        } else if moves_off {
            Some(format!("现在的账号「{current_name}」没有启用 {}，会自动换一个启用了的", model_name.clone().unwrap_or_default()))
        } else {
            None
        };
        let save_text = if changed { format!("改成 {} · {effort_text} · {chosen_text}", model_name.clone().unwrap_or_else(|| "默认模型".into())) } else { "不变".into() };
        Some(Ok(json!({
            "options": options.clone(),
            "runtimeFixed": fixed,
            "value": value,
            "valueOption": value_option,
            "account": account_view,
            "draft": { "model": model, "runtime": on, "effort": effort, "profile": profile },
            "option": option.map(|o| o["model"].clone()),
            "runtimes": if !fixed && runtimes.len() > 1 { runtimes.clone() } else { Vec::new() },
            "efforts": efforts,
            "accounts": accounts,
            "dropped": dropped.then(|| format!("指定的账号没有启用 {}，改成了自动分配", option_name.unwrap_or_else(|| next["model"].as_str().unwrap_or("").to_string()))),
            "who": who,
            "whoLevel": who_level,
            "autoNote": auto_note,
            "changed": changed,
            "was": was,
            "becomes": becomes,
            "force": force,
            "modelText": model_name.unwrap_or_else(|| "选一个模型".into()),
            "maker": option.map(|o| o["maker"].clone()),
            "accountText": chosen_text,
            "accountNote": if profile.is_none() { "额度用完或登录失效时换一个" } else { "固定用它" },
            "accountWarn": dropped || moves_off,
            "saveText": save_text,
            "next": next,
        })))
    }

    /// `pick.set`: picks in a control's panel (`model`, `runtime`, `effort`, `profile`; null: the default, the
    /// station's pick). `open`: from what it runs on now again; `clear`: a connect being added starts over too.
    pub fn set(&self, station: &str, o: &str, params: &Value) -> Result<()> {
        let o_parsed = of(o)?;
        let topic = Topic::Pick { station: station.to_string(), of: o.to_string() };
        if params["clear"] == true {
            if let Of::ConnectNew(form) = o_parsed { self.adding.borrow_mut().remove(&(station.into(), form.into())); }
        }
        {
            let mut drafts = self.drafts.borrow_mut();
            if params["open"] == true || params["clear"] == true {
                drafts.remove(&topic);
            }
            let fields: Vec<(&str, &Value)> = FIELDS.iter().filter_map(|f| params.get(*f).map(|v| (*f, v))).collect();
            if !fields.is_empty() {
                let draft = drafts.entry(topic.clone()).or_default();
                for (field, v) in fields {
                    draft.insert(field.to_string(), v.clone());
                }
            }
        }
        // A new chat's page shows its control too.
        self.changed();
        Ok(())
    }

    /// `pick.save`: what the panel picked, made what it runs on (nothing changed: nothing done).
    pub fn save(&self, station: &str, o: &str) -> Result<Saved> {
        let o_parsed = of(o)?;
        let topic = Topic::Pick { station: station.to_string(), of: o.to_string() };
        let view = match self.pick(&topic, station, o) {
            Some(Ok(view)) => view,
            Some(Err(error)) => return Err(error),
            None => return Err(CoreError::invalid("还不知道能选什么")),
        };
        let next = view["next"].clone();
        if view["changed"] != true || view["option"].is_null() {
            self.drafts.borrow_mut().remove(&topic);
            self.store.invalidate(&topic);
            return Ok(Saved::Done(json!({ "saved": false })));
        }
        let text_of = |field: &str| json!(next[field].as_str().unwrap_or(""));
        let saved = match o_parsed {
            Of::New => {
                let scope = crate::workspace::of_address(station);
                self.pick_new(scope, &json!({ "station": station_id(station), "model": next["model"], "runtime": next["runtime"], "effort": text_of("effort"), "profile": text_of("profile") }))?;
                Saved::Done(json!({ "saved": true }))
            }
            Of::ConnectNew(form) => {
                self.adding.borrow_mut().insert((station.into(), form.into()), next.clone());
                Saved::Done(json!({ "saved": true }))
            }
            Of::Session(key) => {
                let params = json!({ "station": station, "key": key, "model": next["model"], "effort": next["effort"], "profile": next["profile"] });
                Saved::Op(crate::ops::request("session.settings", &params).ok_or_else(|| CoreError::invalid("session.settings"))??)
            }
            Of::Connect(id) => {
                let params = json!({ "station": station, "id": id, "input": { "bind": { "model": next["model"], "effort": text_of("effort"), "profile": next["profile"] } } });
                Saved::Op(crate::ops::request("connect.put", &params).ok_or_else(|| CoreError::invalid("connect.put"))??)
            }
        };
        self.drafts.borrow_mut().remove(&topic);
        self.changed();
        Ok(saved)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frequent_combos_rank_usage_break_ties_by_recency_and_never_substitute_unavailable_choices() {
        let options = vec![json!({"model": "astra", "name": "Astra", "ids": ["openai/astra"], "runtimes": ["codex"],
            "efforts": {"codex": ["low", "medium", "high"]}, "accounts": {"codex": []}})];
        let choice = |model: &str, runtime: &str, effort: Option<&str>| json!({"model": model, "runtime": runtime, "effort": effort});
        let medium = choice("astra", "codex", Some("medium"));
        let current = resolve(&options, &medium);
        let mut history = vec![];
        for (at, c) in [medium.clone(), medium.clone(), choice("astra", "codex", None), choice("astra", "codex", Some("high")),
            choice("astra", "codex", Some("ultra")), choice("astra", "claude", Some("medium")), choice("gone", "codex", None)].iter().enumerate() {
            record_combo(&mut history, c, at as f64);
        }
        let combos = frequent_combos(history, &options, &current);
        assert_eq!(combos.len(), 3);
        assert_eq!(combos[0]["label"], "Astra · medium");
        assert_eq!(combos[0]["selected"], true);
        assert_eq!(combos[1]["effort"], "high");
        assert_eq!(combos[2]["label"], "Astra · 默认深度");
        assert_eq!(combos[2]["selected"], false);
    }

    #[test]
    fn frequent_combos_deduplicate_aliases_and_limit_visible_and_stored_history() {
        let mut history = vec![];
        let mut options = vec![];
        for i in 0..70 {
            let model = format!("m{i}");
            record_combo(&mut history, &json!({"model": model, "runtime": "codex"}), i as f64);
            options.push(json!({"model": model, "name": model, "runtimes": ["codex"]}));
        }
        assert_eq!(history.len(), 64);
        let current = resolve(&options, &json!({}));
        assert_eq!(frequent_combos(history, &options, &current).len(), 4);
        let options = vec![json!({"model": "astra", "name": "Astra", "ids": ["openai/astra"], "runtimes": ["codex"]})];
        let mut history = vec![];
        for model in ["astra", "openai/astra"] { record_combo(&mut history, &json!({"model": model, "runtime": "codex"}), 1.0); }
        assert_eq!(frequent_combos(history, &options, &resolve(&options, &json!({}))).len(), 1);
    }

    #[test]
    fn model_efforts_follow_the_account_and_survive_resolving_saved_choices() {
        let overview = json!({"profiles": [
            {"id": "full", "runtimes": ["codex"], "models": ["gpt-6-astra"], "check": {"modelEfforts": {"codex": {"gpt-6-astra": ["low", "medium", "high", "xhigh", "max", "ultra"]}}}},
            {"id": "limited", "runtimes": ["codex"], "models": ["openai/gpt-6-astra"], "check": {"modelEfforts": {"codex": {"openai/gpt-6-astra": ["low", "medium", "high", "xhigh", "max"]}}}}
        ]});
        let options = list(&models(Some(&overview), 0.0));
        let choice = |profile: Value, effort: &str| json!({"runtime": "codex", "model": "gpt-6-astra", "profile": profile, "effort": effort});
        assert_eq!(resolve(&options, &choice(Value::Null, "max")).effort.as_deref(), Some("max"));
        assert_eq!(resolve(&options, &choice(Value::Null, "ultra")).effort, None);
        let pinned = resolve(&options, &choice(json!("full"), "ultra"));
        assert_eq!(pinned.effort.as_deref(), Some("ultra"));
        assert!(!pinned.efforts.contains(&json!("minimal")));
        assert_eq!(resolve(&options, &choice(json!("limited"), "ultra")).effort, None);
        assert_eq!(resolve(&options, &choice(json!("full"), "")).effort, None, "default stays unset");
    }


    #[test]
    fn a_machines_session_is_a_line_its_home_as_tilde() {
        let meta = |cwd: &str, ago_ms: f64| {
            let mut s = json!({ "runtime": "claude", "cwd": cwd, "updatedAt": 1_000_000_000.0 });
            machine_meta(&mut s, 1_000_000_000.0 + ago_ms);
            s["meta"].as_str().unwrap().to_string()
        };
        assert_eq!(meta("/Users/bob/src/x", 3_000.0), "Claude Code · ~/src/x · 刚刚");
        assert_eq!(meta("/home/bob", 12_000.0), "Claude Code · ~ · 12 秒前");
        assert_eq!(meta("/srv/x", 4.0 * 60_000.0), "Claude Code · /srv/x · 4 分钟前");
        assert_eq!(meta("/Users/bob/x", 30.0 * 3_600_000.0), "Claude Code · ~/x · 昨天");
        assert_eq!(meta("/Users/bob/x", 3.0 * 86_400_000.0), "Claude Code · ~/x · 3 天前");
    }

    #[test]
    fn a_quota_in_a_line_names_only_the_window_running_low() {
        let q = |windows: Value| quota_line(Some(&json!({ "state": "ok", "windows": windows })));
        assert_eq!(q(json!([{ "label": "每周", "usedPercent": 10 }, { "label": "5 小时", "usedPercent": 40 }])), json!({ "text": "5 小时 60% · 每周 90%" }));
        assert_eq!(q(json!([{ "label": "每周", "usedPercent": 95 }, { "label": "5 小时", "usedPercent": 75 }])), json!({ "text": "每周只剩 5%", "level": "red" }));
        assert_eq!(quota_line(Some(&json!({ "state": "unavailable", "windows": [], "detail": "读不到" }))), json!({ "text": "读不到" }));
        assert_eq!(quota_line(None), Value::Null);
    }
}
