// What chat_nodes_read_stays_wbtest and chat_nodes_read_stays_composer_wbtest share: the long chat's made-up core
// under a run (late, gated, told longer, carded), the page opened as nodes on a screen, what is read of it (the
// message read, the end, the composer's ground) and how a read is held over every frame of a cause (chat_nodes_read_stays_wbtest's
// head says the principle).

///|
/// Half a device pixel, in points (the Tester draws 2 pixels a point).
let rs_still : Double = 0.25

///|
/// How long after a cause the list is looked at, past how late the core is: what it sets off and the glide after.
let rs_watch_ms : Double = @ui.move_most_ms * 4.0

///|
/// The long chat's made-up core under a run, and what the run changes of what it says: its calls held as late as
/// `late` (all of them while `gate` is shut, set off `late` after it opens), answered between frames; its agent at
/// work; messages told longer (`grown`, their seqs) and given a card (`carded`, by seq: whether answered); `told` bumped
/// as any of them changes, the chat's version with it. What each frame looks at (`look`), and the test's clock as the
/// last frame drew (`now`).
priv struct RsCore {
  l : LongChat
  mut now : Double
  mut late : Double
  mut gate : Bool
  held : Array[(Double, () -> Unit)]
  told : @signals.Signal[Int]
  mut working : Bool
  grown : Array[Int]
  carded : Map[Int, Bool]
  mut look : (() -> Unit)?
}

///|
/// What is said further of message `n` once it is told longer.
let rs_more : String = "补充一下：签名那一步要先在钥匙串里解锁证书，上传前再核对一次版本号和构建号，两边对不上的话商店会拒收，这次就是卡在这里。"

///|
/// The long chat's value as `k` changes it.
fn rs_value(k : RsCore, v : Map[String, Json]) -> Map[String, Json] {
  let out = v.copy()
  if k.working {
    out["agents"] = Json::array(
      items(Some(Json::object(v)), "agents").map(fn(a) {
        guard a is Object(m) else { return a }
        let m = m.copy()
        m["status"] = Json::string("running")
        m["since"] = Json::number(1.0e9)
        Json::object(m)
      }),
    )
  }
  if k.grown.length() > 0 || k.carded.length() > 0 {
    out["messages"] = Json::array(
      items(Some(Json::object(v)), "messages").map(fn(j) {
        guard j is Object(was) else { return j }
        let seq = number(Some(j), "seq").to_int()
        let m = was.copy()
        if k.grown.contains(seq) {
          let words = long_words(seq) + rs_more
          m["text"] = Json::string(words)
          m["words"] = Json::array([{ "text": Json::string(words) }])
          m["md"] = [["p", [[0, Json::number(words.length().to_double())]]]]
        }
        match k.carded.get(seq) {
          Some(answered) => {
            m["ending"] = Json::string("need_decision")
            m["card"] = {
              "type": "options",
              "assigneeText": "等 林 决定",
              "options": [
                { "label": "先不换", "detail": "这次只改列表，截图下次再说" },
                { "label": "一起换", "detail": "把首页和聊天页的截图都更新", "recommended": true },
              ],
            }
            m["decision"] = { "resolved": Json::boolean(answered) }
            m["asked"] = Json::boolean(!answered)
          }
          None => ()
        }
        Json::object(m)
      }),
    )
  }
  out
}

///|
/// The long chat's source under `k`: its value as `k` says, every call held as `k` says.
fn rs_source(k : RsCore) -> Source {
  let base = long_source(k.l)
  {
    ..base,
    topic_read: fn(name, params) {
      let got = (base.topic_read)(name, params)
      guard name == "chat" && got.value is Some(Object(v)) else { return got }
      let n = k.told.get()
      { ..got, value: Some(Json::object(rs_value(k, v))), version: got.version + n * 1000000 }
    },
    call: fn(name, params, done) {
      let go = fn() { (base.call)(name, params, done) }
      if k.gate || k.late > 0.0 {
        k.held.push((k.now + k.late, go))
      } else {
        go()
      }
    },
  }
}

