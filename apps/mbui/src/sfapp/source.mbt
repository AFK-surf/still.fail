// Where the app's pages read and write: the still.fail core (src/stillfail, over mbui/core) or a fixture of made-up
// chats (fixture.mbt: no core, the same views' shapes), for screenshots that are the same on every run.

///|
/// A topic as it stands: its value, or why it could not be read; `version` counts its changes.
pub(all) struct Topic {
  value : Json?
  error : Json?
  version : Int
}

///|
pub(all) struct Source {
  /// the topic `name` with its params (the core's `subscribe`): the same each frame
  topic : (String, Map[String, Json]) -> Topic
  /// a call to the core; `done` gets its answer or its error
  call : (String, Json, (Result[Json, Json]) -> Unit) -> Unit
  /// a call with bytes beside it (a file's part going up: `station.upload.part`)
  call_bytes : (String, Json, Bytes, (Result[Json, Json]) -> Unit) -> Unit
  /// a call whose answer has bytes beside it (a part of a drive's file: `drive.read`)
  read_bytes : (String, Json, (Result[(Json, Bytes), Json]) -> Unit) -> Unit
  /// a call whose answer has bytes beside it and that says how far it has got before it (`station.file` with
  /// `progress`: `{loaded, total}` each time, then the file): `on_value` each time, then `done`
  read_going : (String, Json, (Json) -> Unit, (Result[(Json, Bytes), Json]) -> Unit) -> Unit
  /// a call that says how it goes before its answer (`station.preview` with `stream`: the answer's head, then each
  /// piece of its body with its bytes): `on_value(value, bytes)` each time, then `done`; the call's id, for `cancel`
  stream : (String, Json, Bytes?, (Json, Bytes?) -> Unit, (Result[Json, Json]) -> Unit) -> Int
  /// a streamed call stopped (nothing more of it comes)
  cancel : (Int) -> Unit
  /// 登录 pressed
  sign_in : () -> Unit
  /// whether a sign-in is under way
  signing_in : () -> Bool
  /// a picture by its URL (a person's, a station's icon) as it is put up in frame `frame` (Ctx::frame_no): an
  /// image's src once it is here, "" until then (the core's `picture`: core_pictures.mbt)
  picture : (String, Int) -> String
  /// what the core said when it stopped, if it did
  fatal : () -> String?
  /// a file of a chat as its messages show it (`station.file`, an image's thumbnail): by its station, the session
  /// that keeps it and its name; an image's key once it is here, "" while it comes, "!" when it could not be had
  file : (String, String, String) -> String
  /// a video of a chat's still as the station makes it (`station.poster`: its first frame, a small JPEG), by the same
  /// three; an image's key once it is here, "" while it comes, "!" when the station has none
  poster : (String, String, String) -> String
  /// the time of day, in milliseconds since 1970 (how long an agent's turn has run)
  now : () -> Double
  /// a topic no page shows any more (`unsubscribe`)
  leave : (String, Map[String, Json]) -> Unit
  /// nothing the reader does is told to the core (MBUI_READONLY=1): no read marks, no place kept, nothing sent, no
  /// draft kept, no file put up
  read_only : Bool
}

///|
/// Bind the client's core once when it starts: Markdown read and code coloured by it (`markdown`, `code.ink`). Static
/// fixtures have no core (the real core's answers kept instead: src/sfkept); a recorded client binds its replay of the
/// same operations. The live renderer never interprets Markdown, TeX or code while an answer is coming.
pub fn use_core_markdown(src : Source) -> Unit {
  @sf.markdown_read.val = Some(fn(words, done) {
    (src.call)("markdown", { "text": Json::string(words) }, fn(answer) {
      match answer {
        Ok(v) => done(field(Some(v), "md"))
        Err(_) => done(None)
      }
    })
  })
  @sf.ink_read.val = Some(fn(code, lang, done) {
    (src.call)("code.ink", { "code": Json::string(code), "lang": Json::string(lang) }, fn(answer) {
      match answer {
        Ok(v) =>
          done(
            match field(Some(v), "ink") {
              Some(String(s)) => Some(s)
              _ => None
            },
          )
        Err(_) => done(None)
      }
    })
  })
}
