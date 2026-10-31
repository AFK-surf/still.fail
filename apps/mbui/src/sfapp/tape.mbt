// Android's app recorded frame by frame (its motion tests: apps/android/app/src/androidTest/.../motion/Harness.kt,
// each recording's tape.json) and this app given the same: the core's values as they stood at each of the tape's
// moments, its calls answered as Android's were, the same taps at the same moments; each frame's words then compared
// with where Android drew them (tape_differences; the tapes kept as e2e/tapes/NAME.trace, replayed by src/sfreplay/flows/tapes_test.mbt). A tape's moments are the recording's ms, from 0 as it began, its
// pages settled first (Harness.kt settle: tape_settle_ms).
//   { "launched": ["Home", {"chat": station, "thread": N} | {"chat": station, "session": KEY}], "dark": false,
//     "window": {"w": dp, "h": dp}, "bars": {"top": dp, "bottom": dp}, "wall": ms,
//     "topics": [{"topic": {"topic": NAME, …params}, "value": …}],
//     "events": [{"t": ms, "set": {"topic": …}, "value": …} | {"t": ms, "answered": {"topic": …}}
//                | {"t": ms, "call": NAME, "params": …, "ok": … | "error": …}
//                | {"t": ms, "tap": WORDS} | {"t": ms, "tapDescribed": WORDS} | {"t": ms, "tapAt": {"x": dp, "y": dp}}
//                | {"t": ms, "finger": "down" | "move" | "up", "x": dp, "y": dp} | {"t": ms, "listTop": true}
//                | {"t": ms, "back": true}],
//     "frames": [{"t": ms, "words": [{"text": …, "x": dp, "y": dp, "w": dp, "h": dp, "shown": bool}]}] }

///|
/// Words Android drew in a frame: their node's words, its top left and size (dp).
priv struct TapeWord {
  text : String
  x : Double
  y : Double
  w : Double
  h : Double
}

///|
priv struct Tape {
  launched : Array[Json]
  w : Double
  h : Double
  /// the system bars over the window (edge to edge), and the wall clock as it began
  bars : (Double, Double)
  wall : Double
  /// the topics' values as it began, and what happened after, by its moments
  topics : Array[(Json, Json)]
  events : Array[Json]
  frames : Array[(Double, Array[TapeWord])]
}

///|
/// How long Android's harness let its pages settle before a recording began (Harness.kt launch: settle(1500)).
let tape_settle_ms : Double = 1500.0

///|
fn tape_read(json : String) -> Tape {
  let v = @json.parse(json) catch { _ => abort("the tape's JSON does not parse") }
  let topics : Array[(Json, Json)] = []
  for x in items(Some(v), "topics") {
    match (field(Some(x), "topic"), field(Some(x), "value")) {
      (Some(k), Some(val)) => topics.push((k, val))
      _ => ()
    }
  }
  let frames : Array[(Double, Array[TapeWord])] = []
  for f in items(Some(v), "frames") {
    let words : Array[TapeWord] = []
    for w in items(Some(f), "words") {
      let wv = Some(w)
      if flag(wv, "shown") {
        words.push({ text: text(wv, "text"), x: number(wv, "x"), y: number(wv, "y"), w: number(wv, "w"), h: number(wv, "h") })
      }
    }
    frames.push((number(Some(f), "t"), words))
  }
  let win = field(Some(v), "window")
  {
    launched: items(Some(v), "launched"),
    w: number(win, "w"),
    h: number(win, "h"),
    bars: (number(field(Some(v), "bars"), "top"), number(field(Some(v), "bars"), "bottom")),
    wall: number(Some(v), "wall"),
    topics,
    events: items(Some(v), "events"),
    frames,
  }
}

///|
/// A topic as this app asks it, as the tape names it: Android's chat by its thread asked by the session this app opened
/// it with ("thread:N", tape_open).
fn tape_topic_key(name : String, params : Map[String, Json]) -> Json {
  let key : Map[String, Json] = { "topic": Json::string(name) }
  for k, v in params {
    match (k, v) {
      ("session", String(s)) if s.has_prefix("thread:") => {
        let mut n = 0.0
        for ch in s.view(start_offset=7) {
          n = n * 10.0 + (ch.to_int() - 48).to_double()
        }
        key["thread"] = Json::number(n)
      }
      _ => key[k] = v
    }
  }
  Json::object(key)
}

