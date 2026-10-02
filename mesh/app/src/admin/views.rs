//! What the pages read: the overview, sessions, threads, the sidebar and thread entries.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};

use anyhow::Result;
use stillfail_shapes::{AccessKind, RuntimeKind};
use serde_json::{Value, json};

use super::{AdminApi, Asked, http_error, mask};
use crate::access::Viewer;
use crate::chat::internal::INTERNAL_CONNECT;
use crate::config::runtime_name;
use crate::pool::serves;
use crate::store::{AuthorKind, STILLFAIL_SURFACE, EntryRow, MessageRow, SessionStats, ThreadRow, ThreadSummary};

/// How much of a chat's last message the sidebar gets.
const LAST_CHARS: usize = 200;
pub const NO_WORDS: &str = "（还没有消息）";

fn secret_key(key: &str) -> bool {
    let upper = key.to_uppercase();
    ["KEY", "TOKEN", "SECRET", "PASSWORD", "AUTH"].iter().any(|w| upper.contains(w))
}

/// Memory of each recorded runtime process group, from ps (kB).
pub(super) fn process_memory(pgids: &[i64]) -> HashMap<i64, i64> {
    let mut rss = HashMap::new();
    if pgids.is_empty() {
        return rss;
    }
    let Ok(out) = std::process::Command::new("ps").args(["-axo", "pgid=,rss="]).output() else { return rss };
    for line in String::from_utf8_lossy(&out.stdout).lines() {
        let mut fields = line.split_whitespace().map(|f| f.parse::<i64>().unwrap_or(-1));
        if let (Some(pgid), Some(kb)) = (fields.next(), fields.next()) {
            if pgids.contains(&pgid) {
                *rss.entry(pgid).or_insert(0) += kb;
            }
        }
    }
    rss
}

/// How much room the disk holding `path` has, or None when it cannot be read.
fn disk_room(path: &std::path::Path) -> Option<Value> {
    let c = std::ffi::CString::new(path.to_string_lossy().as_bytes()).ok()?;
    let mut stat: libc::statvfs = unsafe { std::mem::zeroed() };
    if unsafe { libc::statvfs(c.as_ptr(), &mut stat) } != 0 {
        return None;
    }
    let block = stat.f_frsize as u64;
    Some(json!({ "freeBytes": stat.f_bavail as u64 * block, "totalBytes": stat.f_blocks as u64 * block }))
}

fn turn_summary(t: &crate::store::TurnSummary) -> Value {
    serde_json::to_value(t).unwrap_or(Value::Null)
}

/// The connect a Slack thread came in through: the first of its sessions' that is not the station's own.
pub fn slack_connect_of(t: &ThreadSummary) -> Option<String> {
    t.sessions.iter().map(|m| m.connect.clone()).find(|c| c != INTERNAL_CONNECT)
}

/// The name a chat has been given: by people, else by its agent (ThreadRow::auto_title).
fn given_title(t: &ThreadSummary) -> Option<&str> {
    given(&t.thread)
}

fn given(thread: &ThreadRow) -> Option<&str> {
    [thread.title.as_deref(), thread.auto_title.as_deref()].into_iter().flatten().map(str::trim).find(|s| !s.is_empty())
}

/// Whether a chat has a title of its own, or something a person said in it to take one from.
fn has_words(t: &ThreadSummary) -> bool {
    given_title(t).is_some() || t.first_text.as_deref().is_some_and(|s| !s.trim().is_empty())
}

/// What a thread is called: the name people gave it, else the one its agent gave it, else the first line a person
/// wrote in it (Slack mentions left out, spaces collapsed), else its Slack channel (`#name`, 私信 for a direct message).
pub fn chat_title(t: &ThreadSummary, channel_name: Option<&str>) -> String {
    title_of(&t.thread, t.first_text.as_deref(), channel_name)
}

/// What a thread is called (chat_title), from its row and the first thing a person said in it.
pub fn title_of(thread: &ThreadRow, first_text: Option<&str>, channel_name: Option<&str>) -> String {
    if let Some(title) = given(thread) {
        return title.to_string();
    }
    let text = without_mentions(first_text.unwrap_or(""));
    if let Some(first) = text.split('\n').map(|line| line.split_whitespace().collect::<Vec<_>>().join(" ")).find(|l| !l.is_empty()) {
        return first;
    }
    if let Some(name) = channel_name.map(str::trim).filter(|s| !s.is_empty()) {
        return format!("#{name}");
    }
    if thread.surface != STILLFAIL_SURFACE && thread.channel.starts_with('D') {
        return "私信".into();
    }
    NO_WORDS.into()
}

/// `<@U…>` mentions taken out.
fn without_mentions(text: &str) -> String {
    let mut out = String::new();
    let mut rest = text;
    while let Some(at) = rest.find("<@") {
        out.push_str(&rest[..at]);
        let after = &rest[at + 2..];
        match after.find('>') {
            Some(end) if end > 0 && after[..end].chars().all(|c| c.is_ascii_uppercase() || c.is_ascii_digit()) => rest = &after[end + 1..],
            _ => {
                out.push_str("<@");
                rest = after;
            }
        }
    }
    out.push_str(rest);
    out
}

