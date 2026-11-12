// Reads the station's own parts ask in the background (station/src/read/ops-sessions.ts): the sessions whose
// workspaces are measured (`sessionsAtWork`), what a week's archive-policy checks say (`policyChecks`), and the people
// of a connect's recent threads (`recentConnectPeople`). The statements are the TypeScript's, as it makes them.

///|
/// jobs/workspace-size.ts SESSIONS_AT_WORK.
let sessions_at_work_sql : String =
  #|SELECT s.key, s.workspace FROM (SELECT rowid AS rid, key, workspace, running, last_active_at
  #|  FROM sessions INDEXED BY sessions_live WHERE archived_at IS NULL ORDER BY last_active_at DESC, rowid DESC LIMIT ?2) s
  #|  WHERE s.running = 1 OR s.key IN (SELECT value FROM json_each(?1)) OR EXISTS (SELECT 1 FROM active_watch_jobs INDEXED BY active_watch_jobs_session WHERE session = s.key)
  #|    OR EXISTS (SELECT 1 FROM active_other_jobs WHERE session = s.key)
  #|    OR (SELECT declared FROM turns INDEXED BY turns_by_session WHERE session_key = s.key ORDER BY started_at DESC, rowid DESC LIMIT 1) = 'waiting'
  #|  ORDER BY s.last_active_at DESC, s.rid DESC

///|
/// jobs/workspace-size.ts SESSIONS_AT_WORK_BEFORE_UPGRADE.
let sessions_at_work_before_upgrade : String =
  #|SELECT s.key, s.workspace FROM (SELECT rowid AS rid, key, workspace, running, last_active_at
  #|  FROM sessions INDEXED BY sessions_live WHERE archived_at IS NULL ORDER BY last_active_at DESC, rowid DESC LIMIT ?2) s
  #|  WHERE s.running = 1 OR s.key IN (SELECT value FROM json_each(?1)) OR EXISTS (SELECT 1 FROM jobs INDEXED BY jobs_by_session WHERE session_key = s.key AND state = 'running')
  #|    OR (SELECT declared FROM turns INDEXED BY turns_by_session WHERE session_key = s.key ORDER BY started_at DESC, rowid DESC LIMIT 1) = 'waiting'
  #|  ORDER BY s.last_active_at DESC, s.rid DESC

///|
/// store/store.ts LATEST_DECISIONS_SCOPED.
let latest_decisions_scoped : String =
  #|WITH RECURSIVE
  #|
  #|
  #|recent AS MATERIALIZED (
  #|  SELECT id FROM decision_checks INDEXED BY decision_checks_lately WHERE ?3 = 0 AND created_at >= ?1 LIMIT 65
  #|),
  #|
  #|connects(connect, n) AS (
  #|  SELECT (SELECT connect FROM sessions INDEXED BY sessions_by_connect ORDER BY connect LIMIT 1), 1
  #|  WHERE (SELECT COUNT(*) FROM recent) = 65
  #|  UNION ALL
  #|  SELECT (SELECT connect FROM sessions INDEXED BY sessions_by_connect WHERE connect > c.connect ORDER BY connect LIMIT 1), n + 1
  #|  FROM connects c WHERE c.connect IS NOT NULL AND n < 65
  #|),
  #|chosen AS MATERIALIZED (
  #|  SELECT s.key FROM connects c CROSS JOIN sessions s INDEXED BY sessions_by_connect
  #|  WHERE c.connect IS NOT NULL AND s.connect = c.connect AND s.ws = ?2 LIMIT 65
  #|),
  #|lookups AS MATERIALIZED (
  #|  SELECT c.key, (SELECT id FROM (
  #|    SELECT id, created_at FROM decision_checks INDEXED BY decision_checks_session WHERE session = c.key ORDER BY id DESC LIMIT 65
  #|  ) WHERE created_at >= ?1 ORDER BY id DESC LIMIT 1) AS id
  #|  FROM chosen c WHERE (SELECT COUNT(connect) FROM connects) <= 64 AND (SELECT COUNT(*) FROM chosen) <= 64
  #|),
  #|mode AS MATERIALIZED (
  #|  SELECT (SELECT COUNT(*) FROM recent) < 65 OR (SELECT COUNT(connect) FROM connects) > 64
  #|    OR (SELECT COUNT(*) FROM chosen) > 64 OR EXISTS (
  #|      SELECT 1 FROM lookups l WHERE l.id IS NULL AND EXISTS (
  #|        SELECT 1 FROM decision_checks INDEXED BY decision_checks_session WHERE session = l.key ORDER BY id DESC LIMIT 1 OFFSET 64
  #|      )
  #|    ) AS use_global
  #|),
  #|latest AS MATERIALIZED (
  #|  SELECT MAX(id) AS id, session FROM mode CROSS JOIN decision_checks WHERE use_global AND created_at >= ?1 GROUP BY +session
  #|  UNION ALL
  #|  SELECT id, key AS session FROM lookups WHERE id IS NOT NULL AND NOT (SELECT use_global FROM mode)
  #|)
  #|SELECT d.id, d.session, d.created_at, d.result FROM latest l
  #|LEFT JOIN sessions s ON s.key = l.session
  #|CROSS JOIN decision_checks d ON d.id = l.id
  #|WHERE s.ws = ?2 OR (?3 AND s.ws IS NULL)
  #|ORDER BY d.created_at, d.id

