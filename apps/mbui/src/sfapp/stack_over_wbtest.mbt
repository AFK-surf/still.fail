// A page pushed over the page's own stack on the tape (Nav::push_over: a chat opened from the page in use) waits for what
// it shows, then slides in: from its causes' moments (pushed, answered, its wait over), whichever frames come between.

///|
let over_chat : ChatRef = { station: "ws1/st1", session: "s-c2", title: "首页的列表改成按天分组", station_name: "Studio" }

///|
/// The fixture's core, the chat opened over the page's view held back till `answered` (an event from outside: what reads
/// it told then, as the core's answer is), and each chat of `also`'s till its own; what else is asked answered as the
/// fixture does.
fn over_source(answered : @signals.Signal[Bool], also? : Array[(ChatRef, @signals.Signal[Bool])] = []) -> Source {
  let base = fixture("chat")
  let held : Map[String, @signals.Signal[Bool]] = {}
  for a in [(over_chat, answered), ..also] {
    held[Json::object(chat_params(a.0)).stringify()] = a.1
  }
  {
    ..base,
    topic: fn(name, params) {
      if name == "chat" && held.get(Json::object(params).stringify()).map(fn(a) { !a.get() }).unwrap_or(false) {
        return { value: None, error: None, version: 0 }
      }
      (base.topic)(name, params)
    },
  }
}

///|
/// 中屏 on the tape (a mouse's, 720 wide), the page in use; the chat opened over it at `t0`, an event of the window's
/// tree with no frame, its view given `late` after (an event of the tree's then, no frame: 0 there already as it is
/// opened, None never); frames at `t0 +` each of `frames`, then at `t0 + at`: where the chat opened is drawn across (-1:
/// not drawn), how deep the stack is; then back with no frame between: the chat on top, how deep, whether the page is
/// still in use.
fn over_seen(late : Double?, frames : Array[Double], at : Double) -> (Double, Int, String, Int, Bool) raise {
  new_run()
  let answered = @signals.signal(false)
  let src = over_source(answered)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=720.0, h=800.0, platform=0)
  t.draw()
  t.run_for(@ui.move_most_ms)
  page_over(t, 720.0)
  assert_eq((@sfdesk.wide.tape_at.get(), app.nav.depth()), (@sfdesk.TapePane::Page, 2))
  let tree = @ui.view_tree().unwrap()
  let t0 = t.time() + between_frames_ms
  t.advance(t0 - t.time())
  if late == Some(0.0) {
    answered.set(true)
  }
  tree.event(t0, fn() { @sfbase.open_page_over(Chat(over_chat)) })
  assert_true(app.nav.top() is Chat({ session: "s-c2", .. }) && app.nav.depth() == 3)
  // (its view given at its moment, before the frames after it)
  let given = fn(upto : Double) {
    match late {
      Some(l) if !answered.get() && t0 + l <= upto => {
        t.advance(t0 + l - t.time())
        tree.event(t0 + l, fn() { answered.set(true) })
      }
      _ => ()
    }
  }
  for f in frames {
    given(t0 + f)
    t.frame_at(t0 + f)
  }
  given(t0 + at)
  t.frame_at(t0 + at)
  let x = over_x(t, over_chat.title)
  let depth = app.nav.depth()
  t.back_raw(2, 0.0, t.time())
  let top = match app.nav.top() {
    Chat(r) => r.session
    _ => "other"
  }
  (x, depth, top, app.nav.depth(), @sfdesk.wide.tape_at.get() == @sfdesk.TapePane::Page)
}

///|
/// Where it is drawn at each of `ats`, frames all along, one just after it was opened, or none: the same.
fn over_same(late : Double?, ats : Array[Double]) -> Unit raise {
  for at in ats {
    let every = Array::makei((at / 16.0).to_int(), fn(i) { 16.0 * (i + 1).to_double() }).filter(fn(f) { f < at })
    let stepped = over_seen(late, every, at)
    let once = over_seen(late, [8.0].filter(fn(f) { f < at }), at)
    let jumped = over_seen(late, [], at)
    assert_eq(once, stepped, msg="at \{at}: one frame just after: \{once} stepped \{stepped}")
    assert_eq(jumped, stepped, msg="at \{at}: none: \{jumped} stepped \{stepped}")
    // (back the stack's: the chat over it off, the page under it on top, still in use)
    assert_eq((stepped.2, stepped.3, stepped.4), ("s-c1", 2, true), msg="at \{at}: back")
  }
}

