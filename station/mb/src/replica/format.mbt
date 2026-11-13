// What a copy of a station's conversations is made of, as station/src/replica/format.ts says it: batches of record
// lines (zstd's frame of JSON lines, the first its header), each generation's head, and records folded into what they
// say now (`Folded`, in a database of its own on disk).

///|
/// The batches' format: a restorer takes those of its own version or before.
pub let version : Int = 1

///|
/// The tables a copy holds, each by its key's columns (format.ts `TABLES`).
let tables : Array[(String, Array[String])] = [
  ("threads", ["id"]),
  ("sessions", ["key"]),
  ("thread_sessions", ["thread", "session"]),
  ("entries", ["thread", "n"]),
  ("letters", ["thread", "n"]),
  ("turns", ["id"]),
  ("runtime_sessions", ["session_key", "id"]),
  ("closed_cards", ["thread", "n"]),
  ("reads", ["viewer", "thread"]),
  ("hidden_chats", ["viewer", "thread"]),
  ("muted_chats", ["viewer", "thread"]),
  ("kept_chats", ["viewer", "thread"]),
  ("dismissed", ["viewer", "thread", "n"]),
  ("pins", ["viewer", "session"]),
  ("opened_chats", ["child_station", "child"]),
]

///|
/// The order a restore puts them in: what a row points at before it.
pub let restore_order : Array[String] = [
  "threads", "sessions", "thread_sessions", "entries", "letters", "turns", "runtime_sessions", "closed_cards", "reads",
  "hidden_chats", "muted_chats", "kept_chats", "dismissed", "pins", "opened_chats",
]

///|
/// The column of a table that names the thread a row is of.
let thread_of : Array[(String, String)] = [
  ("threads", "id"),
  ("thread_sessions", "thread"),
  ("entries", "thread"),
  ("letters", "thread"),
  ("closed_cards", "thread"),
  ("reads", "thread"),
  ("hidden_chats", "thread"),
  ("muted_chats", "thread"),
  ("kept_chats", "thread"),
  ("dismissed", "thread"),
]

///|
/// Where a copy is put into a station with chats of its own (format.ts `THREAD_COLUMNS`): the columns that name a thread
/// by its id here.
let thread_columns : Array[(String, String)] = [
  ("thread_sessions", "thread"),
  ("entries", "thread"),
  ("letters", "thread"),
  ("closed_cards", "thread"),
  ("reads", "thread"),
  ("hidden_chats", "thread"),
  ("muted_chats", "thread"),
  ("kept_chats", "thread"),
  ("dismissed", "thread"),
  ("turns", "about_thread"),
]

///|
/// The tables numbered by a thread's own log (format.ts `OWN_LOG`).
let own_log : Array[String] = ["entries", "letters", "closed_cards", "dismissed", "reads"]

///|
/// still.fail's own chats' surface (store/rows.ts `STILLFAIL_SURFACE`): each station mints their ts itself.
let stillfail_surface : String = "ember"

///|
/// A thread's ts a step on (format.ts `bumpedTs`): its last digits counted up by one, a `1` put after it where it ends
/// in none.
fn bumped_ts(ts : String) -> String {
  let mut i = ts.length()
  while i > 0 && ts.unsafe_charcode_at(i - 1) >= 48 && ts.unsafe_charcode_at(i - 1) <= 57 {
    i -= 1
  }
  if i == ts.length() {
    return ts + "1"
  }
  let digits : Array[Int] = []
  for k in i..<ts.length() {
    digits.push(ts.unsafe_charcode_at(k) - 48)
  }
  let mut j = digits.length() - 1
  while j >= 0 && digits[j] == 9 {
    digits[j] = 0
    j -= 1
  }
  let out = StringBuilder::new()
  out.write_string(ts.view(end_offset=i).to_string())
  if j < 0 {
    out.write_char('1')
  } else {
    digits[j] = digits[j] + 1
  }
  for d in digits {
    out.write_char((d + 48).unsafe_to_char())
  }
  out.to_string()
}

///|
/// The column of a table that names the session a row is of.
let session_of : Array[(String, String)] = [
  ("sessions", "key"),
  ("thread_sessions", "session"),
  ("turns", "session_key"),
  ("runtime_sessions", "session_key"),
  ("pins", "session"),
  ("opened_chats", "child"),
]

