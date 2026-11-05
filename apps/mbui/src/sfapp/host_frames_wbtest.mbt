// A long chat's page used as a phone and a desktop use it, its frames as their host gets them (Tester::run_as_host,
// HostFrame): every input handed in as the host hands it (told at its moment, no frame of the test's), the frames the
// app asks for after it drawn at the display's refreshes. Asserted by counts, never by time (2026-11-05: on a phone
// every key built the old frame whole and every frame was drawn over the whole window, while every test was green):
// a key in the composer builds nothing of the old frame and draws again only the composer; a scrolled list builds
// nothing of the old frame and is not drawn whole; leaving the chat builds no page whole once it moves; nothing
// changes in a frame not asked for; and each frame costs a chat of 3000 messages what it costs one of 30.

///|
/// A phone's display (120 Hz) and a desktop's (60 Hz).
let host_phone_period : Double = 1000.0 / 120.0

///|
let host_desk_period : Double = 1000.0 / 60.0

///|
/// A finger's moves, as a phone's screen samples them (240 Hz).
let host_finger_ms : Double = 1000.0 / 240.0

///|
/// Longer than a fling a finger's drag sets off (Android's spline: about a second).
let host_fling_ms : Double = 2000.0

///|
/// What is typed, a character at a time, and how many are taken back.
let host_typed : Array[String] = ["看", "一", "下", "第", "三", "项", "的", "结", "果", "吧"]

///|
let host_erased : Int = 5

///|
/// `base` with its chats' messages as a core gives them (Source.list: a list followed, @rows.TopicList), not made
/// again of the topic's whole value each time it is read (the made-up source's way, ChatMessages::of_value): told
/// whole only where the messages are another value, as a core's subscription is. What a key typed costs is the
/// page's, not the made-up source's.
fn core_lists(base : Source) -> Source {
  let kept : Map[String, (Json, @rows.TopicList)] = {}
  {
    ..base,
    list: fn(name, params, path, fields) {
      if name != "chat" {
        return (base.list)(name, params, path, fields)
      }
      let v = (base.topic)(name, params).value
      let messages = match v {
        Some(Object(o)) => o.get("messages").unwrap_or(Json::null())
        _ => Json::null()
      }
      let key = Json::object(params).stringify()
      match kept.get(key) {
        Some((was, l)) => {
          if !physical_equal(was, messages) {
            l.given(v)
            kept[key] = (messages, l)
          }
          Some(l)
        }
        None => {
          let l = @rows.TopicList::new(path, fields, v)
          kept[key] = (messages, l)
          Some(l)
        }
      }
    },
  }
}

///|
/// The frames of one step of the walk, and the composer's room as it stood (x0, y0, x1, y1: where a key draws).
struct HostStep {
  what : String
  frames : Array[@ui.HostFrame]
  /// the times the chat's view was worked out in it, its frames and between them (@sfbase.views_worked)
  views : Int
}

