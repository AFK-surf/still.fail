// The export (station/src/replica/export.ts `Exporter`, its AGENTS.md): what must survive of this station's
// conversations, read from stillfail.db and written as batches, a generation of them per workspace, under
// <replica>/own/<workspace>/<gen>/, the exporter's own state in <replica>/export.db. The same reads, records, state and
// files as the TypeScript exporter's, so either takes up where the other left off.

///|
let pass_rows : Int = 5000

///|
let fold_run : Int = 4

///|
let fold_small : Double = 1048576.0

///|
let runs_kept : Int = 512

///|
let state_schema : String =
  #|CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT NOT NULL) WITHOUT ROWID;
  #|CREATE TABLE IF NOT EXISTS digests (ws TEXT NOT NULL, k TEXT NOT NULL, d TEXT NOT NULL, PRIMARY KEY (ws, k)) WITHOUT ROWID;
  #|CREATE TABLE IF NOT EXISTS threads (ws TEXT NOT NULL, thread INTEGER NOT NULL, PRIMARY KEY (ws, thread)) WITHOUT ROWID;
  #|CREATE TABLE IF NOT EXISTS files (path TEXT PRIMARY KEY, size INTEGER NOT NULL, mtime INTEGER NOT NULL, hash TEXT NOT NULL) WITHOUT ROWID;
  #|CREATE INDEX IF NOT EXISTS files_hash ON files (hash);
  #|CREATE TABLE IF NOT EXISTS sent (ws TEXT NOT NULL, path TEXT NOT NULL, PRIMARY KEY (ws, path)) WITHOUT ROWID;
  #|CREATE TABLE IF NOT EXISTS entering (ws TEXT NOT NULL, thread INTEGER NOT NULL, tbl TEXT NOT NULL, after INTEGER NOT NULL, upto INTEGER NOT NULL, PRIMARY KEY (ws, thread, tbl)) WITHOUT ROWID;

///|
let small_tables : Array[String] = [
  "sessions", "threads", "thread_sessions", "runtime_sessions", "closed_cards", "reads", "hidden_chats", "muted_chats",
  "kept_chats", "dismissed", "pins", "opened_chats",
]

///|
let thread_marks : Array[String] = ["reads", "hidden_chats", "muted_chats", "kept_chats", "dismissed"]

///|
fn page_of(table : String) -> String {
  "SELECT rowid AS _rowid, * FROM \{table} WHERE rowid > ? ORDER BY rowid LIMIT ?"
}

///|
fn marks_of(table : String, column : String) -> String {
  "WITH RECURSIVE viewers(viewer) AS (\n  SELECT (SELECT viewer FROM \{table} ORDER BY viewer LIMIT 1)\n  UNION ALL SELECT (SELECT viewer FROM \{table} WHERE viewer > v.viewer ORDER BY viewer LIMIT 1) FROM viewers v WHERE v.viewer IS NOT NULL\n) SELECT m.* FROM viewers v CROSS JOIN \{table} m ON m.viewer = v.viewer AND m.\{column} = ? WHERE v.viewer IS NOT NULL"
}

///|
fn by_key(table : String, cols : Array[String]) -> String {
  "SELECT * FROM \{table} WHERE \{cols.map(c => "\{c} = ?").join(" AND ")}"
}

///|
fn digest(row : JValue) -> String {
  sha1_hex(stringify(row)).view(end_offset=16).to_string()
}

///|
/// A record of two fields, in their order.
fn rec2(k1 : String, v1 : JValue, k2 : String, v2 : JValue) -> JValue {
  Obj([(@jsjson.units(k1), v1), (@jsjson.units(k2), v2)])
}

///|
/// A workspace's generation as a pass writes it: its head and the record lines it adds.
priv struct Out {
  mut head : JValue
  lines : Array[String]
  mut bytes : Int
  files : Array[(String, Double)]
  mut gone : Bool
  mut messages : Double
}

///|
/// The workspaces this station is in (`Places`).
priv struct Places {
  home : String?
  workspaces : Array[(String, JValue)]
}

///|
pub struct Exporter {
  priv host : @host.Host
  priv files : Files
  priv db : @sql.Db
  priv state : @sql.Db
  priv replica : String
  priv data_dir : String
  priv origin : String
  priv most : Int
  priv fold : Bool
  priv now : () -> Double
  priv mut places : Places
  priv mut known : Bool
  /// This run of the exporter.
  run : String
  priv mut read : Int
}

