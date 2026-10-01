//! GET /footprint: how much of the machine the station takes (footprint.rs measures the disk), as a viewer sees it: each chat's
//! directory under the chat's title, the agents' processes and their memory. And cleaning up, for a workspace's owner
//! or admin: what can be made again in chats' workspaces, archived chats (deleted), idle agents' processes (ended).

use std::collections::HashMap;
use std::time::Duration;

use anyhow::Result;
use serde_json::{Value, json};
use tracing::{info, warn};

use super::{AdminApi, Input, http_error};
use crate::access::Viewer;
use crate::footprint::{Scan, measure_room, room_of};

/// A scan older than this is made again when someone looks; one is made this long after the station starts, and again
/// every `RESCAN_EVERY`.
const FRESH_MS: i64 = 60 * 60 * 1000;
const FIRST_AFTER: Duration = Duration::from_secs(90);
const RESCAN_EVERY: Duration = Duration::from_secs(6 * 60 * 60);

impl AdminApi {
    /// Scans now and then while the station runs.
    pub(super) fn follow_footprint(&self) {
        let me = self.me.clone();
        tokio::spawn(async move {
            tokio::time::sleep(FIRST_AFTER).await;
            loop {
                let Some(api) = me.upgrade() else { return };
                api.scan_footprint();
                drop(api);
                tokio::time::sleep(RESCAN_EVERY).await;
            }
        });
    }

    /// Starts a scan in the background unless one runs; the pages are told when it is done (the `footprint` event).
    pub(super) fn scan_footprint(&self) {
        if !self.footprint.begin() {
            return;
        }
        let Some(api) = self.me.upgrade() else { return };
        // Seen as scanning.
        api.events.footprint_changed();
        tokio::spawn(async move {
            let data = api.config().data_dir.clone();
            // Not the machine's own places in tests: going through a developer's caches takes long.
            let home = std::env::var_os("HOME").map(std::path::PathBuf::from).filter(|_| !cfg!(test));
            let sessions: Vec<(String, String)> = api.deps.store.list_sessions().unwrap_or_default().into_iter().map(|s| (s.key, s.workspace)).collect();
            let scan = tokio::task::spawn_blocking(move || crate::footprint::scan(&data, home.as_deref(), &sessions)).await.unwrap_or_else(|e| {
                warn!(error = %e, "footprint scan failed");
                Scan::default()
            });
            info!(ms = scan.took_ms, bytes = scan.total(), chats = scan.rooms.len(), "footprint scanned");
            api.footprint.finish(scan);
            api.events.footprint_changed();
            api.events.overview_changed();
        });
    }

    /// What the overview says of it: how much the station takes (null before the first scan). Its presence says the
    /// station has the footprint page.
    pub(super) fn footprint_brief(&self) -> Value {
        json!({ "bytes": self.footprint.last().filter(|s| s.checked_at > 0).map(|s| s.total()), "scanning": self.footprint.scanning() })
    }

    /// The chats the viewer can see, by their sessions' keys: the chat's id, title and whether it is archived (a chat
    /// that is the session's own wins over one it only takes part in, a listed one over an archived one).
    pub(super) fn chats_by_session(&self, viewer: &Viewer) -> Result<HashMap<String, Value>> {
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
        Ok(chats.into_iter().map(|(k, (_, v))| (k, v)).collect())
    }

