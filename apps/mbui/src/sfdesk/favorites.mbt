// Folders a person keeps at hand on the files' page (its sidebar's 个人收藏: ember web/src/drive/favorites.ts), of any
// station of the workspace, as Finder's favourites: theirs alone, kept on this device among the prefs
// (`driveFavorites`, by workspace), not the station's pinned folders (which every member sees: 团队共享).

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
/// The workspace's favourites, as kept (what does not hold together let go).
pub fn favorites(src : Source, ws : String) -> Array[Favorite] {
  let raw = text(field((src.topic)("prefs", {}).value, "driveFavorites"), ws)
  let out : Array[Favorite] = []
  match (@json.parse(raw) catch { _ => Json::null() }) {
    Array(list) =>
      for f in list {
        let f = Some(f)
        let all = ["station", "root", "path", "name"].iter().all(fn(k) { field(f, k) is Some(String(_)) })
        if all {
          out.push({ station: text(f, "station"), root: text(f, "root"), path: text(f, "path"), name: text(f, "name") })
        }
      }
    _ => ()
  }
  out
}

///|
fn favorites_keep(src : Source, ws : String, list : Array[Favorite]) -> Unit {
  let kept = (if list.length() > favorites_most { list[:favorites_most].to_owned() } else { list }).map(fn(f) -> Json {
    { "station": Json::string(f.station), "root": Json::string(f.root), "path": Json::string(f.path), "name": Json::string(f.name) }
  })
  let o : Map[String, Json] = {}
  o[ws] = Json::string(Json::array(kept).stringify())
  (src.call)("prefs.set", { "driveFavorites": Json::object(o) }, fn(_) {  })
}

///|
/// Whether the folder (`station`, `root`, `path`) is among them.
pub fn favorite_has(list : Array[Favorite], station : String, root : String, path : String) -> Bool {
  list.iter().any(fn(f) { f.station == station && f.root == root && f.path == path })
}

///|
/// One kept (after those kept, unless it is among them).
pub fn favorite_add(src : Source, ws : String, f : Favorite) -> Unit {
  let list = favorites(src, ws)
  if !favorite_has(list, f.station, f.root, f.path) {
    list.push(f)
    favorites_keep(src, ws, list)
  }
}

///|
/// One let go.
pub fn favorite_remove(src : Source, ws : String, station : String, root : String, path : String) -> Unit {
  favorites_keep(src, ws, favorites(src, ws).filter(fn(f) { !(f.station == station && f.root == root && f.path == path) }))
}
