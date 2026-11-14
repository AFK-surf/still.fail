// A chat's page opens whole (the owner's, 2026-11-14): data arriving late is no cause of motion, and what the reader
// has before their eyes does not move. From the press to rest the chat's list is drawn in at most two ways (as at the
// press, and as at rest), and no row of it moves once its messages are drawn: whatever its first screen is laid out by
// is asked with the chat and waited for with it (sfbase's page_opens and chat_opens).
//
// Two ways a person comes to a chat, on the page the app ships (sfbase's chat_page_nodes off: sfbase/chat_list.mbt) and
// on the page made as nodes (on: sfpages/chat_body_node.mbt), on 大屏 (1280x800, a mouse) and 小屏 (390x844, a finger),
// over a core answering at once and 400 ms late: a chat opened from another (case 1 of chat_old_at_once_wbtest), and
// another chat switched to and back (大屏 by the sidebar's rows, 小屏 back to Home and its row pressed: its case 5).
// Before this held, a chat opened over a late core drew its messages as the chat was told and, one lateness later, all
// of them 82 pt higher in one frame.
//
// What is looked at on each display frame: the words of the chat's messages and its agents as drawn (each where, how
// big, how opaque; a line of a kept row by its text run) and each picture of a message, right of where the composer
// starts. The sidebar, Home under a page sliding in, the chat's head and composer are no part of it; a page sliding in
// sideways as a whole is taken by how far all of it moved sideways together.

///|
/// The pictures the fixture's chat holds handed over: what the Testers here hold at most. On 小屏 a chat opened waits
/// off the window's side, made, till what it opens on is answered (sfapp's page_ready): its rows are laid out as its
/// view comes and laid out again as its login's card does, a lateness later, before it slides in, unseen; the Tester
/// sees that row go, once a Tester (rows_steady's), and this file's own judge looks only at what is in the window.
fn init {
  @ui.host_image_bytes_known([("src/sfapp/chat_opens_whole_wbtest.mbt", 4000000)])
  @ui.rows_steady_known([("src/sfapp/chat_opens_whole_wbtest.mbt", 1)])
}

///|
/// The screens: name, width, height, platform.
let ow_screens : Array[(String, Double, Double, Int)] = [("大屏", 1280.0, 800.0, 0), ("小屏", 390.0, 844.0, 2)]

///|
/// How late the core answers (ms).
let ow_lates : Array[Double] = [0.0, 400.0]

///|
/// The chat the cases are about, and another.
let ow_c1 : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }

///|
let ow_c2 : ChatRef = { station: "ws1/st1", session: "s-c2", title: "首页的列表改成按天分组", station_name: "Willow" }

///|
/// The words of the chat's messages and its agents as the core gave them this run: what is looked at.
// kept across runs: emptied as each run of this file begins (ow_begin)
let ow_texts : Map[String, Bool] = Map([])

///|
fn ow_begin() -> Unit {
  ow_texts.clear()
  // (the agent's working line's words: looked at as the chat's, its clock left out by ow_clock)
  ow_texts[tr("android-chat.chat.working")] = true
}

///|
/// Every string of `j` of two letters or more, kept as words to look at.
fn ow_keep_words(j : Json) -> Unit {
  match j {
    String(s) => if s.length() >= 2 { ow_texts[s] = true }
    Array(a) => for x in a { ow_keep_words(x) }
    Object(o) =>
      for k, v in o {
        if k != "md" && k != "seq" && k != "ts" && k != "key" {
          ow_keep_words(v)
        }
      }
    _ => ()
  }
}