impl AdminApi {
    pub(super) fn overview(&self, viewer: &Viewer) -> Value {
        let config = self.config();
        let store = &self.deps.store;
        let sessions = store.list_sessions().unwrap_or_default();
        // The agents' runtime processes; background jobs' groups are recorded too (to be reaped), but they are jobs.
        let processes: Vec<_> = store.list_processes().unwrap_or_default().into_iter().filter(|p| p.runtime != "job").collect();
        let memory = process_memory(&processes.iter().map(|p| p.pgid).collect::<Vec<_>>());
        let connects: Vec<Value> = config
            .connects
            .iter()
            .map(|c| {
                json!({
                    // What it is known by: its bot's name in its Slack workspace, and that workspace.
                    "id": c.id, "name": c.name(), "team": c.slack.team.as_ref().map(|t| t.name.clone()),
                    "botImage": c.slack.bot_image, "enabled": c.enabled, "kind": c.kind, "mode": c.mode, "requireMention": c.require_mention,
                    "bind": { "runtime": c.bind.runtime, "model": c.bind.model, "effort": c.bind.effort, "profile": c.bind.profile },
                    "slack": { "appToken": mask(&c.slack.app_token), "botToken": mask(&c.slack.bot_token) },
                    "connection": self.deps.connections.state(c),
                    "createdBy": c.created_by,
                    "sessions": sessions.iter().filter(|s| s.connect == c.id).count(),
                    "session": if c.mode == stillfail_shapes::ConnectMode::SingleSession { store.binding(&c.id).ok().flatten() } else { None },
                })
            })
            .collect();
        let checks = self.checks.lock().unwrap().clone();
        let quotas = self.quotas.lock().unwrap().clone();
        let profiles: Vec<Value> = config
            .profiles
            .iter()
            .map(|p| {
                let env: Vec<Value> = p
                    .custom_env
                    .iter()
                    .map(|(key, value)| json!({ "key": key, "secret": secret_key(key), "value": if secret_key(key) { mask(value) } else { value.clone() } }))
                    .collect();
                json!({
                    "id": p.id, "name": p.name, "runtime": p.runtime, "runtimes": p.runtimes,
                    "email": if p.access_kind == stillfail_shapes::AccessKind::Subscription && !p.machine { super::edits::account_email(p.runtime, &p.home) } else { None },
                    "access": { "kind": p.access_kind, "key": mask(&p.key) },
                    "home": p.home, "homeExists": p.home.exists(), "model": p.model, "models": p.models,
                    "env": env,
                    // Connects whose sessions can run on it: of its runtime, and its models have theirs.
                    "usedBy": config.connects.iter().filter(|c| p.runtimes.contains(&c.bind.runtime) && serves(p, c.bind.model.as_deref())).map(|c| c.id.clone()).collect::<Vec<_>>(),
                    "loginCommand": crate::profiles::login_command(p.runtime, &p.home.to_string_lossy()),
                    "machine": p.machine,
                    "backgroundOnMessage": p.background_on_message,
                    "fast": (p.runtime == RuntimeKind::Codex && p.access_kind == AccessKind::Subscription).then_some(p.fast),
                    "check": checks.get(&p.id),
                    "login": self.deps.logins.get(&p.id),
                    "quota": quotas.get(&p.id),
                })
            })
            .collect();
        let states: Vec<&'static str> = sessions.iter().map(|s| self.deps.hub.process_state(&s.key)).collect();
        let by = viewer.id();
        let slack_apps: Vec<Value> = config
            .slack_apps
            .iter()
            .filter(|a| a.by == by)
            .map(|a| {
                json!({
                    "appId": a.app_id, "name": a.name, "teamId": a.team_id,
                    "team": config.slack_config_tokens.iter().find(|t| t.team_id == a.team_id).and_then(|t| t.owner.as_ref()).map(|o| o.team.clone()),
                    "created": a.created, "links": crate::chat::slack_apps::slack_app_links(&a.app_id, Some(&a.team_id)),
                    "install": a.oauth.as_ref().map(|o| o.install.clone()), "state": a.oauth.as_ref().map(|o| o.state.clone()),
                    "installed": a.oauth.as_ref().is_some_and(|o| o.bot_token.is_some()),
                    "installedTeam": a.oauth.as_ref().and_then(|o| o.installed_team.clone()),
                })
            })
            .collect();
        let logins: Vec<Value> = self
            .pending
            .lock()
            .unwrap()
            .iter()
            .map(|(id, p)| json!({ "id": id, "runtime": p.runtime, "job": self.deps.logins.get(id), "created": p.created, "error": p.error }))
            .collect();
        json!({
            "viewer": viewer,
            "mesh": self.deps.mesh.as_ref().map(|m| m.status()),
            "connects": connects,
            "profiles": profiles,
            "footprint": null,
            "processes": processes.iter().map(|p| {
                let mut v = serde_json::to_value(p).unwrap_or(Value::Null);
                v["rssMb"] = json!(memory.get(&p.pgid).map(|kb| (*kb as f64 / 1024.0).round() as i64));
                v
            }).collect::<Vec<_>>(),
            "counts": {
                "sessions": sessions.len(),
                "running": states.iter().filter(|s| **s == "running").count(),
                "warm": states.iter().filter(|s| **s == "warm").count(),
            },
            "slackUsers": self.deps.store.slack_identities(&by).unwrap_or_default(),
            // The Slack workspaces the station can make and edit apps in itself (an app configuration token each).
            "slackTeams": self.slack_teams(viewer),
            // The data disk's room, read as the overview is: what clients warn of when it runs low.
            "disk": disk_room(&config.data_dir),
            "logins": logins,
            "machineLogins": self.deps.machine_logins.as_ref().map(|m| m.get()).unwrap_or_default(),
            "updates": self.deps.updates.as_ref().map(|u| u.get()).unwrap_or_default(),
            "slackApps": slack_apps,
        })
    }

