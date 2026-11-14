// An agent at work in one line as nodes (message_working_node.mbt), set beside the old view's (chat_rows.mbt
// activity_row, out of a list) on the same fixture: at work with nothing said, doing something (in the monospaced face
// too), waiting on what it started, with no clock; wide and narrow, at 1.3; one of two under the pointer with its stop;
// what it says changed, once steadied; and its stop pressed. Harness: message_decision_node's (dec_old, dec_new,
// dec_src).

///|
/// The core's moment the fixture's clocks read.
let work_now : Double = 100000.0

///|
/// The fixture's agent at work: its turn began `since` (None: no clock), waiting on `wait` (since, seconds, what).
fn work_agent_json(since? : Double? = Some(work_now - 65000.0), wait? : Json? = None, key? : String = "s-c1", who? : String = "Claude") -> Json {
  let o : Map[String, Json] = {
    "session": {
      "key": Json::string(key),
      "runtime": "claude",
      "maker": { "id": "anthropic", "name": "Anthropic" },
      "agentText": Json::string(who),
    },
    "status": "running",
  }
  match since {
    Some(s) => o["since"] = Json::number(s)
    None => ()
  }
  match wait {
    Some(w) => o["wait"] = w
    None => ()
  }
  Json::object(o)
}

///|
/// The fixture's chat's view with these agents at work.
fn work_view(agents : Array[Json]) -> ChatView {
  @sfbase.chat_view_made({ "title": "发布", "messages": [], "thread": { "id": 7 }, "agents": Json::array(agents) })
}

///|
/// What the core says the agent does now (`live`'s activity), as `live` says as it changes; the clocks at work_now;
/// calls kept in `calls`.
fn work_src(live : @signals.Signal[Json?], calls : Array[(String, Json)]) -> Source {
  let base = dec_src(@signals.signal(None), calls)
  {
    ..base,
    topic_read: fn(name, params) {
      if name == "live" {
        { value: live.get(), error: None, version: 1 }
      } else {
        (base.topic_read)(name, params)
      }
    },
    now: fn() { work_now },
  }
}

///|
/// What the agent does, as the core says it.
fn work_live(words : String, key? : String = "read", mono? : Bool = false) -> Json {
  { "activity": { "now": { "text": Json::string(words), "key": Json::string(key), "mono": Json::boolean(mono) } } }
}

///|
/// The view's first agent as the old view draws it in its row (activity_row out of a list, steadied by `rk`).
fn work_old(w : Double, src : Source, view : ChatView, rk : String, platform? : Int = 0) -> @ui.Tester {
  dec_old(w, view, platform~, fn(c, here) {
    row_box(c, row_side(w), 0.0, fn() {
      activity_row(c, src, here, view.agents[0], @sfbase.emits_of("work-test"), rk, false, None)
    })
    |> ignore
  })
}

///|
/// The same as the nodes draw it (working_said_node), the view as `view` says as it changes.
fn work_new(w : Double, src : Source, view : () -> ChatView, platform? : Int = 0) -> @ui.Tester {
  let steadies = ActivitySteadies::new()
  dec_new(w, view, platform~, fn(f, here) {
    working_said_node(f, src, here, "act:s-c1", fn() { row_side(w) }, fn() { 0.0 }, fn() { (here.view)().agents[0] }, fn() {
      None
    }, steadies)
    |> ignore
  })
}

///|
/// The fixture's states by name: the agents, what the core says the first does.
fn work_cases() -> Array[(String, Array[Json], Json?)] {
  [
    ("at work", [work_agent_json()], None),
    ("doing", [work_agent_json()], Some(work_live("读 chat_rows.mbt"))),
    ("in the monospaced face", [work_agent_json()], Some(work_live("npm test --filter rows", key="run", mono=true))),
    (
      "waiting",
      [work_agent_json(wait=Some({ "since": work_now - 65000.0, "seconds": 600, "text": "等 CI 跑完" }))],
      Some(work_live("读 chat_rows.mbt")),
    ),
    ("no clock", [work_agent_json(since=None)], Some(work_live("读 chat_rows.mbt"))),
  ]
}