///|
/// The walk at window `w` × `h` on `platform`, the chat `mode` (chat-long: 3000 messages; chat-long-30: 30): each
/// step's frames, and the composer's room once focused.
fn host_walk(mode : String, w : Double, h : Double, platform : Int) -> (Array[HostStep], (Double, Double, Double, Double)) {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode~, w~, h~, platform~, wrap=core_lists)
  t.set_frame_period(if platform == 0 { host_desk_period } else { host_phone_period })
  t.run_for(@ui.move_most_ms)
  if w > 600.0 && w < 840.0 {
    t.tap(w - 24.0, h / 2.0)
    t.run_for(@ui.move_most_ms)
  }
  let steps : Array[HostStep] = []
  let step = fn(what : String, ms : Double, f : () -> Unit) {
    t.host_frames() |> ignore
    let views = @sfbase.views_worked()
    f()
    t.run_as_host(ms)
    steps.push({ what, frames: t.host_frames(), views: @sfbase.views_worked() - views })
  }
  t.record_host()
  // (what a chat's page makes outside frames too: its list's entries, its messages made of their JSON)
  t.count_between("entries", @sfbase.entries_made)
  t.count_between("messages", @sfbase.messages_made)
  // (a tap as the host hands it: down and up at one moment, the frames it asks for after)
  let tap = fn(x : Double, y : Double) {
    t.touch_at(0, x, y, t.time())
    t.touch_at(2, x, y, t.time())
  }
  let (fx, fy) = match t.find("发消息") {
    Some(p) => p
    None => abort("no field")
  }
  step("focused", @ui.move_most_ms, fn() { tap(fx, fy) })
  let room = match
    (t.query(Button, label=@sf.t("web-main.composer.attach")), t.query(Button, label=@sf.t("web-main.composer.send"))) {
    (Some(p), Some(s)) => {
      // (its glass, the one round send: what a part reaching it copies again, all of it, @damage.Parts::take)
      let cx = s.rect.0 + s.rect.2 / 2.0
      let cy = s.rect.1 + s.rect.3 / 2.0
      match t.drawn_glass().search_by(fn(g) { cx >= g.0 && cx <= g.0 + g.2 && cy >= g.1 && cy <= g.1 + g.3 }) {
        Some(i) => {
          let g = t.drawn_glass()[i]
          (dmin(p.rect.0, g.0) - 2.0, g.1 - 2.0, dmax(s.rect.0 + s.rect.2, g.0 + g.2) + 2.0, h)
        }
        None => abort("no glass round send")
      }
    }
    _ => abort("no ＋ or send")
  }
  for i, c in host_typed {
    step("typed \{i + 1}", t.frame_period() * 4.0, fn() { t.text_told(c, t.time()) })
  }
  for i in 0..<host_erased {
    step("erased \{i + 1}", t.frame_period() * 4.0, fn() { t.key_told(@ui.key_code_backspace, 0, t.time()) })
  }
  for i, k in [@ui.key_code_left, @ui.key_code_left, @ui.key_code_right] {
    step("arrow \{i + 1}", t.frame_period() * 4.0, fn() { t.key_told(k, 0, t.time()) })
  }
  // (a finger's drag down the messages, toward their start, let go moving: a fling)
  let (lx, ly) = (w / 2.0, h * 0.3)
  step("dragged", 0.0, fn() { t.touch_at(0, lx, ly, t.time()) })
  for i in 1..=12 {
    step("dragged \{i}", host_finger_ms, fn() { t.touch_at(1, lx, ly + 15.0 * i.to_double(), t.time()) })
  }
  step("flung", host_fling_ms, fn() { t.touch_at(2, lx, ly + 180.0, t.time()) })
  // (sent: Enter on a desktop's keyboard; send pressed on a phone)
  step("sent", @ui.move_most_ms, fn() {
    if platform == 0 {
      t.key_told(@ui.key_code_enter, 0, t.time())
    } else {
      match t.query(Button, label=@sf.t("web-main.composer.send")) {
        Some(s) => tap(s.rect.0 + s.rect.2 / 2.0, s.rect.1 + s.rect.3 / 2.0)
        None => abort("no send")
      }
    }
  })
  if w > 840.0 {
    match t.find("夜里的构建又失败了") {
      Some((x, y)) => step("another chosen", @ui.move_most_ms, fn() { tap(x, y) })
      None => abort("no other chat in the list")
    }
    match t.find("整理发布清单") {
      Some((x, y)) => step("chosen back", @ui.move_most_ms, fn() { tap(x, y) })
      None => abort("no chat in the list")
    }
  } else {
    step("left", @ui.move_most_ms, fn() { t.back_told(t.time()) })
    match t.find("整理发布清单") {
      Some((x, y)) => step("entered", @ui.move_most_ms, fn() { tap(x, y) })
      None => abort("no chat in the list")
    }
  }
  (steps, room)
}

///|
/// The walks, each made once for the tests that read it (each takes long: a chat of 3000 messages).
// kept across runs: the walks' results, values of their own, made once in this test program
let host_walks : Map[String, (Array[HostStep], (Double, Double, Double, Double))] = {}

///|
fn host_walk_of(mode : String, w : Double) -> (Array[HostStep], (Double, Double, Double, Double)) {
  let key = "\{mode}@\{w}"
  match host_walks.get(key) {
    Some(r) => r
    None => {
      let r = if w < 600.0 { host_walk(mode, w, 844.0, 2) } else { host_walk(mode, w, 800.0, 0) }
      host_walks[key] = r
      r
    }
  }
}

///|
/// A frame said for a report: when, what of the old frame it built and why, what it drew again.
fn host_said(f : @ui.HostFrame) -> String {
  let drawn = if f.damage_share >= 1.0 {
    "the whole window (why \{f.whole_why})"
  } else {
    "\{f.damage}"
  }
  "at \{f.at}: " + (if f.old_built { "the old frame built whole (\{f.why}), " } else { "" }) +
  "\{f.parts_built} parts built, drew again \{drawn}, glass copied \{f.glass}, laid \{f.laid} in \{f.passes} passes"
}

