// A reader of the station's database (station/src/read/pool.ts), in MoonBit: its asks come as lines of JSON on stdin,
// as the TypeScript reader's come by postMessage (read/worker.ts `Ask`), and its answers go out as lines on stdout
// (`Answer`), first a line saying it is ready. It answers what it has been moved here for, so far `checkpoint`; the
// pool sends it nothing else. With `--builder`, it is one of the builders of old state instead (`builder` below).

///|
/// The connection a checkpoint is made on: one that may write, made at the first, used for nothing else.
struct Reader {
  host : @host.Host
  db : String
  mut writer : Int64?
  /// The connection reads are made on, made at the first.
  mut reading : @sql.Db?
  /// The station's data directory, its paths' separator, and where transcripts were found (kept between reads).
  data : String
  sep : String
  finder : @locate.Finder
}

///|
/// What of the log (the WAL) is not in the database yet, written into it as far as no reader still reads it: a passive
/// checkpoint, waiting for no one (read/worker.ts `checkpoint`). Its row, by its columns' names.
fn Reader::checkpoint(self : Reader) -> Json raise {
  let id = match self.writer {
    Some(id) => id
    None => {
      let opened = self.host.shell_sync("sql.attach", { "path": Json::string(self.db), "wait": 0 })
      guard opened is { "id": Number(n, ..), .. } else { fail("no database id") }
      let id = n.to_int64()
      self.writer = Some(id)
      id
    }
  }
  let all = self.host.shell_sync("sql.all", {
    "id": Json::number(id.to_double()),
    "sql": "PRAGMA wal_checkpoint(PASSIVE)",
    "named": true,
  })
  guard all is { "columns": Array(columns), "rows": Array(rows), .. } else { fail("no rows") }
  guard rows is [Array(row), ..] else { return Json::null() }
  let out : Map[String, Json] = Map([])
  for i, column in columns {
    guard column is String(name) else { continue }
    out[name] = row[i]
  }
  Json::object(out)
}

///|
fn Reader::answer(self : Reader, line : String) -> Json {
  let ask = @json.parse(line) catch {
    e => return { "id": Json::null(), "status": 400, "error": Json::string("not JSON: \{e}") }
  }
  let id = match ask {
    { "id": id, .. } => id
    _ => Json::null()
  }
  match ask {
    { "op": "checkpoint", .. } =>
      try {
        { "id": id, "text": Json::string(self.checkpoint().stringify()) }
      } catch {
        e => { "id": id, "status": 500, "error": Json::string(message(e)) }
      }
    { "op": String(op), .. } if moved(op) =>
      try {
        @readops.prepare_up_jobs.val = None
        @readops.prepare_workspace_up_jobs.val = false
        let answer : Map[String, Json] = { "id": id, "text": Json::string(self.read(op, ask).stringify()) }
        // (an old session whose up jobs' lookup the pool is to prepare now: read/worker.ts `prepareUpJobs`)
        if @readops.prepare_up_jobs.val is Some(session) {
          answer["prepareUpJobs"] = Json::string(session)
        }
        if @readops.prepare_workspace_up_jobs.val {
          answer["prepareWorkspaceUpJobs"] = true
        }
        Json::object(answer)
      } catch {
        @readops.Refused(status, m) => { "id": id, "status": Json::number(status.to_double()), "error": Json::string(m) }
        e => { "id": id, "status": 500, "error": Json::string(message(e)) }
      }
    { "op": String(op), .. } => { "id": id, "status": 500, "error": Json::string("no read \{op}") }
    _ => { "id": id, "status": 400, "error": Json::string("no op") }
  }
}

///|
/// The reads moved here from read/worker.ts (read/pool.ts `MOVED`).
fn moved(op : String) -> Bool {
  ["job", "jobLog", "historyPendingCard", "statePendingCard", "deliveryCardState", "reviewPendingCard", "stateQuestion", "pendingDeliveries", "latestMessages", "chatHistoryMessages", "openedChatSaid", "widgetState", "transcriptFile", "memory", "machineSessions", "machineSession", "sessionsAtWork", "policyChecks", "recentConnectPeople", "usageTurns", "usageCalls", "outflowMessages", "archiveLook", "recentChatList", "searchChatList", "threadList", "sharedOf", "sharedChats", "chatMarks", "entries", "letters", "summary", "sessions", "session", "threads", "thread", "turnNotices", "saidNotices", "chats", "chatRows", "outflowChats", "openJobs", "resourceChats", "usage", "outflowUsage"].contains(
    op,
  )
}

