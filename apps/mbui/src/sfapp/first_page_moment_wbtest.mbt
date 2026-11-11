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
      // (the switch read only by what reads those: one read by every topic's reader tells each of them as it is set,
      // as nothing on a device does)
      if (name == "chats" || name == "workspaceMarks") && slow.get() {
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

///|
/// The home fixture, its topic `gate` (the workspaces, or the prefs: which of them is in view) not answered while
/// `unseen` (no workspace in view) and the chats' list and the
/// workspaces' marks while `slow`, what is let go of kept with the moment it was (`let_go`).
fn first_unseen_src(
  gate : String,
  unseen : @signals.Signal[Bool],
  slow : @signals.Signal[Bool],
  let_go : Array[(String, Double)],
  now : () -> Double,
) -> Source {
  let base = first_slow_src(slow, let_go, now)
  {
    ..base,
    topic_read: fn(name, params) {
      if name == gate && unseen.get() {
        return { value: None, error: None, version: 0 }
      }
      (base.topic_read)(name, params)
    },
  }
}

///|
test "what the first page shows answered in the moment the workspace comes into view, between frames: the core's status let go of then, not a frame after, on every screen" {
  // (小屏, 中屏, 大屏: the first page's check reads what its shell declares at that moment, none of it followed
  // before; read before it was, it was told of none of it and waited for the frame after)
  let cases = [
    ("workspaces", 390.0),
    ("workspaces", @sf.medium_from + 100.0),
    ("workspaces", @sf.large_from + 440.0),
    ("prefs", 390.0),
    ("prefs", @sf.large_from + 440.0),
  ]
  // (a host's frames at each rate, as a device's: none at the answer's moment, the next a frame's length on at most)
  for period in [1000.0 / 7.0, 1000.0 / 24.0, 1000.0 / 60.0, 1000.0 / 120.0] {
    for k in cases {
      let (gate, w) = k
      new_run()
      let unseen = @signals.signal(true)
      let slow = @signals.signal(true)
      let let_go : Array[(String, Double)] = []
      let t_ref : Ref[@ui.Tester?] = Ref(None)
      let src = first_unseen_src(gate, unseen, slow, let_go, fn() { t_ref.val.map(fn(t) { t.time() }).unwrap_or(0.0) })
      let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=844.0, platform=2)
      t_ref.val = Some(t)
      t.run_for(first_slow_ms)
      assert_true(first_from.val < 0.0, msg="no workspace in view yet at \{w} (\{gate}, a frame each \{period} ms)")
      t.set_frame_period(period)
      // between two frames, at every rate: `gate` answered (the workspace in view, what its first page shows asked),
      // then, later and before the next frame, the rest of what it shows: the chats' list and the workspace's marks
      // (which say the page the wide frame's pane lands on: what that reads declared only as they are answered)
      let at = t.time() + first_between_ms
      let last = at + first_later_ms
      let read_before : Ref[Bool] = Ref(false)
      t.fake.due(at, "the workspace's \{gate} answered", fn() { unseen.set(false) })
      t.fake.due(last, "what the first page shows answered", fn() {
        read_before.val = !let_go.iter().any(fn(g) { g.0 == "status {}" })
        slow.set(false)
      })
      t.run_for(first_page_ms)
      assert_eq(first_from.val, at, msg="in view at its moment at \{w} (\{gate}, a frame each \{period} ms)")
      assert_true(read_before.val, msg="status read while the chats are not at \{w} (\{gate}, a frame each \{period} ms)")
      let status = let_go.filter(fn(g) { g.0 == "status {}" })
      assert_eq(status.length(), 1, msg="status let go of once at \{w} (\{gate}, a frame each \{period} ms)")
      assert_eq(status[0].1, last, msg="at the moment what the first page shows was answered (\{last}), not \{status[0].1}, at \{w} (\{gate}, a frame each \{period} ms)")
      assert_true(first_shown.get(), msg="shown at \{w} (\{gate}, a frame each \{period} ms)")
      // (and no fault said: a read of what the shell's function does not say stops the run, faults_stop)
      // (what the first page read held till its readers took it: none of it let go of and asked again)
      assert_eq(let_go.filter(fn(g) { g.0 != "status {}" }).length(), 0, msg="nothing else let go of at \{w} (\{gate}, a frame each \{period} ms): \{@ui.list_text(let_go.map(fn(g) { g.0 }))}")
    }
  }
}

///|
/// A moment after a host's frame and short of the next at any rate of frames tested (7 to 120 a second): between two.
let first_between_ms : Double = 5.0

///|
/// How long after the workspace comes into view the rest of what the first page shows is answered, before the next
/// frame at any rate tested (5 + 2 ms, short of 120 a second's 8.33).
let first_later_ms : Double = 2.0