///|
/// `base` with the words of a chat's messages and agents kept as it gives them.
fn ow_source(base : Source) -> Source {
  {
    ..base,
    topic_read: fn(name, params) {
      let got = (base.topic_read)(name, params)
      // (not an archived chat's, which 已归档 reads for its rows: words of another page)
      let archived = match params.get("session") {
        Some(String(x)) => x.has_prefix("s-a")
        _ => false
      }
      if name == "chat" && !archived && got.value is Some(Object(v)) {
        match v.get("messages") {
          Some(m) => ow_keep_words(m)
          None => ()
        }
        match v.get("agents") {
          Some(a) => ow_keep_words(a)
          None => ()
        }
      }
      got
    },
  }
}

///|
/// Whether words drawn are a duration (the working line's clock: 12s, 1:05, 3 秒, 2分).
fn ow_clock(s : String) -> Bool {
  guard s.length() > 0 else { return false }
  let mut digit = false
  for c in s {
    if c >= '0' && c <= '9' {
      digit = true
    }
  }
  digit && (s.has_suffix("s") || s.has_suffix("秒") || s.has_suffix("分") || s.has_suffix("m") || s.contains(":"))
}

///|
/// Whether words drawn are of the chat's messages or agents (ow_texts), not a clock.
fn ow_said(s : String) -> Bool {
  if s.length() < 2 || ow_clock(s) {
    return false
  }
  let head = if s.length() > 8 { s.unsafe_substring(start=0, end=8) } else { s }
  for k, _ in ow_texts {
    if k.contains(head) {
      return true
    }
  }
  false
}

///|
/// Whether words drawn are a chat's title (s-c2's first message says it, as Home's and the sidebar's rows do): not
/// looked at, a row of the chats being no part of the chat's list.
fn ow_title(s : String) -> Bool {
  ow_c1.title.contains(s) || ow_c2.title.contains(s)
}

///|
/// A thing of the chat's list drawn: its key (what it is, and which of those), where, how big, how opaque.
priv struct OwThing {
  key : String
  words : String
  x : Double
  y : Double
  w : Double
  h : Double
  a : Double
}

///|
/// Where the chat's page starts across now: the composer's field's start less 40 (the lowest field drawn), else `was`.
fn ow_left(t : @ui.Tester, was : Double) -> Double {
  let mut f : (Double, Double, Double, Double)? = None
  for s in t.semantics() {
    if s.role == @ui.Role::TextField && !s.hidden && (f is None || f.unwrap().1 < s.rect.1) {
      f = Some(s.rect)
    }
  }
  match f {
    Some((x, _, _, _)) => x - 40.0
    None => was
  }
}

///|
/// The chat's list as drawn now in a window `across` wide and `h` high, right of `left` (what is held off the window's
/// side, a page waiting to slide in, not: it is not seen).
fn ow_things(t : @ui.Tester, left : Double, across : Double, h : Double) -> Array[OwThing] {
  let out : Array[OwThing] = []
  let seen : Map[String, Int] = Map([])
  let key = fn(k : String) {
    let n = seen.get(k).unwrap_or(0)
    seen[k] = n + 1
    if n == 0 {
      k
    } else {
      "\{k} #\{n + 1}"
    }
  }
  for wd in t.words() {
    let (s, x, y, w, hh, a) = wd
    if a <= 0.0 || y + hh <= 0.0 || y >= h || x + w <= left || x >= across || !ow_said(s) || ow_title(s) {
      continue
    }
    out.push({ key: key("words 「\{s}」"), words: s, x, y, w, h: hh, a })
  }
  for r in t.text_runs() {
    if r.bottom <= 0.0 || r.top >= h || r.x1 <= left || r.x0 >= across || !ow_said(r.text) || ow_title(r.text) {
      continue
    }
    out.push({ key: key("line 「\{r.text}」"), words: r.text, x: r.x0, y: r.top, w: r.x1 - r.x0, h: r.bottom - r.top, a: 1.0 })
  }
  for i in t.drawn_images() {
    if i[2] < 60.0 || i[3] < 40.0 || i[1] + i[3] <= 0.0 || i[1] >= h || i[0] + i[2] <= left || i[0] >= across {
      continue
    }
    let shape = (i[2] / i[3] * 10.0).round() / 10.0
    out.push({ key: key("picture \{shape}"), words: "", x: i[0], y: i[1], w: i[2], h: i[3], a: i[8] })
  }
  // (words drawn more than once cannot be told apart from frame to frame: left out)
  out.filter(fn(o) {
    o.words == "" ||
    (seen.get("words 「\{o.words}」").unwrap_or(0) <= 1 && seen.get("line 「\{o.words}」").unwrap_or(0) <= 1)
  })
}

