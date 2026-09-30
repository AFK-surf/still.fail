//! Background jobs and web services as the clients show them: each job's dot, its state in a word and the line under
//! its name (`shown`), a chat's all together (`chat_jobs`, the `chatJobs` view), those left up a long while
//! (`long_jobs`, the `longJobs` view), a job read again while shown and its output's words kept fresh (`Polls`).
//!
//! Jobs are mostly long-running watchers (a CI run followed, a deploy kept an eye on): what matters is whether each is
//! still alive and what it last said (`stillfail-job notify`), not how long it took. Times in words here count in
//! seconds, so what shows them is computed again when the next of them changes (`next_change`), not only each minute.

use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::rc::{Rc, Weak};

use futures::FutureExt;
use serde_json::{Value, json};

use crate::format;
use crate::host::Host;
use crate::present::Clock;
use crate::protocol::Topic;
use crate::station::{StationAddr, Stations, encode};
use crate::store::Store;

/// A job that ended by itself or failed this long ago is no longer news: it stays in the list, out of what matters now.
const NEWS: f64 = 24.0 * 3_600_000.0;
/// Up this long, a service or job is worth a reminder.
pub const LONG: f64 = 3_600_000.0;

fn str_of<'a>(job: &'a Value, field: &str) -> &'a str {
    job.get(field).and_then(Value::as_str).unwrap_or("")
}

fn ms_of(job: &Value, field: &str) -> Option<f64> {
    job.get(field).and_then(Value::as_f64).filter(|n| *n > 0.0)
}

/// A background job comes with `port: null` from the station (not left out), so either means none.
pub fn is_service(job: &Value) -> bool {
    job.get("port").is_some_and(|p| !p.is_null())
}

/// What its dot says: a service up, a job alive, a service restarting, one that died, one that is over.
pub fn tone(job: &Value) -> &'static str {
    match str_of(job, "state") {
        "failed" => "fail",
        "stopped" => "off",
        state if is_service(job) => if state == "running" { "up" } else { "restart" },
        "running" => "live",
        _ => if job.get("exitCode").and_then(Value::as_i64) == Some(0) { "off" } else { "fail" },
    }
}

/// Whether clearing takes it away: over (stopped, failed, ended by itself), not a service being started again.
pub fn is_ended(job: &Value) -> bool {
    matches!(str_of(job, "state"), "stopped" | "failed") || (str_of(job, "state") == "exited" && !is_service(job))
}

/// Whether it matters now: up, alive, restarting, or died lately.
fn is_current(job: &Value, now: f64) -> bool {
    match tone(job) {
        "off" => false,
        "fail" => now - ms_of(job, "endedAt").or(ms_of(job, "startedAt")).unwrap_or(0.0) < NEWS,
        _ => true,
    }
}

/// Died first, then restarting, then up and alive, then what is over.
fn rank(tone: &str) -> u8 {
    match tone {
        "fail" => 0,
        "restart" => 1,
        "off" => 3,
        _ => 2,
    }
}

/// Its state in a word.
fn word(job: &Value) -> &'static str {
    let (tone, state) = (tone(job), str_of(job, "state"));
    if is_service(job) {
        return match tone { "up" => "在线", "restart" => "正在重启", "fail" => "没能启动", _ => "已停止" };
    }
    match tone {
        "live" => "在盯着",
        "fail" => if state == "failed" { "没能启动" } else { "意外退出" },
        _ => if state == "stopped" { "已停止" } else { "已结束" },
    }
}

/// A time span in words: 12 秒, 4 分钟, 3 小时, 2 天.
pub fn span(ms: f64) -> String {
    let s = (ms / 1000.0).round().max(0.0) as i64;
    if s < 60 {
        format!("{s} 秒")
    } else if s < 3600 {
        format!("{} 分钟", s / 60)
    } else if s < 86_400 {
        format!("{} 小时", s / 3600)
    } else {
        format!("{} 天", s / 86_400)
    }
}

/// How long ago: 刚刚, 12 秒前, 4 分钟前, 3 小时前, 昨天, 2 天前.
pub fn ago(at: f64, now: f64) -> String {
    let s = ((now - at) / 1000.0).round() as i64;
    if s < 5 {
        return "刚刚".into();
    }
    if (86_400..2 * 86_400).contains(&s) {
        return "昨天".into();
    }
    format!("{}前", span(now - at))
}