///|
test "an agent at work, made once as nodes, is drawn as the old view drew it: at work, doing something, in the monospaced face, waiting, with no clock; wide and narrow, at 1.3" {
  for c in work_cases() {
    for w in [760.0, 390.0] {
      let at = "\{c.0} at \{w}"
      let view = work_view(c.1)
      let old = work_old(w, work_src(@signals.signal(c.2), []), view, at)
      old.run_for(@ui.move_most_ms)
      let was = head_drawn(old)
      let t = work_new(w, work_src(@signals.signal(c.2), []), fn() { view })
      t.run_for(@ui.move_most_ms)
      assert_eq(head_drawn(t), was, msg=at)
      assert_eq(t.audit(), [], msg=at)
    }
  }
  for k in [1, 3] {
    let c = work_cases()[k]
    let view = work_view(c.1)
    let at = c.0 + " at 1.3"
    let old = work_old(390.0, work_src(@signals.signal(c.2), []), view, at)
    old.set_font_scale(1.3)
    old.run_for(@ui.move_most_ms)
    let was = head_drawn(old)
    let t = work_new(390.0, work_src(@signals.signal(c.2), []), fn() { view })
    t.set_font_scale(1.3)
    t.run_for(@ui.move_most_ms)
    assert_eq(head_drawn(t), was, msg=at)
    assert_eq(t.audit(), [], msg=at)
  }
}

///|
test "what it says changed: once steadied, the new words in the old's place, as the old view's at rest" {
  let first = work_live("读 chat_rows.mbt")
  let then = work_live("改 decision.mbt", key="edit")
  let view = work_view([work_agent_json()])
  let live_old = @signals.signal(Some(first))
  let old = work_old(760.0, work_src(live_old, []), view, "changed")
  old.run_for(@ui.move_most_ms)
  let before = head_drawn(old)
  live_old.set(Some(then))
  old.run_for(steady_dwell_ms * 2.0)
  let after = head_drawn(old)
  let live = @signals.signal(Some(first))
  let t = work_new(760.0, work_src(live, []), fn() { view })
  t.run_for(@ui.move_most_ms)
  assert_eq(head_drawn(t), before)
  live.set(Some(then))
  t.run_for(steady_dwell_ms * 2.0)
  assert_eq(head_drawn(t), after)
  assert_true(t.find("改 decision.mbt") is Some(_))
  assert_eq(t.audit(), [])
}

///|
test "one of two agents under the pointer, as the old view's: its words in the text's ink, its stop at the row's end; pressed, its turn asked to stop" {
  let view = work_view([work_agent_json(), work_agent_json(key="s-other", who="Codex")])
  let live = Some(work_live("读 chat_rows.mbt"))
  let old = work_old(760.0, work_src(@signals.signal(live), []), view, "hover")
  old.run_for(@ui.move_most_ms)
  let (x, y, w, h) = old.rect_of("读 chat_rows.mbt").unwrap()
  old.move_to(x + w / 2.0, y + h / 2.0)
  old.run_for(@ui.move_most_ms)
  let was = head_drawn(old)
  let calls : Array[(String, Json)] = []
  let t = work_new(760.0, work_src(@signals.signal(live), calls), fn() { view })
  t.run_for(@ui.move_most_ms)
  t.move_to(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(head_drawn(t), was)
  let faults = t.audit()
  assert_eq(faults, [], msg=faults.join(" | "))
  // (pressed with the mouse it shows under: a finger has no pointer over the row)
  t.host_says_finger(Some(false))
  t.click(Button, label=@sf.t("web-main.activity.stop", args=[("who", "Claude")]))
  t.run_for(@ui.move_most_ms)
  let made = calls.filter(fn(c) { c.0 == "session.stop" })
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].1), "key"), "s-c1")
  assert_eq(text(Some(made[0].1), "station"), "ws1/st1")
}