///|
pub fn Exporter::new(
  host : @host.Host,
  sep : String,
  db : String,
  replica : String,
  data_dir : String,
  origin : String,
  now : () -> Double,
  batch_bytes? : Int = batch_bytes,
  fold? : Bool = true,
) -> Exporter raise {
  let files = { host, sep }
  let reading = @sql.Db::attach(host, db, wait=5000)
  files.mkdir(replica)
  let state = @sql.Db::create(host, files.join([replica, "export.db"]), wait=5000)
  state.exec("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;")
  state.exec(state_schema)
  let e = {
    host,
    files,
    db: reading,
    state,
    replica,
    data_dir,
    origin,
    most: batch_bytes,
    fold,
    now,
    places: { home: None, workspaces: [] },
    known: false,
    run: files.random(4),
    read: 0,
  }
  // A database rolled back under its exporter (a backup put back): what it says now was never exported as it is.
  let at = e.meta("entries")
  let max = num(e.first("SELECT MAX(rowid) AS m FROM entries", []).bind(r => get(r, "m")))
  if at is Some(a) && (@string.parse_double(a) catch { _ => 0.0 }) > max {
    e.forget()
  }
  e
}

///|
pub fn Exporter::close(self : Exporter) -> Unit {
  self.db.close()
  self.state.close()
}

///|
fn Exporter::first(self : Exporter, sql : String, params : Array[Json]) -> JValue? raise {
  match self.db.all(sql, params) {
    [r, ..] => Some(row_of(r))
    _ => None
  }
}

///|
fn Exporter::meta(self : Exporter, k : String) -> String? raise {
  match self.state.all("SELECT v FROM meta WHERE k = ?", [s(k)]) {
    [r, ..] => Some(field_text(r, "v"))
    _ => None
  }
}

///|
fn Exporter::set_meta(self : Exporter, k : String, v : String) -> Unit raise {
  ignore(self.state.run("INSERT INTO meta (k, v) VALUES (?, ?) ON CONFLICT (k) DO UPDATE SET v = excluded.v", [s(k), s(v)]))
}

///|
/// Everything exported is forgotten: the next pass writes it all again, in new generations.
fn Exporter::forget(self : Exporter) -> Unit raise {
  self.state.exec("DELETE FROM meta WHERE k <> 'after'; DELETE FROM digests; DELETE FROM threads; DELETE FROM sent; DELETE FROM entering;")
  self.known = false
}

///|
/// The workspaces this station is in, as the station says them: `{home, workspaces: [{workspace, name}]}`.
pub fn Exporter::set_places(self : Exporter, places : JValue) -> Unit {
  let home = text_of(get(places, "home"))
  let workspaces = match get(places, "workspaces") {
    Some(Arr(items)) =>
      items.filter_map(w => match text_of(get(w, "workspace")) {
        Some(ws) => Some((ws, get(w, "name").unwrap_or(Null)))
        None => None
      })
    _ => []
  }
  self.places = { home, workspaces }
}

///|
/// A new generation for each workspace, begun after `after` (`newGenerations`).
pub fn Exporter::new_generations(self : Exporter, after : Double) -> Unit raise {
  self.forget()
  self.set_meta("after", @jsjson.stringify(Num(after)))
}

///|
fn Exporter::root(self : Exporter) -> String {
  self.files.join([self.replica, "own"])
}

///|
fn Exporter::gen_dir(self : Exporter, ws : String, gen : String) -> String {
  self.files.join([self.root(), ws, gen])
}

///|
fn Exporter::read_head(self : Exporter, dir : String) -> JValue? {
  let text = (try { self.files.read(self.files.join([dir, "head.json"])) } catch { _ => None })
  match text {
    Some(t) => Some(@jsjson.parse(t)) catch { _ => None }
    None => None
  }
}

///|
/// A new generation's name: when it began (base 36) and a random part (`genName`).
fn gen_name(now : Double, random : String) -> String {
  let mut v = @math.floor(if now > 0.0 { now } else { 0.0 })
  let digits = "0123456789abcdefghijklmnopqrstuvwxyz"
  let out : Array[Char] = []
  if v == 0.0 {
    out.push('0')
  }
  while v >= 1.0 {
    let d = (v - 36.0 * @math.floor(v / 36.0)).to_int()
    out.push(digits.unsafe_charcode_at(d).unsafe_to_char())
    v = @math.floor(v / 36.0)
  }
  out.rev_in_place()
  String::from_array(out) + "-" + random.view(end_offset=if random.length() < 8 { random.length() } else { 8 }).to_string()
}

///|
/// The generation being written for `ws`, made where there is none.
fn Exporter::gen_of(self : Exporter, ws : String) -> String raise {
  let known = self.meta("gen:\{ws}")
  if known is Some(g) && self.files.exists(self.gen_dir(ws, g)) {
    return g
  }
  let after = match self.meta("after") {
    Some(a) => @string.parse_double(a) catch { _ => 0.0 }
    None => 0.0
  }
  let now = (self.now)()
  let gen = gen_name(if now > after + 1.0 { now } else { after + 1.0 }, self.files.random(4))
  self.set_meta("gen:\{ws}", gen)
  for t in ["digests", "threads", "sent", "entering"] {
    ignore(self.state.run("DELETE FROM \{t} WHERE ws = ?", [s(ws)]))
  }
  gen
}