///|
/// A read, in one snapshot as read/worker.ts makes it (a transaction around it).
fn Reader::read(self : Reader, op : String, ask : Json) -> Json raise {
  let args = ask.value("args").unwrap_or(Json::null())
  let db = match self.reading {
    Some(db) => db
    None => {
      let db = @sql.Db::attach(self.host, self.db, wait=5000)
      self.reading = Some(db)
      db
    }
  }
  // read/worker.ts `learn`: the model catalog as the pool gives it when it changed
  if ask.value("catalog") is Some(models) {
    @readops.learn_catalog(models)
  }
  db.exec("BEGIN")
  defer (db.exec("COMMIT") catch { _ => () })
  match op {
    "job" => @readops.job(db, self.host, args)
    "jobLog" => @readops.job_log(db, self.host, args)
    "historyPendingCard" => @readops.pending_card_number(db, args.value("thread").unwrap_or(Json::null()))
    "statePendingCard" => @readops.state_pending_card(db, args)
    "deliveryCardState" => @readops.delivery_card_state(db, args)
    "reviewPendingCard" => @readops.review_pending_card(db, args)
    "stateQuestion" => @readops.state_question(db, args)
    "pendingDeliveries" => @readops.pending_deliveries(db, args)
    "latestMessages" => @readops.latest_messages(db, args)
    "chatHistoryMessages" => @readops.chat_history_messages(db, args)
    "openedChatSaid" => @readops.opened_chat_said(db, args)
    "widgetState" => @readops.widget_state(db, args)
    "transcriptFile" => @readops.transcript_file(db, self.host, self.data, self.sep, self.finder, args)
    "memory" => @readops.memory(self.host, self.data, self.sep, args)
    "machineSessions" => @readops.machine_sessions(db, self.host, self.sep, args)
    "machineSession" => @readops.machine_session(db, self.host, self.sep, args)
    "sessionsAtWork" => @readops.sessions_at_work(db, args)
    "policyChecks" => @readops.policy_checks(db, args)
    "recentConnectPeople" => @readops.recent_connect_people(db, args)
    "usageTurns" => @readops.usage_turns(db, args)
    "usageCalls" => @readops.usage_calls(db, args)
    "outflowMessages" => @readops.outflow_messages(db, self.host, self.data, self.sep, args)
    "archiveLook" => @readops.archive_look(db, args)
    "recentChatList" => @readops.recent_chat_list(db, args)
    "searchChatList" => @readops.search_chat_list(db, args)
    "threadList" => @readops.thread_list(db)
    "sharedOf" => @readops.shared_of(db, self.host, self.data, self.sep, ask)
    "sharedChats" => @readops.shared_chats(db, self.host, self.data, self.sep, ask)
    "chatMarks" => @readops.chat_marks(db, self.host, self.data, self.sep, ask)
    "entries" => @readops.thread_entries(db, self.host, self.data, self.sep, ask)
    "letters" => @readops.thread_letters(db, self.host, self.data, self.sep, ask)
    "summary" => @readops.session_summary(db, self.host, self.data, self.sep, ask)
    "sessions" => @readops.session_list(db, self.host, self.data, self.sep, ask)
    "session" => @readops.session_page(db, self.host, self.data, self.sep, ask)
    "threads" => @readops.thread_list_of(db, self.host, self.data, self.sep, ask)
    "thread" => @readops.thread_of(db, self.host, self.data, self.sep, ask)
    "turnNotices" => @readops.turn_notices(db, self.host, self.data, self.sep, ask)
    "saidNotices" => @readops.said_notices(db, self.host, self.data, self.sep, ask)
    "chats" => @readops.viewer_chat_list(db, self.host, self.data, self.sep, ask)
    "chatRows" => @readops.viewer_chat_rows(db, self.host, self.data, self.sep, ask)
    "outflowChats" => @readops.outflow_chats(db, self.host, self.data, self.sep, ask)
    "openJobs" => @readops.open_jobs(db, self.host, self.data, self.sep, ask)
    "resourceChats" => @readops.resource_chats(db, self.host, self.data, self.sep, ask)
    "usage" => @readops.usage_page(db, self.host, self.data, self.sep, ask)
    "outflowUsage" => @readops.outflow_usage(db, self.host, self.data, self.sep, ask)
    _ => fail("no read \{op}")
  }
}

///|
fn message(e : Error) -> String {
  match e {
    @wire.ShellError(m) => m
    Failure(m) => m
    e => e.to_string()
  }
}

///|
/// The backfill permit as a builder that takes it only for its writes asks the pool for it (read/requested-builder.ts
/// `lazy`): a line `{"take": true}` answered `{"permit": …}`, and `{"give": true}` when it is done with it before
/// answering (an answer gives it back as well).
struct Permit {
  host : @host.Host
  mut holding : Bool
}

///|
async fn Permit::take(self : Permit) -> Bool {
  if self.holding {
    return true
  }
  let ask : Json = { "take": true }
  self.host.say(ask.stringify())
  guard self.host.line() is Some(line) else { return false }
  let reply : Json = @json.parse(line) catch { _ => Json::null() }
  self.holding = reply is { "permit": True, .. }
  self.holding
}

///|
fn Permit::give(self : Permit) -> Unit {
  if self.holding {
    let given : Json = { "give": true }
    self.host.say(given.stringify())
    self.holding = false
  }
}

