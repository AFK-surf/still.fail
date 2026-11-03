// still.fail's layout held against the web's, by numbers (not pictures): a web story as scripts/web-layout.mjs took it
// (its elements' boxes and looks, the made-up core's topics then, the steps that took it there) and mbui's app given the
// same, in a Tester of this Mac's text (mbui's film's live host: words measured as the Mac's), at the same size, taken
// by the same steps, each looked at a declared moment after it; then what each side has, matched item by item
// (compare.mbt), and what differs listed: missing, extra, off by N px, another corner, ground, words' size, opacity.
// For finding what is still to port, not a check: nothing runs it in CI.
//   LAYOUT_WEB=<story>.web.json LAYOUT_OUT=<report>.md [LAYOUT_BOXES=<mbui boxes>.json] [LAYOUT_ASKED=<topics>.json]
//   _build/native/release/build/stillfail/sflayout/sflayout.exe            (scripts/layout.sh builds and runs it)
// LAYOUT_ASKED: the topics mbui's app asked that the page's tape has not (a JSON array of their keys), for
// web-layout.mjs to take too.

///|
/// The moment each step is looked at, after it: past the sidebar's 380 ms (brand.tsx moveSidebar), as the web's page
/// is taken once its animations have ended.
let step_ms : Double = 1000.0

///|
fn main {
  let web_path = @film.arg("LAYOUT_WEB")
  let out = @film.arg("LAYOUT_OUT")
  if web_path == "" || out == "" {
    @film.say("sflayout: LAYOUT_WEB=<story>.web.json LAYOUT_OUT=<report>.md [LAYOUT_BOXES=…] [LAYOUT_ASKED=…]")
    @film.exit(2)
    return
  }
  let web = @json.parse(@film.read_text(web_path)) catch {
    _ => {
      @film.say("sflayout: \{web_path} does not parse")
      @film.exit(2)
      return
    }
  }
  let w = num(web, "width", 1280.0)
  let h = num(web, "height", 800.0)
  let tape = Tape::new(arr(web, "tape"))
  let src : Ref[@sfapp.Source?] = Ref::new(None)
  // (the app made at the Tester's first frame, as sffilm makes it: the faces it carries given to the Tester's text,
  // which is this Mac's)
  let source = fn() {
    match src.val {
      Some(s) => s
      None => {
        let s = app_over(tape)
        @sf.give_faces()
        src.val = Some(s)
        s
      }
    }
  }
  let view = fn(c : @ui.Ctx) { @sfapp.view(c, source()) }
  @sf.kept_call.val = Some(@sfkept.answer)
  // (a measure of where things are laid out: words over words while something moves are the tests' to hold, words_over.mbt)
  // (the window a tree made once, as src/stillfail's: its shell's nodes, the old views in them)
  let t = @ui.Tester::new(
    view,
    w~,
    h~,
    platform=0,
    live=@film.live(),
    words_over_held=false,
    tree=fn(root) { @sfapp.app_tree(source())(root) },
  )
  // what the story shares into the app as it opens (stories.tsx `share`: the page's offerShare), shared into mbui's as
  // another app's share comes
  match field(web, "share") {
    Some(Object(_) as s) => t.share_in(str(s, "source"), title=str(s, "title"))
    _ => ()
  }
  t.run_for(step_ms)
  let notes : Array[String] = []
  for step in arr(web, "steps") {
    match take(t, step) {
      Some(why) => notes.push(why)
      None => ()
    }
    t.run_for(step_ms)
  }
  let boxes = t.boxes()
  let mine = boxes.map(from_laid)
  let theirs = arr(web, "elements").map(from_web)
  let ground = match field(web, "ground") {
    Some(Array([Number(r, ..), Number(g, ..), Number(b, ..), Number(a, ..)])) =>
      (r.to_int(), g.to_int(), b.to_int(), a.to_int())
    _ => (255, 255, 255, 255)
  }
  let report = compare(theirs, mine, ground)
  let title = str(web, "story") + "（" + str(web, "title") + "）"
  let md = report.markdown(title, w, h, arr(web, "steps"), notes, tape.missing, tape.loose)
  if !@film.write_text(out, md) {
    @film.say("sflayout: \{out} not written")
    @film.exit(1)
    return
  }
  let boxes_path = @film.arg("LAYOUT_BOXES")
  if boxes_path != "" {
    ignore(@film.write_text(boxes_path, Json::array(mine.map(fn(e) { e.to_json() })).stringify()))
  }
  let asked_path = @film.arg("LAYOUT_ASKED")
  if asked_path != "" {
    ignore(@film.write_text(asked_path, Json::array(tape.missing.map(fn(k) { k.1 })).stringify()))
  }
  @film.say("sflayout: \{out}: \{report.summary()}")
  @film.exit(0)
}

