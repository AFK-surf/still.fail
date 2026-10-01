//! What the agents spent (`Topic::Usage`): every online station's `StationUsage` (its calls added up by day, thread,
//! person, profile and model, priced at the providers' API prices) put together for a scope's last 7 or 30 days, as the
//! usage page shows it: a few totals, each day's cost split by who it was for, and who, which chats, which accounts and
//! which models spent the most.

use std::collections::{BTreeMap, HashMap};

use serde_json::{Value, json};

use super::Views;
use crate::error::{CoreError, Result};
use crate::protocol::Topic;

const DAY_MS: i64 = 86_400_000;
/// How many people the days are split by; the rest are 其他.
const SERIES: usize = 4;

/// A station's usage as read, for the view.
pub(super) struct Source {
    pub address: String,
    pub name: String,
    pub online: bool,
    pub value: Option<std::result::Result<Value, CoreError>>,
}

impl Views {
    pub(super) fn usage(&self, scope: &str, days: u32) -> Option<Result<Value>> {
        let stations = match self.stations(scope)? {
            Ok(stations) => stations,
            Err(error) => return Some(Err(error)),
        };
        let sources: Vec<Source> = stations
            .iter()
            .map(|s| Source {
                address: s.address.clone(),
                name: s.name.clone(),
                online: s.online,
                value: if s.online { self.store.value(&Topic::StationUsage { station: s.address.clone() }) } else { None },
            })
            .collect();
        let members: Vec<Value> = self.ok(Topic::Workspace { workspace: scope.to_string() }).and_then(|w| w.get("members").and_then(Value::as_array).cloned()).unwrap_or_default();
        let now = self.host.now_ms();
        let offset = self.host.utc_offset_min(now) as i64;
        Some(Ok(usage_view(&sources, days, now as i64, offset, &self.me(scope), &members)))
    }
}

/// `YYYY-MM-DD` of a moment, on a clock `offset` minutes east of UTC.
fn local_day(ms: i64, offset: i64) -> String {
    let days = (ms + offset * 60_000).div_euclid(DAY_MS);
    // Howard Hinnant's civil_from_days.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!("{y:04}-{m:02}-{d:02}")
}

/// 10/1 for 2026-10-01.
fn day_label(day: &str) -> String {
    let part = |r: std::ops::Range<usize>| day.get(r).and_then(|s| s.parse::<u32>().ok()).unwrap_or(0);
    format!("{}/{}", part(5..7), part(8..10))
}

/// Dollars: $1,911 · $191 · $12.34 · $0.42 · <$0.01.
pub fn money(dollars: f64) -> String {
    if dollars <= 0.0 {
        return "$0".into();
    }
    if dollars < 0.01 {
        return "<$0.01".into();
    }
    if dollars < 100.0 {
        return format!("${dollars:.2}");
    }
    format!("${}", grouped(dollars.round() as i64))
}

/// 1,234,567.
fn grouped(n: i64) -> String {
    let digits = n.abs().to_string();
    let mut out = String::new();
    for (i, c) in digits.chars().enumerate() {
        if i > 0 && (digits.len() - i) % 3 == 0 {
            out.push(',');
        }
        out.push(c);
    }
    if n < 0 { format!("-{out}") } else { out }
}

/// A count as people read it here: 9,850 · 2.9 万 · 1715 万 · 49.1 亿.
pub fn count(n: f64) -> String {
    let cut = |v: f64, unit: &str| {
        let s = if v >= 100.0 { format!("{v:.0}") } else { format!("{v:.1}") };
        format!("{} {unit}", s.strip_suffix(".0").unwrap_or(&s))
    };
    if n >= 1e8 {
        cut(n / 1e8, "亿")
    } else if n >= 1e4 {
        cut(n / 1e4, "万")
    } else {
        grouped(n.round() as i64)
    }
}

fn percent(part: f64, whole: f64) -> String {
    if whole <= 0.0 {
        return "0%".into();
    }
    let p = part / whole * 100.0;
    if p > 0.0 && p < 1.0 { "<1%".into() } else { format!("{p:.0}%") }
}

#[derive(Default, Clone)]
struct Sum {
    cost: f64,
    calls: f64,
    input: f64,
    cache_read: f64,
    cache_write: f64,
    output: f64,
    /// Calls of a model with no price: not in `cost`.
    unpriced: f64,
}