///|
/// The builder of the sessions' turn counts (said-worker.ts's `session` asks): a count kept going between asks; one
/// let go (`cancel`) has its guard removed, under the permit.
async fn turn_builder(host : @host.Host, db_path : String) -> Unit {
  let db = @sql.Db::attach(host, db_path, wait=250)
  db.exec("PRAGMA synchronous = NORMAL")
  let permit = { host, holding: false }
  let counts : Map[String, @turns.Scan] = Map([])
  let tokens = Ref(0)
  let token = () => {
    tokens.val += 1
    "\{@host.now()}-\{tokens.val}-\{@host.pid()}"
  }
  while host.line() is Some(line) {
    if line == "" {
      continue
    }
    let ask : Json = @json.parse(line) catch { _ => Json::null() }
    guard ask is { "session": String(session), .. } else {
      let invalid : Json = { "done": false, "error": "invalid old turn counts preparation request" }
      host.say(invalid.stringify())
      continue
    }
    if ask is { "cancel": True, .. } {
      if counts.get(session) is Some(scan) {
        counts.remove(session)
        if permit.take() {
          // (a later request or a write replaces the guard: a failure here is nothing)
          ignore(
            db.run("DELETE FROM session_turns_guard WHERE session=? AND token=?", [
              Json::string(session),
              Json::string(scan.token()),
            ]),
          ) catch {
            _ => ()
          }
          permit.give()
        }
      }
      continue
    }
    let answer : Json = try {
      let (done, scan) = @turns.step(db, session, counts.get(session), token~, may_write=() => permit.take())
      match scan {
        Some(scan) => counts[session] = scan
        None => counts.remove(session)
      }
      { "done": Json::boolean(done) }
    } catch {
      e => if @sql.busy(e) { { "done": false } } else { { "done": false, "error": Json::string(message(e)) } }
    }
    permit.holding = false
    host.say(answer.stringify())
  }
}

///|
/// The builder of the sidebar's said state (said-worker.ts's `thread` asks without a flag): a search kept going between
/// asks; one let go (`cancel`) has its guard removed, under the permit, if it is not ready. A store read through the
/// legacy lookup is the worker's: answered `{"fallback": true}`, the pool asks the worker instead.
async fn said_builder(host : @host.Host, db_path : String) -> Unit {
  let db = @sql.Db::attach(host, db_path, wait=250)
  db.exec("PRAGMA synchronous = NORMAL")
  let permit = { host, holding: false }
  let scans : Map[Int64, @said.Scan] = Map([])
  let tokens = Ref(0)
  let token = () => {
    tokens.val += 1
    "\{@host.now()}-\{tokens.val}-\{@host.pid()}"
  }
  while host.line() is Some(line) {
    if line == "" {
      continue
    }
    let ask : Json = @json.parse(line) catch { _ => Json::null() }
    guard ask is { "thread": Number(n, ..), .. } else {
      let invalid : Json = { "done": false, "error": "invalid sidebar said state preparation request" }
      host.say(invalid.stringify())
      continue
    }
    let thread = n.to_int64()
    if ask is { "cancel": True, .. } {
      if scans.get(thread) is Some(scan) {
        scans.remove(thread)
        if permit.take() {
          // (a later request or a write replaces the guard: a failure here is nothing)
          ignore(
            db.run("DELETE FROM said_state_guard WHERE thread=? AND token=? AND ready=0", [
              Json::number(thread.to_double()),
              Json::string(scan.token()),
            ]),
          ) catch {
            _ => ()
          }
          permit.give()
        }
      }
      continue
    }
    let answer : Json = try {
      if @said.legacy(db) {
        { "fallback": true }
      } else {
        let (done, scan) = @said.step(db, thread, scans.get(thread), token~, may_write=() => permit.take())
        match scan {
          Some(scan) => scans[thread] = scan
          None => scans.remove(thread)
        }
        { "done": Json::boolean(done) }
      }
    } catch {
      e => if @sql.busy(e) { { "done": false } } else { { "done": false, "error": Json::string(message(e)) } }
    }
    permit.holding = false
    host.say(answer.stringify())
  }
}

///|
/// The builder of the sessions' copy destinations, chat names' order and latest conversation (cc-index-worker.ts):
/// `{"session"}` with `name` or `latest` for the last two; one let go (`cancel`) forgets where its lanes' turn was.
async fn cc_builder(host : @host.Host, db_path : String) -> Unit {
  let db = @sql.Db::attach(host, db_path, wait=250)
  db.exec("PRAGMA synchronous = NORMAL")
  let cc = @cc.Cc::new()
  let names = @cc.Cc::new()
  while host.line() is Some(line) {
    if line == "" {
      continue
    }
    let ask : Json = @json.parse(line) catch { _ => Json::null() }
    guard ask is { "session": String(session), .. } else {
      let invalid : Json = { "done": false, "error": "invalid session conversation preparation request" }
      host.say(invalid.stringify())
      continue
    }
    let named = ask is { "name": True, .. }
    let latest = ask is { "latest": True, .. }
    if ask is { "cancel": True, .. } {
      if !latest {
        (if named { names } else { cc }).cancel(session)
      }
      continue
    }
    let answer : Json = try {
      let done = if latest {
        @cc.latest_step(db, session)
      } else if named {
        names.names_step(db, session)
      } else {
        // (as the worker asks it: a session not there is tracked all the same)
        cc.step(db, session, existing=false)
      }
      { "done": Json::boolean(done) }
    } catch {
      e => if @sql.busy(e) { { "done": false } } else { { "done": false, "error": Json::string(message(e)) } }
    }
    host.say(answer.stringify())
  }
}

