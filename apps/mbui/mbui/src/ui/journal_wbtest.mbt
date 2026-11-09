// The window thread's journal and the hangs found in it (journal.mbt): what is kept, where an interval closes, the
// three rules, and that a Tester's own clock finds none.

///|
fn journal_scene(c : Ctx) -> Unit {
  c.box(w=Fill(1.0), h=Fill(1.0), fn() { c.text("日志", wrap=false) |> ignore }) |> ignore
}

///|
/// A Tester begun, its journal emptied, the work clock the test's from 1000 ms.
fn journal_start() -> (Tester, Ref[Double]) {
  let t = Tester::new(journal_scene)
  journal_reset()
  let clock = Ref(1000.0)
  set_work_clock(Some(fn() { clock.val }))
  (t, clock)
}

///|
test "under a Tester's own clock its frames and events are journaled, and take no time: no hang" {
  let t = Tester::new(journal_scene)
  t.draw()
  view_event_said(fn() {  }, fn() {  }, what="touch-up")
  t.frame(ms=first_frame_ms)
  t.frame(ms=first_frame_ms)
  assert_eq(hangs(), [])
  let j = journal()
  assert_true(j.any(fn(e) { e is Work({ what: Frame(_), .. }) }), msg=j.to_string())
  assert_true(j.any(fn(e) { e is Boundary(Presented, _) }))
  // (an event of no time is folded, as what comes often)
  assert_true(j.any(fn(e) { e is Work({ what: Small(_, _), .. }) }))
}

///|
test "one piece of work at least the stall's length is a hang, closed as the thread goes idle" {
  let (_, clock) = journal_start()
  defer set_work_clock(None)
  let told : Array[Hang] = []
  hangs_told(Some(fn(h) { told.push(h) }))
  view_event_said(fn() {  }, fn() { clock.val += 60.0 }, what="touch-up")
  assert_eq(told.length(), 1)
  let h = told[0]
  assert_eq(h.trigger, Stall)
  assert_eq(h.sealed_by, Idle)
  assert_true(h.startup)
  assert_eq(h.contributors, [{ what: Event("touch-up"), start: 1000.0, end: 1060.0, notes: [] }])
  assert_eq(h.stall_ms, 60.0)
  assert_eq(hangs(), told)
  // (its line names its rule and what made it, nothing of what the event carried)
  assert_true(h.said().has_prefix("trigger=stall sealed=idle phase=startup active=60ms stall=60ms "), msg=h.said())
  assert_true(h.said().contains("by: touch-up 60ms"), msg=h.said())
}

///|
test "what a piece went on, by part, kept with it the longest first: in its hang's line and JSON, a part under 1 ms not" {
  let (_, clock) = journal_start()
  defer set_work_clock(None)
  let told : Array[Hang] = []
  hangs_told(Some(fn(h) { told.push(h) }))
  view_event_said(fn() {  }, fn() {
    @hostapi.work_part(fn() { "core topic chats value" }, fn() { clock.val += 20.0 })
    @hostapi.work_part(fn() { "core topic chat delta" }, fn() { clock.val += 0.5 })
    @hostapi.work_part(fn() { "part a.mbt:1" }, fn() { clock.val += 30.0 })
    @hostapi.work_part(fn() { "core topic chats value" }, fn() { clock.val += 15.0 })
  }, what="messages")
  assert_eq(told.length(), 1)
  let w = told[0].contributors[0]
  assert_eq(w.notes, [("core topic chats value", 35.0), ("part a.mbt:1", 30.0)])
  assert_true(told[0].said().contains("messages 65.5ms on core topic chats value 35ms, part a.mbt:1 30ms"), msg=told[0].said())
  let json = told[0].json().stringify()
  assert_true(json.contains("\"parts\":[{\"part\":\"core topic chats value\",\"ms\":35}"), msg=json)
  // (the next piece begins with none)
  view_event_said(fn() {  }, fn() { clock.val += 60.0 }, what="touch-up")
  assert_eq(told[1].contributors[0].notes, [])
}

///|
test "an event and the frame it asked for, each under the budget, together over it: a late frame" {
  let (_, clock) = journal_start()
  defer set_work_clock(None)
  // the event asks for a frame (h_request_frame): the interval waits on it from then, not closed as the event ends
  view_event_said(fn() {  }, fn() {
    clock.val += 15.0
    h_request_frame()
  }, what="key")
  assert_eq(journal_dirty_at.val, 1015.0)
  assert_false(journal().any(fn(e) { e is Boundary(_, _) }))
  journal_work(Frame({ tree: 0.0, messages: 0.0, build: 12.0, layout: 1.0, paint: 1.0, nodes: 3, insts: 9, why: "built" }), 1020.0, 1034.0)
  journal_work(Present, 1034.0, 1035.0)
  journal_seal(Presented, 1035.0)
  let h = hangs()
  assert_eq(h.length(), 1, msg=h.to_string())
  assert_eq(h[0].trigger, LateFrame)
  assert_eq(h[0].sealed_by, Presented)
  assert_eq(h[0].start, 1000.0)
  assert_eq(h[0].work_ms, 30.0)
  assert_eq(h[0].contributors.map(fn(w) { w.what.name() }), ["key", "frame", "present"])
}

///|
test "a frame whose work is under its budget is no hang, however long since it was asked for" {
  let (_, _) = journal_start()
  defer set_work_clock(None)
  journal_dirty_at.val = 1000.0
  journal_work(Frame({ tree: 0.0, messages: 0.0, build: 8.0, layout: 1.0, paint: 1.0, nodes: 3, insts: 9, why: "" }), 1200.0, 1210.0)
  journal_work(Present, 1210.0, 1211.0)
  journal_seal(Presented, 1211.0)
  assert_eq(hangs(), [])
}

