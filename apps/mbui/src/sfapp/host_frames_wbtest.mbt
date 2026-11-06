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
  // (each topic told only as its answer comes out otherwise, as the core tells a subscription: the made-up core tells
  // every reader of every topic of any change of it, and a page that read the workspaces or the prefs was built
  // again for a chat read in the list)
  let told : Map[String, @signals.Computed[String]] = {}
  let topic = fn(name : String, params : Map[String, Json]) {
    let key = name + "\u{1}" + Json::object(params).stringify()
    let c = match told.get(key) {
      Some(c) => c
      None => {
        let c = @signals.computed(fn(_) {
          let t = (base.topic)(name, params)
          Json::object({ "value": t.value.unwrap_or(Json::null()), "error": t.error.unwrap_or(Json::null()) }).stringify()
        }, same=fn(a, b) { a == b })
        told[key] = c
        c
      }
    }
    c.get() |> ignore
    @signals.untracked(fn() { (base.topic)(name, params) })
  }
  {
    ..base,
    topic,
    list: fn(name, params, path, fields) {
      if name != "chat" {
        return (base.list)(name, params, path, fields)
      }
      let v = topic(name, params).value
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
  /// the pointer's inputs it made (kind, x, y, the moment), as the host hands them
  made : Array[(Int, Double, Double, Double)]
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
  let made_now : Array[(Int, Double, Double, Double)] = []
  let touch = fn(kind : Int, x : Double, y : Double) {
    made_now.push((kind, x, y, t.time()))
    t.touch_at(kind, x, y, t.time())
  }
  let step = fn(what : String, ms : Double, f : () -> Unit) {
    t.host_frames() |> ignore
    let views = @sfbase.views_worked()
    f()
    t.run_as_host(ms)
    steps.push({ what, frames: t.host_frames(), views: @sfbase.views_worked() - views, made: made_now.copy() })
    made_now.clear()
  }
  t.record_host()
  // (what a chat's page makes outside frames too: its list's entries, its messages made of their JSON)
  t.count_between("entries", @sfbase.entries_made)
  t.count_between("messages", @sfbase.messages_made)
  // (a tap as the host hands it: down and up at one moment, the frames it asks for after)
  let tap = fn(x : Double, y : Double) {
    touch(0, x, y)
    touch(2, x, y)
  }
  let (fx, fy) = match t.find("发消息") {
    Some(p) => p
    None => abort("no field")
  }
  step("focused", @ui.move_most_ms, fn() { tap(fx, fy) })
  let room = match
    (t.query(Button, label=@sf.t("web-main.composer.attach")), t.query(Button, label=@sf.t("web-main.composer.send"))) {
    (Some(p), Some(s)) => {
      // (its glass, the one round send: what a part reaching it copies again, all of it, as the damage the frame is drawn
      // by has it: "where a part reaches what a capture of glass copies, all of that is drawn again in that part, so the
      // copy is of this frame's drawing, never of the last frame's glass", @damage's damage.mbt, Parts::take. Its
      // capture as @damage.capture_of says it of the frame drawn, the blur's margin round the glass with it, cut to
      // the window as the parts are; the smallest that holds send's middle)
      let cx = s.rect.0 + s.rect.2 / 2.0
      let cy = s.rect.1 + s.rect.3 / 2.0
      let (a, n, _) = t.presented()
      let mut cap : (Double, Double, Double, Double)? = None
      for k in 0..<n {
        match @damage.capture_of(a, k) {
          Some((_, (x0, y0, x1, y1))) if cx >= x0 && cx <= x1 && cy >= y0 && cy <= y1 =>
            match cap {
              Some((a0, b0, a1, b1)) if (a1 - a0) * (b1 - b0) <= (x1 - x0) * (y1 - y0) => ()
              _ => cap = Some((x0, y0, x1, y1))
            }
          _ => ()
        }
      }
      match cap {
        Some((x0, y0, x1, y1)) =>
          (dmax(0.0, dmin(p.rect.0, x0)), dmax(0.0, y0), dmin(w, dmax(s.rect.0 + s.rect.2, x1)), h)
        None => abort("no glass round send")
      }
    }
    _ => abort("no ＋ or send")
  }
  // (frames with no key, the field focused: what draws again of its own in them, motions going whatever is typed (a
  // chat at work in the list, its glyph turning), measured here for what a key's frames are held to)
  step("idle", 1500.0, fn() {  })
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
  step("dragged", 0.0, fn() { touch(0, lx, ly) })
  for i in 1..=12 {
    step("dragged \{i}", host_finger_ms, fn() { touch(1, lx, ly + 15.0 * i.to_double()) })
  }
  step("flung", host_fling_ms, fn() { touch(2, lx, ly + 180.0) })
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
  "at \{f.at}, \{f.drawn_as}: " + (if f.old_inputs.is_empty() { "" } else { "took \{f.old_inputs} in the old frame, " }) +
  (if f.left_by == "" { "" } else { "left it by the frame before: \{f.left_by}, " }) +
  (if f.drawn_as == "painted" { "painted for \{f.why}, \{f.layers_drawn} layers drawn (\{f.insts_recorded} instances), " } else { "" }) +
  (if f.old_built { "the old frame built whole (\{f.why}" + (if f.for_old_input { ", for its inputs alone" } else { ", for more than its inputs: \{f.not_for_old_input}" }) + "), " } else { "" }) +
  "\{f.parts_built} parts built, drew again \{drawn} (said \{f.damage_said}, glass taken in \{f.glass_taken}), glass copied \{f.glass}, laid \{f.laid} in \{f.passes} passes" +
  (if f.missed.is_empty() { "" } else { ", left out \{f.missed}" })
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
    // (what draws again of its own with no key, measured in the walk's idle frames: a key's frames may draw that too,
    // and the composer's glass's capture, nothing more)
    let own : Array[(Double, Double, Double, Double)] = []
    for s in steps {
      if s.what == "idle" {
        for f in s.frames {
          own.append(f.damage)
        }
      }
    }
    let allowed = fn(r : (Double, Double, Double, Double)) {
      host_within(r, room) || own.iter().any(fn(o) { host_within(r, (o.0, o.1, o.0 + o.2, o.1 + o.3)) })
    }
    for s in steps {
      if !(s.what.has_prefix("typed") || s.what.has_prefix("erased") || s.what.has_prefix("arrow")) {
        continue
      }
      for f in s.frames {
        if f.old_built || f.parts_built > 0 || !f.damage.iter().all(allowed) {
          out.push("\{s.what} at \{w}, the composer \{room}, of its own \{own}: " + host_said(f))
        }
      }
    }
  }
  assert_eq(out, [])
}

