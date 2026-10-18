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
  /// 登录 pressed
  sign_in : () -> Unit
  /// whether a sign-in is under way
  signing_in : () -> Bool
  /// a person's picture by its URL: an image's src once it is here, "" until then (the core's `picture`)
  picture : (String) -> String
  /// what the core said when it stopped, if it did
  fatal : () -> String?
}
