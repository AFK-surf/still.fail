// Folders a person keeps at hand on the files' page, of any station. Old station-pinned folders join the same list;
// removing one hides it on this device without changing the station's settings or another member's access.

///|
/// A folder kept at hand: its station, root, path under it, and its name.
pub(all) struct Favorite {
  station : String
  root : String
  path : String
  name : String
} derive(Eq)

///|
/// At most this many.
let favorites_most : Int = 40

///|
/// A list of places kept in a preference (what does not hold together let go).
fn favorites_read(src : Source, ws : String, key : String) -> Array[Favorite] {
  let raw = text(field((src.topic)("prefs", {}).value, key), ws)
  let out : Array[Favorite] = []
  match (@json.parse(raw) catch { _ => Json::null() }) {
    Array(list) =>
      for f in list {
        let f = Some(f)
        let all = ["station", "root", "path", "name"].iter().all(fn(k) { field(f, k) is Some(String(_)) })
        if all {
          let kept : Favorite = { station: text(f, "station"), root: text(f, "root"), path: text(f, "path"), name: text(f, "name") }
          if !favorite_has(out, kept.station, kept.root, kept.path) {
            out.push(kept)
          }
        }
      }
    _ => ()
  }
  out
}

///|
/// The workspace's favorites and its old pinned places, each folder once. A removed old pin stays out even if the
/// station becomes available later; its configuration is never changed by this list.
pub fn favorites(src : Source, ws : String) -> Array[Favorite] {
  favorites_in(src, ws, dv_stations(src, ws).0.unwrap_or([]))
}

///|
/// The same list using stations already read by its caller.
fn favorites_in(src : Source, ws : String, stations : Array[DvStation]) -> Array[Favorite] {
  let out = favorites_read(src, ws, "driveFavorites")
  let hidden = favorites_read(src, ws, "driveFavoritesHidden")
  for s in stations {
    for r in s.roots {
      if !favorite_has(out, s.station, r.path, "") && !favorite_has(hidden, s.station, r.path, "") {
        out.push({ station: s.station, root: r.path, path: "", name: if r.name == "" { dv_root_label([], r.path) } else { r.name } })
      }
    }
  }
  out
}

///|
fn favorites_json(list : Array[Favorite]) -> String {
  let kept = list.map(fn(f) -> Json {
    { "station": Json::string(f.station), "root": Json::string(f.root), "path": Json::string(f.path), "name": Json::string(f.name) }
  })
  Json::array(kept).stringify()
}

///|
fn favorites_keep(src : Source, ws : String, list : Array[Favorite], hidden : Array[Favorite]) -> Unit {
  let kept = if list.length() > favorites_most { list[:favorites_most].to_owned() } else { list }
  let favorites : Map[String, Json] = {}
  let removed : Map[String, Json] = {}
  favorites[ws] = Json::string(favorites_json(kept))
  removed[ws] = Json::string(favorites_json(hidden))
  (src.call)("prefs.set", { "driveFavorites": Json::object(favorites), "driveFavoritesHidden": Json::object(removed) }, fn(_) {  })
}

///|
/// A folder's absolute path for comparing places: a Windows root's separators and case are interchangeable, while a
/// backslash in a Unix name is a name, not a separator. Keep the stored root and path for reaching the folder.
fn favorite_path(root : String, path : String) -> String {
  let abs = dv_absolute(root, path)
  let abs = if @sfbase.dv_windows_path(root) { abs.replace_all(old="\\", new="/").to_lower() } else { abs }
  if abs == "/" { abs } else { abs.trim_end(chars="/").to_owned() }
}

///|
/// Two ways to the same folder on a station (a shared root and the same folder reached from its parent).
fn favorite_same_path(root : String, path : String, other_root : String, other_path : String) -> Bool {
  favorite_path(root, path) == favorite_path(other_root, other_path)
}

///|
/// Whether the folder (`station`, `root`, `path`) is among them, whatever root it was reached under.
pub fn favorite_has(list : Array[Favorite], station : String, root : String, path : String) -> Bool {
  list.iter().any(fn(f) { f.station == station && favorite_same_path(f.root, f.path, root, path) })
}

///|
/// One kept (after those kept, unless it is among them).
pub fn favorite_add(src : Source, ws : String, f : Favorite) -> Unit {
  let list = favorites_read(src, ws, "driveFavorites")
  let hidden = favorites_read(src, ws, "driveFavoritesHidden").filter(fn(x) {
    !(x.station == f.station && favorite_same_path(x.root, x.path, f.root, f.path))
  })
  if !favorite_has(list, f.station, f.root, f.path) {
    list.push(f)
  }
  favorites_keep(src, ws, list, hidden)
}

///|
/// One let go.
pub fn favorite_remove(src : Source, ws : String, station : String, root : String, path : String) -> Unit {
  let list = favorites_read(src, ws, "driveFavorites").filter(fn(f) { !(f.station == station && favorite_same_path(f.root, f.path, root, path)) })
  let hidden = favorites_read(src, ws, "driveFavoritesHidden")
  if !favorite_has(hidden, station, root, path) {
    hidden.push({ station, root, path, name: "" })
  }
  favorites_keep(src, ws, list, hidden)
}
