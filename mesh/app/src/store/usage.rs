//! What the agents spent, as the station records it (crate::usage reads it from the transcripts): one row per model call,
//! with the turn it was in, whom that turn worked for, in which thread and on which profile. What a call is for is
//! written as it is recorded, so it stays when its session and threads go.

use std::collections::HashMap;

use anyhow::Result;
use rusqlite::{OptionalExtension, params};

use super::{Store, StoreChange};

/// A model call read from a transcript. Tokens as the provider bills them: input not from the cache, read from it,
/// written to it (for five minutes / an hour), and output.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct UsageCall {
    /// The provider's id for it, unique across transcripts (a call written twice, as a sub-agent's copy, counts once).
    pub id: String,
    pub at: i64,
    pub model: Option<String>,
    pub subagent: bool,
    pub fast: bool,
    pub input: i64,
    pub cache_read: i64,
    pub cache_write: i64,
    pub cache_write_long: i64,
    pub output: i64,
}

/// How far a transcript has been read, and for which session (None: none of the station's).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct UsageFile {
    pub session: Option<String>,
    pub offset: u64,
    /// The model the transcript last named (Codex names it once per turn, not per call).
    pub model: Option<String>,
}

/// What a call was for: the turn it was in, and whom that worked for, where, on what.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct UsageFor {
    pub turn: Option<String>,
    pub person: Option<String>,
    pub thread: Option<i64>,
    pub profile: Option<String>,
}

/// A turn as usage takes it: when it started, and whom it worked for (UsageFor without the turn's own id).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UsageTurn {
    pub id: String,
    pub started_at: i64,
    pub of: UsageFor,
}

/// The calls of one day (in the asker's time zone) for one thread, person, profile and model, added up.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct UsageGroup {
    pub day: String,
    pub session: String,
    pub thread: Option<i64>,
    pub person: Option<String>,
    pub profile: Option<String>,
    pub runtime: String,
    pub model: Option<String>,
    pub fast: bool,
    pub calls: i64,
    pub input: i64,
    pub cache_read: i64,
    pub cache_write: i64,
    pub cache_write_long: i64,
    pub output: i64,
}

