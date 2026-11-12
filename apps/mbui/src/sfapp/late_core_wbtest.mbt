// The made-up core a late core's tests run over (sffixture's round_trip_again) sits under the app's own client of its
// core: what it takes for a topic subscribed and let go of is what the client sent, the messages a run's trace keeps,
// never a count of its own of who reads what.

///|
/// What of `heard` is a subscription to, or a letting go of, a topic (the client's messages out): `sub <topic>`,
/// `unsub <topic>`, in order.
fn wire_subs(heard : Array[String]) -> Array[String] {
  let topics : Map[Int, String] = Map([])
  let out : Array[String] = []
  for h in heard {
    guard h.has_prefix("out ") else { continue }
    let text = h.exact_view(start=4).to_owned()
    let j = @json.parse(text) catch { _ => continue }
    guard j is Object(m) && m.get("id") is Some(Number(n, ..)) else { continue }
    match (m.get("subscribe"), m.get("unsubscribe")) {
      (Some(Object(t)), _) =>
        match t.get("topic") {
          Some(String(topic)) => {
            topics[n.to_int()] = topic
            out.push("sub " + topic)
          }
          _ => ()
        }
      (_, Some(True)) => out.push("unsub " + topics.get(n.to_int()).unwrap_or("?"))
      _ => ()
    }
  }
  out
}

///|
test "two readers of a topic over the late core: subscribed once; the first let go of, still subscribed; both, let go of; read again, subscribed again and answered late again" {
  new_run()
  let heard : Array[String] = []
  let src = round_trip_again(fixture("home"), place_core_soon_ms, heard=fn(h) { heard.push(h) })
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=844.0)
  // (the made-up core's moments the window's, as the app's view gives them it: sffixture's made_frame)
  @sffixture.fix_ctx.val = Some(t.ctx())
  t.draw()
  let read = fn() {
    let owner = @signals.set_owner(None)
    let stop = @signals.effect(fn() { src.topic("prefs", {}).get() |> ignore })
    @signals.set_owner(owner) |> ignore
    stop
  }
  let one = read()
  let two = read()
  t.run_for(place_core_soon_ms * 2.0)
  let both = wire_subs(heard)
  let answered = @signals.untracked(fn() { src.topic("prefs", {}).get().value is Some(_) })
  one()
  t.run_for(@ui.frame_period_default * 2.0)
  let first_gone = wire_subs(heard)
  two()
  t.run_for(@ui.frame_period_default * 2.0)
  let all_gone = wire_subs(heard)
  let three = read()
  t.draw()
  let again_now = @signals.untracked(fn() { src.topic("prefs", {}).get().value is Some(_) })
  t.run_for(place_core_soon_ms * 2.0)
  let again_later = @signals.untracked(fn() { src.topic("prefs", {}).get().value is Some(_) })
  let read_again = wire_subs(heard)
  three()
  assert_eq(
    (both, answered, first_gone, all_gone, read_again, again_now, again_later),
    (
      ["sub prefs"],
      true,
      ["sub prefs"],
      ["sub prefs", "unsub prefs"],
      ["sub prefs", "unsub prefs", "sub prefs"],
      false,
      true,
    ),
  )
}

///|
test "a late core done with, a kept conversation taking the core after it as the next Tester begins: the conversation is told what the client sends, and the late core says nothing more to the client" {
  new_run()
  let heard : Array[String] = []
  let src = round_trip_again(fixture("home"), place_core_soon_ms, heard=fn(h) { heard.push(h) })
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=844.0)
  @sffixture.fix_ctx.val = Some(t.ctx())
  t.draw()
  let owner = @signals.set_owner(None)
  let stop = @signals.effect(fn() { src.topic("prefs", {}).get() |> ignore })
  @signals.set_owner(owner) |> ignore
  t.run_for(place_core_soon_ms * 2.0)
  let heard_then = heard.length()
  // (a kept conversation the core, then a Tester begun: as a replay's test begins after this one)
  let replay = @core.Replay::parse("")
  replay.attach()
  let t2 = @ui.Tester::new(fn(_c) {  }, w=390.0, h=844.0)
  t2.draw()
  // (what the client sends now goes to the conversation: an ask the run never made, where the two went apart)
  @core.subscribe("workspaces") |> ignore
  let told = replay.diverged().iter().any(fn(d) { d.contains("workspaces") })
  // (the late core's value changed now: nothing of it to the client)
  @settings.fixture_changed()
  t2.run_for(place_core_soon_ms * 2.0)
  stop()
  @core.Replay::detach()
  assert_eq((told, heard.length() - heard_then), (true, 0))
}

