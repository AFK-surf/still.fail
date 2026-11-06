// Where what the app shows and is told comes from (DataSource), said once by the app's main: a real account's (the
// core of a person, on a phone or a desktop) or made up (a fixture's chats, a Tester's). What writes down what a run
// shows, is typed and is told (the run's tape: MBUI_DRAW_LOG's INPUT, MSG, CLIPSAID, VIEWSAID… lines and a Tester's
// `start_tape`; MBUI_TEXT_RECORD's TEXTREC lines; the app's own dumps of its core, src/stillfail) writes only of a
// made-up one: a real account's run keeps none of it, on the log, its file or a tape, whatever its environment says.
// Real till the main says otherwise: what runs before it says (a package's start) keeps nothing either.
//
// Made up is said of what the app itself shows (a fixture's chats, a gallery's words): what a person gives a made-up
// app (what is typed or pasted into it, MBUI_FIXTURE_JSON's screen, a picture handed to it) is kept as it came, so
// only made-up words go into one that is kept. Kept by its host alone, not by this: where a host's native views are
// put (Android's VIEWAT, VIEWPIC lines with MBUI_DRAW_LOG: their numbers and device pixels, no words), and the host's
// own lines on its log.

///|
/// Where what the app shows and is told comes from.
pub(all) enum DataSource {
  /// A person's account, its core's own: nothing of it written down.
  RealAccount
  /// Made up (a fixture's chats, a Tester's, a test run's own account against its own cloud): a run's tape and text
  /// kept as the environment asks.
  MadeUp
} derive(Eq, Show)

///|
// kept across runs: a Tester sets it as it starts (reset_globals: a test's data is made up)
let data_source : Ref[DataSource] = Ref::new(RealAccount)

///|
/// The app's main says where its data comes from, before anything is drawn.
pub fn set_data_source(s : DataSource) -> Unit {
  data_source.val = s
}

///|
/// Whether what the run shows, is typed and is told may be written down (the tape, the text, the core's dumps): only
/// of made-up data.
pub fn content_kept() -> Bool {
  data_source.val == MadeUp
}

///|
/// Words a person gave or was shown (a file's or a track's name, a link, a page's path, an error's message) as the
/// general log may say them: themselves of made-up data, how many of a real account's (content_kept).
pub fn shown(s : String) -> String {
  if content_kept() {
    s
  } else {
    "(\{s.length()} characters)"
  }
}