    /// A session for lists and events: its row (without the token), process state, counts and people.
    pub(super) fn summary(&self, key: &str) -> Result<Value> {
        let stats = self.deps.store.session_stats(Some(key))?;
        let bindings = self.deps.store.list_bindings()?;
        let participants = self.deps.store.participants(Some(key))?;
        self.summary_with(key, &stats, &bindings, &participants, &crate::jobs::watching(&self.deps.store))
    }

    fn summary_with(&self, key: &str, stats: &BTreeMap<String, SessionStats>, bindings: &BTreeMap<String, Vec<String>>, participants: &BTreeMap<String, Vec<String>>, watches: &HashMap<String, Value>) -> Result<Value> {
        let row = self.session_row(key)?;
        let mut v = serde_json::to_value(&row)?;
        v["boundTo"] = json!(bindings.get(key).cloned().unwrap_or_default());
        v["process"] = json!(self.deps.hub.process_state(key));
        let stat = stats.get(key);
        v["turns"] = json!(stat.map(|s| s.turns).unwrap_or(0));
        v["pending"] = json!(stat.map(|s| s.pending).unwrap_or(0));
        v["firstText"] = json!(stat.and_then(|s| s.first_text.clone()));
        v["lastTurn"] = stat.and_then(|s| s.last_turn.as_ref()).map(turn_summary).unwrap_or(Value::Null);
        v["creator"] = json!(self.creator(row.created_by.as_deref()));
        v["participants"] = json!(self.people(participants.get(key).map(Vec::as_slice).unwrap_or_default()));
        // Keeping watch (jobs::watching): the pages say so, and list it under 监控中.
        if let Some(watch) = watches.get(key) {
            v["watch"] = watch.clone();
        }
        Ok(v)
    }

    /// Sessions shown in lists, or only the archived ones.
    pub(super) fn sessions(&self, connect: Option<&str>, archived: bool) -> Result<Vec<Value>> {
        let store = &self.deps.store;
        let (stats, bindings, participants) = (store.session_stats(None)?, store.list_bindings()?, store.participants(None)?);
        let watches = crate::jobs::watching(store);
        store
            .list_sessions()?
            .into_iter()
            .filter(|s| connect.is_none_or(|c| s.connect == c) && s.archived_at.is_some() == archived)
            .map(|s| self.summary_with(&s.key, &stats, &bindings, &participants, &watches))
            .collect()
    }

    /// Several people, once each: one person may write through Slack and the station's chat under the same email.
    pub(super) fn people(&self, refs: &[String]) -> Vec<Value> {
        let mut seen = HashSet::new();
        refs.iter()
            .filter_map(|r| self.creator(Some(r)))
            .filter(|p| seen.insert(p["email"].as_str().unwrap_or(p["id"].as_str().unwrap_or("")).to_string()))
            .collect()
    }

    /// A creator reference in words: who, and their email where known (to match a still.fail cloud account).
    pub(super) fn creator(&self, reference: Option<&str>) -> Option<Value> {
        let reference = reference?;
        if reference == "local" {
            return Some(json!({ "id": "local", "name": "本机管理页", "email": null, "via": "local" }));
        }
        if let Some(rest) = reference.strip_prefix("slack:") {
            if let Some((connect, user)) = rest.split_once(':').filter(|(c, u)| !c.is_empty() && !u.is_empty()) {
                // Never waits on Slack: what is known now, the rest arrives with the next update.
                let person = self.deps.connections.chat(connect).and_then(|c| c.known_person(user));
                let name = person.as_ref().map(|p| p.name.clone()).filter(|n| !n.is_empty()).unwrap_or_else(|| user.to_string());
                let email = person.map(|p| p.email).filter(|e| !e.is_empty());
                return Some(json!({ "id": reference, "name": name, "email": email, "via": "slack" }));
            }
        }
        let name = self.deps.names.lock().unwrap().get(reference).cloned().unwrap_or_else(|| reference.to_string());
        Some(json!({ "id": reference, "name": name, "email": reference, "via": "cloud" }))
    }