/// How long until `span` (and so `ago`) of a time `ms` ago says something else.
pub fn next_change(ms: f64) -> f64 {
    let s = (ms / 1000.0).round().max(0.0);
    let unit = if s < 60.0 { 1.0 } else if s < 3600.0 { 60.0 } else if s < 86_400.0 { 3600.0 } else { 86_400.0 };
    let next = ((s / unit).floor() + 1.0) * unit;
    ((next - 0.5) * 1000.0 - ms).max(100.0)
}

/// When what `shown` says of a job next changes, from `now`.
fn job_changes(job: &Value, now: f64) -> f64 {
    let mut times: Vec<f64> = ["startedAt", "endedAt", "outputAt"].iter().filter_map(|f| ms_of(job, f)).collect();
    times.extend(job.get("notices").and_then(Value::as_array).into_iter().flatten().filter_map(|n| n.get("at")?.as_f64()));
    let mut next = times.iter().map(|at| next_change(now - at)).fold(f64::INFINITY, f64::min);
    // A failure stops mattering a day after.
    if tone(job) == "fail" {
        let until = ms_of(job, "endedAt").or(ms_of(job, "startedAt")).unwrap_or(0.0) + NEWS - now;
        if until > 0.0 {
            next = next.min(until);
        }
    }
    next
}

/// A job with what the clients show of it put in: its dot, whether it is a service (and open), over, current; its
/// word; the line under its name (`meta`); a detail's head (`detail`); its last output and each notice in words.
pub fn shown(job: &Value, c: Clock) -> Value {
    let mut job = job.clone();
    if !job.is_object() {
        return job;
    }
    let now = c.now;
    let (tone, word, service) = (tone(&job), word(&job), is_service(&job));
    let state = str_of(&job, "state").to_string();
    let started = ms_of(&job, "startedAt").unwrap_or(now);
    let ended = ms_of(&job, "endedAt").map(|at| ago(at, now));
    let said = || json!({ "text": word, "kind": "word" });
    let plain = |text: String| json!({ "text": text });
    let then = |parts: &mut Vec<Value>, text: Option<String>| {
        if let Some(text) = text {
            parts.push(plain(format!(" · {text}")));
        }
    };
    let mut meta = vec![];
    let notices = job.get("notices").and_then(Value::as_array).cloned().unwrap_or_default();
    if service {
        meta.push(said());
        match tone {
            "up" => then(&mut meta, Some(span(now - started))),
            "restart" => then(&mut meta, job.get("restarts").and_then(Value::as_i64).filter(|n| *n > 0).map(|n| format!("第 {n} 次"))),
            _ => then(&mut meta, ended.clone()),
        }
    } else if tone == "live" {
        if let Some(last) = notices.first() {
            meta.push(json!({ "text": str_of(last, "text"), "kind": "notice" }));
            then(&mut meta, Some(ago(last.get("at").and_then(Value::as_f64).unwrap_or(now), now)));
        } else if let Some(at) = ms_of(&job, "outputAt") {
            meta.push(plain(format!("还没通知过 · 最后输出 {}", ago(at, now))));
        } else {
            meta.push(said());
            then(&mut meta, Some(span(now - started)));
        }
    } else if tone == "fail" && state != "failed" {
        meta.push(said());
        then(&mut meta, Some(match job.get("exitCode").and_then(Value::as_i64) {
            Some(code) => format!("退出码 {code}"),
            None => "被信号结束".into(),
        }));
        then(&mut meta, ended.clone());
    } else {
        meta.push(said());
        then(&mut meta, ended.clone());
    }
    let when = if state == "running" { span(now - started) } else { ended.clone().unwrap_or_default() };
    let told = if notices.is_empty() { String::new() } else { format!(" · {} 条通知", notices.len()) };
    job["tone"] = json!(tone);
    job["service"] = json!(service);
    job["open"] = json!(service && matches!(state.as_str(), "running" | "exited"));
    job["ended"] = json!(is_ended(&job));
    job["current"] = json!(is_current(&job, now));
    job["word"] = json!(word);
    job["meta"] = json!(meta);
    job["detail"] = json!(format!("{word} · {when}{told}"));
    job["outputSaid"] = json!(ms_of(&job, "outputAt").map(|at| format!("最后输出 · {}", ago(at, now))));
    job["age"] = json!(span(now - started));
    if let Some(list) = job.get_mut("notices").and_then(Value::as_array_mut) {
        for n in list {
            let at = n.get("at").and_then(Value::as_f64).unwrap_or(now);
            n["ago"] = json!(ago(at, now));
            n["clock"] = json!(format::day_clock(at, now, c.offset_min));
        }
    }
    job
}

