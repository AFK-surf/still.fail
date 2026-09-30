//! Words and marks the clients show, decided here once (they draw them; they do not work them out): numbers, times
//! and durations in words, day headings, a thread's name, an agent's label, a model's maker, a runtime's efforts, a
//! connect's state. Times are the viewer's local ones: `offset_min` is their UTC offset at that moment (Host).

use std::collections::HashMap;
use serde_json::{Value, json};

const MINUTE: f64 = 60_000.0;
const DAY: f64 = 86_400_000.0;

/// 950, 1.2K, 3.4M.
pub fn compact_number(n: f64) -> String {
    let cut = |v: f64, unit: &str| {
        let s = format!("{v:.1}");
        format!("{}{unit}", s.strip_suffix(".0").unwrap_or(&s))
    };
    if n >= 1_000_000.0 {
        cut(n / 1_000_000.0, "M")
    } else if n >= 1000.0 {
        cut(n / 1000.0, "K")
    } else {
        format!("{}", n.round() as i64)
    }
}

/// 850ms, 12 秒, 3 分 5 秒, 2 小时 4 分.
pub fn duration(ms: f64) -> String {
    if ms < 1000.0 {
        return format!("{}ms", ms.round() as i64);
    }
    let s = (ms / 1000.0).round() as i64;
    if s < 60 {
        return format!("{s} 秒");
    }
    let m = s / 60;
    if m < 60 { format!("{m} 分 {} 秒", s % 60) } else { format!("{} 小时 {} 分", m / 60, m % 60) }
}

/// A local time's parts: (year, month 1–12, day, weekday 0 = Sunday, hour, minute).
pub(crate) fn local(ms: f64, offset_min: i32) -> (i64, u32, u32, u32, u32, u32) {
    let local = ms + offset_min as f64 * MINUTE;
    let days = (local / DAY).floor() as i64;
    let in_day = (local - days as f64 * DAY) as i64 / 60_000;
    // Civil from days (Howard Hinnant's algorithm).
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    let y = yoe + era * 400 + i64::from(m <= 2);
    let weekday = (days + 4).rem_euclid(7) as u32;
    (y, m, d, weekday, (in_day / 60) as u32, (in_day % 60) as u32)
}

fn local_day(ms: f64, offset_min: i32) -> i64 {
    ((ms + offset_min as f64 * MINUTE) / DAY).floor() as i64
}

/// 14:05, local.
pub fn clock(ms: f64, offset_min: i32) -> String {
    let (_, _, _, _, h, m) = local(ms, offset_min);
    format!("{h:02}:{m:02}")
}

/// 14:05 today, 9/27 14:05 before: when a job said something.
pub fn day_clock(ms: f64, now: f64, offset_min: i32) -> String {
    let (_, month, day, _, _, _) = local(ms, offset_min);
    let time = clock(ms, offset_min);
    if local_day(ms, offset_min) == local_day(now, offset_min) { time } else { format!("{month}/{day} {time}") }
}

/// 刚刚, 3 分钟前, 5 小时前, 昨天 14:05, 9月20日 14:05.
pub fn relative_time(ms: f64, now: f64, offset_min: i32) -> String {
    let seconds = ((now - ms) / 1000.0).round();
    if seconds < 45.0 {
        return "刚刚".into();
    }
    let minutes = (seconds / 60.0).round();
    if minutes < 60.0 {
        return format!("{minutes} 分钟前");
    }
    let hours = (minutes / 60.0).round();
    if hours < 24.0 {
        return format!("{hours} 小时前");
    }
    let (_, month, day, _, _, _) = local(ms, offset_min);
    let time = clock(ms, offset_min);
    if hours < 48.0 { format!("昨天 {time}") } else { format!("{month}月{day}日 {time}") }
}

/// 9/20 14:05:09, local: a time in full, for a tip.
pub fn absolute_time(ms: f64, offset_min: i32) -> String {
    let (_, month, day, _, h, m) = local(ms, offset_min);
    let s = ((ms / 1000.0).floor() as i64).rem_euclid(60);
    format!("{month}/{day} {h:02}:{m:02}:{s:02}")
}

/// 1 分钟内, 40 分钟后, 3 小时后, 2 天后.
pub fn time_until(ms: f64, now: f64) -> String {
    let minutes = ((ms - now) / MINUTE).round().max(0.0);
    if minutes < 60.0 {
        return if minutes <= 1.0 { "1 分钟内".into() } else { format!("{minutes} 分钟后") };
    }
    let hours = (minutes / 60.0).round();
    if hours < 48.0 { format!("{hours} 小时后") } else { format!("{} 天后", (hours / 24.0).round()) }
}