///|
/// What `k` holds that is due now, answered (between frames, as the core's come), and the long chat's own answers.
fn rs_answer(k : RsCore) -> Unit {
  if !k.gate {
    let due : Array[() -> Unit] = []
    let kept : Array[(Double, () -> Unit)] = []
    for h in k.held {
      if h.0 <= k.now + 1.0e-6 {
        due.push(h.1)
      } else {
        kept.push(h)
      }
    }
    k.held.clear()
    for h in kept {
      k.held.push(h)
    }
    if due.length() > 0 {
      @ui.came_from_outside()
      for f in due {
        f()
      }
    }
  }
  long_answered(k.l)
}

///|
/// The gate opened: what it held set off `k.late` from now.
fn rs_open_gate(k : RsCore) -> Unit {
  let was = k.held.copy()
  k.held.clear()
  for h in was {
    k.held.push((k.now + k.late, h.1))
  }
  k.gate = false
}

///|
/// The long chat opened on screen `s` with its page made as nodes, at its end and at rest, the core answering at once.
fn rs_open(s : (String, Double, Double, Int)) -> (@ui.Tester, Source, RsCore) {
  let (_, w, h, platform) = s
  new_run()
  @sf.presenters_reset()
  @sfbase.chat_page_nodes.set(true)
  let k : RsCore = {
    l: long_chat(),
    now: 0.0,
    late: 0.0,
    gate: false,
    held: [],
    told: @signals.signal(0),
    working: false,
    grown: [],
    carded: Map([]),
    look: None,
  }
  let src = rs_source(k)
  open_chat(long_ref)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~, begun=fn() {
    @sfbase.window_tall.val = h
  })
  // (a list's rows on the device's pixels, as every host lays them: what is held is where things are drawn, the scroll
  // moving by whole pixels; off them, as the Tester's own default, the list counts fractions that Scroll::drawn_by draws
  // put on the pixel, up to half a pixel apart and otherwise as the fraction changes, a mode no device runs)
  t.set_rows_on_pixels(true)
  // (each frame looked at as it was drawn, before what the core answers by then is told: told after the look, it is
  // laid out at once, and the tree read then is between that answer and the frame that draws it, a frame no device
  // draws)
  t.each_frame(
    Some(fn() {
      k.now = t.time()
      match k.look {
        Some(f) => f()
        None => ()
      }
      rs_answer(k)
    }),
  )
  rs_run(t, long_opened_ms)
  (t, src, k)
}

///|
/// `ms` of the display's frames (and at a rate those between).
fn rs_run(t : @ui.Tester, ms : Double) -> Unit {
  let from = t.time()
  while t.time() - from < ms - 1.0e-6 {
    t.run_for(@ui.frame_period_default)
  }
}

///|
/// A stroke reading up by `d` (a finger dragging down on 小屏, the wheel on 大屏), from the middle of the list.
fn rs_up(t : @ui.Tester, s : (String, Double, Double, Int), d : Double) -> Unit {
  let (_, w, h, platform) = s
  if platform == 2 {
    t.drag(w / 2.0, h * 0.3, w / 2.0, h * 0.3 + d)
  } else {
    t.move_to(w * 0.6, h / 2.0)
    t.wheel(w * 0.6, h / 2.0, -d)
  }
}

///|
/// Read up about a screen from the end and come to rest, what that asks of the core answered at once.
fn rs_read_up(t : @ui.Tester, s : (String, Double, Double, Int)) -> Unit {
  rs_up(t, s, s.2 * 0.4)
  rs_run(t, long_rest_ms)
  rs_up(t, s, s.2 * 0.4)
  rs_run(t, long_rest_ms * 2.0)
}