///|
/// Whether `taken`, a pointer's input as a frame says it took it (HostFrame's old_inputs, tree_inputs), is `m` as made
/// (kind, x, y, the moment).
fn host_input_is(m : (Int, Double, Double, Double), taken : String) -> Bool {
  taken.has_prefix("pointer [\{m.0}, \{m.1}, \{m.2},") && taken.has_suffix(" at \{m.3}")
}

///|
/// The inputs made that nothing took, and those taken that none made (one made taken twice: once of them), each
/// paired by its place and moment, once.
fn host_inputs_unmatched(made : Array[(Int, Double, Double, Double)], taken : Array[String]) -> Array[String] {
  let used = Array::make(taken.length(), false)
  let out = []
  for m in made {
    let mut found = false
    for i, k in taken {
      if !used[i] && host_input_is(m, k) {
        used[i] = true
        found = true
        break
      }
    }
    if !found {
      out.push("made, not taken: \{m}")
    }
  }
  for i, k in taken {
    if !used[i] {
      out.push("taken, not made: \{k}")
    }
  }
  out
}

///|
test "each input made taken once, by its place and moment: one taken twice and another not at all is no match, though as many" {
  let made = [(0, 195.0, 253.0, 100.0), (1, 195.0, 268.0, 116.0), (1, 195.0, 283.0, 132.0)]
  let said = fn(m : (Int, Double, Double, Double)) { "pointer \{[m.0.to_double(), m.1, m.2, 0.0, 0.0]} at \{m.3}" }
  assert_eq(host_inputs_unmatched(made, made.map(said)), [])
  assert_eq(host_inputs_unmatched(made, [said(made[2]), said(made[0]), said(made[1])]), [])
  assert_eq(host_inputs_unmatched(made, [said(made[0]), said(made[1]), said(made[1])]), [
    "made, not taken: (1, 195, 283, 132)", "taken, not made: pointer [1, 195, 268, 0, 0] at 116",
  ])
  // (the same place at another moment is another input)
  assert_eq(host_inputs_unmatched([made[0]], ["pointer [0, 195, 253, 0, 0] at 101"]), [
    "made, not taken: (0, 195, 253, 100)", "taken, not made: pointer [0, 195, 253, 0, 0] at 101",
  ])
}

///|
/// Whether frame `f` took an input handed to the old frame (took_input's): the messages' list is the old frame's still,
/// so a pointer on it is that frame's input, what it changes no signal.
fn host_took_old_input(f : @ui.HostFrame) -> Bool {
  !f.old_inputs.is_empty()
}