///|
fn lookup(list : Array[(String, String)], table : String) -> String? {
  for e in list {
    if e.0 == table {
      return Some(e.1)
    }
  }
  None
}

///|
fn order_of(table : String) -> Int {
  match restore_order.search(table) {
    Some(i) => i
    None => -1
  }
}

///|
pub fn key_columns(table : String) -> Array[String] raise {
  for t in tables {
    if t.0 == table {
      return t.1
    }
  }
  fail("no such table in a copy: \{table}")
}

///|
/// The key of a row of `table`, as text: what a later record of it is matched by (`keyOf`).
pub fn key_of(table : String, row : JValue) -> String raise {
  let cols = key_columns(table)
  stringify(Arr(cols.map(c => match get(row, c) { Some(v) => v; None => Null })))
}

///|
fn pad10(n : Int64) -> String {
  let s = n.to_string()
  if s.length() >= 10 {
    s
  } else {
    String::make(10 - s.length(), '0') + s
  }
}

///|
/// A batch's name: its numbers and the start of its bytes' hash.
fn batch_name(from : Int64, to : Int64, sha256 : String) -> String {
  "\{pad10(from)}-\{pad10(to)}-\{sha256.view(end_offset=8)}.ndjson.zst"
}

///|
/// Whether `name` is a batch's (`BATCH`), and its numbers.
pub fn batch_span(name : String) -> (Int64, Int64)? {
  // 0000000001-0000000002-0a1b2c3d.ndjson.zst
  if name.length() != 41 || !name.has_suffix(".ndjson.zst") {
    return None
  }
  let digits = (from : Int, to : Int) => {
    let mut n = 0L
    for i in from..<to {
      let c = name.unsafe_charcode_at(i)
      if c < 0x30 || c > 0x39 {
        return None
      }
      n = n * 10L + (c - 0x30).to_int64()
    }
    Some(n)
  }
  guard name.unsafe_charcode_at(10) == 0x2d && name.unsafe_charcode_at(21) == 0x2d else { return None }
  for i in 22..<30 {
    let c = name.unsafe_charcode_at(i)
    guard (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x66) else { return None }
  }
  match (digits(0, 10), digits(11, 21)) {
    (Some(f), Some(t)) => Some((f, t))
    _ => None
  }
}

///|
/// The paths of the files a row's attachments name (entries' and letters' `attachments`, JSON: [{path, …}]).
pub fn attached_paths(row : JValue) -> Array[String] {
  guard get(row, "attachments") is Some(Str(units)) else { return [] }
  let a = @jsjson.text(units)
  if a == "" || a == "[]" {
    return []
  }
  let list = @jsjson.parse(a) catch { _ => return [] }
  guard list is Arr(items) else { return [] }
  items.filter_map(x => match get(x, "path") {
    Some(Str(p)) if p.length() > 0 => Some(@jsjson.text(p))
    _ => None
  })
}

///|
/// How much of records a batch holds at most, before it is compressed.
pub let batch_bytes : Int = 8 << 20

///|
/// Record lines cut into runs of at most `most` bytes (`runsOf`: one line longer than that a run of its own), each run
/// given to `put` as it is full.
priv struct Runs {
  most : Int
  put : (Array[String]) -> Unit raise
  mut run : Array[String]
  mut size : Int
}

///|
fn Runs::new(most : Int, put : (Array[String]) -> Unit raise) -> Runs {
  { most, put, run: [], size: 0 }
}

///|
fn Runs::push(self : Runs, line : String) -> Unit raise {
  let b = utf8_length(line) + 1
  if self.run.length() > 0 && self.size + b > self.most {
    (self.put)(self.run)
    self.run = []
    self.size = 0
  }
  self.run.push(line)
  self.size += b
}

///|
fn Runs::finish(self : Runs) -> Unit raise {
  if self.run.length() > 0 {
    (self.put)(self.run)
    self.run = []
    self.size = 0
  }
}

