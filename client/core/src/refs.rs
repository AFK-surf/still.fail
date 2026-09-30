//! References to other chats in what is written, and finding chats by a few words (the `chatSearch` view: the
//! composer's `@` menu and ⌘K's switcher). In the composer a reference is a short mark, `@[its title]`; sent, a link,
//! `[its title](its page)`, which the agent reads the chat by. The link of each title picked (`chat.ref`) is kept on
//! the device, the latest 200 of each workspace, and a mark is made its link as it is sent (`chat.send`) in a chat of
//! the same workspace; one whose link is gone, or is another workspace's, stays as written.

use serde_json::{Value, json};

use crate::data::Data;

/// The records the links are kept in, `links:<workspace>`: `[[title, link], …]`, the latest last. `links` is where
/// every workspace's were kept before; each is read only for the workspace its link is in.
const TABLE: &str = "chat_ref";
const KEY: &str = "links";
const KEPT: usize = 200;
/// Characters of a title a reference shows.
const TITLE: usize = 24;
/// The longest title a mark holds (web/src/chatRefs.ts, REF_MARK).
const MARK_MAX: usize = 120;

/// A chat's title, as a reference shows it: its start, on one line.
pub fn title(title: &str) -> String {
    let plain: String = title.chars().map(|c| if matches!(c, '[' | ']' | '\n') { ' ' } else { c }).collect();
    let words = plain.split_whitespace().collect::<Vec<_>>().join(" ");
    let chars: Vec<char> = words.chars().collect();
    let shown = if chars.len() > TITLE { format!("{}…", chars[..TITLE].iter().collect::<String>().trim_end()) } else { words };
    if shown.is_empty() { "对话".into() } else { shown }
}

/// A chat's page: under `base` (the page's own root, or still.fail cloud), its station's pages, then the chat.
pub fn link(base: &str, station: &str, id: &str) -> String {
    let under = match station.split_once('/') {
        Some((workspace, station)) => format!("/w/{workspace}/s/{station}"),
        None => String::new(),
    };
    format!("{}{under}/chats/{}", base.trim_end_matches('/'), crate::core::encode(id))
}

/// The workspace a chat's link (as [`link`] makes it) is in: `/w/<workspace>/s/…`, else a station's own page's.
fn workspace_of(link: &str) -> String {
    let parts: Vec<&str> = link.split('/').collect();
    parts.windows(3).find(|w| w[0] == "w" && w[2] == "s").map(|w| w[1].to_string()).unwrap_or_else(|| crate::workspace::LOCAL.to_string())
}

fn record(data: &Data, key: &str) -> Vec<(String, String)> {
    let kept = data.record(TABLE, key).unwrap_or(Value::Null);
    kept.as_array().into_iter().flatten().filter_map(|pair| Some((pair.get(0)?.as_str()?.to_string(), pair.get(1)?.as_str()?.to_string()))).collect()
}

/// A workspace's links: those kept before workspaces kept their own (of it only), then its own, the latest last.
fn links(data: &Data, workspace: &str) -> Vec<(String, String)> {
    let mut all: Vec<(String, String)> = record(data, KEY).into_iter().filter(|(_, l)| workspace_of(l) == workspace).collect();
    all.extend(record(data, &format!("{KEY}:{workspace}")));
    all
}

/// Keeps these links (title, link), each with its workspace's, the latest, the oldest going past 200.
pub fn keep(data: &Data, added: impl IntoIterator<Item = (String, String)>) {
    let mut by: std::collections::BTreeMap<String, Vec<(String, String)>> = Default::default();
    for (title, link) in added {
        if title.is_empty() || link.is_empty() {
            continue;
        }
        let workspace = workspace_of(&link);
        let all = by.entry(workspace.clone()).or_insert_with(|| record(data, &format!("{KEY}:{workspace}")));
        all.retain(|(t, _)| *t != title);
        all.push((title, link));
    }
    for (workspace, all) in by {
        let from = all.len().saturating_sub(KEPT);
        data.put(TABLE, &format!("{KEY}:{workspace}"), json!(all[from..].iter().map(|(t, l)| json!([t, l])).collect::<Vec<_>>()));
    }
}