///|
/// A long chat's messages dragged and flung, each of its frames: the old frame built whole only by an input handed to it
/// (the list is the old frame's: a pointer on it an input of the old frame, outside_counted), in the frame that takes it
/// and the one after, which the inputs it took leave to build (inputs_taken), each said so; none else. A finger's moves
/// are the list's, which follows it as the tree has it (quiet): on a phone none of the drag's moves nor the fling's
/// frames hands the old frame anything, its press alone does (its letting go the list's, which holds the finger then). A mouse's drag picks the words it goes
/// over: each move an input of the old frame, its pick drawn again. Drawn over the whole window only where the parts said came to more than half of it
/// (@damage's why 5: the glass the list moves under taken in), the host told so; every other frame's parts leave out
/// nothing that changed, nor the glass over it. (The drag's and the fling's frames alone: what the walk's other steps
/// draw, focus, typing, choosing, is not held to it here.) Frames of both at each width, and each input of the drag
/// taken in them once, by the old frame or the tree, the press by the old frame: none, nothing held. (Moved to the window's tree, the press goes to the tree and nothing of
/// the old frame is built at all: what the same walk holds then.)
test "a long chat's messages flung build the old frame only for the inputs it was handed and the frame each left, and draw again all that changed, on a phone and a desktop" {
  let out : Array[String] = []
  for w in [390.0, 1280.0] {
    let (steps, _) = host_walk_of("chat-long", w)
    let frames = []
    for s in steps {
      if s.what.has_prefix("dragged") || s.what == "flung" {
        for f in s.frames {
          frames.push((s.what, f))
        }
      }
    }
    // (what is checked there at all: frames of the drag's moves and of the fling, and each input the drag made taken
    // once in them, by the old frame or the window's tree, by its place and moment (host_inputs_unmatched): the press's
    // own step takes no time, its input taken by the frame after it)
    let moved = frames.iter().any(fn(sf) { sf.0.has_prefix("dragged ") })
    let flung = frames.iter().any(fn(sf) { sf.0 == "flung" })
    let made = []
    for s in steps {
      if s.what.has_prefix("dragged") || s.what == "flung" {
        made.append(s.made)
      }
    }
    let old = []
    let tree = []
    for sf in frames {
      old.append(sf.1.old_inputs.filter(fn(i) { i.has_prefix("pointer ") }))
      tree.append(sf.1.tree_inputs.filter(fn(i) { i.has_prefix("pointer ") }))
    }
    let unmatched = host_inputs_unmatched(made, old + tree)
    if !moved || !flung || made.length() != 14 || !unmatched.is_empty() {
      out.push("at \{w}: frames of the moves \{moved}, of the fling \{flung}, \{made.length()} inputs made; \{unmatched}")
    }
    // (the press the old frame's, at each width; on a phone its letting go the list's, which holds the finger by then)
    for m in made {
      let by_old = old.iter().any(fn(i) { host_input_is(m, i) })
      let by_tree = tree.iter().any(fn(i) { host_input_is(m, i) })
      if (m.0 == 0 && !by_old) || (m.0 == 2 && w < 600.0 && !by_tree) {
        out.push("at \{w}: \{m} taken by the old frame \{by_old}, by the tree \{by_tree}")
      }
    }
    for i, sf in frames {
      let (what, f) = sf
      let said = "\{what} at \{w}: " + host_said(f)
      // (a finger's moves the list's, in the tree, once it holds them: on a phone, the old frame handed its press, and the
      // moves that came with it, before the list took the hold over)
      let pressed_now = f.old_inputs.iter().any(fn(i) { i.has_prefix("pointer [0,") })
      let handed = f.old_inputs.filter(fn(i) {
        !(i.has_prefix("pointer [0,") || (pressed_now && i.has_prefix("pointer [1,")))
      })
      if w < 600.0 && !handed.is_empty() {
        out.push("handed the old frame on a phone \{handed}: " + said)
      }
      if f.old_built {
        // (built for those inputs alone: nothing else changed since the first of them, HostFrame's for_old_input)
        let pressed = host_took_old_input(f) && f.for_old_input
        let after = i > 0 &&
          host_took_old_input(frames[i - 1].1) &&
          frames[i - 1].1.old_built &&
          f.why == "it left more to come" &&
          f.left_by == "the inputs it took (inputs_taken)"
        if !pressed && !after {
          out.push("built: " + said)
        }
      }
      if f.damage_share >= 1.0 && !(f.whole_why == 5 && f.damage == [(0.0, 0.0, -1.0, -1.0)]) {
        out.push("whole: " + said)
      }
      if !f.missed.is_empty() {
        out.push("left out: " + said)
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
