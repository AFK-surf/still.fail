// A lost station's conversations taken back (station/src/replica/restore.ts `takeBack`): the copy brought into
// <data>/restore/ folded on disk and put into this station's database before its store opens, its files put where its
// rows say, that this station took the lost one's place (`formerly.json`) and what came of it (`restored.json`).

///|
priv suberror NotEmpty

///|
priv suberror FilesPending {
  FilesPending(Int, String)
}

///|
let not_empty_words : String = "this station has chats of its own: a copy is taken back only into a new one"

///|
/// A head read back (`asHead`), none where it is none or of a newer format.
fn as_head(v : JValue) -> JValue? {
  guard v is Obj(_) else { return None }
  guard get(v, "v") is Some(Num(ver)) && ver <= version.to_double() else { return None }
  guard get(v, "origin") is Some(Str(_)) && get(v, "workspace") is Some(Str(_)) else { return None }
  guard get(v, "gen") is Some(Str(g)) && gen_ok(@jsjson.text(g)) else { return None }
  guard get(v, "to") is Some(Num(to)) && to == @math.floor(to) && to.abs() <= 9007199254740991.0 else { return None }
  guard get(v, "batches") is Some(Arr(bs)) && bs.iter().all(b => b is Str(u) && batch_span(@jsjson.text(u)) is Some(_)) else {
    return None
  }
  guard get(v, "files") is Some(Obj(fs)) && fs.iter().all(e => hash_ok(@jsjson.text(e.0))) else { return None }
  guard get(v, "runs") is Some(Arr(_)) else { return None }
  Some(v)
}

///|
fn gen_ok(g : String) -> Bool {
  // /^[0-9a-z]{1,16}-[0-9a-f]{8}$/
  guard g.find("-") is Some(dash) else { return false }
  if dash < 1 || dash > 16 || g.length() != dash + 9 {
    return false
  }
  for i in 0..<g.length() {
    let c = g.unsafe_charcode_at(i)
    let digit = c >= 0x30 && c <= 0x39
    let ok = if i < dash {
      digit || (c >= 0x61 && c <= 0x7a)
    } else if i == dash {
      true
    } else {
      digit || (c >= 0x61 && c <= 0x66)
    }
    if !ok {
      return false
    }
  }
  true
}

///|
fn hash_ok(h : String) -> Bool {
  h.length() == 64 && h.iter().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
}

///|
/// `path` as it is on this station: under `to` where it was under `from` (`moved`).
pub fn moved(files : Files, path : String, from : String, to : String) -> String {
  if from == "" || from == to {
    return path
  }
  let f = if from.has_suffix(files.sep) { from.view(end_offset=from.length() - files.sep.length()).to_string() } else { from }
  if path == f {
    return to
  }
  if path.has_prefix(f + files.sep) || path.has_prefix(f + "/") {
    files.join([to, path.view(start_offset=f.length() + 1).to_string()])
  } else {
    path
  }
}

///|
/// A row as this station keeps it: its paths moved, a session at rest (`shaped`).
fn shaped(files : Files, table : String, row : JValue, from : String, to : String) -> JValue {
  let mut out = row
  if table == "sessions" {
    if text_of(get(out, "workspace")) is Some(w) {
      out = set(out, "workspace", str(moved(files, w, from, to)))
    }
    if text_of(get(out, "cwd")) is Some(c) {
      out = set(out, "cwd", str(moved(files, c, from, to)))
    }
    out = set(out, "running", Num(0.0))
  }
  if (table == "entries" || table == "letters") && text_of(get(out, "attachments")) is Some(a) && a != "" {
    match (try { Some(@jsjson.parse(a)) } catch { _ => None }) {
      Some(Arr(list)) => {
        let moved_list = list.map(x => match get(x, "path") {
          Some(Str(p)) => set(x, "path", str(moved(files, @jsjson.text(p), from, to)))
          _ => x
        })
        out = set(out, "attachments", str(stringify(Arr(moved_list))))
      }
      _ => ()
    }
  }
  out
}

///|
fn read_json(files : Files, path : String) -> JValue raise {
  guard files.read(path) is Some(text) else { fail("ENOENT: no such file or directory, open '\{path}'") }
  @jsjson.parse(text)
}