impl Sum {
    fn add(&mut self, row: &Value) {
        let n = |k: &str| row.get(k).and_then(Value::as_f64).unwrap_or(0.0);
        let calls = n("calls");
        match row.get("cost").and_then(Value::as_f64) {
            Some(cost) => self.cost += cost,
            None => self.unpriced += calls,
        }
        self.calls += calls;
        self.input += n("input");
        self.cache_read += n("cacheRead");
        self.cache_write += n("cacheWrite");
        self.output += n("output");
    }

    fn cost_text(&self) -> String {
        if self.unpriced > 0.0 && self.unpriced >= self.calls {
            "未计价".into()
        } else if self.unpriced > 0.0 {
            format!("≥{}", money(self.cost))
        } else {
            money(self.cost)
        }
    }

    fn tokens(&self) -> f64 {
        self.input + self.cache_read + self.cache_write + self.output
    }
}

/// One line of a list: what it is, and what it spent.
struct Item {
    key: String,
    title: String,
    sub: Option<String>,
    extra: Value,
    sum: Sum,
}

fn items_shown(mut items: Vec<Item>, total: &Sum) -> Vec<Value> {
    items.sort_by(|a, b| b.sum.cost.total_cmp(&a.sum.cost).then(b.sum.calls.total_cmp(&a.sum.calls)).then(a.title.cmp(&b.title)));
    // Shares of the cost; of the calls where nothing was priced.
    let by_cost = total.cost > 0.0;
    items
        .into_iter()
        .map(|i| {
            let share = if by_cost { i.sum.cost / total.cost } else if total.calls > 0.0 { i.sum.calls / total.calls } else { 0.0 };
            let mut v = json!({
                "key": i.key,
                "title": i.title,
                "sub": i.sub,
                "cost": i.sum.cost,
                "costText": i.sum.cost_text(),
                "share": share,
                "shareText": percent(share, 1.0),
                "calls": i.sum.calls,
                "detail": format!("{} 次调用 · {} token", count(i.sum.calls), count(i.sum.tokens())),
            });
            if let (Some(v), Some(extra)) = (v.as_object_mut(), i.extra.as_object()) {
                v.extend(extra.clone());
            }
            v
        })
        .collect()
}

/// Keep stations separate: versions can have different tables, and an older station cannot tell us its rates.
fn price_tables(sources: &[Source], first: &str, last: &str) -> Vec<Value> {
    sources.iter().map(|s| {
        let table = s.value.as_ref().and_then(|v| v.as_ref().ok()).and_then(|v| v.get("prices"));
        let note = if !s.online { "station 离线，无法读取价目" } else if table.is_none() {
            "station 尚未提供价目表，请更新 station 后查看"
        } else { table.and_then(|t| t.get("note")).and_then(Value::as_str).unwrap_or("美元 / 100 万 token") };
        let used: std::collections::BTreeSet<String> = s.value.as_ref().and_then(|v| v.as_ref().ok())
            .and_then(|v| v.get("rows")).and_then(Value::as_array).into_iter().flatten()
            .filter(|r| r.get("day").and_then(Value::as_str).is_some_and(|d| d >= first && d <= last)
                && r.get("calls").and_then(Value::as_f64).unwrap_or(0.0) > 0.0)
            .map(|r| r.get("model").and_then(Value::as_str).map(stillfail_shapes::model::key).unwrap_or_else(|| "未知模型".into())).collect();
        let prices = table.and_then(|t| t.get("rows")).and_then(Value::as_array);
        let matched: Vec<_> = used.iter().map(|model| {
            let rate = prices.into_iter().flatten().find(|p| p.get("model").and_then(Value::as_str).is_some_and(|key|
                model == key || model.strip_prefix(key).is_some_and(|suffix| suffix.starts_with('['))));
            (model, rate)
        }).collect();
        // Every row has the same columns; cache-write columns appear only when a counted model uses them.
        let columns: Vec<_> = [("input", "输入"), ("cacheRead", "缓存读取"), ("cacheWrite", "缓存写入 / 5 分钟"), ("cacheWriteLong", "缓存写入 / 1 小时"), ("output", "输出")]
            .into_iter().filter(|(key, _)| !key.starts_with("cacheWrite") || matched.iter().any(|(_, p)| p.and_then(|p| p.get(*key)).and_then(Value::as_f64).is_some())).collect();
        let rows: Vec<Value> = if s.online { matched.iter().map(|(model, r)| {
            let rates: Vec<Value> = columns.iter().map(|(key, label)| json!({"label": label,
                "value": r.and_then(|r| r.get(*key)).and_then(Value::as_f64).map(|n| format!("${n}")).unwrap_or_else(|| "—".into())})).collect();
            json!({"model": if r.is_some() { (*model).clone() } else { format!("{model}（未计价）") }, "rates": rates})
        }).collect() } else { vec![] };
        json!({"station": s.name, "note": note, "rows": rows})
    }).collect()
}