///|
/// The heads of this station's generations now, by workspace.
pub fn Exporter::heads(self : Exporter) -> JValue raise {
  let out : Array[(Array[Int], JValue)] = []
  for w in self.places.workspaces {
    match self.meta("gen:\{w.0}") {
      Some(gen) =>
        match self.read_head(self.gen_dir(w.0, gen)) {
          Some(head) => out.push((@jsjson.units(w.0), head))
          None => ()
        }
      None => ()
    }
  }
  Obj(out)
}

///|
/// One pass (`pass`): what changed, as told and as found, written as batches. Its answer as the TypeScript one's
/// (`Passed` and whether the station has no chat of its own).
pub fn Exporter::pass(self : Exporter, told : JValue) -> JValue raise {
  guard self.places.home is Some(home) && self.places.workspaces.length() > 0 else {
    return Obj([
      (@jsjson.units("heads"), Obj([])),
      (@jsjson.units("more"), Bool(false)),
      (@jsjson.units("wrote"), Num(0.0)),
      (@jsjson.units("read"), Num(0.0)),
      (@jsjson.units("empty"), Bool(self.empty())),
    ])
  }
  self.state.exec("BEGIN IMMEDIATE")
  let passed = self.pass_in(told, home) catch {
    e => {
      self.state.exec("ROLLBACK") catch {
        _ => ()
      }
      raise e
    }
  }
  self.state.exec("COMMIT")
  set(passed, "empty", Bool(self.empty()))
}

///|
fn list_of(v : JValue?) -> Array[JValue] {
  match v {
    Some(Arr(items)) => items
    _ => []
  }
}