    pub(super) fn session(&self, key: &str, viewer: &Viewer) -> Result<Value> {
        let turns: Vec<Value> = self
            .deps
            .store
            .list_turns(key)?
            .into_iter()
            .map(|t| {
                let mut v = turn_summary(&t.summary);
                v["id"] = json!(t.id);
                v
            })
            .collect();
        // Its background jobs and web services (jobs.rs), newest first.
        let jobs: Vec<Value> = self.deps.store.list_jobs(Some(key))?.iter().map(|j| crate::jobs::shown(&self.deps.store, j)).collect();
        Ok(json!({ "session": self.summary(key)?, "threads": self.threads(viewer, Some(key))?, "turns": turns, "jobs": jobs }))
    }

    /// The jobs still up (running, or a service being started again), newest first, each with the chat it is in as the
    /// viewer's list has it (`chat`: its id, title and whether it is archived), or none when no chat shows its session.
    pub(super) fn open_jobs(&self, viewer: &Viewer) -> Result<Vec<Value>> {
        let open: Vec<_> = self.deps.store.list_jobs(None)?.into_iter().filter(|j| j.state == "running" || (j.port.is_some() && j.state == "exited")).collect();
        if open.is_empty() {
            return Ok(vec![]);
        }
        // An archived chat first, so a listed one showing the same session wins; a chat that is the session's own wins over one it only takes part in.
        let mut chats: HashMap<String, (bool, Value)> = HashMap::new();
        for (archived, chat) in self.chats(viewer, true)?.into_iter().map(|c| (true, c)).chain(self.chats(viewer, false)?.into_iter().map(|c| (false, c))) {
            let shown = json!({ "id": chat["id"], "title": chat["title"], "archived": archived });
            for agent in chat["agents"].as_array().into_iter().flatten() {
                let Some(key) = agent["key"].as_str() else { continue };
                let own = chat["session"].as_str() == Some(key);
                if own || chats.get(key).is_none_or(|(was_own, _)| !was_own) {
                    chats.insert(key.to_string(), (own, shown.clone()));
                }
            }
        }
        Ok(open
            .iter()
            .map(|j| {
                let mut v = crate::jobs::shown(&self.deps.store, j);
                if let Some((_, chat)) = chats.get(&j.session_key) {
                    v["chat"] = chat.clone();
                }
                v
            })
            .collect())
    }

    // ── threads ────────────────────────────────────────────────────────────

    pub(super) fn threads(&self, viewer: &Viewer, session: Option<&str>) -> Result<Vec<Value>> {
        Ok(self.deps.store.list_threads(&viewer.id(), session, None)?.iter().map(|t| self.thread_view(t)).collect())
    }

    /// What the agents spent (crate::usage): its rows, and the threads, people and profiles they name, as the pages show
    /// them. `reading`: the transcripts are still being read for the first time, so the rows are short of it.
    pub(super) fn usage(&self, from: i64, to: i64, utc_offset_min: i64) -> Result<Value> {
        let Some(usage) = &self.deps.usage else { return Err(http_error(404, "这台 station 不记用量")) };
        let rows = usage.summary(from, to, utc_offset_min)?;
        let wanted: HashSet<i64> = rows.iter().filter_map(|r| r.thread).collect();
        let threads: serde_json::Map<String, Value> = self
            .deps
            .store
            .usage_threads(&wanted.into_iter().collect::<Vec<_>>())?
            .iter()
            .map(|(t, first)| {
                let channel_name = if t.surface == STILLFAIL_SURFACE { None } else { self.thread_chat(t.id).and_then(|c| c.known_channel(&t.channel)) };
                let title = title_of(t, first.as_deref(), channel_name.as_deref());
                (t.id.to_string(), json!({ "title": title, "surface": t.surface, "home": t.home, "archived": t.hidden_at.is_some() }))
            })
            .collect();
        let refs: Vec<String> = rows.iter().filter_map(|r| r.person.clone()).collect::<BTreeSet<_>>().into_iter().collect();
        let people: serde_json::Map<String, Value> = refs.iter().filter_map(|r| Some((r.clone(), self.creator(Some(r))?))).collect();
        let config = self.config();
        let profiles: serde_json::Map<String, Value> = config.profiles.iter().map(|p| (p.id.clone(), json!({ "name": p.name, "runtime": runtime_name(p.runtime) }))).collect();
        Ok(json!({
            "from": from,
            "to": to,
            "since": self.deps.store.usage_since()?,
            "reading": usage.reading_all(),
            "prices": crate::usage::price_table(),
            "rows": rows,
            "threads": threads,
            "people": people,
            "profiles": profiles,
        }))
    }

    pub(super) fn thread(&self, id: i64, viewer: &Viewer) -> Result<Value> {
        let threads = self.deps.store.list_threads(&viewer.id(), None, Some(id))?;
        let thread = threads.first().ok_or_else(|| http_error(404, format!("unknown thread {id}")))?;
        Ok(self.thread_view(thread))
    }

