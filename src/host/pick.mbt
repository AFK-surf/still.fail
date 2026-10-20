// Files picked by the person through the system's own pickers, as a composer's ＋ asks for them (still.fail's Android
// app, chat/screens/Attach.kt): the photo picker (Android's ACTION_PICK_IMAGES, macOS's open panel on images), the
// file picker (ACTION_OPEN_DOCUMENT; the open panel), a photo taken now (ACTION_IMAGE_CAPTURE's picture). The system
// asks on its own; `files` is None until it has answered, then what was picked (none when it was called off). A frame
// is asked for as the answer comes, so a view can look each frame. Not on iOS, Windows or the web yet (`pick` is None
// there).

///|
/// What the system's pickers offer.
pub(all) enum PickKind {
  /// the photo picker: pictures, more than one
  Photos
  /// any files, more than one
  Files
  /// a photo taken with the camera now
  Camera
} derive(Eq)

///|
/// A file picked: its name and its bytes.
pub(all) struct Picked {
  name : String
  bytes : Bytes
}

///|
/// An ask of the system's under way.
pub struct Pick {
  priv id : Int
}

///|
/// Its id, as the host's event names it when the system has answered (set_outside: kind 3).
pub fn Pick::id(self : Pick) -> Int {
  self.id
}

///|
/// Asks the system for files of `kind`: None when this host cannot.
pub fn pick(kind : PickKind) -> Pick? {
  let id = pk_start(
    match kind {
      Photos => 1
      Files => 2
      Camera => 3
    },
  )
  if id == 0 {
    None
  } else {
    Some({ id, })
  }
}

///|
/// A photo of the gallery (gallery.mbt's `src`) read whole, as a pick of it: None where the host has no gallery.
pub fn pick_photo(src : String) -> Pick? {
  match pk_photo(src) {
    0 => None
    id => Some({ id, })
  }
}

///|
/// What was picked, once the system has answered (empty: called off, or nothing could be read); None while it asks.
/// Taken once: the ask is forgotten as it is answered.
pub fn Pick::files(self : Pick) -> Array[Picked]? {
  match pk_state(self.id) {
    0 => None
    1 => {
      let out = []
      for i in 0..<pk_count(self.id) {
        out.push({ name: pk_name(self.id, i), bytes: pk_bytes(self.id, i) })
      }
      pk_end(self.id)
      Some(out)
    }
    _ => {
      pk_end(self.id)
      Some([])
    }
  }
}