///|
fn Exporter::pass_in(self : Exporter, told : JValue, home : String) -> JValue raise {
  let names = self.places.workspaces
  let ws_of_session = (ws : JValue?) => match ws {
    Some(Str(u)) if u.length() > 0 => @jsjson.text(u)
    _ => home
  }
  let outs : Map[String, Out] = Map([])
  for w in names {
    let ws = w.0
    let gen = self.gen_of(ws)
    let dir = self.gen_dir(ws, gen)
    let head = match self.read_head(dir) {
      Some(h) => h
      None =>
        Obj([
          (@jsjson.units("v"), Num(version.to_double())),
          (@jsjson.units("origin"), str(self.origin)),
          (@jsjson.units("workspace"), str(ws)),
          (@jsjson.units("gen"), str(gen)),
          (@jsjson.units("name"), match w.1 { Null => str(""); v => v }),
          (@jsjson.units("dataDir"), str(self.data_dir)),
          (@jsjson.units("made"), Num(0.0)),
          (@jsjson.units("to"), Num(0.0)),
          (@jsjson.units("batches"), Arr([])),
          (@jsjson.units("files"), Obj([])),
          (@jsjson.units("chats"), Num(0.0)),
          (@jsjson.units("messages"), Num(0.0)),
          (@jsjson.units("bytes"), Num(0.0)),
          (@jsjson.units("runs"), Arr([])),
        ])
    }
    outs[ws] = { head, lines: [], bytes: 0, files: [], gone: false, messages: 0.0 }
  }
  if self.meta("entries") is None {
    for k in ["entries", "letters", "turns"] {
      self.set_meta(k, "0")
    }
    self.set_meta("ended", "[-1,0]")
    self.known = false
  }
  let say = (ws : String, rec : JValue) => {
    guard outs.get(ws) is Some(out) else { return }
    let line = stringify(rec)
    out.lines.push(line)
    out.bytes += utf8_length(line) + 1
    if get(rec, "gone") is Some(_) {
      out.gone = true
    }
    if get(rec, "file") is Some(Str(f)) {
      let h = @jsjson.text(f)
      let size = num(get(rec, "size"))
      match out.files.search_by(e => e.0 == h) {
        Some(i) => out.files[i] = (h, size)
        None => out.files.push((h, size))
      }
    }
  }
  let most = self.most
  let enough = () => {
    if self.read >= pass_rows {
      return true
    }
    for _, o in outs {
      if o.bytes >= most {
        return true
      }
    }
    false
  }
  self.read = 0
  let all = (sql : String, params : Array[Json]) => {
    let rows = self.db.all(sql, params)
    self.read += rows.length()
    rows.map(row_of)
  }
  let get_digest = (ws : String, k : String) => match self.state.all("SELECT d FROM digests WHERE ws = ? AND k = ?", [s(ws), s(k)]) {
    [r, ..] => Some(field_text(r, "d"))
    _ => None
  }
  let has_thread = (ws : String, thread : Double) => self.state.all("SELECT 1 FROM threads WHERE ws = ? AND thread = ?", [s(ws), Json::number(thread)]).length() > 0
  let drop_thread = (ws : String, thread : Double) => ignore(self.state.run("DELETE FROM threads WHERE ws = ? AND thread = ?", [s(ws), Json::number(thread)]))
  let drop_digest = (ws : String, k : String) => ignore(self.state.run("DELETE FROM digests WHERE ws = ? AND k = ?", [s(ws), s(k)]))
  // A row of a table that changes in place, written where it differs from what was written of it.
  let changed = (ws : String, table : String, row : JValue) => {
    let clean = without(row, "_rowid")
    let k = "\{table}|\{key_of(table, clean)}"
    let d = digest(clean)
    if get_digest(ws, k) == Some(d) {
      return
    }
    ignore(self.state.run("INSERT INTO digests (ws, k, d) VALUES (?, ?, ?) ON CONFLICT (ws, k) DO UPDATE SET d = excluded.d", [s(ws), s(k), s(d)]))
    say(ws, rec2("r", str(table), "row", clean))
  }
  let thread_ws : Map[Double, Array[String]] = Map([])
  let ws_of_thread = (thread : Double) => match thread_ws.get(thread) {
    Some(w) => w
    None => {
      let of = all("SELECT s.ws AS ws FROM thread_sessions ts JOIN sessions s ON s.key = ts.session WHERE ts.thread = ?", [Json::number(thread)]).map(r => ws_of_session(get(r, "ws")))
      let list : Array[String] = []
      if of.length() == 0 {
        list.push(home)
      } else {
        for w in of {
          if !list.contains(w) {
            list.push(w)
          }
        }
      }
      let kept = list.filter(w => outs.contains(w))
      thread_ws[thread] = kept
      kept
    }
  }
  let files_said : Array[(String, Array[String])] = []
  let attached = (ws : String, row : JValue) => {
    for path in attached_paths(row) {
      match files_said.search_by(e => e.0 == ws) {
        Some(i) => if !files_said[i].1.contains(path) { files_said[i].1.push(path) }
        None => files_said.push((ws, [path]))
      }
    }
  }
  let cursor_entries = @string.parse_double(self.meta("entries").unwrap_or("0")) catch { _ => 0.0 }
  let cursor_letters = @string.parse_double(self.meta("letters").unwrap_or("0")) catch { _ => 0.0 }
  let thread_rows = (ws : String, thread : Double) => {
    match all("SELECT * FROM threads WHERE id = ?", [Json::number(thread)]) {
      [t, ..] => changed(ws, "threads", t)
      _ => ()
    }
    for r in all("SELECT * FROM thread_sessions WHERE thread = ?", [Json::number(thread)]) {
      changed(ws, "thread_sessions", r)
    }
    for r in all("SELECT * FROM closed_cards WHERE thread = ?", [Json::number(thread)]) {
      changed(ws, "closed_cards", r)
    }
    for table in thread_marks {
      for r in all(marks_of(table, "thread"), [Json::number(thread)]) {
        changed(ws, table, r)
      }
    }
  }
  let enter = (thread : Double) => {
    for ws in ws_of_thread(thread) {
      if has_thread(ws, thread) {
        continue
      }
      ignore(self.state.run("INSERT OR IGNORE INTO threads (ws, thread) VALUES (?, ?)", [s(ws), Json::number(thread)]))
      thread_rows(ws, thread)
      if cursor_entries > 0.0 {
        ignore(self.state.run("INSERT OR IGNORE INTO entering (ws, thread, tbl, after, upto) VALUES (?, ?, ?, 0, ?)", [s(ws), Json::number(thread), s("entries"), Json::number(cursor_entries)]))
      }
      if cursor_letters > 0.0 {
        ignore(self.state.run("INSERT OR IGNORE INTO entering (ws, thread, tbl, after, upto) VALUES (?, ?, ?, 0, ?)", [s(ws), Json::number(thread), s("letters"), Json::number(cursor_letters)]))
      }
    }
  }
  let count_message = (ws : String, table : String, r : JValue) => {
    if table == "entries" && get(r, "kind") is Some(Str(k)) && @jsjson.text(k) == "message" {
      match outs.get(ws) {
        Some(o) => o.messages += 1.0
        None => ()
      }
    }
  }
  let drain_entering = () => {
    while true {
      if enough() {
        return true
      }
      let next = self.state.all("SELECT ws, thread, tbl, after, upto FROM entering LIMIT 1", [])
      guard next is [e, ..] else { return false }
      let ws = field_text(e, "ws")
      let thread = field_num(e, "thread")
      let tbl = field_text(e, "tbl")
      let key = [s(ws), Json::number(thread), s(tbl)]
      if !outs.contains(ws) {
        ignore(self.state.run("DELETE FROM entering WHERE ws = ? AND thread = ? AND tbl = ?", key))
        continue
      }
      let sql = if tbl == "entries" {
        "SELECT rowid AS _rowid, * FROM entries WHERE thread = ? AND n > ? ORDER BY n LIMIT ?"
      } else {
        "SELECT rowid AS _rowid, * FROM letters WHERE thread = ? AND n > ? ORDER BY n LIMIT ?"
      }
      let rows = all(sql, [Json::number(thread), Json::number(field_num(e, "after")), ni(page)])
      let upto = field_num(e, "upto")
      for r in rows {
        if num(get(r, "_rowid")) > upto {
          continue
        }
        say(ws, rec2("r", str(tbl), "row", without(r, "_rowid")))
        attached(ws, r)
        count_message(ws, tbl, r)
      }
      if rows.length() < page {
        ignore(self.state.run("DELETE FROM entering WHERE ws = ? AND thread = ? AND tbl = ?", key))
      } else {
        ignore(self.state.run("UPDATE entering SET after = ? WHERE ws = ? AND thread = ? AND tbl = ?", [Json::number(num(get(rows[rows.length() - 1], "n"))), key[0], key[1], key[2]]))
      }
    }
    false
  }
  let session_ws = (table : String, row : JValue) => self.session_ws(table, row, ws_of_session)
  let session_rows = (key : String) => {
    guard all("SELECT * FROM sessions WHERE key = ?", [s(key)]) is [sess, ..] else { return }
    let ws = ws_of_session(get(sess, "ws"))
    if !outs.contains(ws) {
      return
    }
    changed(ws, "sessions", sess)
    for r in all("SELECT * FROM thread_sessions WHERE session = ?", [s(key)]) {
      changed(ws, "thread_sessions", r)
      enter(num(get(r, "thread")))
    }
    for r in all("SELECT * FROM runtime_sessions WHERE session_key = ?", [s(key)]) {
      changed(ws, "runtime_sessions", r)
    }
    for r in all("SELECT rowid AS _rowid, * FROM turns WHERE session_key = ? ORDER BY started_at DESC LIMIT 2", [s(key)]) {
      changed(ws, "turns", r)
    }
    for r in all("SELECT * FROM opened_chats WHERE child_station = '' AND child = ?", [s(key)]) {
      changed(ws, "opened_chats", r)
    }
    for r in all(marks_of("pins", "session"), [s(key)]) {
      changed(ws, "pins", r)
    }
  }
  let mut more = false
  self.db.exec("BEGIN")
  let body = () => {
    // What was deleted, as told.
    for r in list_of(get(told, "removedSessions")) {
      let key = text_of(get(r, "key")).unwrap_or("")
      let w = ws_of_session(get(r, "ws"))
      say(w, rec2("gone", str("session"), "key", str(key)))
      let k = "sessions|\{stringify(Arr([str(key)]))}"
      ignore(self.state.run("DELETE FROM digests WHERE ws = ? AND k >= ? AND k < ?", [s(w), s(k), s(k + "\u{ffff}")]))
    }
    for r in list_of(get(told, "removedThreads")) {
      let id = num(get(r, "id"))
      let wss = match get(r, "ws") {
        None | Some(Null) => outs.keys().collect()
        ws => [ws_of_session(ws)]
      }
      for w in wss {
        if !has_thread(w, id) {
          continue
        }
        say(w, rec2("gone", str("thread"), "id", Num(id)))
        drop_thread(w, id)
      }
    }
    // The small tables whole, once a run.
    if !self.known {
      let seen : Map[String, Set[String]] = Map([])
      for table in small_tables {
        let mut after = 0.0
        while true {
          let rows = all(page_of(table), [Json::number(after), ni(page)])
          for r in rows {
            let wss = if table == "sessions" || table == "runtime_sessions" || table == "pins" || table == "opened_chats" {
              session_ws(table, r)
            } else {
              ws_of_thread(num(get(r, if table == "threads" { "id" } else { "thread" })))
            }
            for ws in wss {
              if !outs.contains(ws) {
                continue
              }
              if table == "threads" {
                enter(num(get(r, "id")))
              }
              changed(ws, table, r)
              let set = match seen.get(ws) {
                Some(x) => x
                None => {
                  let x : Set[String] = Set([])
                  seen[ws] = x
                  x
                }
              }
              set.add("\{table}|\{key_of(table, without(r, "_rowid"))}")
            }
          }
          if rows.length() < page {
            break
          }
          after = num(get(rows[rows.length() - 1], "_rowid"))
        }
      }
      // What was written of before and is not there now: gone.
      for ws in outs.keys().collect() {
        let set = seen.get(ws).unwrap_or(Set([]))
        for d in self.state.all("SELECT k FROM digests WHERE ws = ?", [s(ws)]) {
          let k = field_text(d, "k")
          if set.contains(k) || k.has_prefix("turns|") {
            continue
          }
          let bar = k.find("|").unwrap_or(0)
          let table = k.view(end_offset=bar).to_string()
          let key = match (@jsjson.parse(k.view(start_offset=bar + 1).to_string()) catch { _ => Arr([]) }) {
            Arr(items) => items
            _ => []
          }
          drop_digest(ws, k)
          if table == "sessions" {
            let v = key.get(0).unwrap_or(Null)
            say(ws, rec2("gone", str("session"), "key", str(match v { Str(u) => @jsjson.text(u); Null => "null"; x => stringify(x) })))
          } else if table == "threads" {
            let id = num(key.get(0))
            say(ws, rec2("gone", str("thread"), "id", Num(id)))
            drop_thread(ws, id)
          } else {
            let named = key_columns(table).mapi((i, c) => (@jsjson.units(c), key.get(i).unwrap_or(Null)))
            say(ws, rec2("del", str(table), "key", Obj(named)))
          }
        }
      }
      self.known = true
    }
    // What changed in place, as told.
    for k in list_of(get(told, "sessions")) {
      match text_of(Some(k)) {
        Some(key) => session_rows(key)
        None => ()
      }
    }
    for t in list_of(get(told, "threads")) {
      let thread = num(Some(t))
      enter(thread)
      for ws in ws_of_thread(thread) {
        thread_rows(ws, thread)
      }
    }
    for m in list_of(get(told, "marks")) {
      let table = text_of(get(m, "table")).unwrap_or("")
      let key = get(m, "key").unwrap_or(Obj([]))
      let cols = key_columns(table)
      let row = all(by_key(table, cols), cols.map(c => param(get(key, c)))).get(0)
      let wss = if table == "pins" { session_ws("pins", key) } else { ws_of_thread(num(get(key, "thread"))) }
      for ws in wss {
        let k = "\{table}|\{key_of(table, key)}"
        match row {
          Some(r) => changed(ws, table, r)
          None =>
            if get_digest(ws, k) is Some(_) {
              drop_digest(ws, k)
              say(ws, rec2("del", str(table), "key", key))
            }
        }
      }
    }
    // A thread new to a workspace: its logs before.
    if drain_entering() {
      more = true
    }
    // The logs, past where they were exported.
    for pair in [("entries", cursor_entries), ("letters", cursor_letters)] {
      let (table, start) = pair
      let mut at = start
      while true {
        if enough() {
          more = true
          break
        }
        let rows = all("SELECT rowid AS _rowid, * FROM \{table} WHERE rowid > ? ORDER BY rowid LIMIT ?", [Json::number(at), ni(page)])
        for r in rows {
          let thread = num(get(r, "thread"))
          enter(thread)
          for ws in ws_of_thread(thread) {
            say(ws, rec2("r", str(table), "row", without(r, "_rowid")))
            attached(ws, r)
            count_message(ws, table, r)
          }
          at = num(get(r, "_rowid"))
        }
        if rows.length() < page {
          break
        }
      }
      self.set_meta(table, @jsjson.stringify(Num(at)))
    }
    for k in ["turns", "ended"] {
      let mut at = if k == "turns" {
        (@string.parse_double(self.meta("turns").unwrap_or("0")) catch { _ => 0.0 }, 0.0)
      } else {
        match (@jsjson.parse(self.meta("ended").unwrap_or("[-1,0]")) catch { _ => Arr([]) }) {
          Arr([a, b, ..]) => (num(Some(a)), num(Some(b)))
          _ => (-1.0, 0.0)
        }
      }
      while true {
        if enough() {
          more = true
          break
        }
        let rows = if k == "turns" {
          all("SELECT rowid AS _rowid, * FROM turns WHERE rowid > ? ORDER BY rowid LIMIT ?", [Json::number(at.0), ni(page)])
        } else {
          all("SELECT rowid AS _rowid, * FROM turns INDEXED BY turns_ended WHERE ended_at > ?1 OR (ended_at = ?1 AND rowid > ?2) ORDER BY ended_at, rowid LIMIT ?3", [
            Json::number(at.0),
            Json::number(at.1),
            ni(page),
          ])
        }
        for r in rows {
          match session_ws("turns", r).get(0) {
            Some(ws) if outs.contains(ws) => changed(ws, "turns", r)
            _ => ()
          }
          at = if k == "turns" { (num(get(r, "_rowid")), 0.0) } else { (num(get(r, "ended_at")), num(get(r, "_rowid"))) }
        }
        if rows.length() < page {
          break
        }
      }
      self.set_meta(k, if k == "turns" { @jsjson.stringify(Num(at.0)) } else { stringify(Arr([Num(at.0), Num(at.1)])) })
    }
  }
  body() catch {
    e => {
      self.db.exec("COMMIT") catch {
        _ => ()
      }
      raise e
    }
  }
  self.db.exec("COMMIT")
  // The files the rows name, each once in a generation: by the hash of what it holds.
  for e in files_said {
    let (ws, paths) = e
    for path in paths {
      if self.state.all("SELECT 1 FROM sent WHERE ws = ? AND path = ?", [s(ws), s(path)]).length() > 0 {
        continue
      }
      guard self.hashed(path) is Some((hash, size)) else { continue }
      ignore(self.state.run("INSERT OR IGNORE INTO sent (ws, path) VALUES (?, ?)", [s(ws), s(path)]))
      say(ws, Obj([(@jsjson.units("file"), str(hash)), (@jsjson.units("size"), Num(size)), (@jsjson.units("path"), str(path))]))
    }
  }
  let mut wrote = 0
  let heads : Array[(Array[Int], JValue)] = []
  for w in names {
    guard outs.get(w.0) is Some(out) else { continue }
    if out.lines.length() > 0 {
      self.write(w.0, out)
      wrote += 1
    }
    heads.push((@jsjson.units(w.0), out.head))
  }
  Obj([
    (@jsjson.units("heads"), Obj(heads)),
    (@jsjson.units("more"), Bool(more)),
    (@jsjson.units("wrote"), Num(wrote.to_double())),
    (@jsjson.units("read"), Num(self.read.to_double())),
  ])
}