///|
/// The three screens a switch is held on: its name, the window and the platform it is drawn on (小屏 a phone's; 中屏 on
/// the tape; 大屏 off it).
let switch_screens : Array[(String, Double, Double, Int)] = [
  ("小屏", 390.0, 844.0, 2),
  ("中屏", 720.0, 800.0, 0),
  ("大屏", 1280.0, 800.0, 0),
]

///|
/// The made-up core answering each topic as late as `late` says by its name, through the app's own client, what the
/// places open on asked ahead (reads_ahead), with a third workspace (ws3, 第三个) where `three`: what the client sent and
/// was told put in `heard`. Made in a run begun for it (switch_on).
fn switch_core(late : (String) -> Double, heard : Array[String], three? : Bool = false) -> Source {
  let base = fixture("home")
  let base = if three {
    {
      ..base,
      topic_read: fn(name, params) {
        let t = (base.topic_read)(name, params)
        guard name == "workspaces" && t.value is Some(Array([Object(o)])) else { return t }
        guard o.get("workspaces") is Some(Array(list)) else { return t }
        let m = o.copy()
        m["workspaces"] = Json::array([..list, { "id": "ws3", "name": "第三个", "stations": 1, "members": 1 }])
        { value: Some(Json::array([Json::object(m)])), error: t.error, version: t.version }
      },
    }
  } else {
    base
  }
  {
    ..round_trip_again(base, 0.0, heard=fn(h) { heard.push(h) }, late=fn(name, _) { late(name) }),
    reads_ahead: fn() { true },
  }
}

///|
/// The app over `src` in a window `w` by `h` on `platform`, at rest on ws1 (星火工作室) (its core `most` late at most:
/// what is asked as what it waits for is answered answered too by then).
fn switch_screen(src : Source, w : Double, h : Double, platform : Int, most : Double) -> @ui.Tester {
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  t.draw()
  t.run_for(most * 8.0 + 1000.0)
  t
}

///|
/// A phone over the made-up core answering `ms` late, at rest on Home of ws1 (星火工作室), what the places open on asked
/// ahead (reads_ahead): what the client sent and was told put in `heard`.
fn switch_phone(ms : Double, heard : Array[String]) -> (@ui.Tester, Source) {
  switch_on(fn(_) { ms }, heard, 390.0, 844.0, 2, ms)
}

///|
/// A run begun, the made-up core answering as late as `late` says (switch_core) and the app over it at rest in a
/// window `w` by `h` on `platform` (switch_screen): the run's own Tester, and its source.
fn switch_on(
  late : (String) -> Double,
  heard : Array[String],
  w : Double,
  h : Double,
  platform : Int,
  most : Double,
  three? : Bool = false,
) -> (@ui.Tester, Source) {
  new_run()
  let src = switch_core(late, heard, three~)
  (switch_screen(src, w, h, platform, most), src)
}