///|
/// The topics as the page had them, by their keys; the keys asked that it had not, and those answered by a topic of
/// the same name with other params (the only one of that name).
struct Tape {
  exact : Map[String, Json]
  by_name : Map[String, Array[Json]]
  missing : Array[(String, Json)]
  loose : Array[(String, String)]
  said : Map[String, Bool]
}

///|
fn Tape::new(items : Array[Json]) -> Tape {
  let exact = {}
  let by_name : Map[String, Array[Json]] = {}
  for it in items {
    match (field(it, "topic"), field(it, "value")) {
      (Some(k), Some(v)) => {
        exact[canon(k)] = v
        let name = str(k, "topic")
        match by_name.get(name) {
          Some(a) => a.push(v)
          None => by_name[name] = [v]
        }
      }
      _ => ()
    }
  }
  { exact, by_name, missing: [], loose: [], said: {} }
}

///|
fn Tape::topic(self : Tape, name : String, params : Map[String, Json]) -> @sfapp.Topic {
  let key : Map[String, Json] = { "topic": Json::string(name) }
  for k, v in params {
    key[k] = v
  }
  let want = canon(Json::object(key))
  match self.exact.get(want) {
    Some(v) => { value: Some(v), error: None, version: 1 }
    None => {
      let first = !self.said.contains(want)
      self.said[want] = true
      match self.by_name.get(name) {
        Some([v]) => {
          if first {
            self.loose.push((want, name))
          }
          { value: Some(v), error: None, version: 1 }
        }
        _ => {
          if first {
            self.missing.push((want, Json::object(key)))
          }
          { value: None, error: None, version: 0 }
        }
      }
    }
  }
}

///|
/// mbui's app over the tape: the made-up source's other parts (pictures, files, the kept answers), the tape's topics,
/// and the chat the page has open (its `chat` topic) opened over Home.
fn app_over(tape : Tape) -> @sfapp.Source {
  let open : Array[Json] = []
  for k, _ in tape.exact {
    let key = @json.parse(k) catch { _ => continue }
    if str(key, "topic") == "chat" {
      open.push(
        Json::object({
          "page": Json::string("chat"),
          "station": Json::string(str(key, "station")),
          "session": Json::string(str(key, "session")),
        }),
      )
    }
  }
  let base = @sfapp.fixture_json_app(Json::object({ "open": Json::array(open) }).stringify())
  { ..base, topic: fn(name, params) { tape.topic(name, params) } }
}