    fn thread_view(&self, t: &ThreadSummary) -> Value {
        let chat = self.thread_chat(t.thread.id);
        let mut names = self.author_names(t.thread.id);
        let channel_name = if t.thread.surface == STILLFAIL_SURFACE { None } else { chat.as_ref().and_then(|c| c.known_channel(&t.thread.channel)) };
        let mut v = serde_json::to_value(&t.thread).unwrap_or_else(|_| json!({}));
        v["sessions"] = serde_json::to_value(&t.sessions).unwrap_or(Value::Null);
        v["last"] = json!(t.last);
        v["lastMessage"] = t.last_message.as_ref().map(|m| message_view(m, &mut names)).unwrap_or(Value::Null);
        v["read"] = json!(t.read);
        v["unread"] = json!(t.unread);
        v["people"] = json!(self.people(&t.people));
        v["firstText"] = json!(t.first_text);
        v["channelName"] = json!(channel_name);
        v["creator"] = json!(self.creator(t.thread.created_by.as_deref()));
        v
    }

    // ── the sidebar ────────────────────────────────────────────────────────

    /// The viewer's sidebar: one kind of item, an agent (a shown session) merged with its internal chat. An agent in an
    /// internal chat is that chat's item; one with none yet is an item without a chat, whose chat is made with its
    /// first message. A Slack thread is no item: it lends its agent's item a title (while the chat has no words of its
    /// own), the connect and the origin. `archived`: the archive's items instead, archived sessions (with their own
    /// chats) and chats of their own archived alone, each with `archived: {at, by, alone}`. Each says when the viewer pinned
    /// it (`pinned`), or null.
    pub(super) fn chats(&self, viewer: &Viewer, archived: bool) -> Result<Vec<Value>> {
        let store = &self.deps.store;
        let is_mine = self.is_mine(viewer);
        let stats = store.session_stats(None)?;
        let sessions = store.list_sessions()?;
        let shown: BTreeMap<String, crate::store::SessionRow> =
            sessions.iter().filter(|s| s.archived_at.is_some() == archived).map(|s| (s.key.clone(), s.clone())).collect();
        let order: Vec<String> = sessions.iter().filter(|s| s.archived_at.is_some() == archived).map(|s| s.key.clone()).collect();
        // In the archive, a chat of its own shows its agents whatever they are doing elsewhere.
        let all: BTreeMap<String, crate::store::SessionRow> = sessions.into_iter().map(|s| (s.key.clone(), s)).collect();
        let listed = |t: &ThreadSummary| t.thread.hidden_at.is_some() == archived;
        let in_chat = |t: &ThreadSummary| -> Vec<String> {
            let alone = archived && t.thread.home.is_none();
            t.sessions.iter().filter(|m| if alone { all.contains_key(&m.session) } else { shown.contains_key(&m.session) }).map(|m| m.session.clone()).collect()
        };
        let archived_of = |s: &crate::store::SessionRow| {
            json!({ "at": s.archived_at.unwrap_or(0), "by": s.archived_by.as_deref().unwrap_or(crate::store::MANUAL), "alone": false })
        };
        let watches = crate::jobs::watching(store);
        let agent = |key: &str| {
            let s = &all[key];
            let stat = stats.get(key);
            let mut v = json!({
                "key": key, "runtime": s.runtime, "model": s.model, "effort": s.effort, "process": self.deps.hub.process_state(key),
                "pending": stat.map(|s| s.pending).unwrap_or(0), "lastTurn": stat.and_then(|s| s.last_turn.as_ref()).map(turn_summary),
            });
            if let Some(watch) = watches.get(key) {
                v["watch"] = watch.clone();
            }
            v
        };
        let threads = store.list_threads(&viewer.id(), None, None)?;
        // Per agent: the Slack thread it came from (the latest one it is in), and whether it has an internal chat.
        let mut origins: HashMap<String, &ThreadSummary> = HashMap::new();
        let mut chatted = HashSet::new();
        for t in &threads {
            for m in &t.sessions {
                if t.thread.surface == STILLFAIL_SURFACE {
                    if listed(t) {
                        chatted.insert(m.session.clone());
                    }
                } else {
                    origins.entry(m.session.clone()).or_insert(t);
                }
            }
        }
        let mut rows = Vec::new();
        // The decisions the viewer said they will not take up.
        let dismissed = store.dismissed(&viewer.id())?;
        let kept = store.kept_chats(Some(&viewer.id()))?;
        // The cards the viewer answered lately, by chat: the 奏 page counts and lists the day's.
        let mut answered: HashMap<i64, Vec<Value>> = HashMap::new();
        if !archived {
            for a in store.answers_since(crate::store::now_ms() - ANSWERED_WITHIN)? {
                if !is_mine(self.creator(Some(&a.by)).as_ref()) {
                    continue;
                }
                answered.entry(a.question.thread).or_default().push(answered_view(&a));
            }
        }
        for t in threads.iter().filter(|t| t.thread.surface == STILLFAIL_SURFACE && listed(t) && !in_chat(t).is_empty()) {
            let from = t.sessions.iter().find_map(|m| origins.get(&m.session).copied());
            let agents: Vec<Value> = in_chat(t).iter().map(|key| agent(key)).collect();
            let origin = from.map(|f| self.origin(f));
            let creator = self.creator(t.thread.created_by.as_deref());
            let people = self.people(&t.people);
            let mut names = self.author_names(t.thread.id);
            let last = t.last_message.as_ref().map(|m| message_view(m, &mut names));
            let starters: Vec<Option<Value>> = agents.iter().map(|a| self.creator(all.get(a["key"].as_str().unwrap_or("")).and_then(|s| s.created_by.as_deref()))).collect();
            let key = agents[0]["key"].clone();
            let title = match (from, &origin) {
                (Some(f), Some(o)) if !has_words(t) => chat_title(f, o["channelName"].as_str()),
                _ => chat_title(t, None),
            };
            let last = last.map(|l| {
                let text = l["text"].as_str().unwrap_or("").trim().to_string();
                // Something to show when there are no words: a message that only quotes says so.
                let text = if text.is_empty() && l["quotes"].as_array().is_some_and(|q| !q.is_empty()) { "引用了一条消息".to_string() } else { text };
                json!({
                    "seq": l["seq"], "authorKind": l["authorKind"], "author": l["author"], "authorName": l["authorName"],
                    "text": l["text"].as_str().map(|_| text.chars().take(LAST_CHARS).collect::<String>()), "createdAt": l["createdAt"],
                })
            });
            let mine = is_mine(creator.as_ref()) || people.iter().any(|p| is_mine(Some(p))) || starters.iter().any(|s| is_mine(s.as_ref()));
            let mut row = json!({
                // An item is its agent's, from its first moment to its last: the session key is its id, chat or no chat.
                "id": key, "session": key, "thread": t.thread.id,
                "title": title,
                "agents": agents,
                "last": last,
                "unread": t.unread > 0,
                "mine": mine,
                "lastActiveAt": t.thread.created_at.max(t.last_message.as_ref().map(|m| m.created_at).unwrap_or(0)),
                "connect": from.and_then(slack_connect_of),
                "origin": origin,
                // Who is in it, for the row's pictures: who started it, and everyone who wrote in it.
                "creator": creator,
                "people": people,
            });
            row["archiveReminderDismissed"] = json!(kept.contains(&t.thread.id));
            if let Some(client) = key.as_str().and_then(|k| self.deps.hub.client_key(k)) {
                row["clientKey"] = json!(client);
            }
            // The card it waits on, if any (an agent's post with a card no one has answered yet), and whether the viewer
            // dismissed it; a chat with none says nothing. An options card is its `decision` too, as clients from before
            // cards read it.
            if !archived && let Some(card) = self.card_view(t.thread.id, &dismissed, &mut names) {
                if card["card"]["type"] == "options" {
                    let mut decision = card.clone();
                    if let Some(d) = decision.as_object_mut() {
                        d.remove("card");
                    }
                    decision["options"] = card["card"]["options"].clone();
                    row["decision"] = decision;
                }
                row["card"] = card;
            }
            if let Some(list) = answered.remove(&t.thread.id) {
                row["answered"] = json!(list);
            }
            if archived {
                row["archived"] = match t.thread.home.as_ref().and_then(|home| all.get(home)) {
                    Some(home) => archived_of(home),
                    None => json!({
                        "at": t.thread.hidden_at.unwrap_or(0), "by": t.thread.hidden_by.as_deref().unwrap_or(crate::store::MANUAL), "alone": true,
                    }),
                };
            }
            rows.push(row);
        }
        for key in order.iter().filter(|k| !chatted.contains(*k)) {
            let s = &shown[key];
            let from = origins.get(key).copied();
            let origin = from.map(|f| self.origin(f));
            let title = match s.title.as_deref().map(str::trim).filter(|t| !t.is_empty()) {
                Some(title) => title.to_string(),
                None => match (from, &origin) {
                    (Some(f), Some(o)) => chat_title(f, o["channelName"].as_str()),
                    _ => NO_WORDS.to_string(),
                },
            };
            let starter = self.creator(s.created_by.as_deref());
            let mut row = json!({
                "id": key, "session": key, "thread": null,
                "title": title,
                "agents": [agent(key)],
                "last": null,
                "unread": false,
                // No chat yet: mine only if the viewer started the session; others in its Slack thread do not count.
                "mine": is_mine(starter.as_ref()),
                "lastActiveAt": s.last_active_at,
                "connect": if s.connect == INTERNAL_CONNECT { None } else { Some(s.connect.clone()) },
                "origin": origin,
                // No one has written yet: only who started it.
                "people": starter.iter().collect::<Vec<_>>(),
                "creator": starter,
            });
            if let Some(client) = self.deps.hub.client_key(key) {
                row["clientKey"] = json!(client);
            }
            if archived {
                row["archived"] = archived_of(s);
            }
            rows.push(row);
        }
        // When the viewer pinned each to the top of their list, or null (a station from before pins says nothing).
        let pins = store.pins(&viewer.id())?;
        for row in &mut rows {
            row["pinned"] = json!(row["id"].as_str().and_then(|id| pins.get(id)));
        }
        Ok(rows)
    }