///|
test "中屏: a chat opened over the page in use, its view there already: sliding in from the moment it was opened; where it is drawn at a moment the same whichever frames came between" {
  let rest = over_seen(Some(0.0), [], 600.0).0
  let sliding = over_seen(Some(0.0), [], 100.0).0
  assert_true(rest > 0.0 && sliding > rest && sliding < 720.0, msg="sliding in: \{sliding} (in place \{rest})")
  over_same(Some(0.0), [8.0, 100.0, 300.0])
}

///|
test "中屏: a chat opened over the page in use, its view given while it waits: not drawn till then; where it is drawn at a moment the same whichever frames came between" {
  assert_eq(over_seen(Some(120.0), [], 60.0).0, -1.0, msg="waiting for its view")
  over_same(Some(120.0), [60.0, 128.0, 220.0, 420.0])
}

///|
test "中屏: a chat opened over the page in use, its view later than its wait: not drawn while it waits, then sliding in from its wait's end; where it is drawn at a moment the same whichever frames came between" {
  let rest = over_seen(Some(0.0), [], 600.0).0
  assert_eq(over_seen(None, [], page_local_ms / 2.0).0, -1.0, msg="waiting for its view")
  let sliding = over_seen(None, [], page_local_ms + 60.0).0
  assert_true(sliding > rest && sliding < 720.0, msg="sliding in from its wait's end: \{sliding} (in place \{rest})")
  assert_eq(over_seen(None, [], page_local_ms + 600.0).0, rest, msg="in place")
  over_same(None, [page_local_ms / 2.0, page_local_ms + 60.0, page_local_ms + 300.0])
}

///|
test "中屏: a chat opened over the page in use, then back at once, no frame between: the chat taken off, the page under it on top, still in use" {
  new_run()
  let src = over_source(@signals.signal(true))
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=720.0, h=800.0, platform=0)
  t.draw()
  t.run_for(@ui.move_most_ms)
  page_over(t, 720.0)
  assert_eq((@sfdesk.wide.tape_at.get(), app.nav.depth()), (@sfdesk.TapePane::Page, 2))
  let t0 = t.time() + between_frames_ms
  t.advance(t0 - t.time())
  @ui.view_tree().unwrap().event(t0, fn() { @sfbase.open_page_over(Chat(over_chat)) })
  assert_eq(app.nav.depth(), 3)
  t.back_raw(2, 0.0, t0)
  let top = match app.nav.top() {
    Chat(r) => r.session
    _ => "other"
  }
  assert_eq((top, app.nav.depth(), @sfdesk.wide.tape_at.get()), ("s-c1", 2, @sfdesk.TapePane::Page))
}

///|
/// 中屏 on the tape (a mouse's, 720 wide), the page in use, its core `src`: the tester, the window's tree, and a moment
/// just after its last frame.
fn over_tape(src : Source) -> (@ui.Tester, @view.Tree, Double) raise {
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=720.0, h=800.0, platform=0)
  t.draw()
  t.run_for(@ui.move_most_ms)
  page_over(t, 720.0)
  assert_eq((@sfdesk.wide.tape_at.get(), app.nav.depth()), (@sfdesk.TapePane::Page, 2))
  (t, @ui.view_tree().unwrap(), t.time() + between_frames_ms)
}

///|
/// Where the chat titled `title` is drawn across, its title in its bar (-1: not drawn; not where the page under it says
/// it, as a link in a message, nor the sidebar's row of it).
fn over_x(t : @ui.Tester, title : String) -> Double {
  match t.locate(title).iter().filter(fn(p) { p.1 < @sf.wide_bar_h }).collect() {
    [p, ..] => p.0
    [] => -1.0
  }
}

///|
let third_chat : ChatRef = { station: "ws1/st1", session: "s-c3", title: "第三个对话", station_name: "Studio" }

///|
/// Events at their moments (ms after `t0`, in order), each before the frames at and after it; frames at `t0 +` each of
/// `frames`, then at `t0 + at`.
fn over_run(
  t : @ui.Tester,
  tree : @view.Tree,
  t0 : Double,
  events : Array[(Double, () -> Unit)],
  frames : Array[Double],
  at : Double,
) -> Unit {
  let mut k = 0
  for f in [..frames, at] {
    while k < events.length() && events[k].0 <= f {
      t.advance(t0 + events[k].0 - t.time())
      tree.event(t0 + events[k].0, events[k].1)
      k = k + 1
    }
    t.frame_at(t0 + f)
  }
}

