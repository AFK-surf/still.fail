// A station's drive as the core shows it (client/core-ts shapes: StationView.overview.drive is DriveRoots, the `drive`
// topic's DriveFolder of DriveEntry, `drivePlace`'s DrivePlace; the prefs' `driveViews` and `reader`), read into what
// the drive's pages draw (ember apps/android drive/Files.kt, DriveScreen.kt; shared data/Drives.kt).

///|
/// Where a page of a drive is: a station, one of its roots (None: the drive itself, its roots), a path under it.
pub(all) struct DriveAt {
  station : String
  root : String?
  path : String
} derive(Eq)

///|
/// A file of a drive handed to the viewer that previews it (open_file): where it is and what it is.
pub(all) struct DriveFile {
  station : String
  root : String
  /// under the root, `/` between its parts
  path : String
  name : String
  size : Double
  mtime : Double
  /// the core's DriveKind: image, pdf, code, csv, html, subtitle, video, audio, other…
  kind : String
  /// its media type, by its name
  mime : String
} derive(Eq)

///|
/// An entry of a folder (DriveEntry).
priv struct DvEntry {
  name : String
  dir : Bool
  size : Double
  mtime : Double
  mime : String
  kind : String
  size_text : String
  time_text : String
}

///|
/// A folder lent (DriveRoot): where it is on the station, its name, whether it can be browsed now.
priv struct DvRoot {
  path : String
  name : String
  /// ok | missing | not_a_directory | unreadable
  state : String
}

///|
/// A station as its drive is seen: its name, whether it is up, whether its overview has come and has a drive, the
/// folders it lends, whether the viewer browses every folder (from `home`), deletes to a trash, zips.
priv struct DvStation {
  station : String
  name : String
  online : Bool
  overview : Bool
  drive : Bool
  roots : Array[DvRoot]
  anywhere : Bool
  home : String
  trash : Bool
  zip : Bool
  /// the viewer's role there (a read-only member: viewer)
  role : String
}

///|
fn dv_entry(v : Json) -> DvEntry {
  let s = Some(v)
  {
    name: text(s, "name"),
    dir: flag(s, "dir"),
    size: number(s, "size"),
    mtime: number(s, "mtime"),
    mime: text(s, "type"),
    kind: match text(s, "kind") {
      "" => if flag(s, "dir") { "folder" } else { "other" }
      k => k
    },
    size_text: text(s, "sizeText"),
    time_text: text(s, "timeText"),
  }
}

///|
fn dv_station(v : Json) -> DvStation {
  let s = Some(v)
  let ov = field(s, "overview")
  let d = field(ov, "drive")
  {
    station: text(s, "station"),
    name: text(s, "name"),
    online: flag(s, "online"),
    overview: ov is Some(Object(_)),
    drive: d is Some(Object(_)),
    roots: items(d, "roots").map(fn(r) {
      let r = Some(r)
      { path: text(r, "path"), name: text(r, "name"), state: text(r, "state") }
    }),
    anywhere: flag(d, "anywhere"),
    home: text(d, "home"),
    trash: flag(d, "trash"),
    zip: flag(d, "zip"),
    role: text(field(ov, "viewer"), "role"),
  }
}