/// A chat's services and jobs (its agents' together) as its pages show them (`ChatJobsView`), and in how many ms what
/// it says changes.
pub fn chat_jobs(chat: &Value, c: Clock) -> (Value, f64) {
    let mut jobs: Vec<Value> = chat.get("agents").and_then(Value::as_array).into_iter().flatten()
        .flat_map(|a| a.get("jobs").and_then(Value::as_array).cloned().unwrap_or_default()).collect();
    let next = jobs.iter().map(|j| job_changes(j, c.now)).fold(f64::INFINITY, f64::min);
    jobs.sort_by(|a, b| rank(tone(a)).cmp(&rank(tone(b))).then(ms_of(b, "startedAt").unwrap_or(0.0).total_cmp(&ms_of(a, "startedAt").unwrap_or(0.0))));
    let current: Vec<&Value> = jobs.iter().filter(|j| is_current(j, c.now)).collect();
    let count = |service: bool, t: &str| current.iter().filter(|j| is_service(j) == service && tone(j) == t).count();
    let alarm = if current.iter().any(|j| tone(j) == "fail") {
        Some("fail")
    } else if current.iter().any(|j| tone(j) == "restart") {
        Some("restart")
    } else {
        None
    };
    let services_note = [(count(true, "up"), "在线"), (count(true, "restart"), "在重启")].iter()
        .filter(|(n, _)| *n > 0).map(|(n, what)| format!("{n} 个{what}")).collect::<Vec<_>>().join("，");
    let jobs_note = match count(false, "live") {
        0 => String::new(),
        n => format!("{n} 个在盯着"),
    };
    let ended: Vec<&Value> = jobs.iter().filter(|j| is_ended(j)).collect();
    let mut clear: Vec<String> = vec![];
    for session in ended.iter().map(|j| str_of(j, "session")).filter(|s| !s.is_empty()) {
        if !clear.iter().any(|s| s == session) {
            clear.push(session.to_string());
        }
    }
    let value = json!({
        "alarm": alarm,
        "servicesNote": services_note,
        "jobsNote": jobs_note,
        "current": current.len(),
        "ended": ended.len(),
        "clear": clear,
        "allText": format!("全部 {} 个", jobs.len()),
        "clearText": format!("清掉 {} 个已结束的", ended.len()),
        "hiddenText": format!("另有 {} 个已停止或结束", jobs.len() - current.len()),
        "jobs": jobs.iter().map(|j| shown(j, c)).collect::<Vec<_>>(),
    });
    (value, next)
}

/// Those of the stations' open jobs (each station's `jobs` topic, with its name when there are several) up longer
/// than `LONG`, oldest first, web services and background jobs apart (`LongJobsView`).
pub fn long_jobs(stations: &[(String, Option<String>, Vec<Value>)], c: Clock) -> Value {
    let mut long: Vec<Value> = stations.iter().flat_map(|(address, name, jobs)| {
        jobs.iter().filter(|j| c.now - ms_of(j, "startedAt").unwrap_or(c.now) >= LONG).map(move |j| {
            let mut job = shown(j, c);
            let chat = j.get("chat").filter(|c| c.is_object());
            let title = chat.map(|c| str_of(c, "title")).filter(|t| !t.is_empty()).unwrap_or(if chat.is_some() { "对话" } else { "不在任何对话里" });
            let archived = chat.and_then(|c| c.get("archived")).and_then(Value::as_bool) == Some(true);
            let place: Vec<&str> = [name.as_deref(), Some(title), archived.then_some("已归档")].into_iter().flatten().collect();
            job["station"] = json!(address);
            job["stationName"] = json!(name);
            job["whereText"] = json!(place.join(" · "));
            job
        })
    }).collect();
    long.sort_by(|a, b| ms_of(a, "startedAt").unwrap_or(0.0).total_cmp(&ms_of(b, "startedAt").unwrap_or(0.0)));
    let groups: Vec<Value> = [("services", "开了很久的网页服务", true), ("jobs", "一直在跑的后台任务", false)].iter().filter_map(|(key, head, service)| {
        let list: Vec<&Value> = long.iter().filter(|j| is_service(j) == *service).collect();
        (!list.is_empty()).then(|| json!({ "key": key, "head": format!("{head} · {}", list.len()), "jobs": list }))
    }).collect();
    json!({ "groups": groups })
}