///|
/// A chat opened over the page in use at `t0`, another over it at `t0 + 500` (events, no frame), neither's view given:
/// frames at `t0 +` each of `frames`, then at `t0 + at`: where the second is drawn across (-1: not drawn), how deep the
/// stack is.
fn over_two(frames : Array[Double], at : Double) -> (Double, Int) raise {
  new_run()
  let src = over_source(@signals.signal(false), also=[(third_chat, @signals.signal(false))])
  let (t, tree, t0) = over_tape(src)
  over_run(
    t,
    tree,
    t0,
    [(0.0, fn() { @sfbase.open_page_over(Chat(over_chat)) }), (500.0, fn() { @sfbase.open_page_over(Chat(third_chat)) })],
    frames,
    at,
  )
  (over_x(t, third_chat.title), app.nav.depth())
}

///|
test "中屏: a chat opened over the page in use, another over it while it waits: the second waits its own while, the first's wait over before it none of it; where it is drawn at a moment the same whichever frames came between" {
  for at in [page_local_ms + 200.0, page_local_ms + 600.0, page_local_ms + 1200.0] {
    let every = Array::makei((at / 16.0).to_int(), fn(i) { 16.0 * (i + 1).to_double() }).filter(fn(f) { f < at })
    let stepped = over_two(every, at)
    assert_eq(over_two([8.0], at), stepped, msg="at \{at}: one frame just after")
    assert_eq(over_two([], at), stepped, msg="at \{at}: none")
  }
  // (past the first's wait, not the second's: not drawn)
  assert_eq(over_two([], page_local_ms + 200.0), (-1.0, 4))
  let sliding = over_two([], page_local_ms + 600.0).0
  let rest = over_two([], page_local_ms + 1200.0).0
  assert_true(rest > 0.0 && sliding > rest, msg="from its own wait's end: \{sliding}, in place \{rest}")
}

///|
/// A chat opened over the page in use at `t0` (an event, no frame), its view not given, then back at `t0 + 20` (no
/// frame); its view given at `t0 + 50`; frames at `t0 +` each of `frames`, then at `t0 + page_local_ms + 100` (its wait
/// over by then): what is on top, how deep the stack is, where the chat opened is drawn across (-1: not drawn).
fn over_back_waiting(frames : Array[Double]) -> (String, Int, Double) raise {
  new_run()
  let answered = @signals.signal(false)
  let (t, tree, t0) = over_tape(over_source(answered))
  over_run(
    t,
    tree,
    t0,
    [
      (0.0, fn() { @sfbase.open_page_over(Chat(over_chat)) }),
      (20.0, fn() { t.back_raw(2, 0.0, t0 + 20.0) }),
      (50.0, fn() { answered.set(true) }),
    ],
    frames,
    page_local_ms + 100.0,
  )
  let top = match app.nav.top() {
    Chat(r) => r.session
    _ => "other"
  }
  (top, app.nav.depth(), over_x(t, over_chat.title))
}

///|
test "中屏: a chat opened over the page in use, back while it waits: nothing of it brought in after, whichever frames came between" {
  assert_eq(over_back_waiting([]), ("s-c1", 2, -1.0))
  assert_eq(over_back_waiting([8.0, 30.0, 60.0, 500.0]), ("s-c1", 2, -1.0))
  // (each frame drawn as it comes: nothing of it in any, the page under it in place)
  assert_eq(over_back_waiting(Array::makei(40, fn(i) { 16.0 * (i + 1).to_double() })), ("s-c1", 2, -1.0))
}

///|
/// A chat opened over the page in use while it waits for its view, then the window made 1280 wide at `t0 + 100` (the
/// frame off the tape's, 大屏) and 720 again at `t0 + 200` (the tape made anew), another chat opened over the page in
/// use then, neither's view given: where the second is drawn across at `t0 + page_local_ms + 100` (past the first's wait,
/// not its own), and at its own wait's end and 600 on.
fn over_left(frames : Bool) -> (Double, Double, String) raise {
  new_run()
  let src = over_source(@signals.signal(false), also=[(third_chat, @signals.signal(false))])
  let (t, tree, t0) = over_tape(src)
  t.advance(t0 - t.time())
  tree.event(t0, fn() { @sfbase.open_page_over(Chat(over_chat)) })
  t.frame_at(t0 + 100.0)
  t.resize(1280.0, 800.0)
  t.frame_at(t0 + 200.0)
  t.resize(720.0, 800.0)
  if @sfdesk.wide.tape_at.get() != @sfdesk.TapePane::Page {
    page_over(t, 720.0)
  }
  let t1 = t.time() + between_frames_ms
  assert_true(t1 < t0 + page_local_ms - 100.0, msg="opened before the first's wait is over: \{t1 - t0}")
  t.advance(t1 - t.time())
  tree.event(t1, fn() { @sfbase.open_page_over(Chat(third_chat)) })
  if frames {
    let mut f = t1 + 16.0
    while f < t0 + page_local_ms + 100.0 {
      t.frame_at(f)
      f = f + 16.0
    }
  }
  t.frame_at(t0 + page_local_ms + 100.0)
  let before = over_x(t, third_chat.title)
  t.frame_at(t1 + page_local_ms + 600.0)
  let top = match app.nav.top() {
    Chat(r) => r.session
    _ => "other"
  }
  // (what stands then, for what is said of it when it is not as it should be)
  let stands = "\{top} \{app.nav.depth()} over \{app.nav.top_over()} \{@sfdesk.wide.tape_at.get()} at \{t1 - t0}"
  (before, over_x(t, third_chat.title), stands)
}