/// The view (see the module): `days` local days to `now`, the viewer `me` among the workspace's `members`.
pub(super) fn usage_view(sources: &[Source], days: u32, now: i64, offset: i64, me: &Value, members: &[Value]) -> Value {
    let days = days.clamp(1, 30);
    let day_list: Vec<String> = (0..days as i64).rev().map(|i| local_day(now - i * DAY_MS, offset)).collect();
    let first = day_list[0].clone();
    let several = sources.iter().filter(|s| s.online).count() > 1;
    let (mut loading, mut reading, mut notes) = (false, false, Vec::<String>::new());
    let mut since: Option<f64> = None;
    let mut total = Sum::default();
    let mut by_day: BTreeMap<String, (Sum, HashMap<String, f64>)> = day_list.iter().map(|d| (d.clone(), Default::default())).collect();
    let (mut people, mut chats, mut profiles, mut models): (HashMap<String, Item>, HashMap<String, Item>, HashMap<String, Item>, HashMap<String, Item>) = Default::default();
    for s in sources {
        if !s.online {
            notes.push(format!("{} 离线，它的用量没算进来", s.name));
            continue;
        }
        let value = match &s.value {
            None => {
                loading = true;
                continue;
            }
            Some(Err(e)) if e.status == Some(404) => {
                notes.push(format!("{} 的 station 还没更新到记用量的版本", s.name));
                continue;
            }
            Some(Err(e)) => {
                notes.push(format!("{}：{}", s.name, e.message));
                continue;
            }
            Some(Ok(value)) => value,
        };
        reading |= value.get("reading").and_then(Value::as_bool) == Some(true);
        if let Some(at) = value.get("since").and_then(Value::as_f64) {
            since = Some(since.map_or(at, |s: f64| s.min(at)));
        }
        let place = several.then(|| s.name.clone());
        let threads = value.get("threads").cloned().unwrap_or(Value::Null);
        let station_people = value.get("people").cloned().unwrap_or(Value::Null);
        let station_profiles = value.get("profiles").cloned().unwrap_or(Value::Null);
        for row in value.get("rows").and_then(Value::as_array).into_iter().flatten() {
            let day = row.get("day").and_then(Value::as_str).unwrap_or("");
            let Some((day_sum, day_people)) = by_day.get_mut(day) else { continue };
            day_sum.add(row);
            total.add(row);
            let text = |k: &str| row.get(k).and_then(Value::as_str).map(str::to_string);

            // Who it was for: one person however they wrote (Slack or the page), by their email.
            let reference = text("person");
            let known_person = reference.as_ref().and_then(|r| station_people.get(r)).filter(|p| p.is_object());
            let mut person = known_person.cloned().unwrap_or_else(|| json!({ "id": reference.clone().unwrap_or_default(), "name": "说不清是谁", "email": null }));
            crate::present::person(&mut person, me, members);
            let person_key = person.get("email").and_then(Value::as_str).or_else(|| person.get("id").and_then(Value::as_str)).unwrap_or("").to_ascii_lowercase();
            let name = person["shown"]["display"].as_str().unwrap_or("").to_string();
            let cost = row.get("cost").and_then(Value::as_f64).unwrap_or(0.0);
            *day_people.entry(person_key.clone()).or_default() += cost;
            // An unknown person still has a total and label, but no Creator: the display fallback above is not
            // a complete identity (in particular it has no `via`), and Android decodes the whole view strictly.
            people.entry(person_key.clone()).or_insert_with(|| Item { key: person_key.clone(), title: name, sub: None, extra: json!({ "person": known_person.map(|_| person) }), sum: Sum::default() }).sum.add(row);

            // Where: its chat (a Slack thread too), named as the station names it.
            let session = text("session").unwrap_or_default();
            let thread = row.get("thread").and_then(Value::as_u64);
            let chat_key = format!("{}/{}", s.address, thread.map(|t| t.to_string()).unwrap_or_else(|| session.clone()));
            chats
                .entry(chat_key.clone())
                .or_insert_with(|| {
                    let known = thread.and_then(|t| threads.get(t.to_string()));
                    let title = known.and_then(|t| t.get("title")).and_then(Value::as_str).map(str::to_string).unwrap_or_else(|| "已删除的对话".into());
                    let archived = known.and_then(|t| t.get("archived")).and_then(Value::as_bool) == Some(true);
                    let slack = known.and_then(|t| t.get("surface")).and_then(Value::as_str).is_some_and(|s| s != "ember");
                    let sub: Vec<String> = place.iter().cloned().chain(slack.then(|| "Slack".to_string())).chain(archived.then(|| "已归档".to_string())).collect();
                    // Its page: an ember chat by its thread; a Slack thread by its agent's own chat.
                    let page = match (known, slack) {
                        (Some(_), false) => json!({ "station": s.address, "thread": thread }),
                        (Some(t), true) if t.get("home").is_some_and(|h| !h.is_null()) => json!({ "station": s.address, "session": t["home"] }),
                        (_, _) if !session.is_empty() && known.is_some() => json!({ "station": s.address, "session": session }),
                        _ => Value::Null,
                    };
                    Item { key: chat_key.clone(), title, sub: (!sub.is_empty()).then(|| sub.join(" · ")), extra: json!({ "chat": page }), sum: Sum::default() }
                })
                .sum
                .add(row);

            // On what: the station's profile (account), and the model.
            let profile = text("profile").unwrap_or_default();
            let profile_key = format!("{}/{profile}", s.address);
            profiles
                .entry(profile_key.clone())
                .or_insert_with(|| {
                    let name = station_profiles.get(&profile).and_then(|p| p.get("name")).and_then(Value::as_str).filter(|n| !n.is_empty()).map(str::to_string);
                    let title = name.unwrap_or_else(|| if profile.is_empty() { "说不清是哪个账号".into() } else { format!("{profile}（已删除）") });
                    Item { key: profile_key.clone(), title, sub: place.clone(), extra: json!({}), sum: Sum::default() }
                })
                .sum
                .add(row);
            // One model however its profiles spell it.
            let model = text("model").unwrap_or_default();
            models
                .entry(stillfail_shapes::model::key(&model))
                .or_insert_with(|| {
                    let title = if model.is_empty() { "说不清是哪个模型".into() } else { stillfail_shapes::model::name(&model) };
                    let priced = row.get("cost").is_some_and(|c| !c.is_null());
                    Item { key: stillfail_shapes::model::key(&model), title, sub: (!priced).then(|| "没有价目，不计费用".to_string()), extra: json!({}), sum: Sum::default() }
                })
                .sum
                .add(row);
        }
    }

    // The days split by the people who spent most; the rest together.
    let mut ranked: Vec<(&String, &Item)> = people.iter().collect();
    ranked.sort_by(|a, b| b.1.sum.cost.total_cmp(&a.1.sum.cost).then(a.1.title.cmp(&b.1.title)));
    let top: Vec<(String, String)> = ranked.iter().take(if ranked.len() > SERIES + 1 { SERIES } else { SERIES + 1 }).map(|(k, i)| ((*k).clone(), i.title.clone())).collect();
    let rest = ranked.len() > top.len();
    let mut series: Vec<Value> = top.iter().map(|(key, name)| json!({ "key": key, "name": name })).collect();
    if rest {
        series.push(json!({ "key": "", "name": "其他" }));
    }
    let today = local_day(now, offset);
    let daily: Vec<Value> = by_day
        .iter()
        .map(|(day, (sum, split))| {
            let mut parts: Vec<f64> = top.iter().map(|(k, _)| split.get(k).copied().unwrap_or(0.0)).collect();
            if rest {
                parts.push(split.iter().filter(|(k, _)| !top.iter().any(|(t, _)| t == *k)).map(|(_, v)| v).sum());
            }
            json!({ "day": day, "label": day_label(day), "today": *day == today, "cost": sum.cost, "costText": sum.cost_text(), "calls": sum.calls, "callsText": format!("{} 次调用", count(sum.calls)), "partsText": parts.iter().map(|p| money(*p)).collect::<Vec<_>>(), "parts": parts })
        })
        .collect();
    let max = by_day.values().map(|(s, _)| s.cost).fold(0.0, f64::max);

    let input = total.input + total.cache_read + total.cache_write;
    let tiles = json!([
        { "label": "折合费用", "value": total.cost_text(), "sub": "按 API 标准单价估算" },
        { "label": "模型调用", "value": format!("{} 次", count(total.calls)), "sub": format!("日均 {} 次", count(total.calls / days as f64)) },
        { "label": "输入 token", "value": count(input), "sub": format!("缓存命中 {}", percent(total.cache_read, input)) },
        { "label": "输出 token", "value": count(total.output), "sub": format!("平均每次 {}", count(if total.calls > 0.0 { total.output / total.calls } else { 0.0 })) },
    ]);
    let lists = json!([
        { "key": "people", "title": "按人", "items": items_shown(people.into_values().collect(), &total) },
        { "key": "chats", "title": "按对话", "items": items_shown(chats.into_values().collect(), &total) },
        { "key": "profiles", "title": "按账号", "items": items_shown(profiles.into_values().collect(), &total) },
        { "key": "models", "title": "按模型", "items": items_shown(models.into_values().collect(), &total) },
    ]);
    if reading {
        notes.insert(0, "正在读取以前的记录，数字还会变".into());
    }
    if let Some(at) = since.filter(|at| local_day(*at as i64, offset) > first) {
        let day = local_day(at as i64, offset);
        notes.push(format!("{} 日起才有记录", day_label(&day).replace('/', " 月 ")));
    }
    if total.unpriced > 0.0 {
        notes.push(format!("{} 次调用的模型没有价目，没算进费用", count(total.unpriced)));
    }
    json!({
        "days": days,
        "prices": price_tables(sources, &first, &today),
        "loading": loading,
        "empty": total.calls == 0.0,
        "tiles": tiles,
        "series": series,
        "daily": daily,
        "max": max,
        "lists": lists,
        "notes": notes,
        "basis": "订阅账号不按 token 收费；费用按 API 标准单价估算，不含长上下文和服务等级等加价",
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(day: &str, person: &str, thread: u64, profile: &str, model: &str, calls: i64, cost: Option<f64>) -> Value {
        json!({ "day": day, "session": "ember:c-1", "thread": thread, "person": person, "profile": profile, "runtime": "claude", "model": model,
                "calls": calls, "input": 10 * calls, "cacheRead": 90 * calls, "cacheWrite": 0, "output": calls, "cost": cost })
    }

    fn station(rows: Vec<Value>) -> Value {
        json!({
            "since": 0, "reading": false, "rows": rows,
            "threads": { "7": { "title": "修登录", "surface": "ember", "home": "ember:c-1", "archived": false }, "8": { "title": "#ops", "surface": "slack:T1", "home": "ember:c-2", "archived": true } },
            "people": { "a@x": { "id": "a@x", "name": "a@x", "email": "a@x", "via": "cloud" }, "slack:ds:U1": { "id": "slack:ds:U1", "name": "阿一", "email": "a@x", "via": "slack" }, "b@x": { "id": "b@x", "name": "b@x", "email": "b@x", "via": "cloud" } },
            "profiles": { "cc": { "name": "公司账号", "runtime": "claude" } },
        })
    }

    // 2026-10-02T04:00Z: 12:00 on the 2nd in UTC+8.
    const NOW: i64 = 1_790_913_600_000;

    #[test]
    fn days_split_by_who_and_lists_ranked_by_cost() {
        assert_eq!(local_day(NOW, 480), "2026-10-02");
        let rows = vec![
            row("2026-10-02", "a@x", 7, "cc", "claude-opus-5-5", 10, Some(3.0)),
            // The same person through Slack, in a Slack thread.
            row("2026-10-02", "slack:ds:U1", 8, "cc", "claude-opus-5-5", 5, Some(1.0)),
            row("2026-10-01", "b@x", 7, "gone", "gpt-6", 4, None),
            // Out of the 7 days.
            row("2026-09-20", "b@x", 7, "cc", "claude-opus-5-5", 100, Some(100.0)),
        ];
        let sources = [Source { address: "ws/st".into(), name: "studio".into(), online: true, value: Some(Ok(station(rows))) }];
        let members = [json!({ "email": "a@x", "name": "阿一", "picture": "https://p/a" })];
        let v = usage_view(&sources, 7, NOW, 480, &json!({ "id": "b@x", "email": "b@x" }), &members);
        assert_eq!(v["tiles"][0]["value"], "≥$4.00");
        assert_eq!(v["tiles"][1]["value"], "19 次");
        let daily = v["daily"].as_array().unwrap();
        assert_eq!((daily.len(), daily[6]["label"].as_str(), daily[6]["today"].as_bool()), (7, Some("10/2"), Some(true)));
        assert_eq!(v["series"], json!([{ "key": "a@x", "name": "阿一" }, { "key": "b@x", "name": "你" }]));
        assert_eq!(daily[6]["parts"], json!([4.0, 0.0]));
        let list = |k: usize| v["lists"][k]["items"].as_array().unwrap().clone();
        let people = list(0);
        assert_eq!((people[0]["title"].as_str(), people[0]["shareText"].as_str(), people[0]["person"]["shown"]["picture"].as_str()), (Some("阿一"), Some("100%"), Some("https://p/a")));
        let chats = list(1);
        assert_eq!((chats[0]["title"].as_str(), chats[0]["chat"].clone()), (Some("修登录"), json!({ "station": "ws/st", "thread": 7 })));
        assert_eq!((chats[1]["sub"].as_str(), chats[1]["chat"].clone()), (Some("Slack · 已归档"), json!({ "station": "ws/st", "session": "ember:c-2" })));
        let profiles = list(2);
        assert_eq!((profiles[0]["title"].as_str(), profiles[1]["title"].as_str()), (Some("公司账号"), Some("gone（已删除）")));
        let models = list(3);
        assert_eq!((models[0]["title"].as_str(), models[1]["sub"].as_str()), (Some("Opus 5.5"), Some("没有价目，不计费用")));
        assert_eq!(v["notes"], json!(["4 次调用的模型没有价目，没算进费用"]));
    }

    #[test]
    fn price_tables_keep_station_rates_separate_and_handle_older_stations() {
        let source = |name: &str, rate: f64| Source { address: name.into(), name: name.into(), online: true,
            value: Some(Ok(json!({"rows": [{"day": "2026-10-02", "model": "gpt-6-astra", "calls": 1}], "prices": {"note": "standard", "rows": [{"model": "gpt-6-astra", "input": rate, "cacheRead": 0.01, "output": 50.0}]}}))) };
        let tables = price_tables(&[source("alpha", 10.0), source("beta", 12.0), Source { address: "old".into(), name: "old".into(), online: true, value: Some(Ok(json!({}))) }], "2026-09-26", "2026-10-02");
        assert_eq!(tables[0]["rows"][0]["rates"][0]["value"], "$10");
        assert_eq!(tables[1]["rows"][0]["rates"][0]["value"], "$12");
        assert_eq!(tables[0]["rows"][0]["rates"][1]["value"], "$0.01");
        assert_eq!(tables[2]["rows"], json!([]));
        assert!(tables[2]["note"].as_str().unwrap().contains("更新 station"));
    }

    #[test]
    fn price_table_only_lists_counted_models_in_the_selected_period() {
        let sources = [Source { address: "st".into(), name: "st".into(), online: true, value: Some(Ok(json!({
            "rows": [
                {"day": "2026-10-02", "model": "openai/gpt-6-astra", "calls": 2},
                {"day": "2026-10-01", "model": "gpt-6-astra", "calls": 3},
                {"day": "2026-09-10", "model": "claude-opus-5-5", "calls": 1},
                {"day": "2026-10-02", "model": "gpt-6-sol", "calls": 0},
                {"day": "2026-10-02", "model": "new-model", "calls": 1}
            ],
            "prices": {"rows": [
                {"model": "gpt-6-astra", "input": 10.0, "cacheRead": 1.0, "output": 50.0},
                {"model": "claude-opus-5-5", "input": 4.0, "cacheWrite": 5.0},
                {"model": "gpt-6-sol", "input": 2.0}
            ]}
        }))) }];
        let short = price_tables(&sources, "2026-09-26", "2026-10-02");
        assert_eq!(short[0]["rows"].as_array().unwrap().len(), 2);
        assert_eq!(short[0]["rows"][0]["model"], "gpt-6-astra");
        assert_eq!(short[0]["rows"][0]["rates"].as_array().unwrap().len(), 3);
        assert_eq!(short[0]["rows"][1]["model"], "new-model（未计价）");
        let long = price_tables(&sources, "2026-09-03", "2026-10-02");
        assert_eq!(long[0]["rows"].as_array().unwrap().len(), 3);
        assert_eq!(long[0]["rows"][0]["rates"].as_array().unwrap().len(), 4);
    }

    #[test]
    fn unknown_prices_are_not_shown_as_zero_and_tokens_stay_counted() {
        let sources = [Source { address: "ws/st".into(), name: "studio".into(), online: true,
            value: Some(Ok(station(vec![row("2026-10-02", "a@x", 7, "cc", "unknown-model", 2, None)]))) }];
        let v = usage_view(&sources, 7, NOW, 480, &json!({}), &[]);
        assert_eq!(v["tiles"][0]["value"], "未计价");
        assert_eq!(v["tiles"][1]["value"], "2 次");
        assert_eq!(v["daily"][6]["costText"], "未计价");
        assert_eq!(v["daily"][0]["costText"], "$0");
        for list in v["lists"].as_array().unwrap() {
            assert_eq!(list["items"][0]["costText"], "未计价");
            assert_eq!(list["items"][0]["detail"], "2 次调用 · 202 token");
        }
        serde_json::from_value::<stillfail_shapes::UsageView>(v).unwrap();
    }

    #[test]
    fn unknown_people_keep_their_usage_and_the_view_decodes() {
        for reference in [Value::Null, json!("missing@x")] {
            let mut unknown = row("2026-10-02", "", 7, "cc", "gpt-6", 2, Some(3.0));
            unknown["person"] = reference;
            let sources = [Source {
                address: "ws/st".into(), name: "studio".into(), online: true,
                value: Some(Ok(station(vec![unknown, row("2026-10-02", "a@x", 7, "cc", "gpt-6", 1, Some(1.0))]))),
            }];
            let v = usage_view(&sources, 7, NOW, 480, &json!({}), &[]);
            // Decode the actual output with the same contract that generates Android's UsageView/Creator.
            let decoded: stillfail_shapes::UsageView = serde_json::from_value(v).expect("usage view must match the clients' shapes");
            let people = &decoded.lists[0].items;
            assert_eq!(decoded.tiles[0].value, "$4.00");
            assert_eq!(decoded.tiles[1].value, "3 次");
            assert_eq!(people[0].title, "说不清是谁");
            assert!(people[0].person.is_none());
            assert_eq!(people[0].cost, 3.0);
            assert_eq!(people[1].person.as_ref().unwrap().via, "cloud");
        }
    }

    #[test]
    fn stations_that_cannot_say_are_noted_and_one_not_read_yet_is_loading() {
        let sources = [
            Source { address: "ws/a".into(), name: "alpha".into(), online: true, value: None },
            Source { address: "ws/b".into(), name: "beta".into(), online: true, value: Some(Err(CoreError::new("http_404", "no").with_status(404))) },
            Source { address: "ws/c".into(), name: "gamma".into(), online: false, value: None },
        ];
        let v = usage_view(&sources, 30, NOW, 0, &json!({}), &[]);
        assert_eq!((v["loading"].as_bool(), v["empty"].as_bool(), v["daily"].as_array().unwrap().len()), (Some(true), Some(true), 30));
        assert_eq!(v["notes"], json!(["beta 的 station 还没更新到记用量的版本", "gamma 离线，它的用量没算进来"]));
    }

    #[test]
    fn numbers_read_as_people_say_them() {
        assert_eq!((money(1911.16), money(191.4), money(12.346), money(0.004), money(0.0)), ("$1,911".into(), "$191".into(), "$12.35".into(), "<$0.01".into(), "$0".into()));
        assert_eq!((count(9850.0), count(29_443.0), count(17_146_455.0), count(4_914_110_860.0)), ("9,850".into(), "2.9 万".into(), "1715 万".into(), "49.1 亿".into()));
    }
}