///|
/// store/store.ts LATEST_DECISIONS_SCOPED_FALLBACK.
let latest_decisions_scoped_fallback : String =
  #|WITH latest AS MATERIALIZED (
  #|  SELECT MAX(id) AS id, session FROM decision_checks WHERE created_at >= ?1 GROUP BY +session
  #|)
  #|SELECT d.id, d.session, d.created_at, d.result FROM latest l
  #|LEFT JOIN sessions s ON s.key = l.session
  #|CROSS JOIN decision_checks d ON d.id = l.id
  #|WHERE s.ws = ?2 OR (?3 AND s.ws IS NULL)
  #|ORDER BY d.created_at, d.id

///|
/// store/store.ts RECENT_CONNECT_THREADS.
let recent_connect_threads : String =
  #|WITH recent AS MATERIALIZED (
  #|  SELECT t.id, t.surface, t.created_at, COALESCE(e.at, 0) AS said_at
  #|  FROM threads t LEFT JOIN thread_state s ON s.thread = t.id
  #|  LEFT JOIN entries e ON e.thread = t.id AND e.n = s.said_n AND e.kind = 'message'
  #|  ORDER BY said_at DESC, t.created_at DESC, t.id DESC LIMIT ?1
  #|) SELECT r.id, r.surface FROM recent r
  #|  WHERE EXISTS (SELECT 1 FROM thread_sessions m WHERE m.thread = r.id AND m.connect = ?2)
  #|  ORDER BY r.said_at DESC, r.created_at DESC, r.id DESC

///|
/// The most of the sessions shown a round of workspace measuring looks at (workspace-size.ts MEASURED_MOST).
const MEASURED_MOST = 1000

///|
/// How many chats an option of the archive policy's view lists (archive-policy.ts VIEW_CHATS).
const VIEW_CHATS = 20

///|
fn sql_message(e : Error) -> String {
  match e {
    @wire.ShellError(m) => m
    Failure(m) => m
    e => e.to_string()
  }
}

///|
/// workspace-size.ts `workspaceSessionsToMeasure`: the sessions shown that are at work; `processes`, those whose
/// process runs now.
pub fn sessions_at_work(db : @sql.Db, args : Json) -> Json raise {
  let processes = args.value("processes").unwrap_or(Json::array([]))
  let params = [Json::string(processes.stringify()), Json::number(MEASURED_MOST.to_double())]
  let rows = db.all(sessions_at_work_sql, params) catch {
    e => {
      let m = sql_message(e)
      guard m.contains("no such table: active_watch_jobs") || m.contains("no such table: active_other_jobs") else { raise e }
      db.all(sessions_at_work_before_upgrade, params)
    }
  }
  Json::array(rows.map(r => ({ "key": field(r, "key"), "workspace": field(r, "workspace") } : Json)))
}

///|
fn sqlite_has(db : @sql.Db, kind : String, name : String) -> Bool raise {
  one(db, "SELECT 1 FROM sqlite_master WHERE type=? AND name=?", [Json::string(kind), Json::string(name)]) is Some(_)
}

