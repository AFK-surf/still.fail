// The device's gallery, for a picker's recent photos (still.fail's Android app, chat/screens/Attach.kt RecentPhotos):
// how much of it the app may read (Android: READ_MEDIA_IMAGES, or on Android 14 and later the photos the person chose
// for it, READ_MEDIA_VISUAL_USER_SELECTED; below 13 READ_EXTERNAL_STORAGE), asking for it (the system's dialog; asked
// and turned down for good, the app's page of the system's settings, where it is allowed), and its photos with what
// the gallery says of when each came (read off the app's thread; the view ranks them). A photo's `src` is an image
// source of its own (Android: its content:// address, drawn by `Ctx::image` as the gallery's thumbnail at the size
// it is shown), and @host.pick_photo reads it whole for a message. Android only: the others say NoGallery.

///|
/// How much of the gallery the app may read.
pub(all) enum GalleryAccess {
  /// all of it
  Whole
  /// the photos the person chose for it (Android 14 on)
  Chosen
  /// none: not allowed (yet)
  Refused
  /// this host has no gallery to read
  NoGallery
}

///|
pub fn gallery_access() -> GalleryAccess {
  match ga_access() {
    1 => Whole
    2 => Chosen
    0 => Refused
    _ => NoGallery
  }
}

///|
/// The system asked to let the app read the gallery (asked and turned down for good: the app's settings opened).
pub fn gallery_ask() -> Unit {
  ga_ask()
}

///|
/// How many times the system has answered an ask (a view reads the gallery again when it changes).
pub fn gallery_answers() -> Int {
  ga_answers()
}

///|
/// A photo of the gallery: its own id, its image source, and when it came as the gallery says it, in seconds (-1
/// where it says nothing; possibly wrong: written in milliseconds, or ahead of now).
pub(all) struct GalleryPhoto {
  id : Int64
  src : String
  added : Int64
  modified : Int64
  taken : Int64
}

///|
/// The gallery being read.
pub struct GalleryRead {
  priv id : Int
}

///|
/// Its id, as the host's event names it once read (set_outside: kind 4).
pub fn GalleryRead::id(self : GalleryRead) -> Int {
  self.id
}

///|
/// The gallery's photos read (as many as the app may read): None where there is no gallery.
pub fn gallery_read() -> GalleryRead? {
  match ga_read() {
    0 => None
    id => Some({ id, })
  }
}

///|
/// Its photos once read (empty: none, or not allowed), None while it reads; taken once.
pub fn GalleryRead::photos(self : GalleryRead) -> Array[GalleryPhoto]? {
  match ga_read_state(self.id) {
    0 => None
    1 => {
      let rows = ga_read_rows(self.id)
      ga_read_end(self.id)
      let out = []
      for line in rows.split("\n") {
        let f = line.split("\t").to_array()
        if f.length() < 5 {
          continue
        }
        out.push({ id: ga_int(f[0]), src: f[1].to_owned(), added: ga_int(f[2]), modified: ga_int(f[3]), taken: ga_int(f[4]) })
      }
      Some(out)
    }
    _ => {
      ga_read_end(self.id)
      Some([])
    }
  }
}

///|
/// A whole number as the host writes it (digits, a leading -); -1 for anything else.
fn ga_int(s : StringView) -> Int64 {
  let mut n = 0L
  let mut neg = false
  let mut any = false
  let mut first = true
  for ch in s {
    if first && ch == '-' {
      neg = true
    } else if ch >= '0' && ch <= '9' {
      n = n * 10L + (ch.to_int() - '0'.to_int()).to_int64()
      any = true
    } else {
      return -1L
    }
    first = false
  }
  if !any {
    -1L
  } else if neg {
    -n
  } else {
    n
  }
}