///|
fn Exporter::session_ws(self : Exporter, table : String, row : JValue, ws_of : (JValue?) -> String) -> Array[String] raise {
  let key = get(row, if table == "sessions" { "key" } else if table == "pins" { "session" } else if table == "opened_chats" { "child" } else { "session_key" })
  if table == "opened_chats" && !(get(row, "child_station") is Some(Str([]))) {
    return []
  }
  if table == "sessions" {
    return [ws_of(get(row, "ws"))]
  }
  match self.db.all("SELECT ws FROM sessions WHERE key = ?", [param(key)]) {
    [r, ..] => {
      self.read += 1
      [ws_of(get(row_of(r), "ws"))]
    }
    _ => []
  }
}

///|
/// The hash and size of the file at `path`, read once while it is as it was; none where it is not there.
fn Exporter::hashed(self : Exporter, path : String) -> (String, Double)? raise {
  guard self.files.kind(path) is Some("file") else { return None }
  guard self.files.meta(path) is Some((size, mtime)) else { return None }
  match self.state.all("SELECT size, mtime, hash FROM files WHERE path = ?", [s(path)]) {
    [k, ..] if field_num(k, "size") == size && field_num(k, "mtime") == mtime => return Some((field_text(k, "hash"), size))
    _ => ()
  }
  guard self.files.hash(path) is Some(hash) else { return None }
  ignore(
    self.state.run("INSERT INTO files (path, size, mtime, hash) VALUES (?, ?, ?, ?) ON CONFLICT (path) DO UPDATE SET size = excluded.size, mtime = excluded.mtime, hash = excluded.hash", [
      s(path),
      Json::number(size),
      Json::number(mtime),
      s(hash),
    ]),
  )
  Some((hash, size))
}