    /// GET /footprint. A scan older than an hour is made again (it says `scanning` meanwhile, with the last one).
    pub(super) async fn footprint_view(&self, viewer: &Viewer) -> Result<Value> {
        if self.footprint.stale(FRESH_MS) {
            self.scan_footprint();
        }
        let config = self.config();
        let store = &self.deps.store;
        let scan = self.footprint.last();
        let chats = self.chats_by_session(viewer)?;
        let sessions = store.list_sessions()?;
        // Chats the viewer cannot see are counted, not named.
        let (mut rows, mut unseen) = (vec![], (0u64, 0u64));
        if let Some(scan) = &scan {
            for s in &sessions {
                let Some(room) = scan.rooms.get(&s.key) else { continue };
                match chats.get(&s.key) {
                    Some(chat) => rows.push(json!({
                        "key": s.key, "chat": chat, "bytes": room.bytes, "rebuildBytes": room.rebuild_bytes(),
                        "archived": s.archived_at.is_some(), "lastActiveAt": s.last_active_at, "state": self.deps.hub.process_state(&s.key),
                    })),
                    None => {
                        unseen.0 += 1;
                        unseen.1 += room.bytes;
                    }
                }
            }
        }
        rows.sort_by_key(|r| std::cmp::Reverse(r["bytes"].as_u64().unwrap_or(0)));
        // The agents' processes, each under its chat: Claude Code runs one per session (labelled with its transcript's
        // id), Codex one per profile.
        let by_runtime_id: HashMap<String, &crate::store::SessionRow> = sessions.iter().filter_map(|s| Some((s.runtime_session_id.clone()?, s))).collect();
        let processes: Vec<_> = store.list_processes().unwrap_or_default().into_iter().filter(|p| p.runtime != "job").collect();
        let memory = super::views::process_memory(&processes.iter().map(|p| p.pgid).collect::<Vec<_>>());
        let processes: Vec<Value> = processes
            .iter()
            .map(|p| {
                let session = p.label.split_whitespace().last().and_then(|id| by_runtime_id.get(id)).filter(|_| p.runtime == "claude");
                json!({
                    "pgid": p.pgid, "runtime": p.runtime, "startedAt": p.started_at,
                    "rssBytes": memory.get(&p.pgid).map(|kb| *kb as u64 * 1024),
                    "key": session.map(|s| s.key.clone()),
                    "chat": session.and_then(|s| chats.get(&s.key)),
                    "state": session.map(|s| self.deps.hub.process_state(&s.key)),
                    "lastActiveAt": session.map(|s| s.last_active_at),
                })
            })
            .collect();
        let host = crate::host::host_info(&config.data_dir).await;
        Ok(json!({
            "checkedAt": scan.as_ref().map(|s| s.checked_at).filter(|at| *at > 0),
            "tookMs": scan.as_ref().map(|s| s.took_ms),
            "scanning": self.footprint.scanning(),
            "manage": viewer.manages(),
            "disk": { "totalBytes": host.disk.total_bytes, "freeBytes": host.disk.free_bytes },
            "parts": scan.as_ref().map(|s| s.parts.clone()).unwrap_or_default(),
            "elsewhere": scan.as_ref().map(|s| s.elsewhere.clone()).unwrap_or_default(),
            "chats": rows,
            "unseen": { "count": unseen.0, "bytes": unseen.1 },
            "memory": { "totalBytes": host.memory.total_bytes, "usedBytes": host.memory.used_bytes, "stationBytes": host.stillfail_rss_bytes },
            "processes": processes,
        }))
    }

    fn manager(viewer: &Viewer) -> Result<()> {
        if !viewer.manages() {
            return Err(http_error(403, "只有 workspace 的 owner 或管理员能清理 station"));
        }
        Ok(())
    }

    /// The sessions `input` names (`keys`), the viewer's to see; all the viewer sees when it names none.
    fn footprint_keys(&self, viewer: &Viewer, input: &Input) -> Result<Vec<String>> {
        let seen = self.chats_by_session(viewer)?;
        let keys: Vec<String> = match input.get("keys").and_then(Value::as_array) {
            Some(keys) => keys.iter().filter_map(Value::as_str).map(String::from).collect(),
            None => seen.keys().cloned().collect(),
        };
        if let Some(key) = keys.iter().find(|k| !seen.contains_key(*k)) {
            return Err(http_error(404, format!("unknown session {key}")));
        }
        Ok(keys)
    }

