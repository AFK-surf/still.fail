// A screen as the core's JSON gives it (client/fixtures/screens/NAME.json): what each topic says, the answers to the
// calls, and the pages it opens. The same file still.fail's Android app draws the screen from
// (apps/android ScreensRefTest), so the two are compared over one set of made-up data (scripts/android-ref.sh).
//   { "workspace": "ws1",
//     "open": [{"page": "chat", "station": …, "session": …} | {"page": "history", …, "key": …} | {"page": "settings"}],
//     "ui": "chat-info" (what is open over the pages: the fixture mode's, ScreensRefTest's `opens`; none: the pages alone),
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
  // what it has open over its pages or in them (`ui`: the fixture mode it was made from, opened as sffix opens it:
  // its pages and the sheet, the menu, the word picked, as Android's test opens them), else its pages
  match text(Some(screen), "ui") {
    "" =>
      for p in items(Some(screen), "open") {
        match json_page(p) {
          Some(page) => app.nav.push(page)
          None => ()
        }
      }
    mode => open_fixture_mode(mode)
  }
  src
}

///|
/// The page a screen's JSON opens (`open`'s each, as screen_dump_wbtest page_json writes them and Android's
/// ScreensRefTest page reads them), over Home: None for one it does not know.
fn json_page(p : Json) -> Page? {
  let j = Some(p)
  let station = text(j, "station")
  let r : ChatRef = { station, session: text(j, "session"), title: "", station_name: "" }
  let route : @settings.Route? = match text(j, "page") {
    "chat" => return Some(Chat(r))
    "history" => return Some(History(r, text(j, "key"), None))
    "new" => return Some(NewChat)
    "decisions" => return Some(Decisions)
    "settings" => return Some(Settings)
    "files" => return Some(Files)
    "drive" =>
      return Some(
        Drive({
          station,
          root: match field(j, "root") {
            Some(String(s)) => Some(s)
            _ => None
          },
          path: text(j, "path"),
        }),
      )
    "drive-read" => return Some(DriveRead({ station, root: Some(text(j, "root")), path: text(j, "path") }))
    "me" => Some(Me)
    "appearance" => Some(Appearance)
    "fonts" => Some(Fonts)
    "workspace" => Some(Workspace)
    "security" => Some(Security)
    "vault" => Some(Vault)
    "stations" => Some(Stations)
    "station" => Some(Station(station))
    "profiles" => Some(Profiles(station))
    "profile" => Some(Profile(station, text(j, "profile")))
    "pick-models" => Some(PickModels(station, text(j, "profile")))
    "connects" => Some(Connects(station))
    "connect" => Some(Connect(station, text(j, "connect")))
    "new-profile" => Some(NewProfile(station))
    "new-connect" => Some(NewConnect(station))
    "memories" => Some(Memories)
    "memory" => Some(Memory(station))
    "memory-doc" => Some(MemoryDoc(station, text(j, "skill"), number(j, "at").to_int()))
    "usage" => Some(Usage)
    "archive" => Some(Archive)
    "auto-decisions" => Some(AutoDecisions)
    "bar-settings" => Some(BarSettings)
    "kept-files" => Some(KeptFiles)
    "changelog" => Some(Changelog)
    _ => None
  }
  route.map(fn(r) { Setting(r) })
}

///|
/// The app as src/sffix starts it over a screen's JSON (MBUI_FIXTURE=json), for a Tester made next
/// (src/sfscreens/android_ref_wbtest.mbt): the app as at the start (whatever ran before in the process reset), then the
/// screen's source and its pages.
pub fn fixture_json_app(json : String) -> Source {
  reset()
  fixture_json(json)
}