    /// A chat's card still pending (store `pending_card`), for its row: `seq` (its post's entry), the `card` as the agent
    /// gave it, `dismissed` when the viewer will not take it up, the post itself (`message`, as lists show messages, with
    /// its card) and the two messages before it (`before`), for a page of them to show without reading the chat.
    fn card_view(&self, thread: i64, dismissed: &HashSet<(i64, i64)>, names: &mut impl FnMut(AuthorKind, &str) -> Option<String>) -> Option<Value> {
        let store = &self.deps.store;
        let (m, card) = store.pending_card(thread).ok().flatten()?;
        let mut message = message_view(&m, names);
        if card["type"] == "options" {
            message["options"] = card["options"].clone();
        }
        message["card"] = card.clone();
        let before: Vec<Value> = store.messages_before(thread, Some(m.n), 2).unwrap_or_default().iter().map(|b| message_view(b, names)).collect();
        let mut v = json!({ "seq": m.n, "card": card, "message": message, "before": before });
        if dismissed.contains(&(thread, m.n)) {
            v["dismissed"] = json!(true);
        }
        Some(v)
    }

    /// Whether a person is the viewer: by id, by email, or as a Slack user the viewer said is them.
    fn is_mine(&self, viewer: &Viewer) -> impl Fn(Option<&Value>) -> bool {
        let id = viewer.id();
        let Viewer::Mesh { email, .. } = viewer;
        let email = Some(email.to_lowercase());
        let slack: HashSet<String> = self.deps.store.slack_identities(&id).unwrap_or_default().into_iter().collect();
        move |person| {
            let Some(p) = person else { return false };
            let pid = p["id"].as_str().unwrap_or("");
            pid == id
                || email.as_deref().is_some_and(|e| p["email"].as_str().is_some_and(|pe| pe.to_lowercase() == e))
                || (p["via"] == "slack" && slack.contains(&pid[pid.rfind(':').map(|i| i + 1).unwrap_or(0)..]))
        }
    }

