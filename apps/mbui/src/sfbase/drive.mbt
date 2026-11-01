// A station's drive as the core shows it, what the phone's drive pages and the desktop's files' page both read (client/core-ts shapes: StationView.overview.drive is DriveRoots, the `drive`
// topic's DriveFolder of DriveEntry, `drivePlace`'s DrivePlace; the prefs' `driveViews` and `reader`), read into what
// the drive's pages draw (ember apps/android drive/Files.kt, DriveScreen.kt; shared data/Drives.kt).


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
pub(all) struct DvEntry {
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
pub(all) struct DvRoot {
  path : String
  name : String
  /// ok | missing | not_a_directory | unreadable
  state : String
}

///|
/// A station as its drive is seen: its name, whether it is up, whether its overview has come and has a drive, the
/// folders it lends, whether the viewer browses every folder (from `home`), deletes to a trash, zips.
pub(all) struct DvStation {
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
  /// whether it takes copies from another station (`drive.transfer`: one from before does not)
  transfers : Bool
  /// its mark (StationMark: an emoji, or an icon's name), none set
  emoji : String
  icon : String
  /// its disk's size and what is free on it (none known: 0)
  disk_total : Double
  disk_free : Double
}

///|
/// Folder `path` of `root` on `station`: its entries as the station said them (the core's `drive` topic), worked out
/// once for each version of it; None while it has not said them.
pub fn dv_entries(src : Source, station : String, root : String, path : String) -> Array[DvEntry]? {
  dv_entries_read.read(src, drive_params(station, root, path)).0
}

///|
/// A folder's entries as the core's `drive` topic gives them.
// kept across runs: what it keeps is let go of by a run anew and by reset (derived.mbt)
let dv_entries_read : Derived[Array[DvEntry]] = Derived::new("drive", fn(v, _) {
  items(Some(v), "entries").map(dv_entry)
})

///|
pub fn dv_entry(v : Json) -> DvEntry {
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
pub fn dv_station(v : Json) -> DvStation {
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
    // a folder zips for one who browses every folder (the station's rule, routes/drive.ts: GET /drive says `zip`, its
    // overview does not)
    zip: flag(d, "zip") || flag(d, "anywhere"),
    role: text(field(ov, "viewer"), "role"),
    transfers: flag(d, "transfers"),
    emoji: text(s, "emoji"),
    icon: text(s, "icon"),
    disk_total: number(field(ov, "disk"), "totalBytes"),
    disk_free: number(field(ov, "disk"), "freeBytes"),
  }
}

///|
/// The workspace's stations (the `stations` topic), and why they could not be read.
pub fn dv_stations(src : Source, ws : String) -> (Array[DvStation]?, String?) {
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
pub(all) struct DvRights {
  manage : Bool
  write : Bool
  trash : Bool
  zip : Bool
}

///|
pub fn dv_rights(src : Source, ws : String, s : DvStation?) -> DvRights {
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
pub fn dv_join(dir : String, name : String) -> String {
  if dir == "" {
    name
  } else {
    dir + "/" + name
  }
}

///|
pub fn dv_parent(path : String) -> String {
  match path.rev_find("/") {
    Some(i) => path.view(end_offset=i).to_owned()
    None => ""
  }
}

///|
/// Whether an absolute path names a Windows drive or UNC share. A backslash in a Unix name is not a separator.
pub fn dv_windows_path(path : String) -> Bool {
  path.has_prefix("\\\\") ||
  (path.find(":") is Some(1) && (path.view(start_offset=2).has_prefix("\\") || path.view(start_offset=2).has_prefix("/")))
}

///|
pub fn dv_name(path : String) -> String {
  let slash = path.rev_find("/")
  let backslash = if dv_windows_path(path) { path.rev_find("\\") } else { None }
  let last = match (slash, backslash) {
    (Some(a), Some(b)) => Some(if a > b { a } else { b })
    (Some(a), None) | (None, Some(a)) => Some(a)
    _ => None
  }
  match last {
    Some(i) => path.view(start_offset=i + 1).to_owned()
    None => path
  }
}

///|
/// What a root is called: its name as the station lends it, else its path's last part.
pub fn dv_root_label(roots : Array[DvRoot], root : String) -> String {
  match roots.iter().find_first(fn(r) { r.path == root }) {
    Some(r) => r.name
    None => {
      let p = dv_trim_root(root)
      match dv_name(p) {
        "" => root
        n => n
      }
    }
  }
}

///|
/// Remove trailing path separators without treating a Unix name's backslash as one.
pub fn dv_trim_root(root : String) -> String {
  root.trim_end(chars=if dv_windows_path(root) { "/\\" } else { "/" }).to_owned()
}

///|
/// Where a path under a root is on the station.
pub fn dv_absolute(root : String, path : String) -> String {
  if path == "" {
    root
  } else {
    dv_trim_root(root) + "/" + path
  }
}

///|
/// Why a root cannot be browsed and what to do about it (useDrive.ts rootTrouble); None while it can.
pub fn dv_trouble(state : String) -> (String, String)? {
  match state {
    "ok" | "" => None
    "missing" =>
      Some((@sf.t("web-pages.drive.root.missing"), @sf.t("web-pages.drive.root.missingHint")))
    "not_a_directory" =>
      Some((@sf.t("web-pages.drive.root.notFolder"), @sf.t("web-pages.drive.root.notFolderHint")))
    _ =>
      Some((@sf.t("web-pages.drive.root.unreadable"), @sf.t("web-pages.drive.root.unreadableHint")))
  }
}

///|
/// A name typed for a file or folder, as the core says it may be (`drive.check`: not empty, no slash, not . or ..):
/// `then(None)` where it may, else `then(Some(why))`.
pub fn dv_check_name(src : Source, name : String, then : (String?) -> Unit) -> Unit {
  (src.call)("drive.check", { "text": Json::string(name) }, fn(r) {
    match r {
      Ok(v) =>
        then(
          match field(Some(v), "problem") {
            Some(String(p)) => Some(p)
            _ => None
          },
        )
      Err(e) => then(Some(dv_error(e)))
    }
  })
}

///|
/// The line icon an entry is drawn with, by its kind (Controls.kt kindIcon).
pub fn dv_kind_icon(kind : String) -> String {
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
pub fn dv_file(station : String, root : String, dir : String, e : DvEntry) -> DriveFile {
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
pub fn dv_count(key : String, n : Int) -> String {
  @sf.t(key, args=[("n", "\{n}")])
}

///|
/// The words that are not empty, `sep` between them.
pub fn dv_words(words : Array[String], sep : String) -> String {
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
pub fn dv_manager(w : Json?) -> Bool {
  flag(w, "manager") || text(w, "role") == "owner" || text(w, "role") == "admin"
}

///|
/// The name a file takes kept beside one of its name in the folder `path` of `root` (保留两者), as the station keeps
/// both (the core's `drive.name`, beside: `a 2.txt`), not among the folder's names as the core holds them nor `taken`:
/// `then(Ok(name))`, or why it could not be named.
pub fn dv_beside_name(
  src : Source,
  station : String,
  root : String,
  path : String,
  name : String,
  taken : Array[String],
  then : (Result[String, String]) -> Unit,
) -> Unit {
  (src.call)(
    "drive.name",
    {
      "name": Json::string(name),
      "station": Json::string(station),
      "root": Json::string(root),
      "path": Json::string(path),
      "taken": Json::array(taken.map(fn(n) { Json::string(n) })),
      "beside": Json::boolean(true),
    },
    fn(r) {
      match r {
        Ok(v) => then(Ok(text(Some(v), "name")))
        Err(e) => then(Err(dv_error(e)))
      }
    },
  )
}

///|
/// A file whose name was taken in its folder kept beside it (保留两者: dv_beside_name over the others going up there),
/// then on its way again.
pub fn dv_keep_both(src : Source, u : DvUpload) -> Unit {
  let others = ups.uploads.filter(fn(x) { x.serial != u.serial && x.station == u.station && x.root == u.root && x.dir == u.dir })
  u.state.set("naming")
  dv_beside_name(src, u.station, u.root, u.dir, u.name.get(), others.map(fn(x) { x.name.get() }), fn(r) {
    match r {
      Ok(name) => {
        u.name.set(name)
        u.state.set("waiting")
      }
      Err(why) => {
        u.state.set("failed")
        u.error.set(why)
      }
    }
    dv_pump(src)
  })
}


///|
/// A station's file or folder dragged out of a list of its drive (drag.ts Dragged: the files' page, a chat's 文件 tab):
/// its station and that station's name, its root and its path under it, its absolute path, its name, its size,
/// whether it is a folder. What a composer takes of it is named by its path on its station.
pub(all) struct Dragged {
  station : String
  station_name : String
  root : String
  path : String
  abs : String
  name : String
  size : Double
  dir : Bool
}
