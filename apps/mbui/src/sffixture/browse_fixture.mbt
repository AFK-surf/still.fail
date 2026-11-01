// The made-up core's browsing of the drive (the core's views/browse.ts over drive-browse.ts `Browsing`): the
// `driveBrowse` and `filesTabs` topics and the calls (drive.browse, drive.arrange, drive.name, drive.moves, files.tabs,
// files.go), each a step the real core answered, kept (src/sfkept/browse.mbt): what the browsing held before it, the
// prefs it reads, the made-up folders' entries it reads, what is done. What it holds after a call is kept here for the
// next; the prefs it changes go among the fixture's (driveViews, filesTabs, and the favourites the pages keep).

///|
/// What the browsing holds (its snapshot: null before any call), the number its next new id is made of, the prefs it
/// and the pages keep (each by its key, as prefs.set merges it), and the topics' values worked out since the fixture last
/// changed (by their params); how often a test changed what it holds itself (not by a call of the fixture's, which
/// counts in its version): counted in the topics' versions as the core counts every change (fixture_topic).
pub(all) struct FixBrowse {
  mut state : Json
  mut id : Int
  prefs : Map[String, Map[String, Json]]
  shown : Map[String, Json?]
  mut version : Int
  mut changes : Int
}

///|
pub let fix_browse : FixBrowse = { state: Json::null(), id: 0, prefs: {}, shown: {}, version: -1, changes: 0 }

///|
/// What the browsing holds changed: the topics' values worked out again, their versions on by one.
pub fn fix_browse_changed() -> Unit {
  fix_browse.shown.clear()
  fix_browse.changes += 1
  @settings.fixture_changed()
}

///|
pub fn fix_browse_reset() -> Unit {
  fix_browse.state = Json::null()
  fix_browse.id = 0
  fix_browse.prefs.clear()
  fix_browse.shown.clear()
  fix_browse.version = -1
  fix_browse.changes = 0
}

///|
/// The prefs the browsing reads and the pages keep, as the core's prefs topic gives them.
// kept across runs: a table, never written
pub let fix_browse_prefs : Array[String] = ["driveViews", "filesTabs", "driveFavorites"]

///|
/// The prefs kept here, into the prefs topic's value.
pub fn fix_browse_prefs_into(o : Map[String, Json]) -> Unit {
  for k in fix_browse_prefs {
    o[k] = Json::object(fix_browse.prefs.get(k).unwrap_or({}).copy())
  }
}

///|
/// A prefs.set (or a patch the browsing made) of those kept here, merged as the core merges it (null: let go).
pub fn fix_browse_prefs_set(params : Json) -> Bool {
  let mut changed = false
  for k in fix_browse_prefs {
    match field(Some(params), k) {
      Some(Object(m)) => {
        let kept = match fix_browse.prefs.get(k) {
          Some(x) => x
          None => {
            let x : Map[String, Json] = {}
            fix_browse.prefs[k] = x
            x
          }
        }
        for name, v in m {
          match v {
            Null => kept.remove(name)
            _ => kept[name] = v
          }
        }
        changed = true
        fix_browse_changed()
      }
      _ => ()
    }
  }
  changed
}

///|
/// A made-up folder's entries as the browsing orders them (drive-browse.ts Ordered), null while the drive is read.
pub fn fix_browse_folder(mode : String, root : String, path : String) -> Json {
  if mode == "drive-loading" {
    return Json::null()
  }
  Json::array(
    fix_folder(root, path).map(fn(e) {
      let e = Some(e)
      {
        "name": Json::string(text(e, "name")),
        "dir": Json::boolean(flag(e, "dir")),
        "size": Json::number(number(e, "size")),
        "mtime": Json::number(number(e, "mtime")),
        "kind": Json::string(text(e, "kind")),
      }
    }),
  )
}

///|
/// The workspace's stations with a drive as the browsing names them (their address, name and home).
pub fn fix_browse_stations(f : Fixture, ws : String) -> Json {
  let out : Array[Json] = []
  match fixture_topic_inner(f, "stations", { "scope": Json::string(ws) }) {
    Some(Array(list)) =>
      for s in list {
        let s = Some(s)
        let d = field(field(s, "overview"), "drive")
        if d is Some(Object(_)) {
          out.push({
            "station": Json::string(text(s, "station")),
            "name": Json::string(text(s, "name")),
            "home": if text(d, "home") == "" { Json::null() } else { Json::string(text(d, "home")) },
          })
        }
      }
    _ => ()
  }
  Json::array(out)
}

