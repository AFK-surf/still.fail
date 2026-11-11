// The first page's wait ends at the moment its cause comes, not as a frame after it finds it (app.mbt's
// first_page_node): `first_page_ms` after the workspace came into view where what it shows never comes; and the core's
// status, read for the splash's words over it, let go of at the moment what the first page shows is answered.

///|
/// The home fixture, the chats' list and the workspaces' marks not answered while `slow`, what is let go of kept with
/// the moment it was (`let_go`).
fn first_slow_src(slow : @signals.Signal[Bool], let_go : Array[(String, Double)], now : () -> Double) -> Source {
  let base = fixture("home")
  {
    ..base,
    topic_read: fn(name, params) {
      if slow.get() && (name == "chats" || name == "workspaceMarks") {
        return { value: None, error: None, version: 0 }
      }
      base.topic(name, params).get().snapshot()
    },
    release: fn(name, params) {
      let_go.push((name + " " + Json::object(params).stringify(), now()))
      (base.release)(name, params)
    },
  }
}

///|
/// A moment short of another, a test's step there and back.
let first_short_ms : Double = 1.0

///|
test "what the first page shows never come: shown first_page_ms after the workspace came into view, at that moment, at any rate of frames" {
  for w in [390.0, 1280.0] {
    new_run()
    let slow = @signals.signal(true)
    let t_ref : Ref[@ui.Tester?] = Ref(None)
    let src = first_slow_src(slow, [], fn() { t_ref.val.map(fn(t) { t.time() }).unwrap_or(0.0) })
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=800.0, platform=0)
    t_ref.val = Some(t)
    let from = first_from.val
    assert_true(from >= 0.0, msg="the wait begun at \{w}")
    t.run_for(from + first_page_ms - first_short_ms - t.time())
    assert_true(!first_shown.get(), msg="not shown just before at \{w}")
    t.run_for(first_short_ms)
    assert_true(first_shown.get(), msg="shown at its moment at \{w}")
    assert_true(!@sfbase.first_page_waits.get(), msg="its splash gone then at \{w}")
  }
}

///|
test "the core's status, read for the splash's words over the first page, let go of at the moment what the page shows is answered, no frame waited for" {
  new_run()
  let slow = @signals.signal(true)
  let let_go : Array[(String, Double)] = []
  let t_ref : Ref[@ui.Tester?] = Ref(None)
  let src = first_slow_src(slow, let_go, fn() { t_ref.val.map(fn(t) { t.time() }).unwrap_or(0.0) })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t_ref.val = Some(t)
  t.run_for(first_slow_ms)
  assert_true(@sfbase.first_page_waits.get(), msg="waiting")
  assert_true(!let_go.iter().any(fn(g) { g.0 == "status {}" }), msg="status still read")
  // answered between frames: status let go of then, before any frame after it
  let at = t.time()
  slow.set(false)
  let status = let_go.filter(fn(g) { g.0 == "status {}" })
  assert_eq(status.length(), 1)
  assert_eq(status[0].1, at)
}

///|
/// How long what the first page shows is not answered in the test above: short of first_page_ms.
let first_slow_ms : Double = splash_label_ms - 200.0

///|
test "a chat opened over the first page before what it shows is answered: status let go of at the moment the first page's is, not the chat's" {
  new_run()
  let slow = @signals.signal(true)
  let let_go : Array[(String, Double)] = []
  let t_ref : Ref[@ui.Tester?] = Ref(None)
  let home = first_slow_src(slow, let_go, fn() { t_ref.val.map(fn(t) { t.time() }).unwrap_or(0.0) })
  // (the chat answered later than what the first page shows: never, here)
  let src = {
    ..home,
    topic_read: fn(name, params) {
      if name == "chat" {
        return { value: None, error: None, version: 0 }
      }
      (home.topic_read)(name, params)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t_ref.val = Some(t)
  t.run_for(first_slow_ms)
  // (a chat tapped on what shows of it: its own page waits for the chat too)
  @sfbase.open_page(Chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }))
  t.run_for(first_short_ms)
  assert_true(!let_go.iter().any(fn(g) { g.0 == "status {}" }), msg="status still read")
  let at = t.time()
  slow.set(false)
  let status = let_go.filter(fn(g) { g.0 == "status {}" })
  assert_eq(status.length(), 1)
  assert_eq(status[0].1, at)
}
