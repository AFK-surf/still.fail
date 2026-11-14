// The window's runtime runs its timers and fibers as a frame begins, outside the frame's reading (fx_frame_start): what
// they read is not the frame's to follow, what they change is drawn by that frame, an effect they make is their own.
// Each case with the Tester's looks compared no more (check_looks(false)): that frame read again over the frame's
// watch would leave it following what it read itself (tester_looks.mbt), which is not a device's way.

///|
/// How long a Tester runs before the timer is set, and how long after its moment the signal it read is set.
let fx_untracked_before_ms : Double = 100.0

///|
let fx_untracked_after_ms : Double = 400.0

///|
/// The timer's wait (and the fiber's sleep), in the runtime's whole ms.
let fx_untracked_wait_ms : Int = 50

///|
/// How a signal `s` is read: in a timer's callback, in a fiber after a sleep, or as the frame is built (an old view's
/// build: what the frame's watch is for).
priv enum FxRead {
  InTimer
  InFiber
  InBuild
}

///|
/// A Tester (the window's tree, or an old view) where `s` is read as `read` says, the read done; then `s` set: why the
/// frame after it was built whole ("" none), and whether the read was done.
fn fx_read_then_set(read : FxRead, nodes : Bool) -> (String, Bool) {
  let s : @signals.Signal[Int] = @signals.signal(0)
  let done = Ref(false)
  let t = if nodes {
    let t = Tester::new(fn(_c) {  }, w=200.0, h=200.0)
    set_view_app(fn(root) { root.box(fn(b) { b.words(Is("x")) |> ignore }) |> ignore })
    t.draw()
    t
  } else {
    Tester::new(
      fn(c) {
        if read is InBuild {
          s.get() |> ignore
          done.val = true
        }
        c.text("x", wrap=false) |> ignore
      },
      w=200.0,
      h=200.0,
    )
  }
  t.check_looks(false)
  t.run_for(fx_untracked_before_ms)
  match read {
    InTimer =>
      runtime().after(fx_untracked_wait_ms, fn() {
        s.get() |> ignore
        done.val = true
      })
    InFiber =>
      runtime().fork(async fn() {
        @effect.sleep(fx_untracked_wait_ms)
        s.get() |> ignore
        done.val = true
      })
      |> ignore
    InBuild => ()
  }
  t.run_for(fx_untracked_after_ms)
  s.set(1)
  t.frame()
  (t.built_why(), done.val)
}

///|
test "a signal read in a timer's callback, set later: no frame built whole for it" {
  assert_eq(fx_read_then_set(InTimer, true), ("", true))
  assert_eq(fx_read_then_set(InTimer, false), ("", true))
}

///|
test "a signal read in a fiber of the window's runtime, set later: no frame built whole for it" {
  assert_eq(fx_read_then_set(InFiber, true), ("", true))
  assert_eq(fx_read_then_set(InFiber, false), ("", true))
}

///|
test "a signal read as an old view is built, set later: the next frame built whole for it" {
  let (why, done) = fx_read_then_set(InBuild, false)
  assert_true(done)
  assert_true(why.contains("what it read changed"), msg=why)
}

///|
/// An effect made in a timer's callback is the callback's, never the frame's: the frames after it built whole (by
/// what the old view's build reads, `k`), it is still there, run again as what it reads (`s`) changes; never told as
/// made in a watch (@signals.effect_in_watch).
test "an effect made in a timer's callback lives past the frames built whole after it, following what it reads" {
  let s : @signals.Signal[Int] = @signals.signal(0)
  let k : @signals.Signal[Int] = @signals.signal(0)
  let seen : Array[Int] = []
  let told : Array[String] = []
  let was = @signals.effect_in_watch.val
  @signals.effect_in_watch.val = Some(fn(loc) { told.push(loc.to_string()) })
  let t = Tester::new(fn(c) { c.text("k \{k.get()}", wrap=false) |> ignore }, w=200.0, h=200.0)
  t.check_looks(false)
  t.run_for(fx_untracked_before_ms)
  let stop : Ref[() -> Unit] = Ref(fn() {  })
  runtime().after(fx_untracked_wait_ms, fn() { stop.val = @signals.effect(fn() { seen.push(s.get()) }) })
  t.run_for(fx_untracked_after_ms)
  k.set(1)
  t.frame()
  let why = t.built_why()
  s.set(5)
  (stop.val)()
  s.set(6)
  @signals.effect_in_watch.val = was
  assert_true(why.contains("what it read changed"), msg=why)
  assert_eq(told, [])
  // (made, run at once; run again for 5; stopped by its maker before 6)
  assert_eq(seen, [0, 5])
}

///|
/// What a timer's callback changes is drawn by the frame it fires in, the view reading it after (the window's tree's
/// binding, an old view's build).
fn fx_set_drawn_at_once(nodes : Bool) -> Array[String] {
  let label : @signals.Signal[String] = @signals.signal("before")
  let t = if nodes {
    let t = Tester::new(fn(_c) {  }, w=200.0, h=200.0)
    set_view_app(fn(root) {
      root.box(fn(b) { b.words(By(fn() { label.get() })) |> ignore }) |> ignore
    })
    t.draw()
    t
  } else {
    Tester::new(fn(c) { c.text(label.get(), wrap=false) |> ignore }, w=200.0, h=200.0)
  }
  t.check_looks(false)
  t.run_for(fx_untracked_before_ms)
  let fired = Ref(false)
  // (the words each frame drew from the one the timer fired in on)
  let drawn : Array[String] = []
  t.each_frame(
    Some(fn() {
      if fired.val {
        drawn.push(t.words().map(fn(w) { w.0 }).join(" "))
      }
    }),
  )
  runtime().after(fx_untracked_wait_ms, fn() {
    label.set("after")
    fired.val = true
  })
  t.run_for(fx_untracked_after_ms)
  t.each_frame(None)
  drawn
}

///|
test "what a timer's callback sets is drawn by the frame it fires in" {
  let tree = fx_set_drawn_at_once(true)
  assert_true(tree.length() > 0)
  assert_eq(tree[0], "after")
  let old = fx_set_drawn_at_once(false)
  assert_true(old.length() > 0)
  assert_eq(old[0], "after")
}