///|
fn ow_median(xs : Array[Double]) -> Double {
  if xs.length() == 0 {
    return 0.0
  }
  let s = xs.copy()
  s.sort()
  s[s.length() / 2]
}

///|
fn ow_r(x : Double) -> Double {
  (x * 10.0).round() / 10.0
}

///|
/// What changed from `was` to `now`: each thing moved (taken by how far all moved sideways together), sized otherwise,
/// drawn more or less opaque (`moved`: one of those), come or gone within the window across.
fn ow_diff(was : Array[OwThing], now : Array[OwThing], across : Double) -> Array[(String, Bool)] {
  let before : Map[String, OwThing] = Map([])
  for w in was {
    before[w.key] = w
  }
  let after : Map[String, OwThing] = Map([])
  for n in now {
    after[n.key] = n
  }
  let dxs = []
  for n in now {
    match before.get(n.key) {
      Some(w) => dxs.push(n.x - w.x)
      None => ()
    }
  }
  let mdx = ow_median(dxs)
  let within = fn(o : OwThing) { o.x >= 0.0 && o.x + o.w <= across }
  let out = []
  for n in now {
    match before.get(n.key) {
      Some(w) => {
        let ddx = n.x - w.x - mdx
        let ddy = n.y - w.y
        if ddx.abs() > 0.5 || ddy.abs() > 0.5 || (n.w - w.w).abs() > 0.5 || (n.h - w.h).abs() > 0.5 || (n.a - w.a).abs() > 0.02 {
          out.push((
            "\{n.key} (x \{ow_r(w.x)}, y \{ow_r(w.y)}, \{ow_r(w.w)}x\{ow_r(w.h)}, a \{ow_r(w.a)}) -> (x \{ow_r(n.x)}, y \{ow_r(n.y)}, \{ow_r(n.w)}x\{ow_r(n.h)}, a \{ow_r(n.a)})",
            true,
          ))
        }
      }
      // (come in at the side a page slides in from, all else moving with it)
      None if mdx < -0.5 && n.x - mdx + n.w > across => ()
      None => if within(n) { out.push(("\{n.key} came at (x \{ow_r(n.x)}, y \{ow_r(n.y)}, \{ow_r(n.w)}x\{ow_r(n.h)})", false)) }
    }
  }
  for w in was {
    // (gone off the side a page slides out to, all else moving with it)
    if !after.contains(w.key) && within(w) && !(mdx > 0.5 && w.x + mdx + w.w > across) {
      out.push(("\{w.key} gone from (x \{ow_r(w.x)}, y \{ow_r(w.y)}, \{ow_r(w.w)}x\{ow_r(w.h)})", false))
    }
  }
  out
}

