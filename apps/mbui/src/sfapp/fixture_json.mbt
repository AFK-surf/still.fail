// A screen as the core's JSON gives it (client/fixtures/screens/NAME.json): what each topic says, the answers to the
// calls, and the pages it opens. The same file still.fail's Android app draws the screen from
// (apps/android ScreensRefTest), so the two are compared over one set of made-up data (scripts/android-ref.sh).
//   { "workspace": "ws1",
//     "open": [{"page": "chat", "station": …, "session": …} | {"page": "history", …, "key": …} | {"page": "settings"}],
//     "at": 3000, "shows": ["words on the screen then"],
//     "topics": [{"topic": {"topic": NAME, …params}, "value": …}],
//     "calls": [{"call": NAME, "params": {…}, "ok": …}] }

///|
/// The screen's file read (`json`, its text): its topics and calls as a source over the made-up one's other parts
/// (pictures, files), and its pages opened over Home.
pub fn fixture_json(json : String) -> Source {
  let screen = @json.parse(json) catch { _ => abort("the screen's JSON does not parse") }
  let topics : Array[(Json, Json)] = []
  for t in items(Some(screen), "topics") {
    match (field(Some(t), "topic"), field(Some(t), "value")) {
      (Some(k), Some(v)) => topics.push((k, v))
      _ => ()
    }
  }
  let calls = items(Some(screen), "calls")
  let base = fixture("")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      let key : Map[String, Json] = { "topic": Json::string(name) }
      for k, v in params {
        key[k] = v
      }
      let want = Json::object(key)
      match topics.iter().find_first(fn(t) { t.0 == want }) {
        Some((_, v)) => { value: Some(v), error: None, version: 1 }
        None => { value: None, error: None, version: 0 }
      }
    },
    call: fn(name, params, done) {
      // answered as the core's answer comes: an event from outside (its ticket ended: a frame for what it changed),
      // here at once
      let rt = @ui.runtime()
      let ticket = rt.outside_start("core: " + name)
      defer rt.outside_end(ticket)
      let said = match
        calls.iter().find_first(fn(c) { text(Some(c), "call") == name && field(Some(c), "params") == Some(params) }) {
        Some(c) => Some(c)
        None => calls.iter().find_first(fn(c) { text(Some(c), "call") == name })
      }
      match said {
        Some(c) => done(Ok(field(Some(c), "ok").unwrap_or(Json::null())))
        None =>
          done(Err({ "code": "unknown_call", "message": Json::string("the screen's JSON has no " + name) }))
      }
    },
  }
  for p in items(Some(screen), "open") {
    let station = text(Some(p), "station")
    let session = text(Some(p), "session")
    let r : ChatRef = { station, session, title: "", station_name: "" }
    match text(Some(p), "page") {
      "chat" => open_chat(r)
      "history" => app.nav.push(History(r, text(Some(p), "key"), None))
      "settings" => open_setting("home")
      _ => ()
    }
  }
  src
}

///|
/// The app as src/sffix starts it over a screen's JSON (MBUI_FIXTURE=json), for a Tester made next
/// (src/sfscreens/android_ref_wbtest.mbt): the app as at the start (whatever ran before in the process reset), then the
/// screen's source and its pages.
pub fn fixture_json_app(json : String) -> Source {
  reset()
  fixture_json(json)
}
