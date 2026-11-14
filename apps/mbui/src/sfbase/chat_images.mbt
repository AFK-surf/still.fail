// Chats' pictures as their messages show them (`station.file` with `thumb`, `station.poster`), asked of the core once
// each and kept as images: "" while one comes, "!" when it could not be had. One its station could not be reached for
// (the network, the station away: any failure but the station saying it has none) is asked again, not kept failed
// for the app's life (pengxiao, 2026-10-25): when its station is reached again, when its chat is opened again, when it
// is pressed (`again`). How far one has come while it comes, as the core says it (`coming`), for its message to show.

///|
pub struct ChatImages {
  /// by its id: its image's key, "" while it comes, "!" failed
  keys : Map[String, String]
  /// the ones failed for want of their station, by id: their station
  unreached : Map[String, String]
  /// each station's being reached as last seen (`seen`)
  reached : Map[String, Bool]
  /// the ones the device had (the core's `held`), by id
  held : Map[String, Bool]
  /// how far the ones coming have come, by id: the bytes here, of how many when that is known (the core's
  /// `{loaded, total}`)
  coming : Map[String, (Double, Double?)]
  /// what a node of the window's tree read of each picture (the `*_told` reads), by id: told as that one changes, made
  /// as one is first read so, let go as nothing reads it any more. The old views' reads track nothing (they are built
  /// again each frame), so none is made for them and nothing is told of what they read.
  priv told : Map[String, @signals.Signal[Int]]
  /// when each one coming was first said to be on its way to what shows it (the cause's moment its node was told so:
  /// coming_since), by id: what shows how far it has come counts from it, a row let go of and made again not waiting
  /// anew; let go as it is here, fails or is asked again
  priv since : Map[String, Double]
}

///|
pub fn ChatImages::new() -> ChatImages {
  { keys: {}, unreached: {}, reached: {}, held: {}, coming: {}, told: {}, since: {} }
}

///|
/// As at the start: nothing asked yet.
pub fn ChatImages::clear(self : ChatImages) -> Unit {
  self.keys.clear()
  self.unreached.clear()
  self.reached.clear()
  self.held.clear()
  self.coming.clear()
  self.since.clear()
  let ids = self.told.keys().to_array()
  for id in ids {
    self.tell(id)
  }
  self.told.clear()
}

///|
/// What a node read of picture `id` changed: told, where one reads it (none made where none does).
fn ChatImages::tell(self : ChatImages, id : String) -> Unit {
  match self.told.get(id) {
    Some(s) =>
      if s.watched() {
        s.set(s.untracked() + 1)
      } else {
        self.told.remove(id)
      }
    None => ()
  }
}

///|
/// Picture `id` read by a node: what reads it told as it changes (its key, how far it has come, failed or not).
pub fn ChatImages::track(self : ChatImages, id : String) -> Unit {
  let s = match self.told.get(id) {
    Some(s) => s
    None => {
      let s = @signals.signal(0)
      self.told[id] = s
      s
    }
  }
  s.get() |> ignore
}

///|
/// Picture `id` of `station`: its key once here (put up as `name`), "" while it comes (asked now with `ask`, the
/// first time or again, told how far it has come as it comes and then its answer), "!" when it could not be had.
pub fn ChatImages::get(
  self : ChatImages,
  station : String,
  id : String,
  name : String,
  ask : ((Json) -> Unit, (Result[(Json, Bytes?), Json]) -> Unit) -> Unit,
) -> String {
  match self.keys.get(id) {
    Some(k) => k
    None => {
      self.keys[id] = ""
      ask(
        fn(v) {
          match field(Some(v), "loaded") {
            Some(Number(n, ..)) if self.keys.get(id) == Some("") =>
              {
                self.coming[id] = (
                  n,
                  match field(Some(v), "total") {
                    Some(Number(t, ..)) if t > 0.0 => Some(t)
                    _ => None
                  },
                )
                self.tell(id)
              }
            _ => ()
          }
        },
        fn(r) {
        self.coming.remove(id)
        self.since.remove(id)
        match r {
          // (its whole picture given meanwhile, by the viewer that read it: kept, not swapped for the smaller)
          _ if self.keys.get(id) is Some(k) && k != "" && k != "!" => ()
          Ok((said, Some(bytes))) if bytes.length() > 0 => {
            @ui.add_image(name, bytes)
            self.keys[id] = name
            self.unreached.remove(id)
            if field(Some(said), "held") is Some(True) {
              self.held[id] = true
            }
          }
          Ok(_) => self.keys[id] = "!"
          Err(e) => {
            self.keys[id] = "!"
            if !refused(e) {
              self.unreached[id] = station
            }
          }
        }
        // (told once all of it is said: its key, failed or not, held or not)
        self.tell(id)
      },
      )
      ""
    }
  }
}