///|
/// The chat's list on `t` (a window `s`) from `cause` done now to `upto` ms after it, a display frame at a time: each
/// frame it changed in (but one where only pictures came, each whole: decoded, drawn the frame they are), and each
/// change after the first, or a thing moved once the messages were drawn, said as `label` and returned.
fn ow_watch(t : @ui.Tester, s : (String, Double, Double, Int), label : String, cause : () -> Unit, upto : Double) -> Array[String] {
  let h = s.2
  let mut left = ow_left(t, 0.0)
  let mut last = ow_things(t, left, s.1, h)
  let from = t.time()
  let changes : Array[(Double, Array[(String, Bool)], String)] = []
  cause()
  t.frame_at(t.time())
  let mut first = true
  while true {
    if !first {
      if t.time() - from >= upto - 1.0e-6 {
        break
      }
      t.run_for(@ui.frame_period_default)
    }
    let now_at = (t.time() - from).round()
    left = ow_left(t, left)
    let now = ow_things(t, left, s.1, h)
    let what = ow_diff(last, now, s.1)
    let decoded = what.length() > 0 &&
      what.iter().all(fn(w) { w.0.has_prefix("picture ") && w.0.contains(" came at ") })
    if what.length() > 0 && !decoded {
      changes.push((now_at, what, t.built_why()))
    }
    last = now
    first = false
  }
  let said = []
  if changes.length() > 1 {
    let line = "\{label}: drawn in \{changes.length() + 1} ways from the press to rest, changed at +\{@ui.list_text(changes.map(fn(c) { c.0.to_string() }))} ms"
    said.push(line)
    println("OPENS_WHOLE \{line}")
    for c in changes {
      for x, w in c.1 {
        if x < 4 {
          println("OPENS_WHOLE_WHAT \{label} +\{c.0}: \{w.0}")
        }
      }
      println("OPENS_WHOLE_WHY \{label} +\{c.0}: \{c.2}")
    }
  } else if changes.length() == 1 &&
    changes[0].1.filter(fn(w) { w.1 }).length() * 2 >= changes[0].1.length() &&
    changes[0].1.iter().any(fn(w) { w.1 }) {
    // (the one change moved what was drawn before it: rows of the chat drawn at the press, put again. Not one where
    // most of it came or went, the chat's messages in another's place: words both say, an agent's name, are one
    // thing to this judge, seen as moved from where the other had them)
    let line = "\{label}: what was drawn moved at +\{changes[0].0} ms"
    said.push(line)
    println("OPENS_WHOLE \{line}")
    for x, w in changes[0].1 {
      if x < 6 {
        println("OPENS_WHOLE_WHAT \{label} +\{changes[0].0}: \{w.0}")
      }
    }
  }
  said
}

///|
/// `ms` of display frames.
fn ow_run(t : @ui.Tester, ms : Double) -> Unit {
  let from = t.time()
  while t.time() - from < ms - 1.0e-6 {
    t.run_for(@ui.frame_period_default)
  }
}

///|
/// The app over a core answering every topic subscribed from `armed` on `ms` late, at rest on chat `at`.
fn ow_app(
  s : (String, Double, Double, Int),
  nodes : Bool,
  ms : Double,
  at : ChatRef,
  mode? : String = "chat",
  heard? : (String) -> Unit = fn(_) {  },
  core? : (Source) -> Source = fn(s) { s },
) -> @ui.Tester {
  new_run()
  ow_begin()
  @sfbase.chat_page_nodes.set(nodes)
  let armed = Ref(false)
  let src = ow_source(
    round_trip_again(core(fixture(mode)), 0.0, heard~, late=fn(_, _) { if armed.val { ms } else { 0.0 } }),
  )
  open_chat(at)
  let (_, w, h, platform) = s
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~, begun=fn() {
    @sfbase.window_tall.val = h
  })
  ow_run(t, 1000.0)
  armed.val = true
  t
}

///|
fn ow_name(nodes : Bool) -> String {
  if nodes {
    "new page"
  } else {
    "old page"
  }
}

///|
/// Where `title` is drawn furthest left (a row of the sidebar, of Home): its middle.
fn ow_row(t : @ui.Tester, title : String) -> (Double, Double)? {
  let mut best : (Double, Double)? = None
  let mut bx = 1.0e9
  for w in t.words() {
    let (s, x, y, ww, hh, a) = w
    if s == title && a > 0.0 && x < bx {
      bx = x
      best = Some((x + ww / 2.0, y + hh / 2.0))
    }
  }
  best
}

