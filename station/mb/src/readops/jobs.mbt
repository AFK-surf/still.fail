// The reads of a background job (station/src/read/jobs.ts `job`, `jobLog`): its record as the pages show it, what it
// said lately and when its output last grew, and its log's last lines.

///|
/// A read refused with an HTTP status (views.ts HttpError).
pub(all) suberror Refused {
  Refused(Int, String)
}

///|
let notices_shown : Int = 20

///|
let log_bytes : Int = 65536

///|
fn field(row : Map[String, Json], name : String) -> Json {
  row.get(name).unwrap_or(Json::null())
}

///|
/// jobs.ts `outputAt`: when a log last grew (ms), none when it is empty or does not stat.
fn output_at(host : @host.Host, path : Json) -> Json {
  guard path is String(p) else { return Json::null() }
  match (try { Ok(host.shell_sync("fs.meta", { "path": Json::string(p) })) } catch { e => Err(e) }) {
    Ok({ "size": Number(size, ..), "mtimeMs": Number(_, ..) as at, .. }) if size > 0.0 => at
    _ => Json::null()
  }
}

///|
fn job_row(db : @sql.Db, id : Json) -> Map[String, Json] raise {
  guard db.all("SELECT * FROM jobs WHERE id = ?", [id]).get(0) is Some(r) else {
    raise Refused(404, "no job \{match id { String(s) => s; j => j.stringify() }}")
  }
  r
}

///|
/// jobs.ts `shown`: the record as serde writes it (the token skipped, `sessionKey` as `session`), its notices, when its
/// output last grew.
pub fn shown(db : @sql.Db, host : @host.Host, j : Map[String, Json]) -> Json raise {
  let notices = db
    .all("SELECT at, text FROM job_notices WHERE job_id = ? ORDER BY at DESC, rowid DESC LIMIT ?", [
      field(j, "id"),
      Json::number(notices_shown.to_double()),
    ])
    .map(r => ({ "at": field(r, "at"), "text": field(r, "text") } : Json))
  {
    "id": field(j, "id"),
    "session": field(j, "session_key"),
    "name": field(j, "name"),
    "command": field(j, "command"),
    "cwd": field(j, "cwd"),
    "port": field(j, "port"),
    "state": field(j, "state"),
    "pgid": field(j, "pgid"),
    "exitCode": field(j, "exit_code"),
    "startedAt": field(j, "started_at"),
    "endedAt": field(j, "ended_at"),
    "restarts": field(j, "restarts"),
    "log": field(j, "log"),
    "watch": Json::boolean(field(j, "watch") != Json::number(0.0)),
    "notices": Json::array(notices),
    "outputAt": output_at(host, field(j, "log")),
  }
}

///|
/// GET /jobs/:id.
pub fn job(db : @sql.Db, host : @host.Host, args : Json) -> Json raise {
  shown(db, host, job_row(db, args.value("id").unwrap_or(Json::null())))
}

///|
/// jobs.ts `rustLines`: split at \n, a \r before it dropped, no last empty line.
fn rust_lines(text : String) -> Array[String] {
  if text == "" {
    return []
  }
  let parts = text.split("\n").map(v => v.to_owned()).collect()
  let ended = parts[parts.length() - 1] == ""
  if ended {
    ignore(parts.pop())
  }
  parts.mapi((i, l) => if (i < parts.length() - 1 || ended) && l.has_suffix("\r") {
    l.view(end_offset=l.length() - 1).to_owned()
  } else {
    l
  })
}

///|
/// jobs.ts `parseUsize`: digits with a + at most. (A number given whose digits pass fails as it fails there.)
fn parse_usize(v : Json?) -> Double? raise {
  let text = match v {
    Some(String(s)) => s
    Some(Number(n, ..)) =>
      if n == n.floor() && n >= 0.0 && n < 1.0e21 {
        raise Refused(500, "text.replace is not a function")
      } else {
        return None
      }
    _ => return None
  }
  let body = if text.has_prefix("+") { text.view(start_offset=1).to_owned() } else { text }
  if body == "" || !body.iter().all(c => c >= '0' && c <= '9') {
    return None
  }
  // (past a usize by its digits, as the BigInt compares them)
  let mut start = 0
  while start < body.length() - 1 && body.unsafe_charcode_at(start) == '0' {
    start += 1
  }
  let digits = body.view(start_offset=start).to_owned()
  if digits.length() > 20 || (digits.length() == 20 && digits > "18446744073709551615") {
    return None
  }
  let mut n = 0.0
  for c in digits {
    n = n * 10.0 + (c.to_int() - '0'.to_int()).to_double()
  }
  Some(n)
}

///|
/// GET /jobs/:id/log.
pub fn job_log(db : @sql.Db, host : @host.Host, args : Json) -> Json raise {
  let j = job_row(db, args.value("id").unwrap_or(Json::null()))
  let wanted = parse_usize(args.value("lines")).unwrap_or(200.0)
  let n = if wanted < 1.0 { 1 } else if wanted > 1000.0 { 1000 } else { wanted.to_int() }
  let log = field(j, "log")
  let text = match log {
    String(p) =>
      match (try { Ok(host.shell_sync("fs.tail", { "path": Json::string(p), "bytes": Json::number(log_bytes.to_double()) })) } catch { e => Err(e) }) {
        Ok(String(t)) => {
          let all = rust_lines(t)
          let from = if all.length() > n { all.length() - n } else { 0 }
          all.view(start=from).iter().collect().join("\n")
        }
        _ => ""
      }
    _ => ""
  }
  { "text": Json::string(text), "outputAt": output_at(host, log), "follows": true, "state": field(j, "state") }
}
