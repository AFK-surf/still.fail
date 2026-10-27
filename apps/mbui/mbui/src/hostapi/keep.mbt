// A file the app has read (a drive's file, a folder zipped, a chat's picture) kept on the device, where the person
// keeps files, as still.fail's Android app keeps a download (FileKinds.kt download: MediaStore's Downloads).
//
// Three ways: `Downloads`, nothing asked, where the system keeps downloads (Android: Downloads through MediaStore;
// macOS: ~/Downloads; Windows: the Downloads known folder); `Choose`, where the person says (Android: the documents
// UI's ACTION_CREATE_DOCUMENT; macOS: a save panel over the window; Windows: the Downloads folder still); `Photos`, a
// picture or a film into the phone's photo album (iOS: Photos, the system asking once whether the app may add to it;
// Android: Pictures/ or Movies/<the app's name> through MediaStore, nothing asked), as Downloads elsewhere. iOS has no downloads of its
// own: Downloads and Choose both have the Files sheet ask where (UIDocumentPickerViewController exporting a copy).
// MBUI_DOWNLOADS_DIR (macOS, iOS, Windows) is the downloads for scripted runs, nothing asked either way.
//
// The bytes come a part at a time as they are read (`append`: into a file of the host's temporary directory, never
// whole in memory), then `finish` hands the file to its place; the system may take a while (a panel, a sheet, a big
// file copied off the app's thread): `kept` is Keeping until it has answered, then where the file is (its name as the
// system has it: a name taken gets a number), or that the person called it off, or that it failed. A frame is asked
// for as the answer comes. `end` lets go of a keep (one not finished is called off, its part file removed). None
// where the host keeps nothing (the web page).

///|
/// How a file is kept.
pub(all) enum KeepWay {
  /// where the system keeps downloads, nothing asked (iOS: the Files sheet)
  Downloads
  /// where the person chooses (a save panel, the documents UI, the Files sheet)
  Choose
  /// a picture or a film into the phone's photo album (iOS Photos, Android's Pictures or Movies); where there is none, as
  /// Downloads
  Photos
} derive(Eq, Show)

///|
/// How a keep stands.
pub(all) enum Kept {
  /// its bytes still coming, or the system has not answered yet
  Keeping
  /// kept: where, as the system names it (a path, or Download/ and the file's name)
  KeptAt(String)
  /// the person called it off (a panel or a sheet cancelled)
  CalledOff
  /// it could not be written
  Failed
}

///|
/// A file being kept.
pub struct Keep {
  priv id : Int
}

///|
/// A file named `name` (`mime`, "" when unknown) to keep on the device, its bytes to come: None when this host keeps
/// none.
pub fn keep_begin(name : String, mime : String, way? : KeepWay = Downloads) -> Keep? {
  let id = kp_begin(name, mime, match way {
    Downloads => 1
    Choose => 2
    Photos => 3
  })
  if id == 0 {
    None
  } else {
    Some({ id, })
  }
}

///|
/// The next of its bytes; false when they could not be written (it has failed then).
pub fn Keep::append(self : Keep, data : Bytes) -> Bool {
  kp_append(self.id, data) != 0
}

///|
/// All of it is here: the host puts it in its place (or asks where first).
pub fn Keep::finish(self : Keep) -> Unit {
  kp_finish(self.id)
}

///|
/// How it stands.
pub fn Keep::kept(self : Keep) -> Kept {
  match kp_state(self.id) {
    0 => Keeping
    1 => KeptAt(kp_where(self.id))
    2 => CalledOff
    _ => Failed
  }
}

///|
/// Let go of: forgotten by the host; one not finished is called off and what came of it removed.
pub fn Keep::end(self : Keep) -> Unit {
  kp_end(self.id)
}

///|
/// `data`, all here, kept as a file named `name`: None when this host keeps none.
pub fn keep(name : String, mime : String, data : Bytes, way? : KeepWay = Downloads) -> Keep? {
  match keep_begin(name, mime, way~) {
    Some(k) => {
      if k.append(data) {
        k.finish()
      }
      Some(k)
    }
    None => None
  }
}
