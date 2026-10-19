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
  /// 登录 pressed
  sign_in : () -> Unit
  /// whether a sign-in is under way
  signing_in : () -> Bool
  /// a person's picture by its URL: an image's src once it is here, "" until then (the core's `picture`)
  picture : (String) -> String
  /// what the core said when it stopped, if it did
  fatal : () -> String?
  /// a file of a chat as its messages show it (`station.file`, an image's thumbnail): by its station, the session
  /// that keeps it and its name; an image's key once it is here, "" while it comes, "!" when it could not be had
  file : (String, String, String) -> String
  /// the time of day, in milliseconds since 1970 (how long an agent's turn has run)
  now : () -> Double
  /// a topic no page shows any more (`unsubscribe`)
  leave : (String, Map[String, Json]) -> Unit
  /// nothing the reader does is told to the core (MBUI_READONLY=1): no read marks, no place kept, nothing sent, no
  /// draft kept, no file put up
  read_only : Bool
}