///|
/// Chat `r` opened as a person opens it: its row pressed (the sidebar's on 大屏, Home's on 小屏).
fn ow_open_by_hand(t : @ui.Tester, s : (String, Double, Double, Int), r : ChatRef) -> Unit raise {
  match ow_row(t, r.title) {
    Some((x, y)) if s.3 == 0 || x < s.1 => t.tap(x, y)
    _ => fail("\{s.0}: the row of 「\{r.title}」 not drawn")
  }
}

///|
/// Case 1: chat s-c1 opened from s-c2.
fn ow_opened(
  s : (String, Double, Double, Int),
  nodes : Bool,
  ms : Double,
  core? : (Source) -> Source = fn(s) { s },
) -> Array[String] {
  let t = ow_app(s, nodes, ms, ow_c2, core~)
  ow_watch(t, s, "\{ow_name(nodes)} \{s.0} opened, core \{ms} ms", fn() {
    @ui.view_tree().unwrap().event(t.time(), fn() { open_chat(ow_c1) })
  }, ms * 2.0 + 1000.0)
}

///|
/// Case 5: from s-c1 to s-c2 and back, each by its row.
fn ow_switched(
  s : (String, Double, Double, Int),
  nodes : Bool,
  ms : Double,
  core? : (Source) -> Source = fn(s) { s },
) -> Array[String] raise {
  let t = ow_app(s, nodes, ms, ow_c1, core~)
  let small = s.3 == 2
  let out = []
  for r in [ow_c2, ow_c1] {
    if small {
      t.back()
      ow_run(t, 1000.0)
    }
    let missing : Ref[Error?] = Ref(None)
    out.push_iter(
      ow_watch(t, s, "\{ow_name(nodes)} \{s.0} to 「\{r.title}」, core \{ms} ms", fn() {
        ow_open_by_hand(t, s, r) catch {
          e => missing.val = Some(e)
        }
      }, ms * 2.0 + 1000.0).iter(),
    )
    if missing.val is Some(e) {
      raise e
    }
  }
  out
}

///|
/// `base` with its login's `machineLogin` answered as the core answers one it cannot read soon (its station down, not
/// in the list, or whose list it would not give: client/core-ts station/topics.ts `#logins`): an error, at once.
fn ow_login_unread(base : Source) -> Source {
  {
    ..base,
    topic_read: fn(name, params) {
      if name == "machineLogin" {
        { value: None, error: Some({ "code": "offline", "message": "Willow 连不上" }), version: 1 }
      } else {
        (base.topic_read)(name, params)
      }
    },
  }
}

///|
fn ow_case(nodes : Bool, core? : (Source) -> Source = fn(s) { s }) -> Unit raise {
  let all = []
  for s in ow_screens {
    for ms in ow_lates {
      all.push_iter(ow_opened(s, nodes, ms, core~).iter())
      all.push_iter(ow_switched(s, nodes, ms, core~).iter())
    }
  }
  if all.length() > 0 {
    fail(all.join("\n"))
  }
}

///|
test "a chat opens whole, old page: opened, and switched to and back, over a core at once and 400 ms late, on 大屏 and 小屏: drawn in two ways at most, nothing drawn moving" {
  ow_case(false)
}

///|
test "a chat opens whole, new page: opened, and switched to and back, over a core at once and 400 ms late, on 大屏 and 小屏: drawn in two ways at most, nothing drawn moving" {
  ow_case(true)
}

///|
/// The login's card of a station the core cannot read now (answered at once with why: an error): the chat's messages
/// drawn one lateness after the chat's own answer, the card as one unanswered, and nothing moving as it is.
test "a chat opens whole with a login's card the core says it cannot read now, on both pages, over a core at once and 400 ms late, on 大屏 and 小屏: drawn in two ways at most, nothing drawn moving" {
  ow_case(false, core=ow_login_unread)
  ow_case(true, core=ow_login_unread)
}