///|
/// What the generation in `dir` says put into the database at `db` (`build`): (rows by table, files placed, missing).
/// `merge`: beside this station's own chats (a station retired into it).
/// `connects`: how the ids of that station's connects go here; `ws`: what its sessions' `ws` is here, where said.
fn build(host : @host.Host, files : Files, db_path : String, dir : String, from_files : String, data_dir : String, now : Double, merge : Bool, connects : JValue, ws : JValue?) -> (JValue, Int, Int) raise {
  guard as_head(read_json(files, files.join([dir, "head.json"]))) is Some(head) else {
    fail("no copy here, or one of a newer station's")
  }
  let origin = text_of(get(head, "origin")).unwrap_or("")
  let gen = text_of(get(head, "gen")).unwrap_or("")
  let head_dir = text_of(get(head, "dataDir")).unwrap_or("")
  let d = @sql.Db::attach(host, db_path, wait=30000)
  let mut rows : JValue = Obj([])
  let body = () => {
    d.exec("CREATE TABLE IF NOT EXISTS replica_restored (origin TEXT NOT NULL, gen TEXT NOT NULL, at INTEGER NOT NULL, rows TEXT NOT NULL, PRIMARY KEY (origin, gen))")
    match d.all("SELECT rows FROM replica_restored WHERE origin = ? AND gen = ?", [s(origin), s(gen)]) {
      [done, ..] => rows = @jsjson.parse(field_text(done, "rows"))
      _ => {
        d.exec("BEGIN IMMEDIATE")
        let put = () => {
          let has = (t : String) => d.all("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [s(t)]).length() > 0
          if !has("threads") || !has("sessions") {
            fail("this station's database is not made yet")
          }
          let empty = d.all("SELECT 1 FROM threads LIMIT 1", []).length() == 0 && d.all("SELECT 1 FROM sessions LIMIT 1", []).length() == 0
          if !empty && !merge {
            raise NotEmpty
          }
          let merging = !empty
          let ids : Map[Double, Double] = Map([])
          let followed : Map[Double, Bool] = Map([])
          let put_rows : Map[String, Double] = Map([])
          let columns : Map[String, Array[String]] = Map([])
          let columns_of = (table : String) => match columns.get(table) {
            Some(c) => c
            None => {
              let c = d.all("SELECT name FROM pragma_table_info('\{table}')", []).map(r => field_text(r, "name"))
              columns[table] = c
              c
            }
          }
          d.exec("CREATE TEMP TABLE restore_files (path TEXT PRIMARY KEY, hash TEXT NOT NULL) WITHOUT ROWID")
          let work = "\{db_path}.restore-fold"
          files.remove(work)
          let folded = Folded::new(host, work)
          let fold = () => {
            for b in strings_of(get(head, "batches")) {
              for line in batch_lines(files, files.join([dir, "log", b])) {
                folded.apply(line)
              }
            }
            folded.records(line => {
              let rec = @jsjson.parse(line)
              if get(rec, "r") is Some(r) {
                let table = text_of(Some(r)).unwrap_or("")
                if !has(table) {
                  return
                }
                let mut row = shaped(files, table, get(rec, "row").unwrap_or(Obj([])), head_dir, data_dir)
                if (table == "sessions" || table == "thread_sessions") && text_of(get(row, "connect")) is Some(c) && get(connects, c) is Some(Str(there)) {
                  row = set(row, "connect", Str(there))
                }
                if table == "sessions" && merge {
                  match ws {
                    Some(w) => row = set(row, "ws", w)
                    None => ()
                  }
                }
                if merging {
                  if table == "threads" {
                    let was = num(get(row, "id"))
                    match d.all("SELECT id FROM threads WHERE surface = ? AND channel = ? AND thread_ts = ?", [param(get(row, "surface")), param(get(row, "channel")), param(get(row, "thread_ts"))]) {
                      [here, ..] =>
                        if text_of(get(row, "surface")) != Some(stillfail_surface) {
                          ids[was] = field_num(here, "id")
                          followed[was] = true
                          return
                        } else {
                          let mut ts = bumped_ts(text_of(get(row, "thread_ts")).unwrap_or(""))
                          while d.all("SELECT 1 FROM threads WHERE surface = ? AND channel = ? AND thread_ts = ?", [param(get(row, "surface")), param(get(row, "channel")), s(ts)]).length() > 0 {
                            ts = bumped_ts(ts)
                          }
                          row = set(row, "thread_ts", str(ts))
                        }
                      _ => ()
                    }
                    row = without(row, "id")
                  }
                  match lookup(thread_columns, table) {
                    Some(column) =>
                      if get(row, column) is Some(Num(was)) {
                        let id = ids.get(was)
                        let shared = followed.contains(was)
                        if table == "turns" {
                          match id {
                            Some(i) if !shared => row = set(row, "about_thread", Num(i))
                            _ => {
                              row = set(row, "about_thread", Null)
                              row = set(row, "about_n", Null)
                            }
                          }
                        } else {
                          match id {
                            Some(i) if !(own_log.contains(table) && shared) => row = set(row, column, Num(i))
                            _ => return
                          }
                        }
                      }
                    None => ()
                  }
                }
                let have = columns_of(table)
                let cols = keys_of(row).filter(c => have.contains(c))
                let changed = d.run("INSERT\{if merging { " OR IGNORE" } else { "" }} INTO \{table} (\{cols.join(", ")}) VALUES (\{cols.map(_ => "?").join(", ")})", cols.map(c => param(get(row, c))))
                if merging {
                  put_rows[table] = put_rows.get(table).unwrap_or(0.0) + changed.to_double()
                  if table == "threads" {
                    match d.all("SELECT last_insert_rowid() AS id", []) {
                      [r, ..] => ids[num(get(get(rec, "row").unwrap_or(Obj([])), "id"))] = field_num(r, "id")
                      _ => ()
                    }
                  }
                }
              } else if get(rec, "file") is Some(f) {
                let path = text_of(get(rec, "path")).unwrap_or("")
                ignore(d.run("INSERT OR REPLACE INTO restore_files (path, hash) VALUES (?, ?)", [s(moved(files, path, head_dir, data_dir)), param(Some(f))]))
              }
            })
          }
          fold() catch {
            e => {
              folded.close()
              files.remove(work) catch {
                _ => ()
              }
              raise e
            }
          }
          folded.close()
          files.remove(work)
          let counted : Array[(Array[Int], JValue)] = []
          for table in restore_order {
            if has(table) {
              let n = if merging {
                put_rows.get(table).unwrap_or(0.0)
              } else {
                match d.all("SELECT COUNT(*) AS n FROM \{table}", []) {
                  [r, ..] => field_num(r, "n")
                  _ => 0.0
                }
              }
              counted.push((@jsjson.units(table), Num(n)))
            }
          }
          rows = Obj(counted)
          ignore(d.run("INSERT INTO replica_restored (origin, gen, at, rows) VALUES (?, ?, ?, ?)", [s(origin), s(gen), Json::number(now), s(stringify(rows))]))
          d.exec("CREATE TABLE IF NOT EXISTS replica_restore_files (path TEXT PRIMARY KEY, hash TEXT NOT NULL) WITHOUT ROWID; INSERT OR REPLACE INTO replica_restore_files SELECT path, hash FROM temp.restore_files;")
          d.exec("COMMIT")
        }
        put() catch {
          e => {
            d.exec("ROLLBACK") catch {
              _ => ()
            }
            raise e
          }
        }
      }
    }
    // The files the rows still name, where they say, a page of rows at a time.
    let mut placed = 0
    let mut missing = 0
    let named = match d.all("SELECT COUNT(*) AS n FROM replica_restore_files", []) {
      [r, ..] => field_num(r, "n").to_int()
      _ => 0
    }
    let place = () => {
      for table in ["entries", "letters"] {
        let mut after = 0.0
        while true {
          let page_rows = d.all("SELECT rowid AS r, attachments FROM \{table} WHERE rowid > ? AND attachments IS NOT NULL AND attachments <> '[]' ORDER BY rowid LIMIT 500", [Json::number(after)])
          for p in page_rows {
            for path in attached_paths(row_of(p)) {
              guard d.all("SELECT hash FROM replica_restore_files WHERE path = ?", [s(path)]) is [f, ..] else { continue }
              if files.exists(path) {
                placed += 1
                continue
              }
              let from = files.join([from_files, field_text(f, "hash")])
              if !files.exists(from) {
                missing += 1
                continue
              }
              files.mkdir(files.dirname(path))
              files.copy(from, "\{path}.restoring")
              files.rename("\{path}.restoring", path)
              placed += 1
            }
          }
          if page_rows.length() < 500 {
            break
          }
          after = field_num(page_rows[page_rows.length() - 1], "r")
        }
      }
    }
    place() catch {
      e => {
        let left = named - placed - missing
        raise FilesPending((if left > 0 { left } else { 0 }), "the chats are in; \{if left > 0 { left } else { 0 }} of their files not placed yet: \{words(e)}")
      }
    }
    d.exec("DELETE FROM replica_restore_files")
    (rows, placed, missing)
  }
  let result = body() catch {
    e => {
      d.close()
      raise e
    }
  }
  d.close()
  result
}

///|
fn words(e : Error) -> String {
  match e {
    @wire.ShellError(m) => m
    Failure(m) => m
    NotEmpty => not_empty_words
    FilesPending(_, m) => m
    @jsjson.SyntaxError(m) => m
    e => e.to_string()
  }
}

///|
/// That this station took `origin`'s place (`addFormerly`).
fn add_formerly(files : Files, data : String, origin : String) -> Unit raise {
  let file = files.join([data, "replica", "formerly.json"])
  let list = match (try { Some(read_json(files, file)) } catch { _ => None }) {
    Some(Arr(items)) => items
    _ => []
  }
  let list = if list.iter().any(x => x is Str(u) && @jsjson.text(u) == origin) { list } else { list + [str(origin)] }
  files.mkdir(files.dirname(file))
  ignore(files.write("\{file}.tmp", stringify(Arr(list))))
  files.rename("\{file}.tmp", file)
}

///|
/// The restore brought to this station before, put in as its store is about to open (`takeBack`): what it was, or none
/// where none waited.
pub fn take_back(host : @host.Host, sep : String, data : String, db : String, now : Double) -> JValue? raise {
  let files = { host, sep }
  let restore = files.join([data, "restore"])
  let ready = match (try { Some(read_json(files, files.join([restore, "ready.json"]))) } catch { _ => None }) {
    Some(r) => r
    None => return None
  }
  let dir = files.join([restore, "copy"])
  let origin = text_of(get(ready, "origin")).unwrap_or("")
  let field = (k : String) => get(ready, k).unwrap_or(Null)
  let mut outcome : JValue = Obj([
    (@jsjson.units("origin"), field("origin")),
    (@jsjson.units("name"), field("name")),
    (@jsjson.units("from"), field("from")),
    (@jsjson.units("at"), Num(now)),
    (@jsjson.units("rows"), Obj([])),
    (@jsjson.units("files"), Num(0.0)),
    (@jsjson.units("missing"), Num(0.0)),
    (@jsjson.units("error"), Null),
    (@jsjson.units("reason"), Null),
    (@jsjson.units("pending"), Bool(false)),
    (@jsjson.units("left"), Num(0.0)),
  ])
  let gen = text_of(get(ready, "gen")).unwrap_or("")
  let attempt = () => {
    let merge = get(ready, "merge") is Some(Bool(true))
    let connects = get(ready, "connects").unwrap_or(Obj([]))
    let (rows, placed, missing) = build(host, files, db, files.join([dir, gen]), files.join([dir, "files"]), data, now, merge, connects, get(ready, "ws"))
    add_formerly(files, data, origin)
    outcome = set(outcome, "rows", rows)
    outcome = set(outcome, "files", Num(placed.to_double()))
    outcome = set(outcome, "missing", Num(missing.to_double()))
  }
  attempt() catch {
    e => {
      let message = words(e)
      outcome = set(outcome, "error", str(message))
      let lower = message.to_lower()
      let reason = match e {
        NotEmpty => "notEmpty"
        _ =>
          if lower.contains("enospc") || lower.contains("disk is full") || lower.contains("no space left on device") {
            "full"
          } else {
            "error"
          }
      }
      outcome = set(outcome, "reason", str(reason))
      if e is FilesPending(left, _) {
        add_formerly(files, data, origin)
        outcome = set(outcome, "pending", Bool(true))
        outcome = set(outcome, "left", Num(left.to_double()))
      }
    }
  }
  let out = files.join([data, "replica", "restored.json"])
  files.mkdir(files.dirname(out))
  ignore(files.write("\{out}.tmp", stringify(outcome)))
  files.rename("\{out}.tmp", out)
  if !(get(outcome, "pending") is Some(Bool(true))) {
    files.remove(restore, recursive=true)
  }
  Some(ready)
}
