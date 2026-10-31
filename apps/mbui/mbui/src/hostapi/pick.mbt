// Files picked by the person through the system's own pickers, as a composer's ＋ asks for them (still.fail's Android
// app, chat/screens/Attach.kt): the photo picker (Android's ACTION_PICK_IMAGES, macOS's open panel on images), the
// file picker (ACTION_OPEN_DOCUMENT; the open panel), a photo taken now (ACTION_IMAGE_CAPTURE's picture). The system
// asks on its own; `files` is None until it has answered, then what was picked (none when it was called off). A frame
// is asked for as the answer comes, so a view can look each frame. iOS: its photo picker (PHPickerViewController), its
// document picker, its camera (UIImagePickerController). Windows: its file dialog (IFileOpenDialog, the pictures' kinds
// for Photos; no camera: win_files.h). The web: the page's file input (web/host.js H.pickStart).

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
/// A file picked: its name and its bytes; or, one too big to be read whole (a video), held by the host: `held` its id
/// there (0: read whole, its bytes here), its `size`; and `src`, held or not, where it is where the host can say it (an
/// image source the host draws: its gallery's content:// address, a video's still; "" where it cannot). A file held goes up through the core a part at a time, read from
/// the host as it goes (the core's `composer.add` with `blob: {hostFile: held, size}`: the host answers `picked.read`,
/// `picked.hash`, `picked.release`; still.fail's Android app's PickedFiles.kt).
pub(all) struct Picked {
  name : String
  bytes : Bytes
  held : Int
  size : Double
  src : String
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
/// Asks the system for files of `kind`: None when this host cannot. `hold`: a file too big to be read whole may be held
/// by the host (Picked.held: for what sends it up through the core); else every one is read whole (16 added to the
/// kind the host is told).
pub fn pick(kind : PickKind, hold? : Bool = false) -> Pick? {
  let id = pk_start(
    (match kind {
      Photos => 1
      Files => 2
      Camera => 3
    }) +
    (if hold { 16 } else { 0 }),
  )
  if id == 0 {
    None
  } else {
    Some({ id, })
  }
}

///|
/// Files let go on the window from outside (the host's `mbui.drop` message names the pick their reading is: ui's
/// drop.mbt), as an ask of the system's: read whole, a folder's by their way down from where it was dropped
/// ("照片/2026/a.jpg"), each folder itself named with a "/" at its end and no bytes. Asked how it goes from now: a
/// host may read them only once asked (macOS's: mac_app.m drop_pick), so a drop taken otherwise reads nothing.
pub fn dropped_pick(id : Int) -> Pick {
  pk_state(id) |> ignore
  { id, }
}

///|
/// Files let go on the window that nothing took as files (taken as their paths, or by nothing): let go, unread where
/// the host has not read them yet.
pub fn forget_dropped(id : Int) -> Unit {
  pk_end(id)
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
        // (its id held by the host, 0 for one read whole, its size and address, a tab between; none from a host that says
        // none)
        let info = pk_info(self.id, i).split("\t").to_array()
        let bytes = pk_bytes(self.id, i)
        match info {
          [held, size, src] =>
            out.push({
              name: pk_name(self.id, i),
              bytes,
              held: ga_int(held).to_int(),
              size: ga_int(size).to_double(),
              src: src.to_string(),
            })
          _ =>
            out.push({ name: pk_name(self.id, i), bytes, held: 0, size: bytes.length().to_double(), src: "" })
        }
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