///|
/// The tape's core at its moment `at()`: each topic's value as last set by then (its version how many times it was),
/// each call answered as Android's was (the one recorded with the same name and params, else the same name); over
/// `base` (a made-up core's, the caller's: the app's own code links none).
fn tape_source(tape : Tape, at : () -> Double, base : Source) -> Source {
  {
    ..base,
    // the wall clock as Android's had it: from the tape's start on, at its moments
    now: fn() { tape.wall + at() },
    topic: fn(name, params) {
      let want = tape_topic_key(name, params)
      let mut value : Json? = None
      let mut version = 0
      let now = at()
      // (a topic first answered while it recorded, as late as Android's app heard it: a chat opened from the list,
      // its value a moment after the tap)
      match tape.events.iter().find_first(fn(e) { field(Some(e), "answered") == Some(want) }) {
        Some(e) if number(Some(e), "t") > now =>
          return @sfbase.topic_as_read(name, params, { value: None, error: None, version: 0 })
        _ => ()
      }
      for t in tape.topics {
        if t.0 == want {
          value = Some(t.1)
          version = 1
        }
      }
      for e in tape.events {
        let ev = Some(e)
        if number(ev, "t") <= now && field(ev, "set") == Some(want) {
          value = field(ev, "value")
          version = version + 1
        }
      }
      // (the device's prefs, which Android's tapes kept none of: a new device's, as the core has them from the start)
      if name == "prefs" && value is None {
        return @sfbase.topic_as_read(name, params, { value: Some(Json::object(Map::new())), error: None, version: 1 })
      }
      // (its values as the tape set them by now, the clock going: followed as it is read)
      @sfbase.topic_as_read(name, params, { value, error: None, version })
    },
    call: fn(name, params, done) {
      // answered as the core's answer comes: an event from outside, here at once
      let rt = @ui.runtime()
      let ticket = rt.outside_start("core: " + name)
      defer rt.outside_end(ticket)
      let calls = tape.events.filter(fn(e) { text(Some(e), "call") == name })
      let said = match calls.iter().find_first(fn(c) { field(Some(c), "params") == Some(params) }) {
        Some(c) => Some(c)
        None => calls.get(0)
      }
      match said {
        Some(c) =>
          match field(Some(c), "error") {
            Some(err) => done(Err(err))
            None => done(Ok(field(Some(c), "ok").unwrap_or(Json::null())))
          }
        None => done(Ok(Json::null()))
      }
    },
  }
}

///|
/// The tape's pages opened over Home: a chat by its thread as "thread:N" (tape_topic_key), by its session as itself.
fn tape_open(tape : Tape) -> Unit {
  for p in tape.launched {
    tape_open_one(p)
  }
}

///|
/// A page of a tape opened over what shows (tape_open).
fn tape_open_one(p : Json) -> Unit {
  let pv = Some(p)
  let station = text(pv, "chat")
  if station != "" {
    let session = match field(pv, "thread") {
      Some(Number(n, ..)) => "thread:" + n.to_int64().to_string()
      _ => text(pv, "session")
    }
    open_chat({ station, session, title: "", station_name: "" })
  }
}

///|
/// How far this app's words may be from Android's (dp): rounding of whole pixels between the two.
let tape_slack : Double = 2.0