///|
/// What the frame drawn now shows, `start` the press's moment: the moment after it (to a thousandth of a ms: the same
/// moment however it was summed), the bones drawn, the workspace in view, whose chats' list's words it draws (ws1's
/// first row; ws2's, which has no station: 小屏's Home its first station asked for, the wide frame's sidebar that it has
/// none; "" neither), and whether a new chat's page is drawn whole (its heading: the page the wide frame's pane lands
/// on in either workspace).
fn switch_frame(t : @ui.Tester, src : Source, start : Double) -> (Double, Int, String, String, Bool) {
  let ws = @signals.untracked(fn() { workspace_in_view(src).0.map(fn(w) { w.id }).unwrap_or("") })
  let words = t.words().map(fn(w) { w.0 })
  let home = if words.contains("整理发布清单") {
    "ws1"
  } else if words.contains("添加第一台 station") || words.contains(@sf.t("web-main.sidebar.noStation.before")) {
    "ws2"
  } else {
    ""
  }
  (
    ((t.time() - start) * 1000.0).round() / 1000.0,
    t.bones_drawn(),
    ws,
    home,
    words.contains("想让 agent 做什么？"),
  )
}

///|
/// What every frame shows (switch_frame's, its moment after `start`) from a press now on to `upto` after `start`: the
/// press's own frame (drawn at its moment), then each of the display's frames (@ui.frame_period_default), what is due
/// between them drawn at its own moment on the way.
fn switch_frames(t : @ui.Tester, src : Source, start : Double, upto : Double) -> Array[(Double, Int, String, String, Bool)] {
  t.frame_at(t.time())
  let out = [switch_frame(t, src, start)]
  while t.time() - start < upto - 1.0e-6 {
    t.run_for(@ui.frame_period_default)
    out.push(switch_frame(t, src, start))
  }
  out
}

///|
/// The client's subscriptions to `chats` and lettings go of them, in order: `sub <scope>`, `unsub <scope>`.
fn wire_chats(heard : Array[String]) -> Array[String] {
  let scopes : Map[Int, String] = Map([])
  let out : Array[String] = []
  for h in heard {
    guard h.has_prefix("out ") else { continue }
    let j = @json.parse(h.exact_view(start=4).to_owned()) catch { _ => continue }
    guard j is Object(m) && m.get("id") is Some(Number(n, ..)) else { continue }
    match (m.get("subscribe"), m.get("unsubscribe")) {
      (Some(Object(t)), _) if t.get("topic") == Some(Json::string("chats")) => {
        let scope = match t.get("scope") {
          Some(String(s)) => s
          _ => "?"
        }
        scopes[n.to_int()] = scope
        out.push("sub " + scope)
      }
      (_, Some(True)) =>
        match scopes.get(n.to_int()) {
          Some(scope) => out.push("unsub " + scope)
          None => ()
        }
      _ => ()
    }
  }
  out
}

///|
test "the workspaces' sheet open asks nothing of another workspace; its row tapped over a core 60 ms late draws no bone, the first workspace shown till the answer and the other the frame after it" {
  let heard : Array[String] = []
  let (t, src) = switch_phone(60.0, heard)
  @ui.view_tree().unwrap().event(t.time(), fn() { @sfpages.open_workspaces(src, At(32.0, 16.0, 150.0, 38.0)) })
  t.run_for(@ui.move_most_ms * 2.0)
  let asked_open = wire_chats(heard)
  let sheet = t.semantics().iter().find_first(fn(s) { !s.hidden && s.role == @ui.Role::Dialog })
  guard sheet is Some(s) else { fail("no sheet") }
  let (sx, sy, sw, sh) = s.rect
  guard t.words().iter().find_first(fn(w) { w.0 == "个人" && w.1 >= sx && w.1 <= sx + sw && w.2 >= sy && w.2 <= sy + sh }) is Some(w) else {
    fail("no 个人 in the sheet")
  }
  let start = t.time()
  t.tap(w.1 + 4.0, w.2 + 4.0)
  let frames = switch_frames(t, src, start, @sfbase.switch_wait_ms + @ui.move_most_ms * 2.0)
  assert_eq(asked_open, ["sub ws1"])
  assert_eq(frames.filter(fn(f) { f.1 > 0 }), [])
  assert_eq(frames.filter(fn(f) { f.0 < 60.0 && f.2 != "ws1" }), [])
  assert_eq(frames.filter(fn(f) { f.0 > 60.0 && (f.2 != "ws2" || f.3 != "ws2") }), [])
}