///|
/// The composer's ground: of the wide glass drawn, the one reaching lowest (x, top, width).
fn rs_ground(t : @ui.Tester) -> (Double, Double, Double)? {
  let mut at : (Double, Double, Double, Double)? = None
  for g in t.drawn_glass() {
    let (x, y, w, h, _, _) = g
    if w > 150.0 {
      match at {
        Some((_, ay, _, ah)) if ay + ah > y + h || (ay + ah == y + h && ay <= y) => ()
        _ => at = Some((x, y, w, h))
      }
    }
  }
  at.map(fn(a) { (a.0, a.1, a.2) })
}

///|
/// The bottom of the page's head (the bar the list runs under): of what is drawn at the window's top across the chat's
/// pane (over the composer's ground, rs_ground), glass (小屏's bar) or a ground (大屏's), less than a third of the window
/// `h` tall, the one reaching lowest.
fn rs_bar(t : @ui.Tester, h : Double) -> Double? {
  guard rs_ground(t) is Some((gx, _, gw)) else { return None }
  guard @ui.view_tree() is Some(tree) else { return None }
  let mut at : Double? = None
  for d in tree.drawn() {
    if d.y.abs() < 0.5 &&
      d.h < h / 3.0 &&
      d.w > 150.0 &&
      d.x < gx + gw &&
      d.x + d.w > gx &&
      (d.glass is Some(_) || d.ground != 0L) {
      match at {
        Some(b) if b >= d.y + d.h => ()
        _ => at = Some(d.y + d.h)
      }
    }
  }
  at
}

///|
/// The message read: the first of the long chat whose words start at or under the page's head (rs_bar) and end
/// over the composer's: its number and the top of its words.
fn rs_read(t : @ui.Tester, k : RsCore, s : (String, Double, Double, Int)) -> (Int, Double)? {
  let bottom = match rs_ground(t) {
    Some((_, y, _)) => y
    None => s.2
  }
  let bar = rs_bar(t, s.2).unwrap_or(0.0)
  for n in k.l.first.get()..=k.l.last.get() {
    match t.rect_of("第\{n}条：") {
      Some((_, y, _, h)) if y >= bar - 0.001 && y + h <= bottom => return Some((n, y))
      _ => ()
    }
  }
  None
}

///|
/// Where message `n`'s words start now, if drawn.
fn rs_top(t : @ui.Tester, n : Int) -> Double? {
  t.rect_of("第\{n}条：").map(fn(r) { r.1 })
}

///|
/// Where the words of the window's tree are that what holds them cuts away whole (a part on its way cut to itself, a
/// clip), as they are drawn now: Tester::words lists them, but they are drawn nowhere (a card closing over the last
/// row: its options laid out whole at the size it comes from, under the part's foot as it shrinks).
fn rs_cut_words() -> Array[(Double, Double)] {
  guard @ui.view_tree() is Some(tree) else { return [] }
  let all = tree.drawn_held()
  let out = []
  for e in all {
    let (d, up, _) = e
    guard d.words != "" else { continue }
    let mut h = up
    let mut cut = false
    while h >= 0 && !cut {
      let (hd, hu, _) = all[h]
      if hd.clips && (d.y >= hd.y + hd.h || d.y + d.h <= hd.y) {
        cut = true
      }
      h = hu
    }
    if cut {
      out.push((d.x, d.y))
    }
  }
  out
}

///|
/// At the list's end: how far the composer's ground stands under the lowest words drawn over it across its width (not
/// those cut away whole: rs_cut_words).
fn rs_end_gap(t : @ui.Tester) -> Double? {
  guard rs_ground(t) is Some((gx, gy, gw)) else { return None }
  let cut = rs_cut_words()
  let mut low : Double? = None
  for wd in t.words() {
    let (_, x, y, _, h, a) = wd
    if a > 0.0 &&
      x >= gx &&
      x < gx + gw &&
      y >= 0.0 &&
      y + h <= gy + 0.5 &&
      !cut.iter().any(fn(c) { c.0 == x && c.1 == y }) {
      if low is None || low.unwrap() < y + h {
        low = Some(y + h)
      }
    }
  }
  low.map(fn(b) { gy - b })
}