///|
test "closed with no frame, one piece at least the budget is blocking work; under it, none" {
  let (_, clock) = journal_start()
  defer set_work_clock(None)
  view_event_said(fn() {  }, fn() { clock.val += 20.0 }, what="host")
  assert_eq(hangs(), [])
  view_event_said(fn() {  }, fn() { clock.val += 30.0 }, what="messages")
  let h = hangs()
  assert_eq(h.length(), 1)
  assert_eq(h[0].trigger, Blocking)
  assert_eq(h[0].contributors.map(fn(w) { w.what.name() }), ["messages"])
}

///|
test "short events are folded, their count and work kept, and still count toward a frame's budget" {
  let (_, _) = journal_start()
  defer set_work_clock(None)
  for i in 0..<40 {
    let s = 1000.0 + i.to_double()
    journal_work(Event("touch-move"), s, s + 0.5)
  }
  journal_work(Frame({ tree: 0.0, messages: 0.0, build: 4.0, layout: 0.0, paint: 1.0, nodes: 1, insts: 1, why: "" }), 1040.0, 1045.0)
  journal_seal(Presented, 1045.0)
  let j = journal()
  assert_eq(j[0], Work({ what: Small(40, 20.0), start: 1000.0, end: 1039.5, notes: [] }))
  let h = hangs()
  assert_eq(h.length(), 1)
  assert_eq(h[0].trigger, LateFrame)
  assert_eq((h[0].small, h[0].small_ms, h[0].work_ms), (40, 20.0, 25.0))
}

///|
test "a frame's interval closes as it is presented; asked for again as it ends, the next is waited on from there" {
  let (t, clock) = journal_start()
  defer set_work_clock(None)
  t.draw()
  let j = journal()
  assert_true(j.any(fn(e) { e is Boundary(Presented, 1000.0) }), msg=j.to_string())
  // a frame asked for between frames: waited on from then
  clock.val = 1100.0
  h_request_frame()
  assert_eq(journal_dirty_at.val, 1100.0)
  t.draw()
  // presented: none waited on, unless the frame asked for another as it ran
  assert_true(journal_dirty_at.val < 0.0 || journal_dirty_at.val == 1100.0, msg=journal_dirty_at.val.to_string())
}

///|
test "an interval whose beginning the ring let go judges no budget, and says what it lost" {
  let (_, _) = journal_start()
  defer set_work_clock(None)
  for i in 0..<(journal_cap + 10) {
    let s = 1000.0 + i.to_double() * 2.0
    journal_work(Present, s, s + 0.02)
  }
  journal_seal(Presented, 1000.0 + (journal_cap + 10).to_double() * 2.0)
  assert_eq(hangs(), [])
  assert_eq(journal().length(), journal_cap)
}

///|
test "the app hidden closes its interval, and what it did while shown is said" {
  let (t, clock) = journal_start()
  defer set_work_clock(None)
  let said : Array[HangSummary] = []
  hang_summary_told(Some(fn(s) { said.push(s) }))
  view_event_said(fn() {  }, fn() { clock.val += 60.0 }, what="touch-up")
  t.draw()
  clock.val += 1000.0
  view_event_said(fn() {  }, fn() { journal_hidden.val = true }, what="app-state")
  assert_eq(said.length(), 1)
  assert_eq(said[0].stalls, 1)
  assert_eq(said[0].frames, 1)
  assert_eq(said[0].shown_ms, 1060.0)
  assert_true(journal().any(fn(e) { e is Boundary(Hidden, _) }))
}

///|
test "of a frame's why, the code it names alone: no key of what is shown" {
  assert_eq(
    journal_places("the clock read at @mbui/src/sf:motion.mbt:12:3-12:20 (row:chat-01HX, told at page.mbt:40)"),
    " @mbui/src/sf:motion.mbt:12:3-12:20 page.mbt:40",
  )
  assert_eq(journal_places("what it read changed"), "")
}

///|
test "a hang as JSON: its rule, times from its start, each contributor's kind and a frame's parts" {
  let (_, _) = journal_start()
  defer set_work_clock(None)
  journal_work(Frame({ tree: 1.0, messages: 2.0, build: 50.0, layout: 3.0, paint: 4.0, nodes: 7, insts: 8, why: "built a.mbt:1" }), 1000.0, 1060.0)
  journal_seal(Presented, 1061.0)
  let j = hangs()[0].json().stringify()
  assert_true(j.contains("\"trigger\":\"stall\""), msg=j)
  assert_true(j.contains("\"kind\":\"frame\"") && j.contains("\"build_ms\":50") && j.contains("\"why\":\"built a.mbt:1\""), msg=j)
}

///|
test "many short parts of a kind, each under 1 ms, summed: what a burst of messages went on is kept" {
  let (_, clock) = journal_start()
  defer set_work_clock(None)
  let told : Array[Hang] = []
  hangs_told(Some(fn(h) { told.push(h) }))
  view_event_said(fn() {  }, fn() {
    for _ in 0..<200 {
      @hostapi.work_part(fn() { "core topic chat delta" }, fn() { clock.val += 0.3 })
    }
  }, what="messages")
  assert_eq(told.length(), 1)
  assert_eq(told[0].contributors[0].notes.length(), 1)
  let (part, ms) = told[0].contributors[0].notes[0]
  assert_eq(part, "core topic chat delta")
  assert_true(ms > 59.9 && ms < 60.1, msg=ms.to_string())
}
