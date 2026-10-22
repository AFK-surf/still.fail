// The made-up screens as the core's JSON both apps draw a screen from (client/fixtures/screens/NAME.json, read here by
// fixture_json, by Android's ScreensRefTest there): each fixture mode opened as sffix opens it, drawn to its moment,
// what it asked of the core kept as it was told (each topic's value, each call's answer) with the pages it stands on.
// Written out only when asked (MBUI_SCREEN_DUMP=MODE[,MODE…]: scripts/screens-dump.sh), a line each:
// `SCREENDUMP NAME JSON`; core-ts's scripts/screens-fill.ts then holds each to the core's shapes.

///|
/// A page as a screen's JSON opens it (fixture_json, ScreensRefTest page), None for one Android's test does not open.
fn page_json(p : Page) -> Json? {
  let st = fn(s : String) { Json::string(s) }
  match p {
    Home => None
    Chat(r) => Some({ "page": "chat", "station": st(r.station), "session": st(r.session) })
    History(r, key, _) => Some({ "page": "history", "station": st(r.station), "session": st(r.session), "key": st(key) })
    NewChat => Some({ "page": "new" })
    Decisions => Some({ "page": "decisions" })
    Settings => Some({ "page": "settings" })
    Archived => Some({ "page": "archive" })
    Files => Some({ "page": "files" })
    Drive(d) =>
      Some({ "page": "drive", "station": st(d.station), "root": match d.root { Some(r) => st(r); None => Json::null() }, "path": st(d.path) })
    DriveRead(d) => Some({ "page": "drive-read", "station": st(d.station), "root": st(d.root.unwrap_or("")), "path": st(d.path) })
    Place(name) =>
      match name {
        "stations" | "profiles" | "connects" | "usage" | "archive" | "memories" => Some({ "page": st(name) })
        _ => None
      }
    Setting(route) =>
      match route {
        Home => Some({ "page": "settings" })
        Me => Some({ "page": "me" })
        Appearance => Some({ "page": "appearance" })
        Fonts => Some({ "page": "fonts" })
        Workspace => Some({ "page": "workspace" })
        Security => Some({ "page": "security" })
        Vault => Some({ "page": "vault" })
        Stations => Some({ "page": "stations" })
        Station(a) => Some({ "page": "station", "station": st(a) })
        Profiles(a) => Some({ "page": "profiles", "station": st(a) })
        Profile(a, id) => Some({ "page": "profile", "station": st(a), "profile": st(id) })
        PickModels(a, id) => Some({ "page": "pick-models", "station": st(a), "profile": st(id) })
        Connects(a) => Some({ "page": "connects", "station": st(a) })
        Connect(a, id) => Some({ "page": "connect", "station": st(a), "connect": st(id) })
        NewProfile(a) => Some({ "page": "new-profile", "station": st(a) })
        NewConnect(a) => Some({ "page": "new-connect", "station": st(a) })
        Memories => Some({ "page": "memories" })
        Memory(a) => Some({ "page": "memory", "station": st(a) })
        MemoryDoc(a, skill, at) =>
          Some({ "page": "memory-doc", "station": st(a), "skill": st(skill), "at": Json::number(at.to_double()) })
        Usage => Some({ "page": "usage" })
        Archive => Some({ "page": "archive" })
        AutoDecisions => Some({ "page": "auto-decisions" })
        BarSettings => Some({ "page": "bar-settings" })
        KeptFiles => Some({ "page": "kept-files" })
        Changelog => Some({ "page": "changelog" })
        _ => None
      }
    _ => None
  }
}

///|
/// `mode` opened, drawn to `at` ms, and what it asked of the core: its screen's JSON (None when a page it stands on is
/// not one a screen's JSON opens).
fn screen_dump(mode : String, at : Double) -> Json? {
  let topics : Array[(Json, Json)] = []
  let calls : Array[Json] = []
  let made : Ref[Source?] = Ref::new(None)
  let t = @ui.Tester::new(
    fn(c) {
      let s = match made.val {
        Some(s) => s
        None => {
          let base = fixture_app(mode)
          let s : Source = {
            ..base,
            topic: fn(name, params) {
              let got = (base.topic)(name, params)
              match got.value {
                Some(v) => {
                  let key : Map[String, Json] = { "topic": Json::string(name) }
                  for k, x in params {
                    key[k] = x
                  }
                  let k = Json::object(key)
                  match topics.search_by(fn(e) { e.0 == k }) {
                    Some(i) => topics[i] = (k, v)
                    None => topics.push((k, v))
                  }
                }
                None => ()
              }
              got
            },
            call: fn(name, params, done) {
              (base.call)(name, params, fn(res) {
                match res {
                  Ok(v) => calls.push({ "call": Json::string(name), "params": params, "ok": v })
                  Err(_) => ()
                }
                done(res)
              })
            },
          }
          made.val = Some(s)
          s
        }
      }
      view(c, s)
    },
    w=390.0,
    h=844.0,
    platform=2,
  )
  // the words on it as its data is first drawn (what Android's test, and the Tester taking its moment, wait for:
  // src/sfscreens/android_ref_wbtest.mbt to_shows)
  t.draw()
  t.finish_all()
  let first : Array[String] = []
  for w in t.words() {
    if w.5 > 0.0 {
      first.push(w.0.trim(chars=" \n").to_string())
    }
  }
  t.run_for(at)
  // (what lies over the pages, a file's viewer, a sheet: not opened by Android's test yet)
  if viewer.val is Some(_) || @settings.sheet_up() {
    return None
  }
  let open : Array[Json] = []
  for p in app.nav.pages() {
    match p {
      Home => ()
      _ =>
        match page_json(p) {
          Some(j) => open.push(j)
          None => return None
        }
    }
  }
  // what Android's test waits to see before its moment (ScreensRefTest `shows`): the two longest words drawn then and
  // as its data first is, their first six characters (a line cut short there all the same)
  let seen : Array[String] = []
  for w in t.words() {
    let s = w.0.trim(chars=" \n").to_string()
    if w.5 > 0.0 && s.length() >= 4 && !seen.contains(s) && first.contains(s) {
      seen.push(s)
    }
  }
  seen.sort_by(fn(a, b) { b.length().compare(a.length()) })
  let shows = seen[:@cmp.minimum(2, seen.length())].to_array().map(fn(s) { Json::string(s.view(end_offset=@cmp.minimum(6, s.length())).to_owned()) })
  Some({
    "workspace": "ws1",
    "open": Json::array(open),
    "at": Json::number(at),
    "shows": Json::array(shows),
    "topics": Json::array(topics.map(fn(e) { { "topic": e.0, "value": e.1 } })),
    "calls": Json::array(calls),
  })
}

///|
/// The moment a dumped screen is pictured at (ScreensRefTest's `at`: past what any screen opens with).
let dump_at : Double = 3000.0

///|
test "the screens' JSON, when asked (MBUI_SCREEN_DUMP)" {
  let asked = dump_env("MBUI_SCREEN_DUMP")
  if asked == "" {
    return
  }
  for m in asked.split(",") {
    let mode = m.to_owned()
    match screen_dump(mode, dump_at) {
      Some(j) => println("SCREENDUMP \{mode} \{j.stringify()}")
      None => println("SCREENDUMP \{mode} -")
    }
  }
}