///|
/// Whether rect `r` (x, y, w, h; w < 0 all of the window) is within `room` (x0, y0, x1, y1).
fn host_within(r : (Double, Double, Double, Double), room : (Double, Double, Double, Double)) -> Bool {
  r.2 >= 0.0 && r.0 >= room.0 - 0.5 && r.1 >= room.1 - 0.5 && r.0 + r.2 <= room.2 + 0.5 && r.1 + r.3 <= room.3 + 0.5
}

///|
test "a key in a long chat's composer builds nothing of the old frame and draws again only the composer, on a phone and a desktop" {
  let out : Array[String] = []
  for w in [390.0, 1280.0] {
    let (steps, room) = host_walk_of("chat-long", w)
    for s in steps {
      if !(s.what.has_prefix("typed") || s.what.has_prefix("erased") || s.what.has_prefix("arrow")) {
        continue
      }
      for f in s.frames {
        if f.old_built || f.parts_built > 0 || !f.damage.iter().all(fn(r) { host_within(r, room) }) {
          out.push("\{s.what} at \{w}, the composer \{room}: " + host_said(f))
        }
      }
    }
  }
  assert_eq(out, [])
}

///|
test "a long chat's messages flung build nothing of the old frame and are never drawn over the whole window, on a phone and a desktop" {
  let out : Array[String] = []
  for w in [390.0, 1280.0] {
    let (steps, _) = host_walk_of("chat-long", w)
    for s in steps {
      if !s.what.has_prefix("dragged") && s.what != "flung" {
        continue
      }
      for f in s.frames {
        if f.old_built || f.damage_share >= 1.0 {
          out.push("\{s.what} at \{w}: " + host_said(f))
        }
      }
    }
  }
  assert_eq(out, [])
}

///|
test "leaving a long chat, or choosing another, builds no page whole once it moves, on a phone and a desktop" {
  let out : Array[String] = []
  for w in [390.0, 1280.0] {
    let (steps, _) = host_walk_of("chat-long", w)
    for s in steps {
      if s.what != "left" && s.what != "another chosen" {
        continue
      }
      // (the frame that takes the press may build what changed; from the next, the page moves and nothing is built)
      for i, f in s.frames {
        if i > 0 && f.old_built {
          out.push("\{s.what} at \{w}: " + host_said(f))
        }
      }
    }
  }
  assert_eq(out, [])
}

///|
test "a long chat's page changes nothing in a frame it did not ask for, all through its use, on a phone and a desktop" {
  let out : Array[String] = []
  for w in [390.0, 1280.0] {
    let (steps, _) = host_walk_of("chat-long", w)
    for s in steps {
      for f in s.frames {
        if !f.asked && f.changed {
          out.push("\{s.what} at \{w}: changed unasked at \{f.at}")
        }
      }
    }
  }
  assert_eq(out, [])
}

///|
/// Whether frame `a` of the chat of 3000 costs no more than frame `b`, the same of the chat of its last 30: the old
/// frame built only where it is there, no more parts built nor nodes laid out, no more builds, no more of the window
/// drawn again.
fn host_no_more(a : @ui.HostFrame, b : @ui.HostFrame) -> Bool {
  (!a.old_built || b.old_built) && a.parts_built <= b.parts_built && a.laid <= b.laid && a.passes <= b.passes &&
  a.damage_share <= b.damage_share + 1.0e-9
}

///|
/// Each step's frames of the chat of 3000 against those of its last 30 alone (chat-long-30: what shows is the same),
/// frame by frame: as many frames, none costing more. What a page costs as it opens is no history's: a chat's page
/// opened (another chosen, the chats' list come back to) lays out the same at 30 as at 3000, its first frame most
/// of all (991 nodes at 1280, 627 at 390 on 5dd057f64e, the same at both lengths). Where the two part they part by
/// what the shorter one draws more (its scroll bar's thumb, longer; a row that fades in later), never by what the
/// longer one does.
test "each frame of a chat of 3000 messages costs no more than the same frame of its last 30, on a phone and a desktop" {
  let out : Array[String] = []
  for w in [390.0, 1280.0] {
    let (long, _) = host_walk_of("chat-long", w)
    let (short, _) = host_walk_of("chat-long-30", w)
    for i, s in long {
      match short.get(i) {
        Some(o) if o.what == s.what && o.frames.length() == s.frames.length() =>
          for k, f in s.frames {
            if !host_no_more(f, o.frames[k]) {
              out.push("\{s.what} at \{w}, frame \{k}: 3000 " + host_said(f) + "; 30 " + host_said(o.frames[k]))
            }
          }
        Some(o) => out.push("\{s.what} at \{w}: \{s.frames.length()} frames at 3000, \{o.frames.length()} at 30")
        None => out.push("\{s.what} at \{w}: none at 30")
      }
    }
  }
  assert_eq(out, [])
}