/// The mark for a chat picked, its link kept until the mark is sent.
pub fn mark(data: &Data, base: &str, station: &str, id: &str, full_title: &str) -> String {
    let title = title(full_title);
    keep(data, [(title.clone(), link(base, station, id))]);
    format!("@[{title}]")
}

/// What is written in a chat on `station`, its marks made links to chats of its workspace (one whose link is gone
/// stays as written).
pub fn expand(data: &Data, station: &str, text: &str) -> String {
    if !text.contains("@[") {
        return text.to_string();
    }
    let all = links(data, crate::workspace::of_address(station));
    let mut out = String::new();
    let mut rest = text;
    while let Some(at) = rest.find("@[") {
        out.push_str(&rest[..at]);
        let after = &rest[at + 2..];
        // `@[`, 1 to 120 characters with no `]` or line break, `]`.
        let title = after.find([']', '\n']).filter(|end| after[*end..].starts_with(']')).map(|end| &after[..end]);
        match title.filter(|t| !t.is_empty() && t.chars().count() <= MARK_MAX) {
            Some(title) => {
                match all.iter().rev().find(|(t, _)| t == title) {
                    Some((_, link)) => out.push_str(&format!("[{title}]({link})")),
                    None => out.push_str(&format!("@[{title}]")),
                }
                rest = &after[title.len() + 1..];
            }
            None => {
                out.push_str("@[");
                rest = after;
            }
        }
    }
    out.push_str(rest);
    out
}

/// What `query` finds among a `chats` view's rows (as the sidebar lists them): chats made (not those still being
/// made), on `station` if given, not `exclude` (the chat written in, by id or agent); those whose title has the words
/// first, then those whose agent, station, origin or last message has them; `limit` at most.
pub fn search(chats: &Value, query: &str, station: Option<&str>, exclude: Option<&str>, limit: Option<u32>) -> Value {
    let q = query.trim().to_lowercase();
    let has = |v: &Value| v.as_str().is_some_and(|s| s.to_lowercase().contains(&q));
    let rows = chats.get("days").and_then(Value::as_array).into_iter().flatten().flat_map(|d| d.get("items").and_then(Value::as_array).into_iter().flatten());
    let candidates: Vec<&Value> = rows
        .filter(|i| i.get("pending").and_then(Value::as_bool) != Some(true))
        .filter(|i| station.is_none_or(|s| i.get("station").and_then(Value::as_str) == Some(s)))
        .filter(|i| exclude.is_none_or(|x| ["id", "session"].iter().all(|f| i.get(*f).and_then(Value::as_str) != Some(x))))
        .collect();
    let titled = candidates.iter().filter(|i| q.is_empty() || has(&i["title"]));
    let rest = candidates.iter().filter(|i| {
        !q.is_empty() && !has(&i["title"])
            && (i.get("agents").and_then(Value::as_array).into_iter().flatten().any(|a| has(&a["agentText"]))
                || has(&i["stationName"]) || has(&i["originText"]) || i.get("last").is_some_and(|l| has(&l["preview"])))
    });
    let items: Vec<Value> = titled.chain(rest).take(limit.map_or(usize::MAX, |l| l as usize)).map(|i| (*i).clone()).collect();
    json!({ "items": items })
}