///|
test "a workspace switched over a core 120 ms late: the first one's list and no bone till the answer, the other the frame after it, no bone ever" {
  let heard : Array[String] = []
  let (t, src) = switch_phone(120.0, heard)
  let start = t.time()
  @ui.view_tree().unwrap().event(start, fn() { @sfpages.switch_workspace(src, "ws2") })
  let frames = switch_frames(t, src, start, @sfbase.switch_wait_ms + @ui.move_most_ms * 2.0)
  assert_eq(frames.filter(fn(f) { f.1 > 0 }), [])
  assert_eq(frames.filter(fn(f) { f.0 < 120.0 && (f.2 != "ws1" || f.3 != "ws1") }), [])
  assert_eq(frames.filter(fn(f) { f.0 > 120.0 && (f.2 != "ws2" || f.3 != "ws2") }), [])
}

///|
test "a workspace switched over a core 600 ms late: no bone and the first one shown for switch_wait_ms, the other shown from then" {
  let heard : Array[String] = []
  let (t, src) = switch_phone(600.0, heard)
  let start = t.time()
  @ui.view_tree().unwrap().event(start, fn() { @sfpages.switch_workspace(src, "ws2") })
  let frames = switch_frames(t, src, start, 600.0 + @ui.move_most_ms)
  let wait = @sfbase.switch_wait_ms
  assert_eq(frames.filter(fn(f) { f.0 < wait && (f.1 > 0 || f.2 != "ws1" || f.3 != "ws1") }), [])
  assert_eq(frames.filter(fn(f) { f.0 > wait && f.2 != "ws2" }), [])
  // (nothing answered by then: its Home's bones, till the answer)
  assert_true(frames.iter().any(fn(f) { f.0 > wait && f.0 < 600.0 && f.1 > 0 }))
  assert_eq(frames.filter(fn(f) { f.0 > 600.0 && (f.1 > 0 || f.3 != "ws2") }), [])
}

///|
test "a workspace switched and switched back: each workspace's chats subscribed and let go of once per stay, never let go of and asked again around the switch" {
  let heard : Array[String] = []
  let (t, src) = switch_phone(120.0, heard)
  @ui.view_tree().unwrap().event(t.time(), fn() { @sfpages.switch_workspace(src, "ws2") })
  t.run_for(@sfbase.switch_wait_ms + @ui.move_most_ms * 2.0)
  let there = wire_chats(heard)
  @ui.view_tree().unwrap().event(t.time(), fn() { @sfpages.switch_workspace(src, "ws1") })
  t.run_for(@sfbase.switch_wait_ms + @ui.move_most_ms * 2.0)
  let back = wire_chats(heard)
  assert_eq(
    (there, back),
    (["sub ws1", "sub ws2", "unsub ws1"], ["sub ws1", "sub ws2", "unsub ws1", "sub ws1", "unsub ws2"]),
  )
}

///|
/// How late the made-up core answers each of a workspace's topics in the switches below: each at a moment of its own,
/// some tens of ms after it is asked (the marks the wide frame's pane lands by, held from the start; what it lands on
/// asked at the press).
fn switch_late(name : String) -> Double {
  match name {
    "chats" => 40.0
    "longJobs" => 25.0
    "workspaceMarks" => 70.0
    "newChat" => 55.0
    _ => 30.0
  }
}