///|
/// A batch written whole under `dir`'s log, named by its numbers and its bytes' hash.
fn Exporter::write_batch(self : Exporter, dir : String, gen : String, from : Int64, to : Int64, made : Double, lines : Array[String]) -> String raise {
  let log = self.files.join([dir, "log"])
  let writing = self.files.join([log, "\{pad10(from)}-\{pad10(to)}.writing"])
  let sha = self.files.write(writing, batch_text(gen, from, to, made, lines), zstd=true)
  let name = batch_name(from, to, sha)
  self.files.rename(writing, self.files.join([log, name]))
  name
}

///|
fn strings_of(v : JValue?) -> Array[String] {
  list_of(v).filter_map(x => text_of(Some(x)))
}

///|
fn strs(list : Array[String]) -> JValue {
  Arr(list.map(str))
}

///|
/// Batches of what `out` says, then the head that names them; folded as batches build up.
fn Exporter::write(self : Exporter, ws : String, out : Out) -> Unit raise {
  let head = out.head
  let gen = text_of(get(head, "gen")).unwrap_or("")
  let dir = self.gen_dir(ws, gen)
  let made = (self.now)()
  let mut n = num(get(head, "to")).to_int64()
  let names : Array[String] = []
  let first = n + 1L
  let runs = Runs::new(self.most, run => {
    n += 1L
    names.push(self.write_batch(dir, gen, n, n, made, run))
  })
  for l in out.lines {
    runs.push(l)
  }
  runs.finish()
  let runs_list = list_of(get(head, "runs"))
  let last_run = match runs_list.last() {
    Some(r) => text_of(get(r, "run"))
    None => None
  }
  let runs_list = if runs_list.length() == 0 || last_run != Some(self.run) {
    runs_list + [Obj([(@jsjson.units("run"), str(self.run)), (@jsjson.units("from"), Num(first.to_double()))])]
  } else {
    runs_list
  }
  let kept = if runs_list.length() > runs_kept { runs_list[runs_list.length() - runs_kept:].to_array() } else { runs_list }
  let mut files = get(head, "files").unwrap_or(Obj([]))
  for f in out.files {
    files = set(files, f.0, Num(f.1))
  }
  let chats = match self.state.all("SELECT COUNT(*) AS n FROM threads WHERE ws = ?", [s(ws)]) {
    [r, ..] => field_num(r, "n")
    _ => 0.0
  }
  let mut next = head
  next = set(next, "made", Num(made))
  next = set(next, "to", Num(n.to_double()))
  next = set(next, "batches", strs(strings_of(get(head, "batches")) + names))
  next = set(next, "runs", Arr(kept))
  next = set(next, "files", files)
  next = set(next, "chats", Num(chats))
  next = set(next, "messages", Num(num(get(head, "messages")) + out.messages))
  out.head = self.fold_gen(dir, next, out.gone)
}

