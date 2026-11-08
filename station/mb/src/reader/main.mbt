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
    { "op": String(op), .. } => { "id": id, "status": 500, "error": Json::string("no read \{op}") }
    _ => { "id": id, "status": 400, "error": Json::string("no op") }
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
async fn builder(host : @host.Host, db_path : String) -> Unit {
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
    let answer : Json = if ask is { "scope": "all", .. } {
      try {
        { "done": Json::boolean(@marks.step(db)) }
      } catch {
        e => if @sql.busy(e) { { "done": false } } else { { "done": false, "error": Json::string(message(e)) } }
      }
    } else {
      { "done": false, "error": "invalid archive mark preparation request" }
    }
    host.say(answer.stringify())
  }
}

///|
fn main {
  let code = match (flag("--builder"), flag("--db"), flag("--data")) {
    (Some("archive-marks"), Some(db), _) =>
      @host.run(shell_dir=beside(db, "shell"), host => builder(host, db))
    (None, _, Some(data)) =>
      @host.run(shell_dir=data + "/shell", host => {
        let reader = { host, db: data + "/stillfail.db", writer: None }
        let ready : Json = { "ready": { "loadedMs": 0, "openedMs": 0 } }
        host.say(ready.stringify())
        while host.line() is Some(line) {
          if line != "" {
            host.say(reader.answer(line).stringify())
          }
        }
      })
    _ => {
      @host.note("usage: stillfail-reader --data <dir> | --builder archive-marks --db <file>")
      2
    }
  }
  @host.exit(code)
}