/// The chat a draft's key names, as the pages key them: `new:<station>` a new chat there, else `<station>:<chat>`.
pub fn draft_at(key: &str) -> Option<(String, String)> {
    if let Some(station) = key.strip_prefix("new:") {
        return (!station.is_empty()).then(|| (station.to_string(), "new".to_string()));
    }
    let (station, chat) = key.split_once(':')?;
    (!station.is_empty() && !chat.is_empty()).then(|| (station.to_string(), chat.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::{FakeHost, run};

    #[test]
    fn a_reference_shows_the_start_of_the_title_on_one_line() {
        assert_eq!(title("修一下 [登录]\n  的问题"), "修一下 登录 的问题");
        assert_eq!(title("一二三四五六七八九十一二三四五六七八九十一二三 四五"), "一二三四五六七八九十一二三四五六七八九十一二三…");
        assert_eq!(title(" \n "), "对话");
        assert_eq!(link("https://app.still.fail/", "ws/st", "a b/c"), "https://app.still.fail/w/ws/s/st/chats/a%20b%2Fc");
        assert_eq!(link("/admin", "local", "k1"), "/admin/chats/k1");
        assert_eq!(draft_at("new:ws/st"), Some(("ws/st".into(), "new".into())));
        assert_eq!(draft_at("local:thread:7"), Some(("local".into(), "thread:7".into())));
        assert_eq!(draft_at("nothing"), None);
    }

    #[test]
    fn marks_go_out_as_links_while_their_link_is_kept() {
        run(async {
            let data = Data::new(FakeHost::new());
            assert_eq!(mark(&data, "https://x", "ws/st", "k1", "排查登录"), "@[排查登录]");
            assert_eq!(mark(&data, "https://x", "ws/st", "k2", "看看"), "@[看看]");
            // The same title again: the latest link.
            mark(&data, "https://x", "ws/st", "k3", "看看");
            assert_eq!(expand(&data, "ws/st", "见 @[排查登录] 和 @[看看]，@[没有] @[ 不完整 @"), "见 [排查登录](https://x/w/ws/s/st/chats/k1) 和 [看看](https://x/w/ws/s/st/chats/k3)，@[没有] @[ 不完整 @");
            keep(&data, (0..KEPT).map(|i| (format!("t{i}"), format!("https://x/w/ws/s/st/chats/l{i}"))));
            assert_eq!(expand(&data, "ws/other", "@[排查登录] @[t0]"), "@[排查登录] [t0](https://x/w/ws/s/st/chats/l0)", "the oldest go past 200");
        });
    }

    #[test]
    fn a_mark_is_a_link_only_in_a_chat_of_its_workspace() {
        run(async {
            let data = Data::new(FakeHost::new());
            // Kept before workspaces kept their own: each read for its own workspace only.
            data.put(TABLE, KEY, json!([["旧的", "https://x/w/w1/s/st/chats/k0"], ["本机", "/admin/chats/k9"]]));
            mark(&data, "https://x", "w1/st", "k1", "排查登录");
            mark(&data, "https://x", "w2/st", "k2", "看看");
            let text = "@[排查登录] @[看看] @[旧的] @[本机]";
            assert_eq!(expand(&data, "w1/st", text), "[排查登录](https://x/w/w1/s/st/chats/k1) @[看看] [旧的](https://x/w/w1/s/st/chats/k0) @[本机]");
            assert_eq!(expand(&data, "w2/a", text), "@[排查登录] [看看](https://x/w/w2/s/st/chats/k2) @[旧的] @[本机]");
            assert_eq!(expand(&data, "local", text), "@[排查登录] @[看看] @[旧的] [本机](/admin/chats/k9)");
        });
    }

    #[test]
    fn a_search_finds_titles_first_then_what_else_a_chat_says() {
        let item = |id: &str, title: &str, station: &str, preview: &str| json!({ "id": id, "session": format!("s{id}"), "title": title, "station": station, "stationName": "Studio", "agents": [], "last": { "preview": preview } });
        let mut pending = item("p", "登录 新的", "a", "");
        pending["pending"] = json!(true);
        let chats = json!({ "days": [
            { "items": [item("1", "别的", "a", "修登录"), item("2", "登录页", "a", ""), pending] },
            { "items": [item("3", "登录", "b", ""), item("4", "登录 旧的", "a", "")] },
        ] });
        let ids = |v: Value| v["items"].as_array().unwrap().iter().map(|i| i["id"].as_str().unwrap().to_string()).collect::<Vec<_>>();
        assert_eq!(ids(search(&chats, " 登录 ", None, None, None)), ["2", "3", "4", "1"]);
        assert_eq!(ids(search(&chats, "", Some("a"), Some("s2"), Some(2))), ["1", "4"]);
        assert_eq!(ids(search(&chats, "STUDIO", None, None, None)), ["1", "2", "3", "4"]);
    }
}