///|
/// The checker of the kept statistics' coverage (usage/minute-worker.ts): `{id, viewer}`, `{id, detail}`, `{id,
/// remote}` or `{id, chats}` answered `{id}` when complete, `{id, error}` when not; `{"complete": true}` said first
/// when every statistic is.
async fn usage_checker(host : @host.Host, db_path : String) -> Unit {
  let db = @sql.Db::attach(host, db_path, wait=250)
  if @usage.complete(db) {
    let complete : Json = { "complete": true }
    host.say(complete.stringify())
  }
  while host.line() is Some(line) {
    if line == "" {
      continue
    }
    let ask : Json = @json.parse(line) catch { _ => Json::null() }
    let id = match ask {
      { "id": id, .. } => id
      _ => Json::null()
    }
    let answer : Json = try {
      let (ready, name) = match ask {
        { "viewer": _, .. } => (@usage.minutes_ready(db), "minute")
        { "detail": v, .. } => (@usage.detail_ready(db, v), "detail")
        { "chats": v, .. } => (@usage.chats_ready(db, v), "chat and card")
        _ => (@usage.remote_ready(db), "remote task")
      }
      if ready {
        { "id": id }
      } else {
        { "id": id, "error": Json::string("historical \{name} statistics are unavailable") }
      }
    } catch {
      e => { "id": id, "error": Json::string(message(e)) }
    }
    host.say(answer.stringify())
  }
}

///|
/// A step of what is built whole (`{"scope": "all"}`).
fn all(step : (@sql.Db) -> Bool raise) -> (@sql.Db, Json) -> Bool? raise {
  (db, ask) => if ask is { "scope": "all", .. } { Some(step(db)) } else { None }
}

///|
/// `name` in the directory `path` is in (the station's data directory: its database's).
fn beside(path : String, name : String) -> String {
  let slash = path.rev_find("/").unwrap_or(-1)
  let back = path.rev_find("\\").unwrap_or(-1)
  let cut = if slash > back { slash } else { back }
  if cut < 0 {
    name
  } else {
    path.exact_view(end=cut + 1).to_owned() + name
  }
}

///|
/// The value after `name` among the program's arguments.
fn flag(name : String) -> String? {
  let args = @host.args()
  for i = 0; i + 1 < args.length(); i = i + 1 {
    if args[i] == name {
      return Some(args[i + 1])
    }
  }
  None
}

///|
/// A builder of old state, as a builder worker is (read/requested-builder.ts): each line asks for a batch of `scope`
/// (`{"scope": "all"}`; one with `cancel` is let go), each answer says whether all is done, or why not. A database busy
/// with another's write is no error: the batch is asked again. The pool takes the backfill permit around each ask.
/// `step`: one batch of what it builds for what it was asked (None: what it does not build; `name`, said then). A
/// store it leaves to the worker (`@legacy.Fallback`) is answered `{"fallback": true}`.
async fn builder(host : @host.Host, db_path : String, name : String, step : (@sql.Db, Json) -> Bool? raise) -> Unit {
  let db = @sql.Db::attach(host, db_path, wait=250)
  db.exec("PRAGMA synchronous = NORMAL")
  while host.line() is Some(line) {
    if line == "" {
      continue
    }
    let ask : Json = @json.parse(line) catch { _ => Json::null() }
    if ask is { "cancel": True, .. } {
      continue
    }
    let answer : Json = try {
      match step(db, ask) {
        Some(done) => { "done": Json::boolean(done) }
        None => { "done": false, "error": Json::string("invalid \{name} preparation request") }
      }
    } catch {
      @legacy.Fallback => { "fallback": true }
      e => if @sql.busy(e) { { "done": false } } else { { "done": false, "error": Json::string(message(e)) } }
    }
    host.say(answer.stringify())
  }
}

///|
/// The usage statistics' workspace upkeep (usage/scope-worker.ts): each `{"wake": true, scope?, range?}` a batch,
/// answered as the worker answers (`done`, and `session`, `sessions`, `from`, `after`, `converted` where they apply).
async fn usage_scope(host : @host.Host, db_path : String) -> Unit {
  let db = @sql.Db::attach(host, db_path, wait=250)
  db.exec("PRAGMA synchronous = NORMAL")
  while host.line() is Some(line) {
    if line == "" {
      continue
    }
    let ask : Json = @json.parse(line) catch { _ => Json::null() }
    guard ask is { "wake": True, .. } else { continue }
    let answer : Json = @usagefill.scope_batch(db, ask) catch {
      e => if @sql.busy(e) { { "done": false } } else { { "done": false, "error": Json::string(message(e)) } }
    }
    host.say(answer.stringify())
  }
}