/// A job's output as read, with its last line and when it grew in words put in (`JobLogView`).
pub fn log(value: &mut Value, c: Clock) {
    if !value.is_object() {
        return;
    }
    let last = str_of(value, "text").trim().to_string();
    let at = ms_of(value, "outputAt");
    if !last.is_empty() {
        value["last"] = json!(last);
    }
    if at.is_some() || !last.is_empty() {
        value["said"] = json!(format!("最后输出{}", at.map(|at| format!(" · {}", ago(at, c.now))).unwrap_or_default()));
    }
}

/// A job read again and again while shown (`/jobs/:id`: its events keep it current, but a station too old to say whose
/// it is has none, so it is read every 4 s; else each half minute, in case one was missed). A job's output is followed
/// by its station (station.rs, the `jobLog` topic); here only what it says in words goes out fresh as it changes
/// (`words`).
pub struct Polls {
    host: Rc<dyn Host>,
    store: Weak<Store>,
    stations: Weak<Stations>,
    live: RefCell<HashMap<Topic, u64>>,
    count: Cell<u64>,
}

impl Polls {
    pub fn new(host: Rc<dyn Host>, store: Weak<Store>, stations: Weak<Stations>) -> Rc<Polls> {
        Rc::new(Polls { host, store, stations, live: RefCell::default(), count: Cell::new(0) })
    }

    pub fn owns(topic: &Topic) -> bool {
        matches!(topic, Topic::Job { .. })
    }

    /// A job's output while shown: sent again when what it says of when it last grew, in words, changes.
    pub fn words(self: &Rc<Self>, topic: &Topic) {
        self.count.set(self.count.get() + 1);
        let run = self.count.get();
        self.live.borrow_mut().insert(topic.clone(), run);
        let (this, topic) = (Rc::downgrade(self), topic.clone());
        self.host.spawn(async move {
            let mut said = None;
            loop {
                let Some(me) = this.upgrade() else { return };
                if me.live.borrow().get(&topic) != Some(&run) {
                    return;
                }
                let now = me.host.now_ms();
                let at = me.store.upgrade().and_then(|s| s.get(&topic)).as_ref().and_then(|v| ms_of(v, "outputAt"));
                let words = at.map(|at| ago(at, now));
                if words != said && said.is_some() {
                    if let Some(store) = me.store.upgrade() {
                        store.invalidate(&topic);
                    }
                }
                said = words;
                // Its first value comes from the station; until then, looked for each second.
                let wait = at.map(|at| next_change(now - at)).unwrap_or(1000.0).min(1000.0);
                let sleep = me.host.sleep(wait as u64);
                drop(me);
                sleep.await;
            }
        }.boxed_local());
    }

    pub fn start(self: &Rc<Self>, topic: &Topic) {
        self.count.set(self.count.get() + 1);
        let run = self.count.get();
        self.live.borrow_mut().insert(topic.clone(), run);
        let (this, topic) = (Rc::downgrade(self), topic.clone());
        self.host.spawn(async move {
            // How long until it is read again.
            let mut due = 0.0;
            loop {
                let Some(me) = this.upgrade() else { return };
                if me.live.borrow().get(&topic) != Some(&run) {
                    return;
                }
                if due <= 0.0 {
                    due = me.read(&topic).await;
                    if me.live.borrow().get(&topic) != Some(&run) {
                        return;
                    }
                } else if let Some(store) = me.store.upgrade() {
                    // Not read again yet: what it says in words goes out as it is now.
                    store.invalidate(&topic);
                }
                let value = me.store.upgrade().and_then(|s| s.get(&topic));
                let words = value.as_ref().and_then(|v| ms_of(v, "outputAt")).map(|at| next_change(me.host.now_ms() - at)).unwrap_or(f64::INFINITY);
                let wait = due.min(words).max(100.0);
                let sleep = me.host.sleep(wait as u64);
                drop(me);
                sleep.await;
                due -= wait;
            }
        }.boxed_local());
    }

    pub fn stop(&self, topic: &Topic) {
        self.live.borrow_mut().remove(topic);
    }