    /// POST /footprint/rebuild {keys?}: removes what can be made again from those chats' directories (all the viewer sees
    /// when none are named), skipping any whose agent is at work. Answers how much it freed and which it skipped.
    pub(super) async fn clean_rebuild(&self, viewer: &Viewer, input: &Input) -> Result<Value> {
        Self::manager(viewer)?;
        let keys = self.footprint_keys(viewer, input)?;
        let data = self.config().data_dir.clone();
        let (mut freed, mut busy) = (0u64, vec![]);
        for key in keys {
            let Some(row) = self.deps.store.get_session(&key)? else { continue };
            let Some(dir) = room_of(&data, &row.workspace) else { continue };
            if row.running || self.deps.hub.process_state(&key) == "running" {
                busy.push(key);
                continue;
            }
            let room = tokio::task::spawn_blocking(move || {
                // Found again now: the scan's list may be old.
                for (path, _) in measure_room(&dir).rebuild {
                    if let Err(e) = std::fs::remove_dir_all(&path) {
                        warn!(path = %path.display(), error = %e, "not removed");
                    }
                }
                measure_room(&dir)
            })
            .await?;
            let before = self.footprint.last().and_then(|s| s.rooms.get(&key).map(|r| r.bytes));
            freed += before.unwrap_or(room.bytes).saturating_sub(room.bytes);
            self.footprint.update_room(&key, Some(room));
        }
        info!(by = viewer.id(), freed, skipped = busy.len(), "rebuildable files cleaned");
        self.events.footprint_changed();
        self.events.overview_changed();
        Ok(json!({ "freedBytes": freed, "busy": busy }))
    }

    /// POST /footprint/delete {keys}: deletes those chats' sessions, which must be archived: their workspaces and records go
    /// with them (Hub::delete_session). Answers how much it freed.
    pub(super) async fn delete_archived(&self, viewer: &Viewer, input: &Input) -> Result<Value> {
        Self::manager(viewer)?;
        if input.get("keys").and_then(Value::as_array).is_none_or(|k| k.is_empty()) {
            return Err(http_error(400, "keys is required"));
        }
        let keys = self.footprint_keys(viewer, input)?;
        let rows: Vec<_> = keys.iter().filter_map(|k| self.deps.store.get_session(k).ok().flatten()).collect();
        if let Some(row) = rows.iter().find(|r| r.archived_at.is_none()) {
            return Err(http_error(409, format!("{} 没有归档，先归档再删除", row.key)));
        }
        let mut freed = 0u64;
        for row in rows {
            let bytes = self.footprint.last().and_then(|s| s.rooms.get(&row.key).map(|r| r.bytes)).unwrap_or(0);
            self.deps.hub.delete_session(&row.key).await?;
            self.footprint.update_room(&row.key, None);
            freed += bytes;
        }
        info!(by = viewer.id(), count = keys.len(), freed, "archived chats deleted from the footprint page");
        self.events.footprint_changed();
        self.events.overview_changed();
        Ok(json!({ "freedBytes": freed, "deleted": keys.len() }))
    }

    /// POST /footprint/evict {keys?}: ends those sessions' idle processes (all idle ones when none are named); they start
    /// again with the next message.
    pub(super) async fn evict_idle(&self, viewer: &Viewer, input: &Input) -> Result<Value> {
        Self::manager(viewer)?;
        let named = input.get("keys").and_then(Value::as_array).map(|k| k.iter().filter_map(Value::as_str).map(String::from).collect::<Vec<_>>());
        let keys: Vec<String> = match named {
            Some(keys) => keys,
            None => self.deps.store.list_sessions()?.into_iter().map(|s| s.key).collect(),
        };
        let mut ended = 0;
        for key in keys.iter().filter(|k| self.deps.hub.process_state(k) == "warm") {
            self.deps.hub.evict(key).await;
            ended += 1;
        }
        info!(by = viewer.id(), ended, "idle processes ended from the footprint page");
        self.events.footprint_changed();
        Ok(json!({ "ended": ended }))
    }
}