///|
/// The vault's use reader (vault/use-index.ts `UseIndex`): each line an operation (@vaultuses.operate), answered
/// `{"busy": true}` while another's write holds the database, `{"error"}` when it failed.
async fn vault_uses(host : @host.Host, db_path : String) -> Unit {
  let db = @sql.Db::attach(host, db_path, wait=100)
  db.exec("PRAGMA synchronous = NORMAL")
  while host.line() is Some(line) {
    if line == "" {
      continue
    }
    let answer : Json = @vaultuses.operate(db, line) catch {
      e => if @sql.busy(e) { { "busy": true } } else { { "error": Json::string(message(e)) } }
    }
    host.say(answer.stringify())
  }
}

///|
/// The export of the station's conversations (replica/runner.ts `MbRunner`, in its worker's place): each line an ask
/// `{id, type, …}` (`places`, `pass`, `newGenerations`, `sources`, `close`), answered `{id, answer}` or `{id, error}`,
/// one at a time. The time is the station's, said with each ask (`now`).
async fn replica_export(host : @host.Host, db : String, replica : String, data_dir : String, origin : String, sep : String) -> Unit {
  let clock = Ref(0.0)
  // (a test's: batches smaller than BATCH_BYTES, or left as written)
  let batch_bytes = match flag("--batch-bytes") {
    Some(n) => @string.parse_int(n) catch { _ => @replica.batch_bytes }
    None => @replica.batch_bytes
  }
  let fold = !@host.args().contains("--no-fold")
  let exporter = @replica.Exporter::new(host, sep, db, replica, data_dir, origin, () => clock.val, batch_bytes~, fold~) catch {
    e => {
      let failed : Json = { "failed": Json::string(message(e)) }
      host.say(failed.stringify())
      return
    }
  }
  while host.line() is Some(line) {
    if line == "" {
      continue
    }
    let ask = @jsjson.parse(line) catch { _ => @jsjson.JValue::Null }
    let id = match ask.get("id") {
      Some(Num(n)) => n
      _ => 0.0
    }
    if ask.get("now") is Some(Num(now)) {
      clock.val = now
    }
    let kind = match ask.get("type") {
      Some(Str(u)) => @jsjson.text(u)
      _ => ""
    }
    let answer : Result[@jsjson.JValue, String] = try {
      match kind {
        "places" => {
          exporter.set_places(ask.get("places").unwrap_or(Null))
          Ok(Null)
        }
        "pass" => Ok(exporter.pass(ask.get("told").unwrap_or(Null)))
        "newGenerations" => {
          exporter.new_generations(match ask.get("after") { Some(Num(a)) => a; _ => 0.0 })
          Ok(Null)
        }
        "sources" => {
          let hashes = match ask.get("hashes") {
            Some(Arr(items)) => items.filter_map(h => if h is Str(u) { Some(@jsjson.text(u)) } else { None })
            _ => []
          }
          Ok(exporter.sources(hashes))
        }
        "close" => {
          exporter.close()
          host.say("{\"id\":\{@jsjson.stringify(Num(id))},\"answer\":null}")
          return
        }
        _ => Err("no such ask: \{kind}")
      }
    } catch {
      e => Err(message(e))
    }
    match answer {
      Ok(v) => host.say("{\"id\":\{@jsjson.stringify(Num(id))},\"answer\":\{@jsjson.stringify(v)}}")
      Err(m) => {
        let failed : Json = { "id": Json::number(id), "error": Json::string(m) }
        host.say(failed.stringify())
      }
    }
  }
  exporter.close()
}

///|
/// The live view's transcript locator (sessions/live-locator.ts): each line a `locate` or a reply to one being looked
/// for (@locate.Locator).
async fn live_locator(host : @host.Host, db_path : String, data : String, sep : String) -> Unit {
  let locator = @locate.Locator::new(host, @sql.Db::attach(host, db_path, wait=5000), data, sep)
  while host.line() is Some(line) {
    if line != "" {
      locator.heard(line)
    }
  }
}

