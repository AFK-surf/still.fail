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
  /// the topic `name` with its params (the core's `subscribe`): the same each frame. Read in a computed (mbui/signals:
  /// derived.mbt), followed: the computed is worked out again as the topic changes, a signal of its changes set as
  /// they come (the core client's Sub.changes; a made-up core's own as its state changes)
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
  /// a picture by its URL (a person's, a station's icon) as it is put up on its page's time on top `stint`
  /// (Ctx::page_stint): an image's src once it is here, "" until then (the core's `picture`: core_pictures.mbt)
  picture : (String, Int) -> String
  /// what the core said when it stopped, if it did
  fatal : () -> String?
  /// a file of a chat as its messages show it (`station.file`, an image's thumbnail): by its station, the session
  /// that keeps it and its name; an image's key once it is here, "" while it comes, "!" when it could not be had
  file : (String, String, String) -> String
  /// a video of a chat's still as the station makes it (`station.poster`: its first frame, a small JPEG), by the same
  /// three; an image's key once it is here, "" while it comes, "!" when the station has none
  poster : (String, String, String) -> String
  /// a picture of a draft's file the page holds no bytes of (a draft kept, read again as the app starts:
  /// `composer.picture`), by the draft's key and the file's id: an image's key once here, "" while it comes, "!" when
  /// the device keeps none
  draft_picture : (String, String) -> String
  /// what became of those pictures, each by its id (file_image_id, poster_image_id): which failed for want of their
  /// station, to be asked again (chat_images.mbt)
  images : ChatImages
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

///|
/// A core made up for a page's own test (sfpages' tests, a page drawn alone in a Tester): what each topic says
/// (`topic`, none by default) and how each call is answered (`call`, an error saying so by default); a stream answered
/// the same way, once. Nothing else: no pictures, no files, no sign-in, the clock at 0.
pub fn made_source(
  topic? : (String, Map[String, Json]) -> Json? = fn(_, _) { None },
  call? : (String, Json, (Result[Json, Json]) -> Unit) -> Unit = fn(name, _, done) {
    done(Err({ "code": "unknown_call", "message": Json::string("no " + name + " made up") }))
  },
) -> Source {
  {
    topic: fn(name, params) {
      match topic(name, params) {
        Some(v) => { value: Some(v), error: None, version: 1 }
        None => { value: None, error: None, version: 0 }
      }
    },
    call,
    call_bytes: fn(name, params, _, done) { call(name, params, done) },
    read_bytes: fn(name, _, done) { done(Err({ "code": "unknown_call", "message": Json::string("no " + name) })) },
    read_going: fn(name, _, _, done) { done(Err({ "code": "unknown_call", "message": Json::string("no " + name) })) },
    stream: fn(name, params, _, _, done) {
      call(name, params, done)
      0
    },
    cancel: fn(_) {  },
    sign_in: fn() {  },
    signing_in: fn() { false },
    picture: fn(_, _) { "" },
    fatal: fn() { None },
    file: fn(_, _, _) { "" },
    poster: fn(_, _, _) { "" },
    draft_picture: fn(_, _) { "!" },
    images: ChatImages::new(),
    now: fn() { 0.0 },
    leave: fn(_, _) {  },
    read_only: false,
  }
}

///|
/// The core a page's bones are drawn over (@sf.waiting's `sample`: what it will show, of made-up words): it says
/// nothing and answers nothing, so what is only shown asks the real core for nothing, reads nothing ahead and opens no
/// picture.
// kept across runs: a value (nothing in it is written: its topics none, its calls never answered)
pub let sample_source : Source = { ..made_source(call=fn(_, _, _) {  }), read_only: true }