///|
/// A batch's text: its header, then its lines, each with its newline (`encodeBatch`).
fn batch_text(gen : String, from : Int64, to : Int64, made : Double, lines : Array[String]) -> String {
  let out = StringBuilder::new()
  let header : JValue = Obj([
    (@jsjson.units("v"), Num(version.to_double())),
    (@jsjson.units("gen"), str(gen)),
    (@jsjson.units("from"), Num(from.to_double())),
    (@jsjson.units("to"), Num(to.to_double())),
    (@jsjson.units("made"), Num(made)),
  ])
  out.write_string(stringify(header))
  out.write_char('\n')
  for l in lines {
    out.write_string(l)
    out.write_char('\n')
  }
  out.to_string()
}

///|
/// A batch read (`decodeBatch`): its records' lines (the header checked and left out).
fn batch_lines(files : Files, path : String) -> Array[String] raise {
  guard files.read(path, zstd=true) is Some(text) else { fail("ENOENT: no such file or directory, open '\{path}'") }
  let first = text.find("\n").unwrap_or(text.length())
  let header = @jsjson.parse(text.view(end_offset=first).to_string()) catch { e => raise e }
  guard header is Obj(_) && get(header, "v") is Some(Num(v)) else { fail("not a batch") }
  if v > version.to_double() {
    fail("a batch of format \{@jsjson.stringify(Num(v))}, newer than this station's \{version}")
  }
  let out : Array[String] = []
  let mut at = if first < text.length() { first + 1 } else { text.length() }
  while at < text.length() {
    let end = match text.view(start_offset=at).find("\n") {
      Some(i) => at + i
      None => text.length()
    }
    if end > at {
      out.push(text.view(start_offset=at, end_offset=end).to_string())
    }
    at = end + 1
  }
  out
}

///|
let fold_schema : String =
  #|CREATE TABLE IF NOT EXISTS rows (tbl INTEGER NOT NULL, k TEXT NOT NULL, seq INTEGER NOT NULL, line TEXT NOT NULL, thread INTEGER, session TEXT, message INTEGER NOT NULL, PRIMARY KEY (tbl, k)) WITHOUT ROWID;
  #|CREATE INDEX IF NOT EXISTS rows_order ON rows (tbl, seq);
  #|CREATE INDEX IF NOT EXISTS rows_thread ON rows (thread) WHERE thread IS NOT NULL;
  #|CREATE INDEX IF NOT EXISTS rows_session ON rows (session) WHERE session IS NOT NULL;
  #|CREATE TABLE IF NOT EXISTS attached (tbl INTEGER NOT NULL, k TEXT NOT NULL, path TEXT NOT NULL, PRIMARY KEY (tbl, k, path)) WITHOUT ROWID;
  #|CREATE INDEX IF NOT EXISTS attached_path ON attached (path);
  #|CREATE TABLE IF NOT EXISTS files (path TEXT PRIMARY KEY, seq INTEGER NOT NULL, hash TEXT NOT NULL, size INTEGER NOT NULL) WITHOUT ROWID;
  #|CREATE INDEX IF NOT EXISTS files_order ON files (seq);
  #|CREATE TABLE IF NOT EXISTS dels (tk TEXT PRIMARY KEY, seq INTEGER NOT NULL, line TEXT NOT NULL) WITHOUT ROWID;
  #|CREATE TABLE IF NOT EXISTS gone (line TEXT PRIMARY KEY, seq INTEGER NOT NULL) WITHOUT ROWID;

///|
/// Records folded into what they say now (format.ts `Folded`), in a database of its own at `path`: each key's last
/// row, nothing of what was deleted, the files the rows left still name. Read back a page at a time, so nothing of it in
/// memory grows with the copy.
pub struct Folded {
  db : @sql.Db
  mut seq : Int64
}

///|
pub fn Folded::new(host : @host.Host, path : String) -> Folded raise {
  let db = @sql.Db::create(host, path, wait=5000)
  db.exec("PRAGMA journal_mode = OFF; PRAGMA synchronous = OFF; PRAGMA cache_size = -8192; PRAGMA temp_store = FILE;")
  db.exec(fold_schema)
  db.exec("BEGIN")
  { db, seq: 0L }
}

///|
pub fn Folded::close(self : Folded) -> Unit {
  self.db.exec("COMMIT") catch {
    _ => ()
  }
  self.db.close()
}