impl Store {
    /// Every transcript read for usage so far, by path.
    pub fn usage_files(&self) -> Result<HashMap<String, UsageFile>> {
        self.with(|i, _| {
            let mut stmt = i.db.prepare("SELECT path, session, offset, model FROM usage_files")?;
            let rows = stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, UsageFile { session: r.get(1)?, offset: r.get::<_, i64>(2)? as u64, model: r.get(3)? })))?;
            Ok(rows.collect::<rusqlite::Result<_>>()?)
        })
    }

    /// Records a transcript's calls read up to `file.offset`, each with what it was for; a call recorded before keeps
    /// its row (its output grown, when the transcript wrote it again whole). How many were new.
    pub fn record_usage(&self, path: &str, file: &UsageFile, runtime: &str, calls: &[(UsageCall, UsageFor)]) -> Result<usize> {
        self.with(|i, _| {
            let tx = i.db.transaction()?;
            let mut added = 0;
            if let Some(session) = &file.session {
                let mut insert = tx.prepare(
                    "INSERT INTO usage (id, at, session, turn, thread, person, profile, runtime, model, subagent, fast, input, cache_read, cache_write, cache_write_long, output)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)
                     ON CONFLICT (id) DO UPDATE SET output = MAX(output, excluded.output)",
                )?;
                for (c, of) in calls {
                    let known = tx.query_row("SELECT 1 FROM usage WHERE id = ?", [&c.id], |_| Ok(())).optional()?.is_some();
                    insert.execute(params![
                        c.id, c.at, session, of.turn, of.thread, of.person, of.profile, runtime, c.model, c.subagent, c.fast, c.input, c.cache_read, c.cache_write, c.cache_write_long, c.output
                    ])?;
                    added += usize::from(!known);
                }
            }
            tx.execute(
                "INSERT INTO usage_files (path, session, offset, model) VALUES (?1, ?2, ?3, ?4)
                 ON CONFLICT (path) DO UPDATE SET session = excluded.session, offset = excluded.offset, model = excluded.model",
                params![path, file.session, file.offset as i64, file.model],
            )?;
            tx.commit()?;
            Ok(added)
        })
    }

    /// Tells whoever follows the store that calls were recorded.
    pub fn usage_changed(&self) {
        let _ = self.changes.send(StoreChange::Usage);
    }

    /// Sessions whose transcripts may have grown since `since`: a turn running, or ended since then.
    pub fn usage_active_sessions(&self, since: i64) -> Result<Vec<String>> {
        self.with(|i, _| {
            let mut stmt = i.db.prepare("SELECT DISTINCT session_key FROM turns WHERE ended_at IS NULL OR ended_at >= ?")?;
            Ok(stmt.query_map([since], |r| r.get(0))?.collect::<rusqlite::Result<_>>()?)
        })
    }

    /// A session's turns, oldest first, each with whom it worked for. Turns from before stations said so are worked
    /// out: a turn that answered messages is for the first person whose message it took, in that message's thread
    /// (while the thread's entries are in the database, not archived); any other goes on with the work of the one
    /// before. What is still unknown is the session's: its creator, its own chat, its profile.
    pub fn usage_turns(&self, session: &str) -> Result<Vec<UsageTurn>> {
        self.with(|i, _| {
            let row = i.db.query_row("SELECT created_by, profile FROM sessions WHERE key = ?", [session], |r| Ok((r.get::<_, Option<String>>(0)?, r.get::<_, String>(1)?))).optional()?;
            let (creator, profile) = row.unwrap_or_default();
            let home: Option<i64> = i
                .db
                .query_row(
                    "SELECT id FROM threads WHERE home = ?1 UNION ALL SELECT thread FROM (SELECT thread FROM thread_sessions WHERE session = ?1 ORDER BY joined_at LIMIT 1) LIMIT 1",
                    [session],
                    |r| r.get(0),
                )
                .optional()?;
            let turns: Vec<(String, String, i64, Option<String>, Option<String>, Option<i64>)> = {
                let mut stmt = i.db.prepare("SELECT id, kind, started_at, profile, person, thread FROM turns WHERE session_key = ? ORDER BY started_at")?;
                stmt.query_map([session], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?)))?.collect::<rusqlite::Result<_>>()?
            };
            // The people's messages the session took, as they were delivered (only needed for turns from before).
            // A Slack user is named through the connect the thread came by (store.rs thread_people).
            let delivered: Vec<(i64, String, i64)> = if turns.iter().any(|t| t.4.is_none()) {
                let mut stmt = i.db.prepare(
                    "SELECT d.delivered_at, CASE WHEN t.surface = ?2 THEN e.author ELSE 'slack:' || ts.connect || ':' || e.author END, e.thread
                     FROM deliveries d JOIN entries e ON e.thread = d.thread AND e.n = d.n JOIN threads t ON t.id = d.thread
                     JOIN thread_sessions ts ON ts.thread = d.thread AND ts.session = d.session
                     WHERE d.session = ?1 AND d.delivered_at IS NOT NULL AND e.author_kind = 'person' ORDER BY d.delivered_at",
                )?;
                stmt.query_map(params![session, super::STILLFAIL_SURFACE], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?.collect::<rusqlite::Result<_>>()?
            } else {
                vec![]
            };
            let mut out: Vec<UsageTurn> = Vec::with_capacity(turns.len());
            let mut next = 0;
            for (n, (id, kind, started_at, own_profile, person, thread)) in turns.iter().enumerate() {
                let end = turns.get(n + 1).map(|t| t.2).unwrap_or(i64::MAX);
                while next < delivered.len() && delivered[next].0 < *started_at {
                    next += 1;
                }
                let first = (kind == "input").then(|| delivered.get(next).filter(|d| d.0 < end)).flatten();
                let previous = out.last().map(|t| t.of.clone());
                let person = person.clone().or_else(|| first.map(|d| d.1.clone())).or_else(|| previous.as_ref().and_then(|p| p.person.clone())).or_else(|| creator.clone());
                let thread = thread.or_else(|| first.map(|d| d.2)).or_else(|| previous.as_ref().and_then(|p| p.thread)).or(home);
                let profile = own_profile.clone().unwrap_or_else(|| profile.clone());
                out.push(UsageTurn { id: id.clone(), started_at: *started_at, of: UsageFor { turn: Some(id.clone()), person, thread, profile: Some(profile) } });
            }
            if out.is_empty() {
                out.push(UsageTurn { id: String::new(), started_at: i64::MIN, of: UsageFor { turn: None, person: creator, thread: home, profile: Some(profile) } });
            }
            Ok(out)
        })
    }

    /// The calls from `from` until `to` (ms), added up by day in the asker's time zone (`utc_offset_min`) and by thread,
    /// person, profile and model.
    pub fn usage_groups(&self, from: i64, to: i64, utc_offset_min: i64) -> Result<Vec<UsageGroup>> {
        self.with(|i, _| {
            let mut stmt = i.db.prepare(
                "SELECT strftime('%Y-%m-%d', (at + ?3 * 60000) / 1000, 'unixepoch') AS day, session, thread, person, profile, runtime, model, fast,
                   COUNT(*), SUM(input), SUM(cache_read), SUM(cache_write), SUM(cache_write_long), SUM(output)
                 FROM usage WHERE at >= ?1 AND at < ?2
                 GROUP BY day, session, thread, person, profile, runtime, model, fast",
            )?;
            let rows = stmt.query_map(params![from, to, utc_offset_min], |r| {
                Ok(UsageGroup {
                    day: r.get(0)?,
                    session: r.get(1)?,
                    thread: r.get(2)?,
                    person: r.get(3)?,
                    profile: r.get(4)?,
                    runtime: r.get(5)?,
                    model: r.get(6)?,
                    fast: r.get(7)?,
                    calls: r.get(8)?,
                    input: r.get(9)?,
                    cache_read: r.get(10)?,
                    cache_write: r.get(11)?,
                    cache_write_long: r.get(12)?,
                    output: r.get(13)?,
                })
            })?;
            Ok(rows.collect::<rusqlite::Result<_>>()?)
        })
    }

    /// The threads usage names, each with the first thing a person said in it (for its title; none where its archive
    /// cannot be read). Those gone are left out.
    pub fn usage_threads(&self, ids: &[i64]) -> Result<Vec<(super::ThreadRow, Option<String>)>> {
        self.with(|i, _| {
            let mut out = vec![];
            for id in ids {
                let Some(thread) = i.get_thread(*id)? else { continue };
                let first = if thread.title.is_some() || thread.auto_title.is_some() { None } else { i.first_text(*id).ok().flatten() };
                out.push((thread, first));
            }
            Ok(out)
        })
    }

    /// When the earliest call recorded was made.
    pub fn usage_since(&self) -> Result<Option<i64>> {
        self.with(|i, _| Ok(i.db.query_row("SELECT MIN(at) FROM usage", [], |r| r.get(0))?))
    }
}
