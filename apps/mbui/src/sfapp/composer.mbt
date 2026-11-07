// Station-file metadata and the draft keys shared by app pages.

///|
/// A file on its way to the station: going up, up (`done`, the station's Attachment), or failed. `image`: its picture
/// here, its tile and its message drawn from it (an image's key from its bytes, or the host's picture of an image or a
/// video where it is: host_picture; "" for any other file); `pasted`: the words it was made of and what
/// the core says of them (`paste.info`: their first line, how many characters, the words while they can be put back).
priv struct Pending {
  id : Int
  name : String
  size : Int
  mut image : String
  width : Int
  height : Int
  pasted : (String, Json)?
  /// a picture's bytes as picked (Composer.kt Pending.local): what the viewer shows it from before it is sent; None
  /// for any other file, and for one of a kept draft (only the file it went up as is kept)
  local : Bytes?
  done : @signals.Signal[Json?]
  /// how much of it the station has
  sent : @signals.Signal[Int]
  error : @signals.Signal[String?]
  /// its id in the core, which sends it up (`composer.add`): a message sent before it is up names it (`uploads`); ""
  /// for one going up here (a station's file switched to one) and for any other
  mut core_id : String
  /// failed going up in the core: it can go again from what the core kept (`composer.retry`)
  retry : Bool
  /// a video's bytes, read whole, that the host has no picture of (no address for it: @hostapi.Picked.src): its
  /// `image` its first frame, made from them (draft_stills), None once it is
  mut unseen : Bytes?
  /// asked to go again: the core's failure said before it is not taken again, until it says otherwise
  retrying : @signals.Signal[Bool]
  /// what it is, picked or pasted as a file (file_seed, held_seed): the same added again while it is in the draft is
  /// not added twice; "" for any other
  seed : String
}

///|
fn draft_key(r : ChatRef) -> String {
  r.station + ":" + r.session
}

///|
/// The workspace a station (`<workspace>/<station>`) is in.
fn workspace_of(station : String) -> String {
  match station.find("/") {
    Some(i) => station.view(end_offset=i).to_owned()
    None => station
  }
}

///|
/// The draft interval used by existing recorded flows and regression steps.
pub let draft_keep_ms : Double = 400.0

///|
/// 32 hex digits as a UUID's 8-4-4-4-12.
fn uuid(h : String) -> String {
  h.view(end_offset=8).to_string() +
  "-" +
  h.view(start_offset=8, end_offset=12).to_string() +
  "-" +
  h.view(start_offset=12, end_offset=16).to_string() +
  "-" +
  h.view(start_offset=16, end_offset=20).to_string() +
  "-" +
  h.view(start_offset=20).to_string()
}