///|
/// A step of the story's (stories.tsx Step) taken in mbui's app, as Playwright took it on the page: what it is done to
/// found by its aria-label (a box's `label`) or its words; None when taken, else why not.
fn take(t : @ui.Tester, step : Json) -> String? {
  // (where the page had it, for what mbui's app has no such label or words for)
  let there = match field(step, "at") {
    Some(Array([Number(x, ..), Number(y, ..)])) => Some((x, y))
    _ => None
  }
  let at = fn(sel : String) -> Result[(Double, Double), String] {
    let why = match target(sel) {
      Some(want) =>
        match find(t, want) {
          Some(p) => return Ok(p)
          None => "「\{want.1}」 is not on mbui's screen"
        }
      None =>
        // (a selector of the page's DOM, a link by its href: what the page called what it acted on)
        match field(step, "name") {
          Some(String(name)) if name != "" =>
            match find(t, ("=", name)) {
              Some(p) => return Ok(p)
              None => "「\{name}」 (\{sel}) is not on mbui's screen"
            }
          _ => "its selector is not one this tool reads ([aria-label=…], text=…)"
        }
    }
    match there {
      Some(_) => Err("~" + why + ": taken where the page had it")
      None => Err(why)
    }
  }
  let act = fn(sel : String, f : (Double, Double) -> Unit) -> String? {
    match at(sel) {
      Ok((x, y)) => {
        f(x, y)
        None
      }
      Err(why) if why.has_prefix("~") => {
        let (x, y) = there.unwrap()
        f(x, y)
        Some(sel + ": " + why.unsafe_substring(start=1, end=why.length()))
      }
      Err(why) => Some(sel + ": " + why + ", not taken")
    }
  }
  match step {
    Object(m) => {
      if m.get("click") is Some(String(sel)) {
        return act(sel, fn(x, y) { t.tap(x, y) })
      }
      if m.get("rightClick") is Some(String(sel)) {
        return act(sel, fn(x, y) { t.right_click(x, y) })
      }
      if m.get("hover") is Some(String(sel)) {
        return act(sel, fn(x, y) { t.move(x, y) })
      }
      if m.get("text") is Some(String(s)) {
        return act("text=" + s, fn(x, y) { t.tap(x, y) })
      }
      if m.get("key") is Some(String(k)) {
        return if t.key_named(k.to_lower()) { None } else { Some("\{step.stringify()}: no such key here") }
      }
      if m.get("move") is Some(Array([Number(x, ..), Number(y, ..)])) {
        t.move(x, y)
        return None
      }
      Some("\{step.stringify()}: a step this tool does not take")
    }
    _ => Some("\{step.stringify()}: not a step")
  }
}

///|
/// What a selector names: (how, words) with how "=" an aria-label or words exactly, "^" beginning so, "$" ending so.
fn target(sel : String) -> (String, String)? {
  if sel.has_prefix("text=") {
    return Some(("=", sel.unsafe_substring(start=5, end=sel.length())))
  }
  for how in ["", "^", "$"] {
    let head = "[aria-label" + how + "=\""
    if sel.has_prefix(head) && sel.has_suffix("\"]") {
      let words = sel.unsafe_substring(start=head.length(), end=sel.length() - 2)
      return Some((if how == "" { "=" } else { how }, words))
    }
  }
  None
}

///|
/// The middle of what shows of the last node (drawn over the others) whose label or words are as `want` says.
fn find(t : @ui.Tester, want : (String, String)) -> (Double, Double)? {
  let (how, words) = want
  let fits = fn(s : String) {
    s != "" &&
    (match how {
      "^" => s.has_prefix(words)
      "$" => s.has_suffix(words)
      _ => s == words
    })
  }
  let mut found = None
  for b in t.boxes() {
    let (x, y, w, h) = b.cut
    if w > 0.0 && h > 0.0 && b.opacity > 0.01 && (fits(b.label) || fits(b.text)) {
      found = Some((x + w / 2.0, y + h / 2.0))
    }
  }
  found
}

// ── JSON ────────────────────────────────────────────────────────────────

///|
fn field(v : Json, k : String) -> Json? {
  match v {
    Object(m) => m.get(k)
    _ => None
  }
}

///|
fn str(v : Json, k : String) -> String {
  match field(v, k) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
fn num(v : Json, k : String, none : Double) -> Double {
  match field(v, k) {
    Some(Number(n, ..)) => n
    _ => none
  }
}

///|
fn arr(v : Json, k : String) -> Array[Json] {
  match field(v, k) {
    Some(Array(a)) => a
    _ => []
  }
}

///|
/// A JSON value written with its objects' keys in order: one text for the same key however it was put together.
fn canon(v : Json) -> String {
  match v {
    Object(m) => {
      let keys = m.keys().collect()
      keys.sort()
      let parts = keys.map(fn(k) { Json::string(k).stringify() + ":" + canon(m.get(k).unwrap()) })
      "{" + parts.join(",") + "}"
    }
    Array(a) => "[" + a.map(canon).join(",") + "]"
    _ => v.stringify()
  }
}