///|
test "a workspace switched over a core answering each of its topics tens of ms late, each at its own moment: on 小屏, 中屏 and 大屏 no bone from the press to the switch, the first workspace as it was till then, and the switch's frame the other's list with the pane beside it filled, within switch_wait_ms" {
  // (what each screen does wrong, all three run before it is said)
  let faults : Array[String] = []
  for s in switch_screens {
    let (name, w, h, platform) = s
    let wide = name != "小屏"
    let (t, src) = switch_on(switch_late, [], w, h, platform, 70.0)
    let start = t.time()
    @ui.view_tree().unwrap().event(start, fn() { @sfpages.switch_workspace(src, "ws2") })
    let frames = switch_frames(t, src, start, @sfbase.switch_wait_ms + @ui.move_most_ms * 2.0)
    guard frames.search_by(fn(f) { f.2 == "ws2" }) is Some(i) else {
      faults.push(name + ": not switched")
      continue
    }
    // (every frame before the switch the first workspace as it was, no bone)
    let before = frames[:i].to_owned().filter(fn(f) { f.1 > 0 || f.2 != "ws1" || f.3 != "ws1" })
    if before.length() > 0 {
      faults.push(name + ": before the switch \{Repr(before)}")
    }
    // (the switch's frame and every frame after it the other's, whole (on the wide frame the pane filled), no bone)
    let after = frames[i:].to_owned().filter(fn(f) { f.1 > 0 || f.2 != "ws2" || f.3 != "ws2" || (wide && !f.4) })
    if after.length() > 0 {
      faults.push(name + ": from the switch on \{Repr(after)}")
    }
    // (within switch_wait_ms, and not before the last it waits for came: on the wide frame the new chat the pane lands
    // on, asked at the press as the marks held across the switch say it)
    let f = frames[i]
    // (小屏's Home opens on its list, the latest of what it waits for here)
    let last = if wide { switch_late("newChat") } else { switch_late("chats") }
    if f.0 > @sfbase.switch_wait_ms || f.0 < last {
      faults.push(name + ": switched at \{f.0}, not between \{last} and \{@sfbase.switch_wait_ms}")
    }
  }
  assert_eq(faults, [])
}

///|
test "a workspace switched over a core that answers none of it within switch_wait_ms: on 小屏, 中屏 and 大屏 the first workspace as it was and no bone till then, the other from then" {
  let faults : Array[String] = []
  for s in switch_screens {
    let (name, w, h, platform) = s
    let (t, src) = switch_on(fn(_) { 600.0 }, [], w, h, platform, 600.0)
    let start = t.time()
    @ui.view_tree().unwrap().event(start, fn() { @sfpages.switch_workspace(src, "ws2") })
    let frames = switch_frames(t, src, start, @sfbase.switch_wait_ms + @ui.move_most_ms)
    let wait = @sfbase.switch_wait_ms
    let early = frames.filter(fn(f) { f.0 < wait && (f.1 > 0 || f.2 != "ws1" || f.3 != "ws1") })
    if early.length() > 0 {
      faults.push(name + ": before switch_wait_ms \{Repr(early)}")
    }
    let late = frames.filter(fn(f) { f.0 > wait && f.2 != "ws2" })
    if late.length() > 0 {
      faults.push(name + ": after switch_wait_ms \{Repr(late)}")
    }
  }
  assert_eq(faults, [])
}

///|
test "a workspace shown earlier in the run switched to again, all its first screen reads answered already: on 小屏, 中屏 and 大屏 switched in the press's own handler, drawn in its frame whole" {
  for s in switch_screens {
    let (name, w, h, platform) = s
    let wide = name != "小屏"
    new_run()
    // (each of the core's topics late the first time it is read, at once after: what was read before is answered)
    let src = { ..round_trip_by(fixture("home"), fn() { 60.0 }), reads_ahead: fn() { true } }
    let t = switch_screen(src, w, h, platform, 60.0)
    let tree = @ui.view_tree().unwrap()
    let away = @sfbase.switch_wait_ms + @ui.move_most_ms * 2.0
    tree.event(t.time(), fn() { @sfpages.switch_workspace(src, "ws2") })
    t.run_for(away)
    tree.event(t.time(), fn() { @sfpages.switch_workspace(src, "ws1") })
    t.run_for(away)
    let start = t.time()
    tree.event(start, fn() { @sfpages.switch_workspace(src, "ws2") })
    let now = @signals.untracked(fn() { workspace_in_view(src).0.map(fn(w) { w.id }).unwrap_or("") })
    let f = switch_frames(t, src, start, 0.0)[0]
    assert_eq((name, now, f.1, f.2, f.3, !wide || f.4), (name, "ws2", 0, "ws2", "ws2", true))
  }
}

