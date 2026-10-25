// Chats' pictures as their messages show them (`station.file` with `thumb`, `station.poster`), asked of the core once
// each and kept as images: "" while one comes, "!" when it could not be had. One its station could not be reached for
// (the network, the station away: any failure but the station saying it has none) is asked again, not kept failed
// for the app's life (pengxiao, 2026-10-25): when its station is reached again, when its chat is opened again, when it
// is pressed (`again`).

///|
pub struct ChatImages {
  /// by its id: its image's key, "" while it comes, "!" failed
  keys : Map[String, String]
  /// the ones failed for want of their station, by id: their station
  unreached : Map[String, String]
  /// each station's being reached as last seen (`seen`)
  reached : Map[String, Bool]
}

///|
pub fn ChatImages::new() -> ChatImages {
  { keys: {}, unreached: {}, reached: {} }
}

///|
/// As at the start: nothing asked yet.
pub fn ChatImages::clear(self : ChatImages) -> Unit {
  self.keys.clear()
  self.unreached.clear()
  self.reached.clear()
}

///|
/// Picture `id` of `station`: its key once here (put up as `name`), "" while it comes (asked now with `ask`, the
/// first time or again), "!" when it could not be had.
pub fn ChatImages::get(
  self : ChatImages,
  station : String,
  id : String,
  name : String,
  ask : ((Result[(Json, Bytes?), Json]) -> Unit) -> Unit,
) -> String {
  match self.keys.get(id) {
    Some(k) => k
    None => {
      self.keys[id] = ""
      ask(fn(r) {
        match r {
          Ok((_, Some(bytes))) if bytes.length() > 0 => {
            @ui.add_image(name, bytes)
            self.keys[id] = name
            self.unreached.remove(id)
          }
          Ok(_) => self.keys[id] = "!"
          Err(e) => {
            self.keys[id] = "!"
            if !refused(e) {
              self.unreached[id] = station
            }
          }
        }
      })
      ""
    }
  }
}

///|
/// Whether picture `id` failed for want of its station (asked again by `again`), not for its station having none.
pub fn ChatImages::unreached(self : ChatImages, id : String) -> Bool {
  self.unreached.contains(id)
}

///|
/// The pictures of `station` ("" every station's) that failed for want of it asked again from the next frame on.
pub fn ChatImages::again(self : ChatImages, station : String) -> Unit {
  let ids = self.unreached.iter().filter(fn(e) { station == "" || e.1 == station }).map(fn(e) { e.0 }).to_array()
  for id in ids {
    self.unreached.remove(id)
    self.keys.remove(id)
  }
}

///|
/// `station` seen reached or not: reached again after it was not, its pictures that failed meanwhile asked again.
pub fn ChatImages::seen(self : ChatImages, station : String, reached : Bool) -> Unit {
  if reached && self.reached.get(station) == Some(false) {
    self.again(station)
  }
  self.reached[station] = reached
}

///|
/// Whether a failure is the station's own answer that it has none (a 4xx: no such file, not one's to read): asked again
/// it would say the same.
fn refused(e : Json) -> Bool {
  match field(Some(e), "status") {
    Some(Number(n, ..)) => n >= 400.0 && n < 500.0 && n != 408.0 && n != 429.0
    _ => text(Some(e), "code").has_prefix("http_4")
  }
}

///|
/// A chat's file's picture's id among them: its station, the session that keeps it, its name.
pub fn file_image_id(station : String, key : String, name : String) -> String {
  station + "\u{1}" + key + "\u{1}" + name
}

///|
/// A video's still's id among them.
pub fn poster_image_id(station : String, key : String, name : String) -> String {
  file_image_id(station, key, name) + "\u{1}poster"
}