    /// Reads the topic once into the store; answers how long until it is read again.
    async fn read(&self, topic: &Topic) -> f64 {
        let (station, path) = match topic {
            Topic::Job { station, id } => (station, format!("/jobs/{}", encode(id))),
            _ => return f64::INFINITY,
        };
        let (Some(stations), Some(store)) = (self.stations.upgrade(), self.store.upgrade()) else { return f64::INFINITY };
        let result = match StationAddr::parse(station) {
            Ok(addr) => stations.request(&addr, "GET", &path, None).await,
            Err(error) => Err(error),
        };
        let every = match &result {
            Ok(job) => if str_of(job, "session").is_empty() { 4000.0 } else { 30_000.0 },
            Err(_) => 4000.0,
        };
        match result {
            Ok(value) => store.set(topic, Ok(value)),
            // A failure only shows while there is nothing better to show.
            Err(error) if store.get(topic).is_none() => store.set(topic, Err(error)),
            Err(_) => {}
        }
        every
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const NOW: f64 = 1_790_467_200_000.0;
    fn c() -> Clock {
        Clock { now: NOW, offset_min: 480 }
    }
    fn job(id: &str, patch: Value) -> Value {
        let mut j = json!({"id": id, "session": "a", "name": id, "state": "running", "port": null, "startedAt": NOW - 3_000.0});
        for (k, v) in patch.as_object().unwrap() {
            j[k] = v.clone();
        }
        j
    }
    fn texts(v: &Value) -> String {
        v["meta"].as_array().unwrap().iter().map(|p| p["text"].as_str().unwrap()).collect()
    }

    #[test]
    fn times_in_words_and_when_they_change() {
        assert_eq!((span(12_000.0), span(4.0 * 60_000.0 + 59_000.0), span(3.0 * 3_600_000.0), span(2.0 * 86_400_000.0)), ("12 秒".into(), "4 分钟".into(), "3 小时".into(), "2 天".into()));
        assert_eq!((ago(NOW - 2_000.0, NOW), ago(NOW - 12_000.0, NOW), ago(NOW - 30.0 * 3_600_000.0, NOW), ago(NOW - 3.0 * 86_400_000.0, NOW)), ("刚刚".into(), "12 秒前".into(), "昨天".into(), "3 天前".into()));
        // 12 s says 13 s half a second on; 4 min 10 s says 5 min 49.5 s on.
        assert_eq!((next_change(12_000.0), next_change(250_000.0)), (500.0, 49_500.0));
    }

    #[test]
    fn a_job_is_shown_by_its_dot_its_word_and_its_line() {
        let live = shown(&job("w", json!({})), c());
        assert_eq!((live["tone"].as_str(), live["word"].as_str(), texts(&live)), (Some("live"), Some("在盯着"), "在盯着 · 3 秒".into()));
        assert_eq!(live["meta"][0]["kind"], "word");
        let said = shown(&job("w", json!({"notices": [{"at": NOW - 60_000.0, "text": "CI 绿了"}], "outputAt": NOW - 1_000.0})), c());
        assert_eq!((texts(&said), said["meta"][0]["kind"].as_str()), ("CI 绿了 · 1 分钟前".into(), Some("notice")));
        assert_eq!((said["notices"][0]["ago"].as_str(), said["notices"][0]["clock"].as_str(), said["detail"].as_str()), (Some("1 分钟前"), Some("07:59"), Some("在盯着 · 3 秒 · 1 条通知")));
        let quiet = shown(&job("w", json!({"outputAt": NOW - 20_000.0})), c());
        assert_eq!((texts(&quiet), quiet["outputSaid"].as_str()), ("还没通知过 · 最后输出 20 秒前".into(), Some("最后输出 · 20 秒前")));
        let died = shown(&job("w", json!({"state": "exited", "exitCode": 2, "endedAt": NOW - 7_200_000.0})), c());
        assert_eq!((died["tone"].as_str(), texts(&died), died["ended"].as_bool(), died["current"].as_bool()), (Some("fail"), "意外退出 · 退出码 2 · 2 小时前".into(), Some(true), Some(true)));
        let old = shown(&job("w", json!({"state": "exited", "endedAt": NOW - 2.0 * NEWS})), c());
        assert_eq!((texts(&old), old["current"].as_bool()), ("意外退出 · 被信号结束 · 2 天前".into(), Some(false)));
        let done = shown(&job("w", json!({"state": "exited", "exitCode": 0, "endedAt": NOW - 10_000.0})), c());
        assert_eq!((done["tone"].as_str(), texts(&done)), (Some("off"), "已结束 · 10 秒前".into()));
        let up = shown(&job("s", json!({"port": 4817, "startedAt": NOW - 7_200_000.0})), c());
        assert_eq!((up["tone"].as_str(), texts(&up), up["open"].as_bool(), up["ended"].as_bool()), (Some("up"), "在线 · 2 小时".into(), Some(true), Some(false)));
        let again = shown(&job("s", json!({"port": 4817, "state": "exited", "restarts": 2})), c());
        assert_eq!((again["tone"].as_str(), texts(&again), again["ended"].as_bool()), (Some("restart"), "正在重启 · 第 2 次".into(), Some(false)));
    }

    #[test]
    fn a_chats_jobs_put_what_matters_first_and_say_how_many() {
        let chat = json!({"agents": [
            {"jobs": [job("old", json!({"state": "stopped", "startedAt": NOW - 90_000.0, "endedAt": NOW - 80_000.0})), job("w", json!({}))]},
            {"jobs": [job("s", json!({"session": "b", "port": 1, "startedAt": NOW - 5_000.0})), job("r", json!({"session": "b", "port": 2, "state": "exited"})), job("x", json!({"session": "b", "state": "failed", "endedAt": NOW - 1_000.0}))]},
        ]});
        let (v, next) = chat_jobs(&chat, c());
        let ids: Vec<&str> = v["jobs"].as_array().unwrap().iter().map(|j| j["id"].as_str().unwrap()).collect();
        assert_eq!(ids, ["x", "r", "w", "s", "old"]);
        assert_eq!((v["alarm"].as_str(), v["servicesNote"].as_str(), v["jobsNote"].as_str()), (Some("fail"), Some("1 个在线，1 个在重启"), Some("1 个在盯着")));
        assert_eq!((v["current"].as_u64(), v["ended"].as_u64(), v["clear"].clone()), (Some(4), Some(2), json!(["b", "a"])));
        assert_eq!((v["allText"].as_str(), v["clearText"].as_str(), v["hiddenText"].as_str()), (Some("全部 5 个"), Some("清掉 2 个已结束的"), Some("另有 1 个已停止或结束")));
        // Seconds count: it is computed again within a second.
        assert!(next <= 1000.0);
        let (none, next) = chat_jobs(&json!({"agents": []}), c());
        assert_eq!((none["alarm"].clone(), none["jobs"].clone(), next), (Value::Null, json!([]), f64::INFINITY));
    }

    #[test]
    fn those_up_long_are_grouped_oldest_first_with_where_they_are() {
        let st = |name: Option<&str>, jobs: Vec<Value>| ("w/s1".to_string(), name.map(str::to_string), jobs);
        let v = long_jobs(&[
            st(Some("studio"), vec![
                job("new", json!({"startedAt": NOW - 60_000.0})),
                job("j2", json!({"startedAt": NOW - 2.0 * LONG, "chat": {"id": "7", "title": "修登录", "archived": true}})),
                job("j1", json!({"startedAt": NOW - 3.0 * LONG, "chat": {"id": "8", "title": "", "archived": false}})),
            ]),
            st(None, vec![job("s", json!({"port": 1, "startedAt": NOW - LONG}))]),
        ], c());
        let g = &v["groups"];
        assert_eq!((g[0]["key"].as_str(), g[0]["head"].as_str(), g[0]["jobs"][0]["whereText"].as_str()), (Some("services"), Some("开了很久的网页服务 · 1"), Some("不在任何对话里")));
        assert_eq!((g[1]["head"].as_str(), g[1]["jobs"][0]["id"].as_str(), g[1]["jobs"][0]["whereText"].as_str(), g[1]["jobs"][0]["age"].as_str()), (Some("一直在跑的后台任务 · 2"), Some("j1"), Some("studio · 对话"), Some("3 小时")));
        assert_eq!(g[1]["jobs"][1]["whereText"], "studio · 修登录 · 已归档");
        assert_eq!(long_jobs(&[st(None, vec![job("new", json!({}))])], c()), json!({"groups": []}));
    }

    #[test]
    fn a_logs_last_line_and_when() {
        let mut v = json!({"text": "a\nbuilt ok\n", "outputAt": NOW - 3_000.0, "state": "running"});
        log(&mut v, c());
        assert_eq!((v["last"].as_str(), v["said"].as_str()), (Some("a\nbuilt ok"), Some("最后输出 · 刚刚")));
        let mut empty = json!({"text": ""});
        log(&mut empty, c());
        assert_eq!((empty.get("last"), empty.get("said")), (None, None));
    }
}