///|
/// The search (search/worker.ts): each `{"type": "query"}` looked for in a fiber of its own, the searches taking turns
/// where the worker let others through, answered `{id, groups}` or `{id, error}`; `{"type": "cancel", id}` stops one.
/// Where transcripts were found is kept between searches, as the worker keeps it.
async fn search_program(host : @host.Host, db_path : String, data : String, sep : String) -> Unit {
  let db = @sql.Db::attach(host, db_path, wait=5000)
  let finder = @locate.Finder::new(host, sep)
  let cancelled : Set[String] = Set([])
  while host.line() is Some(line) {
    let told : Json = @json.parse(line) catch { _ => continue }
    guard told is { "id": id, .. } else { continue }
    let key = id.stringify()
    match told {
      { "type": "cancel", .. } => cancelled.add(key)
      { "type": "query", .. } =>
        ignore(
          host.rt.fork(() => {
            let answer : Json = try {
              { "id": id, "groups": Json::array(@history.answer(db, host, data, sep, finder, told, () => cancelled.contains(key))) }
            } catch {
              e => { "id": id, "error": Json::string(@search.describe(e)) }
            }
            cancelled.remove(key)
            host.say(answer.stringify())
          }),
        )
      _ => ()
    }
  }
}

///|
fn main {
  let code = match (flag("--builder"), flag("--db"), flag("--data")) {
    (Some("archive-marks"), Some(db), _) =>
      @host.run(shell_dir=beside(db, "shell"), host => builder(host, db, "archive mark", all(db => @marks.step(db))))
    (Some("session-bindings"), Some(db), _) =>
      @host.run(shell_dir=beside(db, "shell"), host => builder(host, db, "session binding", all(db => @bindings.step(db))))
    (Some("session-up-jobs"), Some(db), _) =>
      @host.run(shell_dir=beside(db, "shell"), host => builder(host, db, "session up jobs", (db, ask) => match ask {
        { "session": String(session), .. } => Some(@upjobs.step(db, session))
        _ => None
      }))
    (Some("widget-sources"), Some(db), _) =>
      @host.run(shell_dir=beside(db, "shell"), host => builder(host, db, "widget source", (db, ask) => match ask {
        { "thread": Number(thread, ..), .. } => Some(@widgets.step(db, thread.to_int64()))
        _ => None
      }))
    (Some("card-posts"), Some(db), _) =>
      @host.run(shell_dir=beside(db, "shell"), host => builder(host, db, "card post", (db, ask) => match ask {
        { "thread": Number(thread, ..), .. } => Some(@cards.step(db, thread.to_int64()))
        _ => None
      }))
    (Some("closed-cards"), Some(db), _) =>
      @host.run(shell_dir=beside(db, "shell"), host => builder(host, db, "closed card", (db, ask) => match ask {
        { "thread": Number(thread, ..), .. } => Some(@lookups.closed_step(db, thread.to_int64()))
        _ => None
      }))
    (Some("people-since"), Some(db), _) =>
      @host.run(shell_dir=beside(db, "shell"), host => builder(host, db, "people-time", (db, ask) => match ask {
        { "thread": Number(thread, ..), .. } => Some(@lookups.people_step(db, thread.to_int64()))
        _ => None
      }))
    (Some("legacy-edits"), Some(db), _) =>
      @host.run(shell_dir=beside(db, "shell"), host => builder(host, db, "legacy edits", (db, ask) => match ask {
        { "thread": Number(_, ..), .. } => Some(@legacy.edits_step(db))
        _ => None
      }))
    (Some("legacy-said"), Some(db), _) =>
      @host.run(shell_dir=beside(db, "shell"), host => builder(host, db, "legacy said", (db, ask) => match ask {
        { "thread": Number(_, ..), .. } => Some(@legacy.said_step(db))
        _ => None
      }))
    (Some("session-counts"), Some(db), _) =>
      // (a backfill the station drives itself: each line, whatever it says, asks for the next batch)
      @host.run(shell_dir=beside(db, "shell"), host => builder(host, db, "session count", (db, _) => Some(@counts.step(db))))
    (Some("session-backfill"), Some(db), _) =>
      // (the backfills sessions/workspace-activity-worker.ts makes by `kind`, none: the activity; those not here yet
      // are left to it)
      @host.run(shell_dir=beside(db, "shell"), host => {
        let letters : Ref[@letters.Letters?] = Ref(None)
        builder(host, db, "session backfill", (db, ask) => match ask {
        { "kind": "activity", .. } => Some(@activity.activity_step(db))
        { "kind": "recovery", .. } => Some(@activity.recovery_step(db))
        { "kind": "awake", .. } => Some(@activity.awake_step(db))
        { "kind": "legacy-said", .. } => Some(@legacy.said_maintenance(db))
        { "kind": "legacy-edits", .. } => Some(@legacy.edits_maintenance(db))
        { "kind": "legacy-policy", .. } => Some(@legacy.policy_step(db))
        { "kind": "directory", .. } => {
          @activity.directory_install(db)
          Some(@activity.directory_step(db))
        }
        { "kind": "chat-share", .. } => {
          @activity.share_install(db)
          Some(@activity.share_step(db))
        }
        { "kind": "sandbox", .. } => {
          @activity.sandbox_enable(db)
          Some(@activity.sandbox_step(db))
        }
        { "kind": "sandbox-off", .. } => {
          @activity.sandbox_disable(db)
          Some(true)
        }
        { "kind": "active-jobs", .. } => Some(@jobs.active_step(db))
        { "kind": "process-jobs", .. } => {
          @jobs.install(db)
          Some(@jobs.step(db))
        }
        { "kind": "legacy-agent", .. } => Some(@legacy.agent_maintenance(db))
        { "kind": "legacy-login", .. } => Some(@legacy.login_cards_maintenance(db))
        { "kind": "page-letter-gc", .. } => {
          let l = match letters.val {
            Some(l) => l
            None => {
              let l = @letters.Letters::new(db)
              letters.val = Some(l)
              l
            }
          }
          Some(l.gc_step())
        }
        { "kind": "legacy-decision-time", .. } => Some(@legacy.decision_time_step(db))
        { "kind": "legacy-decision-session", .. } => Some(@legacy.decision_session_step(db))
        { "kind": "legacy-decision-session-repair", .. } => Some(@legacy.decision_session_repair_step(db))
        { "kind": String(_), .. } => raise @legacy.Fallback
        _ => Some(@activity.activity_step(db))
      })
      })
    (Some("post-blocks"), Some(db), _) =>
      @host.run(shell_dir=beside(db, "shell"), host => builder(host, db, "post block", (db, ask) => match ask {
        { "thread": Number(thread, ..), "after": Number(after, ..), .. } =>
          Some(@posts.step(db, thread.to_int64(), after.to_int64()))
        _ => None
      }))
    (Some("usage-retire"), Some(db), _) =>
      // (asked a step at a time: `{"drop": true}` the retired indexes, else the fill; each answers whether it is done)
      @host.run(shell_dir=beside(db, "shell"), host => builder(host, db, "usage retirement", (db, ask) => match ask {
        { "drop": True, .. } => Some(@usagefill.drop_step(db))
        _ => Some(@usagefill.fill_step(db))
      }))
    (Some("usage-scope"), Some(db), _) =>
      @host.run(shell_dir=beside(db, "shell"), host => usage_scope(host, db))
    (Some("signin-save"), Some(db), _) =>
      @host.run(shell_dir=beside(db, "shell"), host => builder(host, db, "sign-in index", (db, ask) => match ask {
        String(session) => Some(@signin.step(db, session))
        _ => None
      }))
    (Some("search"), Some(db), Some(data)) =>
      @host.run(shell_dir=beside(db, "shell"), host => search_program(host, db, data, flag("--sep").unwrap_or("/")))
    (Some("search-scope"), Some(db), _) => {
      // (the lanes taken in turn across steps, as one SearchScopePreparation keeps its turn)
      let turn = Ref(0)
      @host.run(shell_dir=beside(db, "shell"), host => builder(host, db, "search scope", (db, ask) => match ask {
        { "scope": "all", .. } => {
          let (done, next) = @searchscope.step(db, turn.val)
          turn.val = next
          Some(done)
        }
        _ => None
      }))
    }
    (Some("live-locator"), Some(db), Some(data)) =>
      @host.run(shell_dir=beside(db, "shell"), host => live_locator(host, db, data, flag("--sep").unwrap_or("/")))
    (Some("forward"), _, _) =>
      // (a listening socket, handed down or bound here, carried to a port of this machine: `{"listening": port}` said once
      // it listens; the shell's own files in `--shell-dir`)
      @host.run(shell_dir=flag("--shell-dir").unwrap_or("."), host => {
        let listening = match flag("--listen-fd") {
          Some(fd) => @front.listen(host, fd=@string.parse_int(fd) catch { _ => -1 })
          None => @front.listen(host, port=@string.parse_int(flag("--listen-port").unwrap_or("0")) catch { _ => 0 })
        }
        let said : Json = { "listening": Json::number(listening.port.to_double()) }
        host.say(said.stringify())
        @front.forward(host, listening, @string.parse_int(flag("--to").unwrap_or("0")) catch { _ => 0 })
      })
    (Some("mesh"), _, _) =>
      // (the station's iroh endpoint kept for its Node, asked on the Unix socket at `--socket`: `{"listening": path}`
      // said once it listens; the shell's own files in `--shell-dir`)
      @host.run(shell_dir=flag("--shell-dir").unwrap_or("."), host => @front.mesh(host, flag("--socket").unwrap_or("mesh.sock")))
    (Some("replica-export"), Some(db), _) =>
      @host.run(shell_dir=beside(db, "shell"), host => replica_export(
        host,
        db,
        flag("--replica").unwrap_or(beside(db, "replica")),
        flag("--data-dir").unwrap_or(""),
        flag("--origin").unwrap_or(""),
        flag("--sep").unwrap_or("/"),
      ))
    (Some("replica-restore"), Some(db), Some(data)) =>
      // (the restore brought before, put in: a line `{"ready": …}` (null: none waited) or `{"error"}`)
      @host.run(shell_dir=beside(db, "shell"), host => {
        let now = @string.parse_double(flag("--now").unwrap_or("0")) catch { _ => 0.0 }
        let line = try {
          match @replica.take_back(host, flag("--sep").unwrap_or("/"), data, db, now) {
            Some(ready) => "{\"ready\":\{@jsjson.stringify(ready)}}"
            None => "{\"ready\":null}"
          }
        } catch {
          e => {
            let failed : Json = { "error": Json::string(message(e)) }
            failed.stringify()
          }
        }
        host.say(line)
      })
    (Some("vault-uses"), Some(db), _) =>
      @host.run(shell_dir=beside(db, "shell"), host => vault_uses(host, db))
    (Some("outflow-chats"), Some(db), _) =>
      @host.run(shell_dir=beside(db, "shell"), host => builder(host, db, "outflow chat index", (db, ask) => match ask {
        { "scope": String(scope), .. } => {
          @outflow.install(db)
          Some(@outflow.step(db, scope))
        }
        _ => None
      }))
    (Some("said"), Some(db), _) => @host.run(shell_dir=beside(db, "shell"), host => said_builder(host, db))
    (Some("archive-last"), Some(db), _) =>
      @host.run(shell_dir=beside(db, "shell"), host => {
        let archive : Ref[@archivelast.Archive?] = Ref(None)
        builder(host, db, "archive last message", (db, ask) => {
          let a = match archive.val {
            Some(a) => a
            None => {
              let a = @archivelast.Archive::new(db)
              archive.val = Some(a)
              a
            }
          }
          match ask {
            { "thread": Number(thread, ..), .. } => Some(a.step(thread.to_int64()))
            _ => None
          }
        })
      })
    (Some("page-letters"), Some(db), _) =>
      @host.run(shell_dir=beside(db, "shell"), host => {
        let letters : Ref[@letters.Letters?] = Ref(None)
        builder(host, db, "old page letters", (db, ask) => {
          let l = match letters.val {
            Some(l) => l
            None => {
              let l = @letters.Letters::new(db)
              letters.val = Some(l)
              l
            }
          }
          match ask {
            { "thread": Number(thread, ..), .. } => Some(l.step(thread.to_int64()))
            _ => None
          }
        })
      })
    (Some("recent-chat"), Some(db), _) =>
      @host.run(shell_dir=beside(db, "shell"), host => {
        let preparation : Ref[@recent.Preparation?] = Ref(None)
        builder(host, db, "recent chat", (db, ask) => {
          guard ask is { "scope": String(scope), .. } else { return None }
          // (the scope as the reader names it: `[workspace, home]`, each a string or null)
          let parsed : Json = @json.parse(scope) catch { _ => Json::null() }
          let (ws, home) = match parsed {
            Array([ws, home]) if (ws is (String(_) | Null)) && (home is (String(_) | Null)) =>
              (if ws is String(s) { Some(s) } else { None }, if home is String(s) { Some(s) } else { None })
            _ => raise Failure("invalid recent chat scope")
          }
          let p = match preparation.val {
            Some(p) => p
            None => {
              let p = @recent.Preparation::new(db)
              preparation.val = Some(p)
              p
            }
          }
          Some(p.step(ws, home))
        })
      })
    (Some("usage-check"), Some(db), _) =>
      @host.run(shell_dir=beside(db, "shell"), host => usage_checker(host, db))
    (Some("cc-index"), Some(db), _) =>
      @host.run(shell_dir=beside(db, "shell"), host => cc_builder(host, db))
    (Some("turn-counts"), Some(db), _) =>
      @host.run(shell_dir=beside(db, "shell"), host => turn_builder(host, db))
    (Some("session-list"), Some(db), _) =>
      @host.run(shell_dir=beside(db, "shell"), host => builder(host, db, "session list", (db, ask) => match ask {
        // (the list, and for search the list visited again: each batch takes a step of the list, then of the audit)
        { "scope": "all", .. } => Some(@sessions.step(db))
        { "scope": "search", .. } => Some(@sessions.step(db) && @sessions.audit(db))
        _ => None
      }))
    (None, _, Some(data)) =>
      @host.run(shell_dir=data + "/shell", host => {
        let sep = flag("--sep").unwrap_or("/")
        let reader = { host, db: data + "/stillfail.db", writer: None, reading: None, data, sep, finder: @locate.Finder::new(host, sep) }
        let ready : Json = { "ready": { "loadedMs": 0, "openedMs": 0 } }
        host.say(ready.stringify())
        while host.line() is Some(line) {
          if line != "" {
            host.say(reader.answer(line).stringify())
          }
        }
      })
    _ => {
      @host.note("usage: stillfail-reader --data <dir> | --builder archive-marks|session-bindings|session-up-jobs|widget-sources|card-posts|session-list|outflow-chats|turn-counts|said|archive-last|page-letters|cc-index|usage-check|recent-chat|closed-cards|people-since|legacy-edits|legacy-said|session-counts|session-backfill|post-blocks|usage-retire|usage-scope|signin-save|vault-uses|replica-export --db <file> | --builder replica-restore --db <file> --data <dir>")
      2
    }
  }
  @host.exit(code)
}