///|
/// A step of the browsing (`op`: {topic} or {name, params}) as the real core answered it: the folders it reads given as
/// it asks for them. Err where it is not kept (or there is no kept core here).
pub fn fix_browse_step(f : Fixture?, mode : String, op : Json) -> Result[Json, Json] {
  let kept = match @sf.kept_call.val {
    Some(k) => k
    None => return Err({ "code": "not_kept", "message": "no kept core's answers here" })
  }
  let params = match field(Some(op), "topic") {
    Some(t) => Some(t)
    None => field(Some(op), "params")
  }
  let name = text(Some(op), "name")
  let station = text(params, "station")
  let root = text(params, "root")
  // the folders it surely reads: the way down to the one shown (and to the one a press is in)
  let folders : Map[String, Json] = {}
  let given = fn(path : String) {
    let mut so_far = ""
    let parts = if path == "" { [] } else { path.split("/").map(fn(p) { p.to_string() }).collect() }
    folders[station + "\n" + root + "\n"] = fix_browse_folder(mode, root, "")
    for p in parts {
      so_far = dv_join(so_far, p)
      folders[station + "\n" + root + "\n" + so_far] = fix_browse_folder(mode, root, so_far)
    }
  }
  if station != "" && field(params, "root") is Some(String(_)) {
    given(text(params, "path"))
    if field(params, "folder") is Some(String(_)) {
      given(text(params, "folder"))
    }
  }
  // the stations for a path typed; the time for a letter typed (else none, so a step is the same at any time)
  let stations : Map[String, Json] = {}
  if name == "files.go" {
    match f {
      Some(f) => stations[text(params, "workspace")] = fix_browse_stations(f, text(params, "workspace"))
      None => ()
    }
  }
  // det-ok(app-clock): the core's own input, as the real one reads its host's clock for a letter typed (Host.nowMs)
  let now = if text(params, "act") == "type" { @ui.now() } else { 0.0 }
  let prefs : Map[String, Json] = {}
  for k in ["driveViews", "filesTabs"] {
    prefs[k] = Json::object(fix_browse.prefs.get(k).unwrap_or({}).copy())
  }
  for _ in 0..<16 {
    let fields : Map[String, Json] = {
      "state": fix_browse.state,
      "prefs": Json::object(prefs),
      "folders": Json::object(folders.copy()),
      "stations": Json::object(stations),
      "now": Json::number(now),
      "id": Json::number(fix_browse.id.to_double()),
      "op": op,
    }
    if @sf.language() == "en" && text(field(Some(op), "topic"), "topic") == "driveBrowse" {
      fields["lang"] = Json::string("en")
    }
    let ask = Json::object(fields)
    match kept("browse", ask, None) {
      Some(Ok((answer, _))) =>
        match field(Some(answer), "need") {
          Some(Array(need)) =>
            for k in need {
              let key = match k {
                String(s) => s
                _ => ""
              }
              let parts = key.split("\n").map(fn(p) { p.to_string() }).collect()
              if parts.length() == 3 {
                folders[key] = fix_browse_folder(mode, parts[1], parts[2])
              }
            }
          _ => return Ok(answer)
        }
      Some(Err(e)) => return Err(e)
      None => return Err({ "code": "not_kept", "message": "browse" })
    }
  }
  Err({ "code": "not_kept", "message": "the browsing kept asking for folders" })
}

///|
/// The `driveBrowse` or `filesTabs` topic's value, as the core gives it now.
pub fn fix_browse_topic(f : Fixture, name : String, params : Map[String, Json]) -> Json? {
  if fix_browse.version != f.version {
    fix_browse.shown.clear()
    fix_browse.version = f.version
  }
  let topic : Map[String, Json] = { "topic": Json::string(name) }
  for k, v in params {
    topic[k] = v
  }
  let key = Json::object(topic).stringify()
  match fix_browse.shown.get(key) {
    Some(v) => v
    None => {
      let v = match fix_browse_step(Some(f), f.mode, { "topic": Json::object(topic) }) {
        Ok(a) =>
          match field(Some(a), "value") {
            Some(Null) | None => None
            Some(v) => Some(v)
          }
        Err(_) => None
      }
      fix_browse.shown[key] = v
      v
    }
  }
}

///|
/// A call of the browsing's (drive-browse.ts CALLS), answered: what it holds after it kept, the prefs it changed set.
pub fn fixture_browse_call(f : Fixture, name : String, params : Json) -> Result[Json, Json]? {
  match name {
    "drive.browse" | "drive.arrange" | "drive.name" | "drive.moves" | "files.tabs" | "files.go" => ()
    _ => return None
  }
  let r = fix_browse_do(Some(f), f.mode, name, params)
  f.changed()
  Some(r)
}

///|
/// A call of the browsing's done by the made-up core (by a fixture's mode too, before the app's first frame).
pub fn fix_browse_do(f : Fixture?, mode : String, name : String, params : Json) -> Result[Json, Json] {
  match fix_browse_step(f, mode, { "name": Json::string(name), "params": params }) {
    Ok(a) => {
      match field(Some(a), "state") {
        Some(s) => fix_browse.state = s
        None => ()
      }
      fix_browse.id = number(Some(a), "id").to_int()
      fix_browse_changed()
      for p in items(Some(a), "prefs") {
        fix_browse_prefs_set(p) |> ignore
      }
      match field(Some(a), "error") {
        Some(String(e)) => Err({ "code": "invalid", "message": Json::string(e) })
        _ => Ok(field(Some(a), "value").unwrap_or(Json::null()))
      }
    }
    Err(e) => Err(e)
  }
}

///|
/// The stations a workspace lists, those with a drive, this machine's (`here`) first: as the core gives the `stations`
/// topic asked with `drive` (drive-browse.ts withDrive, kept).
pub fn fix_browse_with_drive(f : Fixture, stations : Json?, here : String) -> Json? {
  ignore(f)
  let stations = match stations {
    Some(s) => s
    None => return None
  }
  let kept = match @sf.kept_call.val {
    Some(k) => k
    None => return None
  }
  let ask : Json = {
    "op": {
      "withDrive": { "stations": stations, "here": if here == "" { Json::null() } else { Json::string(here) } },
    },
  }
  match kept("browse", ask, None) {
    Some(Ok((answer, _))) => field(Some(answer), "value")
    _ => None
  }
}
