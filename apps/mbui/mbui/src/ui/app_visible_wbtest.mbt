// Whether the app is shown, in front, going on (app_visible, app_focused, app_awake), as the host says it (on_app_state,
// an event at its own moment): what reads it in the window's tree, a binding or a `reacts`, told at that moment, at any
// frame rate, and only what reads the one that changed; nothing drawn for it while nothing changes.

///|
/// How long the test runs before the host says anything (any while), and between two things the host says (past what
/// a frame drawn for the last needs, at the slowest rate).
let app_said_before : Double = 100.0

///|
let app_said_between : Double = 400.0

///|
/// A tree whose words read whether the app is shown, and whose `reacts` keep what each of the three said and when.
fn app_said_tree(
  shown : Array[(Bool, Double)],
  front : Array[(Bool, Double)],
  on : Array[(Bool, Double)],
) -> Unit {
  set_view_app(fn(root) {
    root.box(fn(n) {
      n.words(By(fn() { if app_visible() { "shown" } else { "hidden" } })) |> ignore
      n.reacts(fn() { app_visible() }, fn(v) { shown.push((v, n.cause_at())) }, at_start=false)
      n.reacts(fn() { app_focused() }, fn(v) { front.push((v, n.cause_at())) }, at_start=false)
      n.reacts(fn() { app_awake() }, fn(v) { on.push((v, n.cause_at())) }, at_start=false)
    })
    |> ignore
  })
}

///|
test "the app hidden and shown again: what reads it in the tree told at the moment the host said it, at any rate; only what changed" {
  let shown = []
  let front = []
  let on = []
  let t = Tester::new(fn(_c) {  })
  app_said_tree(shown, front, on)
  t.run_for(app_said_before)
  assert_true(t.find("shown") is Some(_))
  // put behind another app's window: shown, not in front
  let behind = t.time()
  on_app_state(1)
  t.run_for(app_said_between)
  assert_eq(shown, [])
  assert_eq(front, [(false, behind)])
  assert_eq(on, [])
  // hidden (a phone's app gone to the background)
  let hidden = t.time()
  on_app_state(0)
  t.run_for(app_said_between)
  assert_eq(shown, [(false, hidden)])
  assert_eq(on, [(false, hidden)])
  assert_true(t.find("hidden") is Some(_))
  // shown and in front again
  let back = t.time()
  on_app_state(3)
  t.run_for(app_said_between)
  assert_eq(shown, [(false, hidden), (true, back)])
  assert_eq(front, [(false, behind), (true, back)])
  assert_eq(on, [(false, hidden), (true, back)])
  assert_true(t.find("shown") is Some(_))
  t.assert_idle()
}

///|
/// While the host says nothing: the app asks for no frame. The one frame `run_for` draws at its end is the run's own,
/// the moment it looks at (tester_time.mbt's run_for: its last `frame_at` is `end`'s whatever is asked); on the way it
/// draws one only as the app asks (Tester::asks_frames) or something is due, and a frame asked for is drawn at its
/// moment first (`draw_owed`). So one more than that end's frame, a frame asked between frames (at_rest) or one for
/// what moves on by the clock (frames_on) is one the app asked for.
fn app_says_nothing(t : Tester) -> Unit raise {
  assert_true(t.at_rest(), msg=t.rest_why())
  let on = t.frames_on()
  let drawn = t.ctx().frame_no
  t.run_for(app_said_between)
  assert_eq(t.ctx().frame_no, drawn + 1)
  assert_true(t.at_rest(), msg=t.rest_why())
  assert_eq(t.frames_on(), on)
}

///|
test "while the host says nothing, what reads whether the app is shown asks for no frame" {
  let shown = []
  let t = Tester::new(fn(_c) {  })
  app_said_tree(shown, [], [])
  t.run_for(app_said_before)
  app_says_nothing(t)
  on_app_state(0)
  t.run_for(app_said_between)
  app_says_nothing(t)
  // the host saying it again as it was: nothing that reads it told (a frame comes for what the host said all the same,
  // as for any of its words: on_app_state_now takes it as an input)
  on_app_state(0)
  t.run_for(app_said_between)
  assert_eq(shown.length(), 1)
  app_says_nothing(t)
  on_app_state(3)
  t.run_for(app_said_between)
  assert_eq(shown.length(), 2)
  app_says_nothing(t)
}