///|
test "an agent at work's segments as nodes are drawn as the old view's: eight arcs in their strengths over the ground" {
  let old = dec_old(390.0, dec_view(), fn(c, _) {
    @sf.segments(c, ring_side, ring_stroke, @sf.theme().p.accent, @sf.theme().p.bg) |> ignore
  })
  old.draw()
  // (where each arc goes, to a millionth: turned about its middle, the two add their sines in another order)
  let near = fn(t : @ui.Tester) {
    t.drawn_lines().map(fn(l) {
      let r = fn(v : Double) { (v * 1.0e6).round() / 1.0e6 }
      (r(l.0), r(l.1), r(l.2), r(l.3), l.4, l.5)
    })
  }
  let was = near(old)
  let t = dec_new(390.0, fn() { dec_view() }, fn(f, _) {
    @sf.segments_node(f, ring_side, ring_stroke, fn() { @sf.theme().p.accent }, fn() { @sf.theme().p.bg }) |> ignore
  })
  t.draw()
  assert_eq(near(t), was)
  assert_eq(t.audit(), [])
}

///|
/// The fixture's agent with no clock as the nodes draw it, steadied in `steadies`, come into its list as `came` says.
fn work_unclocked(src : Source, steadies : ActivitySteadies, came : @signals.Signal[Double?]) -> @ui.Tester {
  let view = work_view([work_agent_json(since=None)])
  dec_new(760.0, fn() { view }, fn(f, here) {
    working_said_node(f, src, here, "act:s-c1", fn() { row_side(760.0) }, fn() { 0.0 }, fn() { (here.view)().agents[0] }, fn() {
      came.get()
    }, steadies)
    |> ignore
  })
}

///|
test "its words cut into their cells once as they are said, not again as each frame draws them coming in or giving way" {
  let live = @signals.signal(Some(work_live("改 chat_rows_node.mbt 和 decision.mbt")))
  let came : @signals.Signal[Double?] = @signals.signal(None)
  let steadies = ActivitySteadies::new()
  let made = working_cells_made.val
  let t = work_unclocked(work_src(live, []), steadies, came)
  t.run_for(@ui.move_most_ms)
  // (its words at rest: cut once)
  assert_eq(working_cells_made.val - made, 1)
  // (coming in glyph by glyph, drawn on the way: cut no more)
  came.set(Some(t.time()))
  let seen : Array[String] = []
  for _ in 0..<8 {
    t.run_for(activity_glyph_in_ms / 8.0)
    seen.push(glyphs_drawn(t))
  }
  assert_true(seen[3].contains(" a0."), msg=seen[3])
  assert_eq(working_cells_made.val - made, 1)
  // (giving way to a step of other words: the two cut as it begins, then nothing as it goes, the new words at rest
  // once more as it is over)
  let (changed, _) = glyphs_walk(t, live, [work_live("读 a.mbt", key="read2")], 0.0, fn() { glyphs_new_due(steadies) })
  assert_true(changed[3].contains(" a0."), msg=changed[3])
  assert_eq(working_cells_made.val - made, 4)
  assert_eq(t.audit(), [])
}

///|
test "its agent's card opens over its picture under a pointer, as over a message's picture, and closes once the pointer has left it" {
  let live = Some(work_live("读 chat_rows.mbt"))
  let t = work_new(760.0, work_src(@signals.signal(live), []), fn() { work_view([work_agent_json()]) })
  t.run_for(@ui.move_most_ms)
  let shut = t.words().length()
  guard t.all(Button).filter(fn(s) { s.label.has_prefix("Claude：") }).last() is Some(line) else {
    fail("no line at work")
  }
  // (its picture: the line's start, the ring's room round it)
  let (x, y, _, h) = line.rect
  t.move_to(x + 15.0, y + h / 2.0)
  t.run_for(hover_open_ms * 2.0)
  assert_true(t.words().length() > shut, msg="its card over its picture")
  t.move_to(1.0, 1.0)
  t.run_for(hover_close_ms * 2.0)
  assert_eq(t.words().length(), shut, msg="closed")
  assert_eq(t.audit(), [])
}