///|
/// What step `s` did between its frames, outside them (HostFrame's `between`), each count summed.
fn host_between(s : HostStep) -> Map[String, Int] {
  let out : Map[String, Int] = {}
  for f in s.frames {
    for c in f.between {
      out[c.0] = out.get(c.0).unwrap_or(0) + c.1
    }
  }
  out
}

///|
/// The entries a long chat's list is made of as it is entered, left or chosen (3000 messages, the rows round them):
/// owed till the list reads its rows by their index (the anchored list), never more.
let entries_owed : Int = 3002

///|
/// Entering a chat, leaving it and choosing another do outside their frames (the events taken as they come, the
/// changes they make settled then: what a phone's PERF does not see, 300–400 ms of it as a long chat is entered or left
/// on 2026-11-05) what they do for a chat of its last 30 alone: no more nodes made, bindings run, nodes laid out, list
/// entries or messages made.
test "entering, leaving or choosing a long chat does no more outside its frames than for a chat of 30, on a phone and a desktop" {
  let out : Array[String] = []
  for w in [390.0, 1280.0] {
    let (long, _) = host_walk_of("chat-long", w)
    let (short, _) = host_walk_of("chat-long-30", w)
    for s in long {
      if !["left", "entered", "another chosen", "chosen back", "sent"].contains(s.what) {
        continue
      }
      match short.search_by(fn(o) { o.what == s.what }) {
        Some(j) => {
          let (a, b) = (host_between(s), host_between(short[j]))
          // (its list's entries owed: the list takes them whole, all of a chat's rows, till the anchored list reads them by
          // their index; never more than that, the debt only to fall)
          let more = a.iter().filter(fn(c) {
            if c.0 == "entries" { c.1 > entries_owed } else { c.1 > b.get(c.0).unwrap_or(0) }
          }).map(fn(c) { "\{c.0} \{c.1} (30: \{b.get(c.0).unwrap_or(0)})" }).collect()
          if !more.is_empty() {
            out.push("\{s.what} at \{w}: " + more.join(", "))
          }
        }
        None => out.push("\{s.what} at \{w}: none at 30")
      }
    }
  }
  assert_eq(out, [])
}

///|
/// A key typed in a long chat's composer makes none of its list's entries and none of its messages, outside its frames
/// or in them: the draft and the composer change the chat's value, none of what its rows are made of (chat_read keeps
/// them; 3002 entries a key before, 2026-11-05).
test "a key in a long chat's composer makes no entries and no messages, on a phone and a desktop" {
  let out : Array[String] = []
  for w in [390.0, 1280.0] {
    let (long, _) = host_walk_of("chat-long", w)
    for s in long {
      guard s.what.has_prefix("typed") || s.what.has_prefix("erased") else { continue }
      let made = host_between(s)
      for k in ["entries", "messages"] {
        let n = made.get(k).unwrap_or(0)
        if n > 0 {
          out.push("\{s.what} at \{w}: \{k} \{n}")
        }
      }
    }
  }
  assert_eq(out, [])
}

///|
/// Entering a chat, leaving it, choosing another and sending in it work the chat's view out (view_of_chat: on a device
/// the core's topic asked for, its params made and written out to find it among the subscriptions) once for each
/// change of what it is made of, however many times its page reads it: never once a read. Each of a page's reads
/// asking anew took 185 of a leave's 378 ms on a phone (2026-11-05): 329 as a chat is left here, 420 as it is
/// entered.
test "entering, leaving or choosing a chat works its view out once for each change, not once for each read, on a phone and a desktop" {
  let out : Array[String] = []
  for w in [390.0, 1280.0] {
    let (long, _) = host_walk_of("chat-long", w)
    for s in long {
      if ["left", "entered", "another chosen", "chosen back", "sent"].contains(s.what) && s.views > 2 {
        out.push("\{s.what} at \{w}: worked out \{s.views} times")
      }
    }
  }
  assert_eq(out, [])
}