///|
fn Exporter::write_head(self : Exporter, dir : String, head : JValue) -> Unit raise {
  ignore(self.files.write(self.files.join([dir, "head.json"]), @jsjson.stringify_indent(head, 1)))
}

///|
/// The generation's batches folded where they built up (`#fold`).
fn Exporter::fold_gen(self : Exporter, dir : String, head : JValue, everything : Bool) -> JValue raise {
  let log = self.files.join([dir, "log"])
  let size = (b : String) => self.files.size(self.files.join([log, b]))
  let level = (b : String) => {
    let sz = size(b)
    @math.floor(@math.ln((if sz > 4096.0 { sz } else { 4096.0 }) / 4096.0) / @math.ln(fold_run.to_double()))
  }
  let mut h = head
  while self.fold {
    let bs = strings_of(get(h, "batches"))
    let take = if everything {
      if bs.length() == 0 {
        break
      }
      bs
    } else {
      if bs.length() < fold_run {
        break
      }
      let tail = bs[bs.length() - fold_run:].to_array()
      let l = level(tail[0])
      let mut same = true
      let mut total = 0.0
      for b in tail {
        if level(b) != l {
          same = false
        }
        total += size(b)
      }
      if !same || total >= fold_small {
        break
      }
      tail
    }
    let work = self.files.join([self.replica, "fold.db"])
    self.files.remove(work)
    let folded = Folded::new(self.host, work)
    let step = () => {
      for b in take {
        for line in batch_lines(self.files, self.files.join([log, b])) {
          folded.apply(line)
        }
      }
      let (from, _) = batch_span(take[0]).unwrap()
      let (_, to) = batch_span(take[take.length() - 1]).unwrap()
      let whole = take.length() == bs.length()
      let names : Array[String] = []
      let gen = text_of(get(h, "gen")).unwrap_or("")
      let made = num(get(h, "made"))
      let runs = Runs::new(self.most, run => names.push(self.write_batch(dir, gen, from, to, made, run)))
      if whole {
        folded.records(line => runs.push(line))
      } else {
        folded.partial(line => runs.push(line))
      }
      runs.finish()
      let mut next = h
      next = set(next, "batches", strs(bs[0:bs.length() - take.length()].to_array() + names))
      if whole {
        let files : Array[(Array[Int], JValue)] = []
        folded.each_named_file((_, hash, sz) => {
          let key = @jsjson.units(hash)
          match files.search_by(e => e.0 == key) {
            Some(i) => files[i] = (key, Num(sz))
            None => files.push((key, Num(sz)))
          }
        })
        next = set(next, "files", Obj(files))
        let (chats, messages) = folded.counts()
        next = set(next, "chats", Num(chats))
        next = set(next, "messages", Num(messages))
      } else {
        next = set(next, "files", get(h, "files").unwrap_or(Obj([])))
        next = set(next, "chats", get(h, "chats").unwrap_or(Null))
        next = set(next, "messages", get(h, "messages").unwrap_or(Null))
      }
      h = next
      self.write_head(dir, h)
      for b in take {
        if !names.contains(b) {
          self.files.remove(self.files.join([log, b]))
        }
      }
    }
    step() catch {
      e => {
        folded.close()
        self.files.remove(work) catch {
          _ => ()
        }
        raise e
      }
    }
    folded.close()
    self.files.remove(work)
    if everything || strings_of(get(h, "batches")).length() >= bs.length() {
      break
    }
  }
  h = set(h, "bytes", Num(self.bytes(dir, h)))
  self.write_head(dir, h)
  // (a batch written by a run that ended before its head was, or half of one: never named, let go)
  let named = strings_of(get(h, "batches"))
  for b in self.files.names(log).unwrap_or([]) {
    if !named.contains(b) {
      self.files.remove(self.files.join([log, b]))
    }
  }
  h
}