/// When a quota window refills, in words: 马上刷新, 40 分钟后刷新, 3 小时 5 分钟后刷新, 2 天 4 小时后刷新.
pub fn refills_in(ms: f64, now: f64) -> String {
    let minutes = ((ms - now) / MINUTE).round() as i64;
    if minutes <= 0 {
        return "马上刷新".into();
    }
    if minutes < 60 {
        return format!("{minutes} 分钟后刷新");
    }
    let hours = minutes / 60;
    if hours < 24 {
        let rest = if minutes % 60 > 0 { format!(" {} 分钟", minutes % 60) } else { String::new() };
        return format!("{hours} 小时{rest}后刷新");
    }
    let rest = if hours % 24 > 0 { format!(" {} 小时", hours % 24) } else { String::new() };
    format!("{} 天{rest}后刷新", hours / 24)
}

/// A quota window marked by its length (5H five hours, W a week, M a month, 3D), and where it goes among the others.
pub fn window_mark(label: &str) -> (String, u8) {
    if label.starts_with("每月") {
        return ("M".into(), 3);
    }
    if label.starts_with("每周") {
        return ("W".into(), 2);
    }
    let lead = |unit: &str| label.split_once(unit).map(|(n, _)| n).filter(|n| !n.is_empty() && n.chars().all(|c| c.is_ascii_digit())).map(str::to_string);
    if let Some(n) = lead(" 小时") {
        return (format!("{n}H"), 0);
    }
    match lead(" 天") {
        Some(n) => (format!("{n}D"), 1),
        None => (label.to_string(), 1),
    }
}

/// Bytes in gigabytes, one decimal below 100: 7.5 GB, 512 GB.
pub fn gb1(bytes: f64) -> String {
    let g = bytes / 1024f64.powi(3);
    if bytes >= 100.0 * 1024f64.powi(3) { format!("{} GB", g.round() as i64) } else { format!("{g:.1} GB") }
}

/// Bytes as whole gigabytes: 32 GB.
pub fn gb(bytes: f64) -> String {
    format!("{} GB", (bytes / 1024f64.powi(3)).round() as i64)
}

/// A day's heading: 今天, 昨天, 星期三 (this week), 9月20日.
pub fn day_label(ms: f64, now: f64, offset_min: i32) -> String {
    let diff = local_day(now, offset_min) - local_day(ms, offset_min);
    if diff == 0 {
        return "今天".into();
    }
    if diff == 1 {
        return "昨天".into();
    }
    let (_, month, day, weekday, _, _) = local(ms, offset_min);
    if diff < 7 {
        return ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"][weekday as usize].into();
    }
    format!("{month}月{day}日")
}

