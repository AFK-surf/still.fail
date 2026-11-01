// What a viewer (reader.mbt, player.mbt) opens: a file as the page has it (web/ui viewer/file.ts). One of a station's
// drive (the app's: read a part at a time, played as it comes, where it was left kept), or one here already (`bytes`:
// a chat's file its preview has read, blob_file).

///|
/// How much of it has come.
pub(all) struct Got {
  loaded : Double
  total : Double
}

///|
/// Where it was left on this device (file.ts usePlace): not known yet, never opened, or at `at` (a text's offset, a
/// film's time in ms) of `of` (0: not said).
pub(all) enum PlaceNow {
  NotKnown
  NeverLeft
  LeftAt(Double, Double)
}

///|
/// A file beside it in its folder, as the folder lists it (a playlist's others, a film's subtitle).
pub(all) struct ViewerEntry {
  name : String
  size : Double
  mtime : Double
  /// its media type ("": not known)
  mime : String
  /// what it is, as the station says: "video", "audio", "text", "markdown"…
  kind : String
  dir : Bool
}

///|
/// A file opened. `read` reads it whole (at most `max` bytes, its progress told); `stream` reads a part of it to play
/// it as it comes (offset, length, then its bytes as they come, the whole's size and whether more comes, stopped by
/// what it gives back: @kit.MediaTrack's read; none: played from what `read` reads); `beside` reads a file beside it (a subtitle); `place` says where it was left on this device, as it is
/// asked each frame; `keep_place` keeps where it is now (at, of); `save` saves it to the device; `facts`, what its
/// message says of a film before it is read.
pub(all) struct ViewerFile {
  name : String
  size : Double
  mtime : Double
  mime : String
  kind : String
  /// where it is, said over its name (its path; "": none)
  title : String
  /// who it is while unchanged, to keep what was read of it ("": not kept)
  key : String
  /// the bytes, here already: shown from them, not read
  bytes : Bytes?
  read : (Int, (Got) -> Unit, (Result[Bytes, String]) -> Unit) -> Unit
  stream : ((Double, Int, (Bytes, Double, Bool) -> Unit) -> () -> Unit)?
  /// how a host reads its `stream`'s parts itself, past the app (@kit.MediaTrack's `direct`; "": none)
  direct : String
  beside : ((ViewerEntry, (Result[Bytes, String]) -> Unit) -> Unit)?
  place : () -> PlaceNow
  keep_place : (Double, Double) -> Unit
  save : () -> Unit
  facts : FileFacts
}

///|
/// What a film's message says of it, as the station read it from the film's header (Attachment): its size as shown,
/// its length in ms and how many frames its picture has; 0 where it says none (a drive's file, a message from before).
pub(all) struct FileFacts {
  width : Double
  height : Double
  duration : Double
  frames : Int
}

///|
/// Nothing said of it.
// kept across runs: a value (no field of it changes)
pub let no_facts : FileFacts = { width: 0.0, height: 0.0, duration: 0.0, frames: 0 }

///|
/// A file here already (a chat's, read by its preview): nothing kept of where it was left (file.ts blobFile).
pub fn blob_file(
  bytes : Bytes,
  name : String,
  size : Double,
  mime? : String = "",
  kind? : String = "",
  save~ : () -> Unit,
) -> ViewerFile {
  {
    name,
    size,
    mtime: 0.0,
    mime,
    kind,
    title: "",
    key: "",
    bytes: Some(bytes),
    read: fn(max, _, done) {
      done(Ok(if max >= 0 && max < bytes.length() { bytes[:max].to_bytes() } else { bytes }))
    },
    stream: None,
    direct: "",
    beside: None,
    place: fn() { NeverLeft },
    keep_place: fn(_, _) {  },
    save,
    facts: no_facts,
  }
}
