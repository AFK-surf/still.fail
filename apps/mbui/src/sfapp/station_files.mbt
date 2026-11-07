// A station's files put into a message (still.fail apps/android chat/screens/StationFiles.kt, as the phone's web does it:
// web/src/mobile/StationFiles.tsx), the draft's side: what ＋'s Station 文件 (sfdesk's station_pick.mbt, the one picker
// of every frame) put into it comes in by files_into. Each goes into the draft named by its path (which station has
// it, and where: the message says so in a line of its own, `common.pathOn`; nothing goes up), or as a file where the
// chat says so (此对话默认发送文件, the core's prefs `dropFiles` by the chat's key, else `dropAs`); its card, tapped,
// opens its sheet (发送方式: 路径 or 文件, a folder of the chat's own station as a zip; the chat's say). A file goes up
// as the station stages it (`drive.stage`) on the chat's own station, else read from the station that has it
// (`drive.read`) and put up to the chat's (`station.upload.part`, as ＋'s files go). Not here yet: keeping them with
// the draft on the device.
///|
/// A file or folder of a station's in a draft, named by its path.
priv struct DraftRef {
  station : String
  station_name : String
  /// where it is on the station (absolute)
  path : String
  name : String
  dir : Bool
  /// where it is in that station's drive (a root and the path under it), to send it as a file
  root : String
  at : String
  size : Double
  /// "path": named by its path; "file": sent (a folder as a zip)
  mut mode : String
  /// sent as a file: it going up, then up (its `done` the attachment)
  up : Pending?
  /// its place among what was put in the draft (next_pending's count, as the draft's files: one row in that order)
  order : Int
}

///|
/// The station files in each draft (by its key), while the app runs.
let draft_refs : @sf.LiveMap[String, Array[DraftRef]] = @sf.LiveMap::new()

///|
/// A station file's card tapped: its sheet (the draft's key, the file), closed (drawn sinking away until it has gone).
priv struct StationFilesUi {
  mut ref : (String, DraftRef)?
  mut ref_closing : Bool
}

///|
let sfs : StationFilesUi = { ref: None, ref_closing: false }