/// Slack mentions and spacing out, for a title.
pub fn clean_text(text: &str) -> String {
    let mut out = String::new();
    let mut rest = text;
    while let Some(at) = rest.find("<@") {
        out.push_str(&rest[..at]);
        let tail = &rest[at + 2..];
        let id = tail.find(|c: char| !(c.is_ascii_uppercase() || c.is_ascii_digit())).unwrap_or(tail.len());
        if id > 0 && tail[id..].starts_with('>') {
            rest = &tail[id + 1..];
        } else {
            out.push_str("<@");
            rest = tail;
        }
    }
    out.push_str(rest);
    out.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// A thread named for people: where (its channel by name, 私信, or an ember chat's title) and when it began.
pub fn thread_name(threads: &[Value], channel: &str, thread_ts: &str, offset_min: i32) -> (String, String) {
    let started = thread_ts.parse::<f64>().unwrap_or(0.0) * 1000.0;
    let (_, month, day, _, _, _) = local(started, offset_min);
    let when = format!("{month}月{day}日 {}", clock(started, offset_min));
    let thread = threads.iter().find(|t| t.get("channel").and_then(Value::as_str) == Some(channel) && t.get("threadTs").and_then(Value::as_str) == Some(thread_ts));
    let text = |k: &str| thread.and_then(|t| t.get(k)).and_then(Value::as_str).unwrap_or("");
    let where_ = if channel == "EMBER" {
        let title = text("title");
        if !title.is_empty() {
            title.to_string()
        } else {
            let first = clean_text(text("firstText"));
            if first.is_empty() { "still.fail 对话".into() } else { first }
        }
    } else if channel.starts_with('D') {
        "私信".into()
    } else {
        let name = text("channelName");
        format!("#{}", if name.is_empty() { channel } else { name })
    };
    (where_, when)
}

/// "C0OPS/1727.0001" → its channel and thread.
pub fn split_thread(address: &str) -> Option<(&str, &str)> {
    let (channel, ts) = address.split_once('/')?;
    let valid = !channel.is_empty() && channel.chars().all(|c| c.is_ascii_uppercase() || c.is_ascii_digit())
        && ts.split_once('.').is_some_and(|(a, b)| !a.is_empty() && !b.is_empty() && a.chars().chain(b.chars()).all(|c| c.is_ascii_digit()));
    valid.then_some((channel, ts))
}

/// A thread address as a place in a client: `{ name, surface: ember | slack, session? }` (an ember chat opens its
/// agent's page), or null for anything else.
/// A Slack workspace as the station's connects know it: its name, and its address while a connect is signed in there.
#[derive(Debug, Clone, Default)]
pub struct SlackWorkspace {
    pub name: String,
    pub url: Option<String>,
}

/// A thread a history entry came from or went to: its name, where it is, and the way there. A Slack thread is named
/// with its workspace (`Cue#ops`) and links to itself in Slack; an ember chat opens its agent's page.
pub fn place(threads: &[Value], address: &str, offset_min: i32, workspaces: &HashMap<String, SlackWorkspace>) -> Value {
    let Some((channel, ts)) = split_thread(address) else { return Value::Null };
    let (name, _) = thread_name(threads, channel, ts, offset_min);
    let thread = threads.iter().find(|t| t.get("channel").and_then(Value::as_str) == Some(channel) && t.get("threadTs").and_then(Value::as_str) == Some(ts));
    let session = thread.and_then(|t| t.get("sessions")?.as_array()?.first()?.get("session")?.as_str().map(str::to_string));
    if channel == "EMBER" {
        return json!({ "name": name, "surface": "ember", "session": session });
    }
    // Its workspace, by the thread's surface ("slack:<team id>").
    let team = thread.and_then(|t| t.get("surface")?.as_str()?.strip_prefix("slack:")).and_then(|id| workspaces.get(id));
    let named = match team.map(|w| w.name.as_str()).filter(|n| !n.is_empty()) {
        Some(team) if name.starts_with('#') => format!("{team}{name}"),
        Some(team) => format!("{team} {name}"),
        None => name,
    };
    let url = team.and_then(|w| w.url.as_deref()).map(|u| format!("{}/archives/{channel}/p{}", u.trim_end_matches('/'), ts.replace('.', "")));
    json!({ "name": named, "surface": "slack", "session": session, "url": url })
}

/// Who made a model, by its name: `(id, name)` for its mark (anthropic, openai, deepseek, qwen, zhipu, gemini, kimi,
/// minimax, xai); None when the marks do not know it.
pub fn maker_of(model: &str) -> Option<(&'static str, &'static str)> {
    let m = model.to_lowercase();
    let has = |words: &[&str]| words.iter().any(|w| m.contains(w));
    let o_series = m.strip_prefix('o').is_some_and(|rest| rest.starts_with(|c: char| c.is_ascii_digit()));
    Some(if has(&["claude", "opus", "sonnet", "haiku", "fable"]) {
        ("anthropic", "Anthropic")
    } else if has(&["gpt", "codex", "openai"]) || o_series {
        ("openai", "OpenAI")
    } else if has(&["deepseek"]) {
        ("deepseek", "DeepSeek")
    } else if has(&["qwen", "qwq"]) {
        ("qwen", "Qwen")
    } else if has(&["glm", "zhipu"]) {
        ("zhipu", "智谱")
    } else if has(&["gemini", "gemma"]) {
        ("gemini", "Google")
    } else if has(&["kimi", "moonshot"]) {
        ("kimi", "Kimi")
    } else if has(&["minimax", "abab"]) {
        ("minimax", "MiniMax")
    } else if has(&["grok"]) {
        ("xai", "xAI")
    } else {
        return None;
    })
}

/// How an agent is named: it has no name, only its model as people call it and its effort (GPT-6 Astra · medium).
pub fn agent_label(model: Option<&str>, effort: Option<&str>) -> String {
    let model = model.filter(|m| !m.is_empty()).map_or_else(|| "默认模型".to_string(), stillfail_shapes::model::name);
    match effort.filter(|e| !e.is_empty()) {
        Some(effort) => format!("{model} · {effort}"),
        None => model.to_string(),
    }
}

/// How hard a runtime's models can think, lowest first.
pub fn efforts(runtime: &str) -> &'static [&'static str] {
    match runtime {
        "codex" => &["minimal", "low", "medium", "high", "xhigh"],
        _ => &["low", "medium", "high", "xhigh", "max"],
    }
}