///|
/// How many times the client subscribed to workspace `ws`'s chats, and how many it let go of (wire_chats').
fn chats_held_of(heard : Array[String], ws : String) -> (Int, Int) {
  let said = wire_chats(heard)
  (said.filter(fn(x) { x == "sub " + ws }).length(), said.filter(fn(x) { x == "unsub " + ws }).length())
}

///|
test "a second workspace asked while a switch waits takes its place, the first never shown and what it asked let go of; on 小屏, 中屏 and 大屏" {
  for s in switch_screens {
    let (name, w, h, platform) = s
    let heard : Array[String] = []
    let (t, src) = switch_on(fn(_) { 150.0 }, heard, w, h, platform, 150.0, three=true)
    let tree = @ui.view_tree().unwrap()
    let start = t.time()
    tree.event(start, fn() { @sfpages.switch_workspace(src, "ws2") })
    // (the second asked some 100 ms after the first, on the display's frame there, before the first is answered)
    let first = switch_frames(t, src, start, 100.0)
    let second = t.time() - start
    tree.event(t.time(), fn() { @sfpages.switch_workspace(src, "ws3") })
    let then = switch_frames(t, src, start, second + @sfbase.switch_wait_ms + @ui.move_most_ms)
    let frames = [..first, ..then]
    // (the first workspace as it was, no bone, till the second's is answered (150 after it), the one asked first never)
    assert_eq((name, frames.filter(fn(f) { f.2 == "ws2" })), (name, []))
    assert_eq(
      (name, frames.filter(fn(f) { f.0 < second + 150.0 && (f.1 > 0 || f.2 != "ws1" || f.3 != "ws1") })),
      (name, []),
    )
    // (the second within switch_wait_ms of its own press)
    assert_eq((name, frames.filter(fn(f) { f.0 > second + @sfbase.switch_wait_ms && f.2 != "ws3" })), (name, []))
    let (sub, unsub) = chats_held_of(heard, "ws2")
    assert_true(sub > 0 && sub == unsub, msg=name + ": ws2's chats subscribed \{sub}, let go of \{unsub}")
  }
}

///|
test "the workspace in view asked while a switch waits calls it off: on 小屏, 中屏 and 大屏 nothing switches, no bone, and what it asked let go of" {
  for s in switch_screens {
    let (name, w, h, platform) = s
    let heard : Array[String] = []
    let (t, src) = switch_on(fn(_) { 150.0 }, heard, w, h, platform, 150.0)
    let tree = @ui.view_tree().unwrap()
    let start = t.time()
    tree.event(start, fn() { @sfpages.switch_workspace(src, "ws2") })
    // (the one in view asked some 50 ms after, on the display's frame there, before the other is answered)
    let first = switch_frames(t, src, start, 50.0)
    let off = t.time() - start
    tree.event(t.time(), fn() { @sfpages.switch_workspace(src, "ws1") })
    let then = switch_frames(t, src, start, off + @sfbase.switch_wait_ms + @ui.move_most_ms * 2.0)
    let frames = [..first, ..then]
    assert_eq((name, frames.filter(fn(f) { f.1 > 0 || f.2 != "ws1" || f.3 != "ws1" })), (name, []))
    let (sub, unsub) = chats_held_of(heard, "ws2")
    assert_true(sub > 0 && sub == unsub, msg=name + ": ws2's chats subscribed \{sub}, let go of \{unsub}")
  }
}
