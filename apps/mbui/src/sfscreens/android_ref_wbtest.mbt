// still.fail's screens held to its Android app's, the original (client/fixtures/screens: the core's JSON both apps draw
// each from; Android's pictures of them the references, client/fixtures/screens/android): drawn here in a Tester over
// the Android host's text as it recorded it for each (screens/text-android.textrec: scripts/android-ref.sh text), in
// the window the emulator gave the app then (its size and scale, in its section's head) and on the frames it drew
// then, to the moment Android's test pictures (ScreensRefTest: the screen's `shows` words on it, then `at` on). Their
// draw lists printed when asked (MBUI_ANDROID_REF=1: scripts/android-ref.sh mbui), for mbui-render to draw offscreen
// on the emulator and compare with Android's pixel by pixel; and that moment, for the Android host's text to be
// recorded to (MBUI_ANDROID_REF=moments: scripts/android-ref.sh text). The app is not run on the emulator for its
// pictures.

///|
/// The screens (their names, as client/fixtures/screens has them, and their JSON).
fn android_screens() -> Array[(String, String)] {
  [("chat-cards", screen_chat_cards), ("history", screen_history), ("settings", screen_settings)]
}

///|
/// `name`'s section of the Android host's text: its head's parts (# NAME FRAME TIME WIDTH HEIGHT SCALE HASH STABLE)
/// and its lines.
fn text_android(name : String) -> (Array[String], String)? {
  let head = "# " + name + " "
  let lines = []
  let mut parts : Array[String] = []
  let mut inside = false
  for v in text_android_kept.split("\n") {
    if v.has_prefix("# ") {
      inside = v.has_prefix(head)
      if inside {
        parts = v.split(" ").map(fn(p) { p.to_owned() }).to_array()
      }
    } else if inside {
      lines.push(v.to_owned())
    }
  }
  if lines.length() == 0 {
    None
  } else {
    Some((parts, lines.join("\n")))
  }
}

///|
fn number_of(s : String) -> Double? {
  match (try Some(@json.parse(s)) catch { _ => None }) {
    Some(Number(d, ..)) => Some(d)
    _ => None
  }
}

///|
/// The screen's JSON's `shows` (the words on it at its moment) and `at` (the moment, from the first frame they are).
fn shows_at(name : String, json : String) -> (Array[String], Double) raise {
  let screen = @json.parse(json) catch { _ => fail("\{name}: its JSON does not parse") }
  match screen {
    Object(m) => {
      let shows = match m.get("shows") {
        Some(Array(a)) => a.filter_map(fn(w) { if w is String(s) { Some(s) } else { None } })
        _ => []
      }
      let at = match m.get("at") {
        Some(Number(d, ..)) => d
        _ => 3000.0
      }
      (shows, at)
    }
    _ => fail("\{name}: its JSON is not an object")
  }
}

///|
/// `json`'s screen in a Tester of the window `w` × `h` at `scale`, over `text` when given (the frames it drew too).
fn android_tester(json : String, w : Double, h : Double, scale : Double, text? : String) -> @ui.Tester {
  let src : Ref[@sfapp.Source?] = Ref::new(None)
  @ui.Tester::new(
    fn(c) {
      let s = match src.val {
        Some(s) => s
        None => {
          let s = @sfapp.fixture_json_app(json)
          src.val = Some(s)
          s
        }
      }
      @sfapp.view(c, s)
    },
    w~,
    h~,
    text?,
    run?=text,
    scale~,
    platform=2,
    time=host_start,
    stable=true,
  )
}

///|
/// The screen walked to the first frame its `shows` words are on it, as Android's test takes it (ScreensRefTest):
/// its pages pushed and their data drawn (the made-up core answers at once: a frame for what it said to be drawn), and
/// what it asked of the host (pictures) done. Fails where they are not then.
fn to_shows(t : @ui.Tester, name : String, shows : Array[String]) -> Unit raise {
  t.draw()
  t.finish_all()
  let lacking = shows.filter(fn(w) { t.find(w) is None })
  if lacking.length() > 0 {
    fail("\{name}: its words \{lacking} not on the screen once its data is drawn")
  }
}