pub fn runtime_label(runtime: &str) -> &'static str {
    if runtime == "codex" { "Codex" } else { "Claude Code" }
}

/// A connect's link to Slack in words, and its dot: `(text, presence)` with presence online | busy | error | offline.
pub fn connection(state: &Value) -> (&'static str, &'static str) {
    match state.get("state").and_then(Value::as_str).unwrap_or("") {
        "connected" => ("在线", "online"),
        "reconnecting" => ("重连中", "busy"),
        "starting" => ("连接中", "busy"),
        "error" => ("连接失败", "error"),
        "no_tokens" => ("未连接 Slack", "offline"),
        "disabled" => ("已停用", "offline"),
        _ => ("未连接 Slack", "offline"),
    }
}

/// How a connect's conversations become sessions, in words: its line, and its short form.
pub fn mode_text(mode: &str, require_mention: bool) -> (&'static str, &'static str) {
    match (mode, require_mention) {
        ("multi-session", _) => ("多会话", "多会话"),
        (_, true) => ("单会话 · @ 唤醒", "单会话"),
        (_, false) => ("单会话 · 全部消息", "单会话"),
    }
}

/// A status in words, and its tone (accent, green, blue, red, neutral).
pub fn status_text(status: &str) -> (&'static str, &'static str) {
    match status {
        "running" => ("进行中", "accent"),
        "queued" => ("排队中", "accent"),
        "final" => ("已完成", "green"),
        "block" => ("Block", "blue"),
        "failed" => ("失败", "red"),
        "unexpected" => ("意外停止", "red"),
        "aborted" => ("已停止", "neutral"),
        _ => ("未开始", "neutral"),
    }
}

/// A profile's last check in words, and its tone.
pub fn check_text(check: &Value) -> (&'static str, &'static str) {
    match check.get("state").and_then(Value::as_str) {
        None => ("未检查", "neutral"),
        Some("ok") => ("可用", "green"),
        Some("login") => ("需要登录", "amber"),
        Some("failed") => ("不可用", "red"),
        Some(_) => ("无法检查", "neutral"),
    }
}

/// A process's state in words.
pub fn process_text(process: &str) -> &'static str {
    match process {
        "running" => "运行中",
        "warm" => "保温中",
        _ => "已释放",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn words_as_the_clients_had_them() {
        assert_eq!(compact_number(950.0), "950");
        assert_eq!(compact_number(1200.0), "1.2K");
        assert_eq!(compact_number(70_600.0), "70.6K");
        assert_eq!(compact_number(3_000_000.0), "3M");
        assert_eq!(duration(850.0), "850ms");
        assert_eq!(duration(185_000.0), "3 分 5 秒");
        // 2026-09-27 00:00 UTC, in UTC+8.
        let now = 1_790_467_200_000.0;
        assert_eq!(relative_time(now - 10_000.0, now, 480), "刚刚");
        assert_eq!(relative_time(now - 3.0 * MINUTE, now, 480), "3 分钟前");
        assert_eq!(relative_time(now - 30.0 * 60.0 * MINUTE, now, 480), "昨天 02:00");
        assert_eq!(day_label(now, now, 480), "今天");
        assert_eq!(day_label(now - DAY, now, 480), "昨天");
        assert_eq!(day_label(now - 20.0 * DAY, now, 480), "9月7日");
        assert_eq!(time_until(now + 3.0 * 60.0 * MINUTE, now), "3 小时后");
        assert_eq!(clock(now, 480), "08:00");
        assert_eq!(maker_of("gpt-6-astra"), Some(("openai", "OpenAI")));
        assert_eq!(maker_of("deepseek-flash"), Some(("deepseek", "DeepSeek")));
        assert_eq!(maker_of("o3"), Some(("openai", "OpenAI")));
        assert_eq!(maker_of("something"), None);
        assert_eq!(agent_label(Some("gpt-6-astra"), Some("medium")), "GPT-6 Astra · medium");
        assert_eq!(agent_label(Some("my-model"), None), "my-model");
        assert_eq!(clean_text("<@U1> hi   there"), "hi there");
        assert_eq!(split_thread("C0OPS/1727.0001"), Some(("C0OPS", "1727.0001")));
        assert_eq!(split_thread("nope"), None);
    }
}