///|
/// The whole of picture `id` read (the viewer's, put up as `key`): what shows it while its own is not here (still
/// coming, or failed) shows that from now on, its own let go of when it comes; one here already is kept as it is.
pub fn ChatImages::whole(self : ChatImages, id : String, key : String) -> Unit {
  match self.keys.get(id) {
    Some(k) if k != "" && k != "!" => ()
    _ => {
      self.keys[id] = key
      self.unreached.remove(id)
      self.coming.remove(id)
      self.since.remove(id)
      self.tell(id)
    }
  }
}

///|
/// How far picture `id` has come while it comes: the bytes here and of how many when known; None before the core has
/// said, or once it is here.
pub fn ChatImages::coming(self : ChatImages, id : String) -> (Double, Double?)? {
  self.coming.get(id)
}

///|
/// How far picture `id` has come (coming), read by a node: told as it changes.
pub fn ChatImages::coming_told(self : ChatImages, id : String) -> (Double, Double?)? {
  self.track(id)
  self.coming.get(id)
}

///|
/// When picture `id` was first said to be on its way to what shows it: `at` (a node's cause's moment as it is told so)
/// the first time it is asked, the moment kept since then after (till it is here, fails or is asked again).
pub fn ChatImages::coming_since(self : ChatImages, id : String, at : Double) -> Double {
  match self.since.get(id) {
    Some(t) => t
    None => {
      self.since[id] = at
      at
    }
  }
}

///|
/// What was on its way as `id` (a download of a chat's file, by its own id: not a picture's) no longer so: when it
/// was first said to be (coming_since) let go, the next time counted anew.
pub fn ChatImages::coming_let_go(self : ChatImages, id : String) -> Unit {
  self.since.remove(id)
}

///|
/// Whether picture `id` failed for want of its station (unreached), read by a node: told as that changes.
pub fn ChatImages::unreached_told(self : ChatImages, id : String) -> Bool {
  self.track(id)
  self.unreached.contains(id)
}

///|
/// Whether picture `id` came from what the device had (held), read by a node: told as that changes.
pub fn ChatImages::held_told(self : ChatImages, id : String) -> Bool {
  self.track(id)
  self.held.contains(id)
}

///|
/// Whether picture `id` failed for want of its station (asked again by `again`), not for its station having none.
pub fn ChatImages::unreached(self : ChatImages, id : String) -> Bool {
  self.unreached.contains(id)
}

///|
/// Whether picture `id` came from what the device had (the core's `held`), not from its station.
pub fn ChatImages::held(self : ChatImages, id : String) -> Bool {
  self.held.contains(id)
}

///|
/// The pictures of `station` ("" every station's) that failed for want of it asked again from the next frame on.
pub fn ChatImages::again(self : ChatImages, station : String) -> Unit {
  let ids = self.unreached.iter().filter(fn(e) { station == "" || e.1 == station }).map(fn(e) { e.0 }).to_array()
  for id in ids {
    self.unreached.remove(id)
    self.keys.remove(id)
    self.coming.remove(id)
    self.since.remove(id)
    self.tell(id)
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

///|
/// The pictures the device holds (Attachment.held) a page's build drew before they were decoded, by their image keys:
/// the app's first page waits for them with the rest of what it shows (sfapp's first_page_done, by the host's word
/// that each is decoded), not shown with a likeness in a picture's place for the frame or two its decoding takes. Said
/// afresh by each build of the page (emptied as it begins).
pub let held_pictures_waiting : Ref[Array[String]] = Ref([])

///|
/// Whether the app's first page is built and waits for what it shows (sfapp's first_waiting), followed: what the chats'
/// lists made once are drawn at none of their opacity by meanwhile, as the old views are (view_in's old_views_look),
/// the splash in their place.
// kept across runs: said by the frame as it is told (sfapp's first_hide)
pub let first_page_waits : @signals.Signal[Bool] = @signals.signal(false)

///|
/// The picture of a chat's file (Source's `file`) read by a node of the window's tree: told as it comes, fails or is
/// asked again (ChatImages::track), where `file` alone tells nothing (the old views' read, built again each frame).
pub fn Source::file_told(self : Source, station : String, key : String, name : String) -> String {
  let k = (self.file)(station, key, name)
  self.images.track(file_image_id(station, key, name))
  k
}

///|
/// A video's still from its station (Source's `poster`) read by a node: told as it comes.
pub fn Source::poster_told(self : Source, station : String, key : String, name : String) -> String {
  let k = (self.poster)(station, key, name)
  self.images.track(poster_image_id(station, key, name))
  k
}