    /// Where a Slack thread is, for the connect icon's tip: the Slack workspace, the channel.
    fn origin(&self, t: &ThreadSummary) -> Value {
        let config = self.config();
        let connect = slack_connect_of(t).and_then(|id| config.connects.iter().find(|c| c.id == id).cloned());
        let team_name = connect.map(|c| self.deps.connections.state(&c)).and_then(|state| match state {
            crate::connections::ConnectState::Connected { workspace, .. } | crate::connections::ConnectState::Reconnecting { workspace, .. } => {
                workspace.map(|w| w.team).filter(|t| !t.is_empty())
            }
            _ => None,
        });
        let channel_name = self.thread_chat(t.thread.id).and_then(|c| c.known_channel(&t.thread.channel));
        json!({ "teamName": team_name, "channel": t.thread.channel, "channelName": channel_name, "threadTs": t.thread.thread_ts })
    }

    /// GET /threads/:id/entries: `after` (an n) gives what came since; `before` pages back (`limit` entries); `from`
    /// and `to` a gap (both included); none of them the latest page.
    pub(super) fn entries(&self, thread: i64, asked: &Asked) -> Result<Value> {
        let number = |name: &str| -> Result<Option<i64>> {
            match asked.param(name) {
                None => Ok(None),
                Some(v) => match v.parse::<f64>() {
                    Ok(n) if n.fract() == 0.0 && n >= 0.0 => Ok(Some(n as i64)),
                    _ => Err(http_error(400, format!("{name} 必须是整数"))),
                },
            }
        };
        let (after, before, from, to) = (number("after")?, number("before")?, number("from")?, number("to")?);
        let limit = asked.param("limit").and_then(|l| l.parse::<f64>().ok()).filter(|l| *l != 0.0).unwrap_or(50.0).clamp(1.0, 500.0) as usize;
        if from.is_some() != to.is_some() {
            return Err(http_error(400, "from 和 to 要一起给"));
        }
        let store = &self.deps.store;
        let last = store.last_entry(thread)?;
        let entries = match (after, from, to) {
            (Some(after), _, _) => store.entries_after(thread, after)?,
            (None, Some(from), Some(to)) => store.entries_between(thread, from, to)?,
            _ => store.entries_before(thread, before, limit)?,
        };
        Ok(json!({ "last": last, "entries": self.entry_views(thread, &entries) }))
    }

    /// A connection that can name the thread's people and channel: that of a session taking part.
    fn thread_chat(&self, thread: i64) -> Option<std::sync::Arc<dyn crate::connections::Connection>> {
        self.deps.store.thread_sessions(thread).ok()?.iter().filter(|m| m.connect != INTERNAL_CONNECT).find_map(|m| self.deps.connections.chat(&m.connect))
    }

