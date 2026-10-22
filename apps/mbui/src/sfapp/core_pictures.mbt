// Pictures by their address as the core gives them (`picture`: a person's account's, a station's or a workspace's
// icon; Android's Parts.kt rememberPicture, rememberStationPicture), kept as images for the app's life. One that could
// not be had (the network down a moment) is asked for again as Android's is: when it is put up anew (Compose's
// produceState, run as its picture comes into the composition), not while it stays up; the core answers that it
// could not until its own while has passed (core-ts asks.ts PICTURE_RETRY_MS), then fetches it again.

///|
/// Pictures by their address, as Source.picture gives them: `(url, frame)`, asked in frame `frame` (Ctx::frame_no),
/// is an image's key once it is here, "" until then. `ask(url, done)` asks the core's `picture` (`done` gets its
/// bytes, or None when it could not be had).
pub fn core_pictures(ask : (String, (Bytes?) -> Unit) -> Unit) -> (String, Int) -> String {
  // an address's image key once here, "" while it is asked
  let keys : Map[String, String] = {}
  // those that could not be had
  let failed : Map[String, Bool] = {}
  // the frame each was last put up in
  let shown : Map[String, Int] = {}
  fn(url, frame) {
    let anew = match shown.get(url) {
      Some(f) => f < frame - 1
      None => true
    }
    shown[url] = frame
    match keys.get(url) {
      Some(key) => key
      None => {
        if failed.contains(url) && !anew {
          return ""
        }
        failed.remove(url)
        keys[url] = ""
        ask(url, fn(bytes) {
          match bytes {
            Some(b) if b.length() > 0 => {
              let key = "mem:picture/\{@ui.stable_hash(url)}/\{url.length()}"
              @ui.add_image(key, b)
              keys[url] = key
            }
            _ => {
              keys.remove(url)
              failed[url] = true
            }
          }
        })
        // (answered at once: its key already)
        keys.get(url).unwrap_or("")
      }
    }
  }
}