///|
/// legacy-decision-time.ts `hasLegacyDecisionTime`: whether the older store's decision-time lookup is still kept.
fn has_legacy_decision_time(db : @sql.Db) -> Bool raise {
  if !sqlite_has(db, "table", "legacy_decision_time_meta") {
    return false
  }
  if !sqlite_has(db, "table", "legacy_decision_time") {
    fail("legacy decision-time metadata has no lookup")
  }
  match one(db, "SELECT version,complete FROM legacy_decision_time_meta WHERE id=1", []) {
    Some(r) if field(r, "version") is Number(1.0, ..) && field(r, "complete") is Number(0.0 | 1.0, ..) => true
    _ => fail("legacy decision-time lookup has an unsupported version")
  }
}

///|
/// policy-checks.ts `policyChecksRead`: what the checks since `since` say of `viewer`'s workspace's chats (each chat's
/// latest, as archive-policy.ts `policyChecks` counts them); null while their lookups are being prepared.
pub fn policy_checks(db : @sql.Db, args : Json) -> Json raise {
  if has_legacy_decision_time(db) || !sqlite_has(db, "index", "decision_checks_lately") || !sqlite_has(db, "index", "decision_checks_session") {
    return Json::null()
  }
  let viewer = args.value("viewer").unwrap_or(Json::null())
  let home = !(viewer.value("home") is Some(False))
  let params = [args.value("since").unwrap_or(Json::null()), viewer.value("workspace").unwrap_or(Json::null()), Json::number(if home { 1.0 } else { 0.0 })]
  let rows = db.all(if home { latest_decisions_scoped_fallback } else { latest_decisions_scoped }, params) catch {
    e => {
      let m = sql_message(e)
      if m.contains("no such index") || m.contains("no such table") {
        return Json::null()
      }
      raise e
    }
  }
  // Each chat's latest, in the order each was first seen (a Map's), newest first after.
  let order : Array[String] = []
  let latest : Map[String, (Json, @jsjson.JValue?)] = Map([])
  for r in rows {
    guard field(r, "session") is String(session) else { continue }
    if !latest.contains(session) {
      order.push(session)
    }
    latest[session] = (field(r, "created_at"), parsed(field(r, "result")))
  }
  let options : Map[String, (Int, Array[Json])] = Map([])
  let picks : Array[String] = []
  let mut failed = 0
  for session in order.rev() {
    guard latest.get(session) is Some((at, detail)) else { continue }
    guard str_of(jget(jget(detail, "result"), "selected")) is Some(picked) else {
      failed += 1
      continue
    }
    let (count, chats) = match options.get(picked) {
      Some(o) => o
      None => {
        picks.push(picked)
        (0, [])
      }
    }
    if chats.length() < VIEW_CHATS {
      chats.push({ "session": Json::string(session), "at": at, "recommended": Json::boolean(jget(detail, "accepted") is Some(Bool(true))) })
    }
    options[picked] = (count + 1, chats)
  }
  let shown : Map[String, Json] = Map([])
  for p in picks {
    guard options.get(p) is Some((count, chats)) else { continue }
    shown[p] = { "count": Json::number(count.to_double()), "chats": Json::array(chats) }
  }
  { "checked": Json::number(order.length().to_double()), "failed": Json::number(failed.to_double()), "options": Json::object(shown) }
}

///|
/// store.ts `recentConnectPeople`: the people of a connect's recent threads, by their user ids on its platform.
pub fn recent_connect_people(db : @sql.Db, args : Json) -> Json raise {
  let connect = args.value("connect").unwrap_or(Json::null())
  let prefix = "slack:" + (match connect { String(c) => c; c => c.stringify() }) + ":"
  let out = []
  for r in db.all(recent_connect_threads, [args.value("limit").unwrap_or(Json::null()), connect]) {
    let thread = field(r, "id")
    let first = match one(db, "SELECT MIN(connect) AS c FROM thread_sessions WHERE thread = ?", [thread]) {
      Some(row) => field(row, "c")
      None => Json::null()
    }
    let authors = db.all("SELECT author FROM thread_people WHERE thread = ? ORDER BY first_n", [thread]).filter_map(a => match field(a, "author") {
      String(s) => Some(s)
      _ => None
    })
    let people = if field(r, "surface") == Json::string("ember") {
      authors
    } else {
      match first {
        String(c) => authors.map(a => "slack:\{c}:\{a}")
        _ => []
      }
    }
    out.push(({
      "thread": thread,
      "people": Json::array(people.filter_map(p => if p.has_prefix(prefix) { Some(Json::string(p.view(start_offset=prefix.length()).to_owned())) } else { None })),
    } : Json))
  }
  Json::array(out)
}
