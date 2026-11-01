// A folder as a place shows it, as the core says (client/core-ts views/browse.ts, drive-browse.ts: the `driveBrowse`
// topic's BrowseView): the order its entries go in and whether hidden ones show (the device's, prefs `driveViews`),
// each folder the place shows by its names in that order, what is chosen there, a tree's folders open, the columns'
// widths dragged, the keys that act now. The phone's drive pages read the order from it; the desktop's files' page all
// of it (src/sfdesk/browse.mbt). And the stations with a drive (`stations {scope, drive: true, here?}`).

///|
/// How a folder's entries are shown (Arrangement): ordered by `by` (name, time, size or kind), the other way (`down`),
/// hidden ones too.
pub(all) struct Arrangement {
  by : String
  down : Bool
  hidden : Bool
} derive(Eq)

///|
/// What is chosen (Chosen): names in one folder (its path under the root), the one ⇧ goes from and the one the keys move
/// from.
pub(all) struct Chosen {
  folder : String
  names : Array[String]
  anchor : String?
  lead : String?
} derive(Eq)

///|
/// Nothing chosen.
pub fn chosen_none() -> Chosen {
  { folder: "", names: [], anchor: None, lead: None }
}

///|
/// The `driveBrowse` topic's value (BrowseView).
pub(all) struct BrowseView {
  arrangement : Arrangement
  folders : Map[String, Array[String]]
  count_text : String?
  chosen : Chosen
  open : Array[String]
  widths : Map[String, Double]
  keys : Array[String]
}

///|
/// As where never said: by name, hidden ones not shown.
pub fn arrangement_none() -> Arrangement {
  { by: "name", down: false, hidden: false }
}

///|
pub fn arrangement_of(v : Json?) -> Arrangement {
  match v {
    Some(Object(_)) => { by: if text(v, "by") == "" { "name" } else { text(v, "by") }, down: flag(v, "down"), hidden: flag(v, "hidden") }
    _ => arrangement_none()
  }
}

///|
fn words_of(v : Json) -> Array[String] {
  match v {
    Array(a) =>
      a.map(fn(x) {
        match x {
          String(s) => s
          _ => ""
        }
      })
    _ => []
  }
}

///|
pub fn chosen_of(v : Json?) -> Chosen {
  {
    folder: text(v, "folder"),
    names: words_of(field(v, "names").unwrap_or(Json::null())),
    anchor: opt_text(v, "anchor"),
    lead: opt_text(v, "lead"),
  }
}

///|
/// The topic's value read (None while the core has not said it).
pub fn browse_view_of(v : Json?) -> BrowseView? {
  match v {
    Some(Object(_)) => {
      let folders : Map[String, Array[String]] = {}
      match field(v, "folders") {
        Some(Object(m)) =>
          for k, x in m {
            folders[k] = words_of(x)
          }
        _ => ()
      }
      let widths : Map[String, Double] = {}
      match field(v, "widths") {
        Some(Object(m)) =>
          for k, x in m {
            match x {
              Number(n, ..) => widths[k] = n
              _ => ()
            }
          }
        _ => ()
      }
      Some({
        arrangement: arrangement_of(field(v, "arrangement")),
        folders,
        count_text: opt_text(v, "countText"),
        chosen: chosen_of(field(v, "chosen")),
        open: words_of(field(v, "open").unwrap_or(Json::null())),
        widths,
        keys: words_of(field(v, "keys").unwrap_or(Json::null())),
      })
    }
    _ => None
  }
}

///|
/// Where a place is, as its topic and its calls say it (`owner`: page or tab; `place`: the client's own name for this
/// one; `view`: columns, tree or list; `write`: names changed and things deleted there).
pub fn browse_where(
  owner : String,
  place : String,
  view : String,
  station : String,
  root : String,
  path : String,
  write? : Bool = false,
) -> Map[String, Json] {
  let o : Map[String, Json] = {
    "owner": Json::string(owner),
    "place": Json::string(place),
    "view": Json::string(view),
    "station": Json::string(station),
    "root": Json::string(root),
    "path": Json::string(path),
  }
  if write {
    o["write"] = Json::boolean(true)
  }
  o
}

///|
/// The place's topic as it stands.
pub fn browse_topic(src : Source, where_ : Map[String, Json]) -> BrowseView? {
  match browse_read.read(src, where_).0 {
    Some(v) => v
    None => None
  }
}

///|
/// How a place browses as the core's `driveBrowse` topic gives it, worked out once for each version of it.
// kept across runs: what it keeps is let go of by a run anew and by reset (derived.mbt)
let browse_read : Derived[BrowseView?] = Derived::new("driveBrowse", fn(v, _) {
  browse_view_of(Some(v))
})

///|
/// A folder's entries in the order the core shows them (`names`), hidden ones as it says; None while it has not said
/// the folder.
pub fn dv_in_order(names : Array[String]?, entries : Array[DvEntry]) -> Array[DvEntry]? {
  match names {
    Some(ns) => {
      let by : Map[String, DvEntry] = {}
      for e in entries {
        by[e.name] = e
      }
      let out : Array[DvEntry] = []
      for n in ns {
        match by.get(n) {
          Some(e) => out.push(e)
          None => ()
        }
      }
      Some(out)
    }
    None => None
  }
}

///|
/// The order and whether hidden files show, changed (`drive.arrange`: what is not said stays).
pub fn dv_arrange(src : Source, by? : String, down? : Bool, hidden? : Bool) -> Unit {
  let o : Map[String, Json] = {}
  match by {
    Some(b) => o["by"] = Json::string(b)
    None => ()
  }
  match down {
    Some(d) => o["down"] = Json::boolean(d)
    None => ()
  }
  match hidden {
    Some(h) => o["hidden"] = Json::boolean(h)
    None => ()
  }
  (src.call)("drive.arrange", Json::object(o), fn(_) {  })
}

///|
/// The workspace's stations with a drive (`stations {scope, drive: true, here?}`: this machine's, `here`, first), and
/// why they could not be read.
pub fn dv_drive_stations(src : Source, ws : String, here? : String = "") -> (Array[DvStation]?, String?) {
  let params : Map[String, Json] = { "scope": Json::string(ws), "drive": Json::boolean(true) }
  if here != "" {
    params["here"] = Json::string(here)
  }
  let t = (src.topic)("stations", params)
  let error = match t.error {
    Some(e) => Some(text(Some(e), "message"))
    None => None
  }
  match t.value {
    Some(Array(a)) => (Some(a.map(dv_station)), error)
    _ => (None, error)
  }
}

///|
/// A folder's entries as the phone's pages show them: in the device's order, hidden ones as it says (the core's, as a
/// list of the phone's own place shows it); as the station lists them while the core has not said it (what is there
/// shown at once, as a page shows what it holds); None only where the core has the place but not the folder.
pub fn dv_shown(src : Source, station : String, root : String, path : String, entries : Array[DvEntry]) -> Array[DvEntry]? {
  let v = browse_topic(src, browse_where("page", "phone", "list", station, root, path))
  match v {
    Some(b) => dv_in_order(b.folders.get(path), entries)
    None => Some(entries)
  }
}

///|
/// How the device orders a folder's entries, as the core says (by name where it has not).
pub fn dv_arrangement(src : Source, station : String, root : String, path : String) -> Arrangement {
  match browse_topic(src, browse_where("page", "phone", "list", station, root, path)) {
    Some(b) => b.arrangement
    None => arrangement_none()
  }
}
