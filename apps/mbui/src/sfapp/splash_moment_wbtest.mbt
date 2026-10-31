// The splash says that the app waits, and for what, a second after the app's first splash (splash_label_ms): set at
// that moment by what lives through the app's states (splash_begin), so the app's state changing meanwhile keeps the
// moment, and it is said waited as that moment comes, a frame drawn or not; before it the ground alone. A failure says
// so at once.

///|
/// The home fixture, its accounts not read till `accounts` says (a signal, told as it changes, as the core's answer
/// is), its workspaces never read: the app starting, then signed in with no workspace in view yet, the splash saying
/// it reads them.
fn splash_src(accounts : @signals.Signal[Bool]) -> Source {
  let base = fixture("home")
  {
    ..base,
    topic: fn(name, params) {
      if name == "workspaces" {
        { value: None, error: None, version: 0 }
      } else if name == "accounts" {
        if accounts.get() {
          { ..(base.topic)(name, params), version: 1 }
        } else {
          { value: None, error: None, version: 0 }
        }
      } else {
        (base.topic)(name, params)
      }
    },
  }
}

///|
/// A moment either side of the splash's second (splash_label_ms), and when the accounts come meanwhile.
let splash_side : Double = 50.0

///|
let accounts_come : Double = splash_label_ms - 400.0

///|
/// Whether the splash says it reads the workspaces (signed in, none in view yet).
fn reads_workspaces(t : @ui.Tester) -> Bool {
  t.find(tr("android-misc.workspaces.loading")) is Some(_)
}

///|
test "the splash's words a second after the app's first splash, the accounts read 400 before it meanwhile: the ground alone just before, the workspaces' words just after, the window shown once then" {
  for w in [390.0, 1280.0] {
    new_run()
    let accounts = @signals.signal(false, same=fn(a, b) { a == b })
    let src = splash_src(accounts)
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=800.0, platform=2)
    let t0 = t.time()
    t.run_for(accounts_come)
    let starting = app_is(src) == Starting && frame_bare.val
    accounts.set(true)
    t.frame()
    t.run_for(t0 + splash_label_ms - splash_side - t.time())
    let before = (frame_bare.val, reads_workspaces(t), t.window_shows())
    t.run_for(t0 + splash_label_ms + splash_side - t.time())
    let after = (frame_bare.val, reads_workspaces(t), t.window_shows())
    // (the window held shown once, as the words come: not for the ground alone)
    assert_eq((starting, before, after), (true, (true, false, 0), (false, true, 1)), msg="at \{w}")
  }
}

///|
test "signed in from the start, the workspaces not read: the ground alone just before the second, their words just after" {
  new_run()
  let accounts = @signals.signal(true, same=fn(a, b) { a == b })
  let src = splash_src(accounts)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=800.0, platform=2)
  let t0 = t.time()
  t.run_for(splash_label_ms - splash_side)
  let bare = frame_bare.val && !reads_workspaces(t)
  t.run_for(t0 + splash_label_ms + splash_side - t.time())
  assert_eq((app_is(src) == SignedIn, bare, !frame_bare.val && reads_workspaces(t)), (true, true, true))
}

///|
test "the splash's second come with no frame drawn: said waited as it comes (an input then brings the tree to it), the frame after it shows the words and the window" {
  new_run()
  let src = splash_src(@signals.signal(false, same=fn(a, b) { a == b }))
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=800.0, platform=2)
  let t0 = t.time()
  t.run_for(splash_label_ms - splash_side)
  let before = (splash_waited.get(), t.window_shows())
  // (a touch on the bare ground past the second, as the host hands it on: nothing of a page under it, no frame drawn)
  let at = t0 + splash_label_ms + splash_side
  // (the host's clock there, no frame drawn)
  t.advance(at - t.time())
  t.touch_at(0, 200.0, 400.0, at)
  t.touch_at(2, 200.0, 400.0, at)
  let waited = splash_waited.get()
  t.frame()
  assert_eq(
    (before, waited, !frame_bare.val, t.window_shows(), t.built_why().contains("set again as it was built")),
    ((false, 0), true, true, 1, false),
  )
}

///|
test "the core failed: said at once, the ground not alone from the first frame" {
  new_run()
  let base = fixture("home")
  let src : Source = { ..base, fatal: fn() { Some("still.fail's core stopped") } }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=800.0, platform=2)
  t.frame()
  assert_eq((app_is(src) == Failed, !frame_bare.val, t.find("still.fail's core stopped") is Some(_)), (true, true, true))
}

///|
test "a run let go while its splash waits: what kept its moment let go with it; the next run, from the same moment, waits a second of its own past the first's" {
  new_run()
  let first = splash_src(@signals.signal(false, same=fn(a, b) { a == b }))
  let t1 = @ui.Tester::new(fn(c) { view(c, first) }, tree=app_tree(first), w=390.0, h=800.0, platform=2)
  let t1_0 = t1.time()
  t1.run_for(accounts_come)
  let owner = splash_owner.val
  let ended = t1.time()
  new_run()
  // (let go with the run: read before the next run's Tester is made, which lets go of what it finds too)
  let gone = match owner {
    Some(o) => !o.alive()
    None => false
  }
  let src = splash_src(@signals.signal(false, same=fn(a, b) { a == b }))
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=800.0, platform=2, time=ended)
  // (past where the first run's second ended, the next's not yet)
  t.run_for(t1_0 + splash_label_ms + splash_side - t.time())
  let past_first = (splash_waited.get(), frame_bare.val)
  t.run_for(ended + splash_label_ms + splash_side - t.time())
  assert_eq((gone, past_first, splash_waited.get(), !frame_bare.val), (true, (false, true), true, true))
}