///|
/// The moment on the run's clock Android's picture of `name` is of (its words on it, then `at`), in the window `w` ×
/// `h` at `scale`: what the Android host's text is recorded to (MBView's shot_at).
fn android_moment(name : String, json : String, w : Double, h : Double, scale : Double) -> Double raise {
  let (shows, at) = shows_at(name, json)
  let t = android_tester(json, w, h, scale)
  to_shows(t, name, shows)
  t.time() + at
}

///|
/// `name`'s screen drawn in a Tester of the window the emulator gave the app, over its text, to the moment Android's
/// picture is of (its `shows` on the screen, then `at`). Fails where the text lacks what it asks for.
fn android_screen(name : String, json : String) -> @ui.Tester raise {
  let (parts, text) = match text_android(name) {
    Some(s) => s
    None => fail("\{name}: no Android text recorded (scripts/android-ref.sh text \{name}, on an emulator)")
  }
  let (w, h, scale) = window_of(name, parts)
  let (shows, at) = shows_at(name, json)
  let t = android_tester(json, w, h, scale, text~)
  to_shows(t, name, shows)
  t.run_for(at)
  let missing = t.text_missing()
  if missing.length() > 0 {
    fail(
      "\{name}: the Android text lacks \{missing.length()} (scripts/android-ref.sh text \{name}, on an emulator): " +
      missing[:5].to_array().join(", "),
    )
  }
  t
}

///|
/// The words the Tester drew, a line at a time (Tester::text_runs: in points), with the window's scale: what
/// android_ref.py holds to Android's lines by where they stand (MBUI/NAME.texts.json).
fn text_runs_json(t : @ui.Tester, scale : Double) -> Json {
  let lines : Array[Json] = t
    .text_runs()
    .map(fn(r) {
      {
        "t": Json::string(r.text),
        "x0": Json::number(r.x0),
        "x1": Json::number(r.x1),
        "b": Json::number(r.base),
        "top": Json::number(r.top),
        "bot": Json::number(r.bottom),
      }
    })
  { "scale": Json::number(scale), "lines": Json::array(lines) }
}

///|
/// The scale of `name`'s window as its section's head says (1 where it says none).
fn scale_of(name : String) -> Double {
  match text_android(name) {
    Some((parts, _)) =>
      match parts.get(6) {
        Some(p) => number_of(p).unwrap_or(1.0)
        None => 1.0
      }
    None => 1.0
  }
}

///|
/// The window in a section's head (# NAME FRAME TIME WIDTH HEIGHT SCALE …).
fn window_of(name : String, parts : Array[String]) -> (Double, Double, Double) raise {
  let num = fn(i : Int) {
    match parts.get(i) {
      Some(p) => number_of(p)
      None => None
    }
  }
  match (num(4), num(5), num(6)) {
    (Some(w), Some(h), Some(s)) => (w, h, s)
    _ => fail("\{name}: its section's head is not # NAME FRAME TIME WIDTH HEIGHT SCALE …: \{parts}")
  }
}

///|
test "still.fail's screens as Android's emulator gave the app its window and text: drawn, nothing of its text missing" {
  let print = android_ref_env("MBUI_ANDROID_REF")
  if print == "moments" {
    // the window the emulator gives the app (MBUI_ANDROID_WINDOW: W H SCALE, scripts/android-ref.sh text)
    let win = android_ref_env("MBUI_ANDROID_WINDOW").split(" ").map(fn(p) { p.to_owned() }).to_array()
    let (w, h, scale) = window_of("MBUI_ANDROID_WINDOW", ["#", "", "", ""] + win)
    for s in android_screens() {
      let (name, json) = s
      println("MOMENT " + name + " " + android_moment(name, json, w, h, scale).to_string())
    }
    return
  }
  for s in android_screens() {
    let (name, json) = s
    let t = android_screen(name, json)
    if print == "1" {
      println("DLBEGIN " + name)
      println(t.drawlist(bytes=true))
      println("DLEND " + name)
      println("TEXTRUNS " + name + " " + text_runs_json(t, scale_of(name)).stringify())
    }
  }
}