///|
/// The tape replayed here (`json`: its tape.json), frame by frame at its moments: each of Android's frames compared
/// with this app's at the same moment. What differs, in order: a frame's words not drawn here, or drawn more than
/// tape_slack away (each word once, at the first frame it differs, with where).
///
/// `trace`: words whose place in each frame, Android's and here, is said too (one line a frame: TRACE …). `base`: the
/// made-up core under the tape's answers (@sffixture.fixture("")).
pub fn tape_differences(json : String, base~ : Source, trace? : Array[String] = []) -> Array[String] {
  new_run()
  let tape = tape_read(json)
  let moment = Ref::new(-1.0)
  let src = tape_source(tape, fn() { moment.val }, base)
  tape_open(tape)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=tape.w, h=tape.h, platform=2)
  // the system bars as Android's window had them (the host says them: bars.mbt)
  let (top, bottom) = tape.bars
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":\{top},\"bottom\":\{bottom},\"left\":0,\"right\":0}}")
  t.run_for(tape_settle_ms)
  let t0 = t.time()
  let out : Array[String] = []
  // each word's frames that differ: from, to, how many, how many not drawn here, the worst offset (here less Android's)
  let runs : Map[String, TapeRun] = {}
  let order : Array[String] = []
  // what the person did: taps (by their words or where they were), a finger's down, moves and up, pages pushed, back
  let taps = tape.events.filter(fn(e) {
    ["tap", "tapAt", "finger", "listTop", "push", "back"].iter().any(fn(k) { field(Some(e), k) is Some(_) })
  })
  let mut next_tap = 0
  for f in tape.frames {
    let (ft, words) = f
    // what happened before this frame (stamped with the frame it was done at the start of): the core's values, taps
    while next_tap < taps.length() && number(Some(taps[next_tap]), "t") < ft {
      let e = taps[next_tap]
      next_tap = next_tap + 1
      let et = number(Some(e), "t")
      if t0 + et > t.time() {
        t.run_for(t0 + et - t.time())
      }
      moment.val = et
      match (field(Some(e), "push"), field(Some(e), "tapAt"), field(Some(e), "finger"), field(Some(e), "back")) {
        (Some(p), _, _, _) => tape_open_one(p)
        (_, Some(at), _, _) => t.tap(number(Some(at), "x"), number(Some(at), "y"))
        (_, _, Some(String(kind)), _) => {
          let (x, y) = (number(Some(e), "x"), number(Some(e), "y"))
          match kind {
            "down" => t.press_at(x, y)
            "move" => t.move(x, y)
            _ => t.release(x, y)
          }
        }
        (_, _, _, Some(_)) => t.back()
        // the list in view at its top
        _ if field(Some(e), "listTop") is Some(_) => {
          t.scroll_to(0)
          t.draw()
        }
        _ =>
          match tape_word_at(t, text(Some(e), "tap")) {
            Some((x, y)) => t.tap(x, y)
            None => out.push("\{et} ms: no \"\{text(Some(e), "tap")}\" to tap")
          }
      }
    }
    moment.val = ft - 0.5
    if t0 + ft > t.time() {
      t.run_for(t0 + ft - t.time())
    }
    let here = t.words()
    for want in trace {
      let a = words.filter(fn(w) { w.text == want }).map(fn(w) { "\{w.x.round()},\{w.y.round()}" })
      let h = here.filter(fn(h) { h.0 == want }).map(fn(h) { "\{h.1.round()},\{h.2.round()} a\{(h.5 * 100.0).round() / 100.0}" })
      out.push("TRACE \{ft} \{want}: android \{a} here \{h}")
    }
    for w in words {
      // (a time counted on the wall clock, which Android's test does not stop: 8s there is 1s here)
      if tape_counted(w.text) {
        continue
      }
      // (off the window: not seen there, nor compared; a list's panes side by side, a page slid away)
      if w.x + w.w <= 0.0 || w.x >= tape.w || w.y + w.h <= 0.0 || w.y >= tape.h {
        continue
      }
      let mut best : (Double, Double)? = None
      for h in here {
        if h.0 == w.text && h.5 > 0.0 {
          let d = (h.2 - w.y).abs()
          match best {
            Some((_, by)) if (by - w.y).abs() <= d => ()
            _ => best = Some((h.1, h.2))
          }
        }
      }
      let off = match best {
        None => Some(None)
        Some((x, y)) if (x - w.x).abs() > tape_slack || (y - w.y).abs() > tape_slack =>
          Some(Some((x - w.x, y - w.y)))
        _ => None
      }
      match off {
        None => ()
        Some(o) => {
          let r = match runs.get(w.text) {
            Some(r) => r
            None => {
              let r = { first: ft, last: ft, frames: 0, missing: 0, worst: (0.0, 0.0), android: (w.x, w.y) }
              runs[w.text] = r
              order.push(w.text)
              r
            }
          }
          r.last = ft
          r.frames = r.frames + 1
          match o {
            None => r.missing = r.missing + 1
            Some((dx, dy)) =>
              if dx.abs() + dy.abs() > r.worst.0.abs() + r.worst.1.abs() {
                r.worst = (dx, dy)
              }
          }
        }
      }
    }
  }
  for k in order {
    let r = runs[k]
    out.push(
      "\"\{k}\" \{r.first}–\{r.last} ms, \{r.frames} frames (\{r.missing} not drawn), worst off by \{r.worst.0.round()}, \{r.worst.1.round()} (Android first at \{r.android.0.round()}, \{r.android.1.round()})",
    )
  }
  out
}

///|
/// Whether `words` are a time counted (an agent's 8s, 1m 4s, 2h).
fn tape_counted(words : String) -> Bool {
  words != "" && words.iter().all(fn(ch) { (ch >= '0' && ch <= '9') || ch == 's' || ch == 'm' || ch == 'h' || ch == ' ' })
}

///|
priv struct TapeRun {
  first : Double
  mut last : Double
  mut frames : Int
  mut missing : Int
  mut worst : (Double, Double)
  android : (Double, Double)
}

///|
/// The centre of the words drawn here that are `words` exactly (as Android's hasText finds a node), shown.
fn tape_word_at(t : @ui.Tester, words : String) -> (Double, Double)? {
  for h in t.words() {
    if h.0 == words && h.5 > 0.0 {
      return Some((h.1 + h.3 / 2.0, h.2 + h.4 / 2.0))
    }
  }
  None
}