///|
test "中屏: a chat opened over the page in use, the tape left and made anew while it waits: its wait gone with the tape, none of it bringing in what is opened over the page after" {
  for frames in [false, true] {
    let (before, after, stands) = over_left(frames)
    assert_eq(before, -1.0, msg="frames \{frames}: past the first's wait, not its own (\{stands})")
    assert_true(after > 0.0, msg="frames \{frames}: shown after its own (\{stands})")
  }
}

///|
/// 中屏 on the tape, the side panel in use (`from_panel`) or the sidebar: a chat opened from there at `t0` (an event, no
/// frame), its view not given; the page's edge pressed at `t0 + 50` (a finger down and up then, as a host hands them on,
/// no frame), the page asked over: which is in use before, as it is pressed, at `t0 + 350` (frames from then), and once
/// its view is given (at `t0 + 400`) and the tape's move had its while.
fn over_brought(from_panel : Bool) -> (
  @sfdesk.TapePane,
  @sfdesk.TapePane,
  @sfdesk.TapePane,
  @sfdesk.TapePane,
) raise {
  new_run()
  let answered = @signals.signal(false)
  let src = over_source(answered)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=720.0, h=800.0, platform=0)
  t.draw()
  t.run_for(@ui.move_most_ms)
  page_over(t, 720.0)
  if from_panel {
    tap_said(t, "打开侧栏")
    t.leave()
    t.run_for(@ui.move_most_ms)
  } else {
    // (back from the page in use, its stack's first: the sidebar comes over)
    t.back()
    t.run_for(@ui.move_most_ms)
  }
  let start = @sfdesk.wide.tape_at.get()
  assert_eq(start, if from_panel { @sfdesk.TapePane::Panel } else { @sfdesk.TapePane::Side })
  assert_true(app.nav.top() is Chat({ session: "s-c1", .. }), msg="the chat before on top")
  let depth = app.nav.depth()
  let tree = @ui.view_tree().unwrap()
  let t0 = t.time() + between_frames_ms
  t.advance(t0 - t.time())
  tree.event(t0, fn() { @sfbase.open_page_over(Chat(over_chat)) })
  assert_true(app.nav.top() is Chat({ session: "s-c2", .. }), msg="the chat opened on top")
  // (over the page, wherever it is opened from: a chat opened from a chat, Shell's open_over)
  assert_eq((app.nav.depth(), app.nav.top_over()), (depth + 1, true))
  // (the page's edge: beside the system's column at the window's left beside the panel in use, at its right beside the sidebar)
  let x = if from_panel {
    @sfdesk.tape_col_now(t.time()) + @sfdesk.tape_shows / 2.0
  } else {
    720.0 - @sfdesk.tape_shows / 2.0
  }
  t.advance(t0 + 50.0 - t.time())
  t.touch_raw(0, 1, x, 400.0, t0 + 50.0)
  t.touch_raw(2, 1, x, 400.0, t0 + 50.0)
  let asked = @sfdesk.wide.tape_at.get()
  t.frame_at(t0 + 350.0)
  let waiting = @sfdesk.wide.tape_at.get()
  t.advance(t0 + 400.0 - t.time())
  tree.event(t0 + 400.0, fn() { answered.set(true) })
  t.run_for(@ui.move_most_ms * 2.0)
  (start, asked, waiting, @sfdesk.wide.tape_at.get())
}

///|
test "中屏: a chat opened from the side panel or the sidebar, the page asked over while it waits for its view: the page brought over once it shows it, not before" {
  let (panel, side, page) = (@sfdesk.TapePane::Panel, @sfdesk.TapePane::Side, @sfdesk.TapePane::Page)
  assert_eq(over_brought(true), (panel, panel, panel, page))
  assert_eq(over_brought(false), (side, side, side, page))
}