    /// Who wrote in a thread, in words: each author asked once.
    pub(super) fn author_names(&self, thread: i64) -> impl FnMut(AuthorKind, &str) -> Option<String> + '_ {
        let t = self.deps.store.get_thread(thread).ok().flatten();
        let chat = self.thread_chat(thread);
        let members = self.deps.store.thread_sessions(thread).unwrap_or_default();
        let config = self.config();
        let mut names: HashMap<String, Option<String>> = HashMap::new();
        move |kind, author| {
            let key = format!("{}:{author}", kind.as_str());
            if let Some(known) = names.get(&key) {
                return known.clone();
            }
            let name = match kind {
                AuthorKind::StillFail => Some("still.fail".to_string()),
                AuthorKind::Agent => {
                    // An agent goes by the name of the connect it posts through (on the page, of the connect that
                    // started it).
                    let session = self.deps.store.get_session(author).ok().flatten();
                    let via = members.iter().find(|m| m.session == author).map(|m| m.connect.clone());
                    let connect = match via {
                        Some(via) if via != INTERNAL_CONNECT => Some(via),
                        _ => session.as_ref().map(|s| s.connect.clone()),
                    };
                    match config.connects.iter().find(|c| Some(&c.id) == connect.as_ref()) {
                        Some(c) => Some(c.name().to_string()),
                        None => session.and_then(|s| s.title),
                    }
                }
                AuthorKind::Person if t.as_ref().is_some_and(|t| t.surface == STILLFAIL_SURFACE) => {
                    Some(if author == "local" { "管理员".to_string() } else { self.deps.names.lock().unwrap().get(author).cloned().unwrap_or_else(|| author.to_string()) })
                }
                AuthorKind::Person => chat.as_ref().and_then(|c| c.known_person(author)).map(|p| p.name).filter(|n| !n.is_empty()),
            };
            names.insert(key, name.clone());
            name
        }
    }

    /// Entries with their authors' names.
    pub(super) fn entry_views(&self, thread: i64, entries: &[EntryRow]) -> Vec<Value> {
        let mut names = self.author_names(thread);
        entries
            .iter()
            .map(|e| {
                let mut v = serde_json::to_value(e).unwrap_or(Value::Null);
                v["authorName"] = json!(names(e.author_kind, &e.author));
                declared_view(&mut v, e.declared.as_deref());
                // Its card, a post's options from before cards (kept so, in an archive file too) as an options card.
                if let Some(card) = e.card() {
                    v["card"] = card;
                }
                v
            })
            .collect()
    }

    /// The viewer's own Slack workspaces (a configuration token each), with whose token it is; never the tokens.
    pub(super) fn slack_teams(&self, viewer: &Viewer) -> Vec<Value> {
        let by = viewer.id();
        self.config()
            .slack_config_tokens
            .iter()
            .filter(|t| t.by == by)
            .map(|t| {
                let name = t.owner.as_ref().map(|o| o.team.clone()).filter(|n| !n.is_empty()).unwrap_or_else(|| t.team_id.clone());
                json!({ "teamId": t.team_id, "name": name, "owner": t.owner })
            })
            .collect()
    }
}

/// A merged message as lists show it (a thread's latest), with its author's name.
pub fn message_view(m: &MessageRow, names: &mut impl FnMut(AuthorKind, &str) -> Option<String>) -> Value {
    let mut v = json!({
        "seq": m.n, "thread": m.thread, "ts": m.ts, "authorKind": m.author_kind, "author": m.author, "authorName": names(m.author_kind, &m.author),
        "text": m.text, "attachments": m.attachments, "quotes": m.quotes, "declared": m.declared, "createdAt": m.created_at, "editedAt": m.edited_at,
    });
    declared_view(&mut v, m.declared.as_deref());
    v
}

/// A post's declared kind as the pages read it: `declared` in the words from before (final, block), which clients from
/// before know, and `ending` in today's (all_done, need_decision, need_help).
fn declared_view(v: &mut Value, declared: Option<&str>) {
    if let Some(d) = declared {
        v["declared"] = json!(crate::store::said_before(d));
        v["ending"] = json!(crate::store::ending(d));
    }
}

#[allow(dead_code)]
fn runtime_label(runtime: stillfail_shapes::RuntimeKind) -> &'static str {
    runtime_name(runtime)
}

/// How far back a row says which cards the viewer answered in it: a day and a half, whatever the viewer's day is.
const ANSWERED_WITHIN: i64 = 36 * 3600 * 1000;

/// A card the viewer answered, for its chat's row (`answered`): the post that asked (`seq`, `text`, when: `askedAt`),
/// its card, when it was answered (`answeredAt`), and with what: their words (`reply`) and whether they quoted the post
/// (`quoted`: an option picked is its label, quoting it), or nothing when a choice closed it (`closed`).
fn answered_view(a: &crate::store::CardAnswer) -> Value {
    let mut v = json!({
        "seq": a.question.n, "text": a.question.text, "askedAt": a.question.created_at, "answeredAt": a.at, "card": a.card,
    });
    match &a.answer {
        Some(m) => {
            v["reply"] = json!(m.text);
            v["quoted"] = json!(m.quotes.iter().any(|q| q.ts.as_deref() == Some(a.question.ts.as_str())));
        }
        None => v["closed"] = json!(true),
    }
    v
}