///|
fn Exporter::bytes(self : Exporter, dir : String, h : JValue) -> Double {
  let mut n = 0.0
  for b in strings_of(get(h, "batches")) {
    match self.files.meta(self.files.join([dir, "log", b])) {
      Some((size, _)) => n += size
      None => ()
    }
  }
  match get(h, "files") {
    Some(Obj(entries)) => for e in entries { n += num(Some(e.1)) }
    _ => ()
  }
  n
}

///|
/// Whether this station has no chat of its own yet.
pub fn Exporter::empty(self : Exporter) -> Bool raise {
  self.db.all("SELECT 1 FROM sessions LIMIT 1", []).length() == 0 && self.db.all("SELECT 1 FROM threads LIMIT 1", []).length() == 0
}

///|
/// Where the files of `hashes` are now on this station, for a place that lacks them (`sources`).
pub fn Exporter::sources(self : Exporter, hashes : Array[String]) -> JValue raise {
  let out : Array[(Array[Int], JValue)] = []
  for h in hashes {
    for r in self.state.all("SELECT path FROM files WHERE hash = ?", [s(h)]) {
      let path = field_text(r, "path")
      if self.files.kind(path) is Some("file") {
        let key = @jsjson.units(h)
        match out.search_by(e => e.0 == key) {
          Some(i) => out[i] = (key, str(path))
          None => out.push((key, str(path)))
        }
        break
      }
    }
  }
  Obj(out)
}
