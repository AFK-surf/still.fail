// Station-file metadata and the draft keys shared by app pages.

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