///|
fn n(v : Int64) -> Json {
  Json::number(v.to_double())
}

///|
fn ni(v : Int) -> Json {
  Json::number(v.to_double())
}

///|
fn s(v : String) -> Json {
  Json::string(v)
}

///|
/// A record, as its line.
pub fn Folded::apply(self : Folded, line : String) -> Unit raise {
  let rec = @jsjson.parse(line) catch { e => raise e }
  self.seq += 1L
  let seq = self.seq
  let db = self.db
  if get(rec, "r") is Some(r) {
    let table = text_of(Some(r)).unwrap_or("")
    let tbl = order_of(table)
    if tbl < 0 {
      return
    }
    let row = get(rec, "row").unwrap_or(Null)
    let key = key_of(table, row)
    let thread = match lookup(thread_of, table) {
      None => Json::null()
      Some(c) => param(get(row, c))
    }
    let session = match lookup(session_of, table) {
      None => Json::null()
      Some(_) if table == "opened_chats" && !(get(row, "child_station") is Some(Str([]))) => Json::null()
      Some(c) => param(get(row, c))
    }
    let message = table == "entries" && get(row, "kind") is Some(Str(k)) && @jsjson.text(k) == "message"
    ignore(
      db.run(
        "INSERT INTO rows (tbl, k, seq, line, thread, session, message) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT (tbl, k) DO UPDATE SET seq = excluded.seq, line = excluded.line, thread = excluded.thread, session = excluded.session, message = excluded.message",
        [ni(tbl), s(key), n(seq), s(line), thread, session, ni(if message { 1 } else { 0 })],
      ),
    )
    ignore(db.run("DELETE FROM attached WHERE tbl = ? AND k = ?", [ni(tbl), s(key)]))
    if table == "entries" || table == "letters" {
      for path in attached_paths(row) {
        ignore(db.run("INSERT OR IGNORE INTO attached (tbl, k, path) VALUES (?, ?, ?)", [ni(tbl), s(key), s(path)]))
      }
    }
    ignore(db.run("DELETE FROM dels WHERE tk = ?", [s("\{table}|\{key}")]))
  } else if get(rec, "del") is Some(d) {
    let table = text_of(Some(d)).unwrap_or("")
    let tbl = order_of(table)
    if tbl < 0 {
      return
    }
    let key = key_of(table, get(rec, "key").unwrap_or(Null))
    ignore(db.run("DELETE FROM rows WHERE tbl = ? AND k = ?", [ni(tbl), s(key)]))
    ignore(db.run("DELETE FROM attached WHERE tbl = ? AND k = ?", [ni(tbl), s(key)]))
    ignore(
      db.run("INSERT INTO dels (tk, seq, line) VALUES (?, ?, ?) ON CONFLICT (tk) DO UPDATE SET seq = excluded.seq, line = excluded.line", [
        s("\{table}|\{key}"),
        n(seq),
        s(line),
      ]),
    )
  } else if get(rec, "gone") is Some(g) {
    let (column, value, list) = if g is Str(u) && @jsjson.text(u) == "session" {
      ("session", param(get(rec, "key")), session_of)
    } else {
      ("thread", param(get(rec, "id")), thread_of)
    }
    let tbls = list.map(e => order_of(e.0))
    for r in db.all("SELECT tbl, k FROM rows WHERE \{column} = ?", [value]) {
      let tbl = match r.get("tbl") {
        Some(Number(x, ..)) => x.to_int()
        _ => -1
      }
      if !tbls.contains(tbl) {
        continue
      }
      let k = r.get("k").unwrap_or(Json::null())
      ignore(db.run("DELETE FROM rows WHERE tbl = ? AND k = ?", [ni(tbl), k]))
      ignore(db.run("DELETE FROM attached WHERE tbl = ? AND k = ?", [ni(tbl), k]))
    }
    ignore(db.run("INSERT INTO gone (line, seq) VALUES (?, ?) ON CONFLICT (line) DO UPDATE SET seq = excluded.seq", [s(line), n(seq)]))
  } else if get(rec, "file") is Some(f) {
    ignore(
      db.run("INSERT INTO files (path, seq, hash, size) VALUES (?, ?, ?, ?) ON CONFLICT (path) DO UPDATE SET seq = excluded.seq, hash = excluded.hash, size = excluded.size", [
        param(get(rec, "path")),
        n(seq),
        param(Some(f)),
        param(get(rec, "size")),
      ]),
    )
  }
}

