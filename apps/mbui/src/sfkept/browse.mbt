// A step of a device's browsing (the core's drive-browse.ts `Browsing`: the `driveBrowse` and `filesTabs` topics, the
// calls drive.browse, drive.arrange, drive.name, drive.moves, files.tabs, files.go) as the real core answered it, kept:
// the made-up core asks each step whole (what the browsing held before it, what it reads, what is done) and is answered
// with what the core gave and held after it (client/core-ts/scripts/kept-answers.ts browseStep). A step is kept by a
// hash of the ask as it is written out; the asks themselves are kept beside (browse_asks.json) to be worked out again.

///|
/// FNV-1a over the ask's UTF-16 code units, 64 bits, as 16 hex digits.
fn ask_key(ask : String) -> String {
  let mut h : UInt64 = 0xcbf29ce484222325UL
  for i in 0..<ask.length() {
    h = h ^ ask.code_unit_at(i).to_int().to_uint64()
    h = h * 0x100000001b3UL
  }
  let out = StringBuilder()
  for k in 0..<16 {
    let d = ((h >> ((15 - k) * 4)) & 0xfUL).to_int()
    out.write_char((if d < 10 { 48 + d } else { 87 + d }).unsafe_to_char())
  }
  out.to_string()
}

///|
/// The core's answer to a step of browsing (`ask`: its state, prefs, folders, stations, now, id and op, as
/// browseStep takes it): {value | error, state, prefs, id}, or {need: the folders it read that were not given}; an
/// error where it is not kept (said on the output).
fn browse_answer(ask : Json) -> Result[(Json, Bytes?), Json]? {
  let key = ask_key(ask.stringify())
  match kept("browse").get(key) {
    Some(a) => Some(Ok((a, None)))
    None => {
      let o : Map[String, Json] = { "call": "browse", "key": Json::string(key) }
      match ask {
        Object(m) =>
          for k, v in m {
            o[k] = v
          }
        _ => ()
      }
      not_kept(o)
    }
  }
}