///|
/// A number in tenths, for what a break says.
fn rs_n(x : Double) -> String {
  let r = if x >= 0.0 { (x * 10.0 + 0.5).to_int() } else { (x * 10.0 - 0.5).to_int() }
  (r.to_double() / 10.0).to_string()
}

///|
/// What `read` gives held over every frame from `cause` (done between frames, before the first looked at) to
/// `rs_watch_ms` past the core's lateness: None where it held within half a device pixel of what it gave before, else
/// what moved, how far at most and when (ms after the cause), and where it is at rest.
fn rs_held(
  t : @ui.Tester,
  k : RsCore,
  what : String,
  read : () -> Double?,
  cause : () -> Unit,
) -> String? {
  guard read() is Some(was) else { return Some("\{what}: nothing read before the cause") }
  let seen : Array[(Double, Double?)] = []
  let start = t.time()
  k.look = Some(fn() { seen.push((t.time() - start, read())) })
  cause()
  rs_run(t, k.late + rs_watch_ms)
  k.look = None
  let mut most = 0.0
  let mut most_at = 0.0
  let mut first_at : Double? = None
  let mut gone : Double? = None
  let mut off = 0
  for f in seen {
    match f.1 {
      None => if gone is None { gone = Some(f.0) }
      Some(y) => {
        let d = y - was
        if d.abs() > rs_still {
          off += 1
          if first_at is None {
            first_at = Some(f.0)
          }
          if d.abs() > most.abs() {
            most = d
            most_at = f.0
          }
        }
      }
    }
  }
  let rest = match seen.last() {
    Some((_, Some(y))) => rs_n(y - was)
    _ => "gone"
  }
  match (first_at, gone) {
    (None, None) => {
      println("READ-STAYS holds: \{what} (\{seen.length()} frames)")
      None
    }
    _ => {
      let moved = match first_at {
        Some(at) => " moved \{rs_n(most)} at most at +\{rs_n(most_at)} ms (first at +\{rs_n(at)} ms)"
        None => ""
      }
      let lost = match gone {
        Some(at) => " not drawn from +\{rs_n(at)} ms"
        None => ""
      }
      // (where it was at some of the frames after the cause: ms after it, how far from where it was)
      let path : Array[String] = []
      for i in [0, 1, 2, 3, 5, 8, 12, 20, 30, 45, 60, 90] {
        if i < seen.length() {
          let (at, y) = seen[i]
          path.push("+\{rs_n(at)}:" + y.map(fn(y) { rs_n(y - was) }).unwrap_or("none"))
        }
      }
      let said = "\{what}:\{moved}\{lost}, off in \{off} of \{seen.length()} frames, at rest \{rest}; " +
        path.join(" ")
      println("READ-STAYS breaks: " + said)
      Some(said)
    }
  }
}

///|
/// The message read (rs_read's) held as `cause` happens, said as `what` (its number put after it).
fn rs_read_held(
  t : @ui.Tester,
  k : RsCore,
  s : (String, Double, Double, Int),
  what : String,
  cause : () -> Unit,
) -> String? {
  guard rs_read(t, k, s) is Some((n, _)) else { return Some("\{what}: no message wholly in sight read up") }
  rs_held(t, k, "\{what} (第\{n}条 read)", fn() { rs_top(t, n) }, cause)
}

///|
/// The end (rs_end_gap's) held as `cause` happens, said as `what`.
fn rs_end_held(t : @ui.Tester, k : RsCore, what : String, cause : () -> Unit) -> String? {
  rs_held(t, k, "\{what} (at the end)", fn() { rs_end_gap(t) }, cause)
}

///|
/// A step of the core's from outside the frames: `k` told what changed.
fn rs_told(k : RsCore, f : () -> Unit) -> Unit {
  @ui.came_from_outside()
  f()
  k.told.set(k.told.get() + 1)
}

///|
fn rs_push(out : Array[String], said : String?) -> Unit {
  match said {
    Some(s) => out.push(s)
    None => ()
  }
}