///|
let page : Int = 500

///|
fn field_text(r : Map[String, Json], name : String) -> String {
  match r.get(name) {
    Some(String(x)) => x
    _ => ""
  }
}

///|
fn field_num(r : Map[String, Json], name : String) -> Double {
  match r.get(name) {
    Some(Number(x, ..)) => x
    _ => 0.0
  }
}

///|
/// Every row's line, table by table in the order they were said, a page at a time.
fn Folded::each_row(self : Folded, f : (String) -> Unit raise) -> Unit raise {
  let mut tbl = -1.0
  let mut seq = 0.0
  while true {
    let rows = self.db.all("SELECT tbl, seq, line FROM rows WHERE tbl > ?1 OR (tbl = ?1 AND seq > ?2) ORDER BY tbl, seq LIMIT ?3", [
      Json::number(tbl),
      Json::number(seq),
      ni(page),
    ])
    for r in rows {
      f(field_text(r, "line"))
      tbl = field_num(r, "tbl")
      seq = field_num(r, "seq")
    }
    if rows.length() < page {
      break
    }
  }
}

///|
/// The files the rows still name, in the order they were said: (path, hash, size).
pub fn Folded::each_named_file(self : Folded, f : (String, String, Double) -> Unit raise) -> Unit raise {
  let mut seq = 0.0
  while true {
    let rows = self.db.all("SELECT f.seq, f.path, f.hash, f.size FROM files f WHERE f.seq > ? AND EXISTS (SELECT 1 FROM attached a WHERE a.path = f.path) ORDER BY f.seq LIMIT ?", [
      Json::number(seq),
      ni(page),
    ])
    for r in rows {
      f(field_text(r, "path"), field_text(r, "hash"), field_num(r, "size"))
      seq = field_num(r, "seq")
    }
    if rows.length() < page {
      break
    }
  }
}

///|
fn file_line(path : String, hash : String, size : Double) -> String {
  stringify(Obj([(@jsjson.units("file"), str(hash)), (@jsjson.units("size"), Num(size)), (@jsjson.units("path"), str(path))]))
}

///|
/// What it says now, as record lines: every row, then the files still named (`records`).
pub fn Folded::records(self : Folded, f : (String) -> Unit raise) -> Unit raise {
  self.each_row(f)
  self.each_named_file((path, hash, size) => f(file_line(path, hash, size)))
}

///|
/// What it says where batches before it are not folded with it (`partial`): what was deleted first, then every row and
/// every file.
fn Folded::partial(self : Folded, f : (String) -> Unit raise) -> Unit raise {
  for table in ["gone", "dels"] {
    let mut seq = 0.0
    while true {
      let rows = self.db.all("SELECT seq, line FROM \{table} WHERE seq > ? ORDER BY seq LIMIT ?", [Json::number(seq), ni(page)])
      for r in rows {
        f(field_text(r, "line"))
        seq = field_num(r, "seq")
      }
      if rows.length() < page {
        break
      }
    }
  }
  self.each_row(f)
  let mut seq = 0.0
  while true {
    let rows = self.db.all("SELECT seq, path, hash, size FROM files WHERE seq > ? ORDER BY seq LIMIT ?", [Json::number(seq), ni(page)])
    for r in rows {
      f(file_line(field_text(r, "path"), field_text(r, "hash"), field_num(r, "size")))
      seq = field_num(r, "seq")
    }
    if rows.length() < page {
      break
    }
  }
}

///|
fn Folded::count(self : Folded, sql : String, params : Array[Json]) -> Double raise {
  match self.db.all(sql, params) {
    [r, ..] => field_num(r, "n")
    _ => 0.0
  }
}

///|
/// How many chats and messages it holds.
fn Folded::counts(self : Folded) -> (Double, Double) raise {
  (
    self.count("SELECT COUNT(*) AS n FROM rows WHERE tbl = ?", [ni(order_of("threads"))]),
    self.count("SELECT COUNT(*) AS n FROM rows WHERE message = 1", []),
  )
}