///|
/// The workspace's stations (the `stations` topic), and why they could not be read.
fn dv_stations(src : Source, ws : String) -> (Array[DvStation]?, String?) {
  let t = (src.topic)("stations", { "scope": Json::string(ws) })
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
/// What the viewer may do with a station's drive (DriveScreen.kt DriveRights): name the folders it lends (the
/// workspace's owners and admins), change what is in them (not a read-only member).
priv struct DvRights {
  manage : Bool
  write : Bool
  trash : Bool
  zip : Bool
}

///|
fn dv_rights(src : Source, ws : String, s : DvStation?) -> DvRights {
  let w = (src.topic)("workspace", { "workspace": Json::string(ws) }).value
  let role = match s {
    Some(st) => st.role
    None => ""
  }
  {
    manage: dv_manager(w),
    write: role != "viewer" && text(w, "role") != "viewer",
    trash: match s {
      Some(st) => st.trash
      None => false
    },
    zip: match s {
      Some(st) => st.zip
      None => false
    },
  }
}

///|
/// A path under a root, `/` between its parts; `dir` empty for the root itself.
fn dv_join(dir : String, name : String) -> String {
  if dir == "" {
    name
  } else {
    dir + "/" + name
  }
}

///|
fn dv_parent(path : String) -> String {
  match path.rev_find("/") {
    Some(i) => path.view(end_offset=i).to_owned()
    None => ""
  }
}

///|
fn dv_name(path : String) -> String {
  match path.rev_find("/") {
    Some(i) => path.view(start_offset=i + 1).to_owned()
    None => path
  }
}

///|
/// What a root is called: its name as the station lends it, else its path's last part.
fn dv_root_label(roots : Array[DvRoot], root : String) -> String {
  match roots.iter().find_first(fn(r) { r.path == root }) {
    Some(r) => r.name
    None => {
      let p = root.trim_end(chars="/\\").to_owned()
      match dv_name(p) {
        "" => root
        n => n
      }
    }
  }
}

///|
/// Where a path under a root is on the station.
fn dv_absolute(root : String, path : String) -> String {
  if path == "" {
    root
  } else {
    root.trim_end(chars="/\\").to_owned() + "/" + path
  }
}

///|
/// Why a root cannot be browsed and what to do about it (DriveScreen.kt rootTrouble); None while it can.
fn dv_trouble(state : String) -> (String, String)? {
  match state {
    "ok" | "" => None
    "missing" =>
      Some((tr("android-misc.drive.root.missing"), tr("android-misc.drive.root.missingHint")))
    "not_a_directory" =>
      Some((tr("android-misc.drive.root.notFolder"), tr("android-misc.drive.root.notFolderHint")))
    _ =>
      Some((tr("android-misc.drive.root.unreadable"), tr("android-misc.drive.root.unreadableHint")))
  }
}

///|
/// What is wrong with a name a file or folder may have (empty, a slash, . or ..); None when nothing is.
fn dv_name_problem(name : String) -> String? {
  let n = name.trim(chars=" \t\n").to_owned()
  if n == "" {
    Some(tr("android-misc.drive.name.empty"))
  } else if n.contains("/") || n.contains("\\") || n == "." || n == ".." {
    Some(tr("android-misc.drive.name.bad"))
  } else {
    None
  }
}

///|
/// A name not among `taken`: "name (1).ext", "name (2).ext"… (Drives.kt freeName).
fn dv_free_name(name : String, taken : Array[String]) -> String {
  if !taken.contains(name) {
    return name
  }
  let dot = match name.rev_find(".") {
    Some(i) if i > 0 => i
    _ => name.length()
  }
  let stem = name.view(end_offset=dot).to_owned()
  let ext = name.view(start_offset=dot).to_owned()
  let mut n = 1
  while taken.contains("\{stem} (\{n})\{ext}") {
    n += 1
  }
  "\{stem} (\{n})\{ext}"
}

///|
/// A name's extension, lower case.
fn dv_ext(name : String) -> String {
  match name.rev_find(".") {
    Some(i) if i > 0 => name.view(start_offset=i + 1).to_owned().to_lower()
    _ => ""
  }
}

///|
/// A folder's entries as shown (Drives.kt arranged): hidden ones (a name starting with `.`) left out unless asked,
/// folders first, then by name (the station's order), time or size (the newest and largest first) or kind; `-down`
/// the other way.
fn dv_arranged(entries : Array[DvEntry], sort : String, hidden : Bool) -> Array[DvEntry] {
  let by = match sort.find("-") {
    Some(i) => sort.view(end_offset=i).to_owned()
    None => sort
  }
  let down = sort.has_suffix("-down")
  let named : Map[String, Int] = {}
  for i, e in entries {
    named[e.name] = i
  }
  let shown = entries.filter(fn(e) { hidden || !e.name.has_prefix(".") })
  let by_name = fn(a : DvEntry, b : DvEntry) {
    named.get(a.name).unwrap_or(0) - named.get(b.name).unwrap_or(0)
  }
  let order = fn(a : DvEntry, b : DvEntry) -> Int {
    let k = match by {
      "time" => b.mtime.compare(a.mtime)
      "size" => b.size.compare(a.size)
      "kind" =>
        match a.kind.compare(b.kind) {
          0 => dv_ext(a.name).compare(dv_ext(b.name))
          x => x
        }
      _ => 0
    }
    if k != 0 {
      k
    } else {
      by_name(a, b)
    }
  }
  shown.sort_by(fn(a, b) {
    if a.dir != b.dir {
      if a.dir {
        -1
      } else {
        1
      }
    } else if down {
      order(b, a)
    } else {
      order(a, b)
    }
  })
  shown
}

///|
/// How a station's files are listed on this device (prefs `driveViews`): their order and whether hidden ones show; as
/// set here until the prefs say.
fn dv_views(src : Source) -> (String, Bool) {
  let v = field((src.topic)("prefs", {}).value, "driveViews")
  let sort = match dv.sort_set {
    Some(s) => s
    None =>
      match text(v, "sort") {
        "" => "name"
        s => s
      }
  }
  let hidden = match dv.hidden_set {
    Some(h) => h
    None => text(v, "hidden") == "shown"
  }
  (sort, hidden)
}

///|
/// One of the drive's views changed (`prefs.set {driveViews: {key: value}}`; None: back to how it was).
fn dv_set_view(src : Source, key : String, value : String?) -> Unit {
  let o : Map[String, Json] = Map([])
  o[key] = match value {
    Some(s) => Json::string(s)
    None => Json::null()
  }
  if key == "sort" {
    dv.sort_set = Some(value.unwrap_or("name"))
  } else {
    dv.hidden_set = Some(value == Some("shown"))
  }
  (src.call)("prefs.set", Json::object({ "driveViews": Json::object(o) }), fn(_) {  })
}

///|
/// The line icon an entry is drawn with, by its kind (Controls.kt kindIcon).
fn dv_kind_icon(kind : String) -> String {
  match kind {
    "folder" => "folder"
    "video" => "file-video"
    "audio" => "file-audio"
    "image" => "photo"
    "markdown" | "text" | "subtitle" => "file-text"
    "code" | "csv" | "html" => "file-code"
    "pdf" => "file-pdf"
    _ => "file"
  }
}

///|
/// A file of a folder as the preview gets it.
fn dv_file(station : String, root : String, dir : String, e : DvEntry) -> DriveFile {
  {
    station,
    root,
    path: dv_join(dir, e.name),
    name: e.name,
    size: e.size,
    mtime: e.mtime,
    kind: e.kind,
    mime: e.mime,
  }
}

///|
/// The words for `key` by how many (`{n}`; the Chinese catalog's one and other are the same).
fn dv_count(key : String, n : Int) -> String {
  fill(key, [("n", "\{n}")])
}

///|
/// The words that are not empty, `sep` between them.
fn dv_words(words : Array[String], sep : String) -> String {
  let out = StringBuilder()
  for w in words {
    if w != "" {
      if !out.is_empty() {
        out.write_string(sep)
      }
      out.write_string(w)
    }
  }
  out.to_string()
}

///|
/// Whether the viewer names a workspace's folders lent (WorkspaceView: its owners and admins).
fn dv_manager(w : Json?) -> Bool {
  flag(w, "manager") || text(w, "role") == "owner" || text(w, "role") == "admin"
}
