// A way said once as it sets out (way.mbt): where it is at a moment a function of what it was told and that moment
// alone, whatever frames were drawn or sampled ahead of what has happened.

///|
/// A way from 0 to 1 over `way_ms` set out at `set_out_at`, a frame drawn at `ahead` first (none: -1), then sent back to
/// 0 at `back_at` (a cause come before that frame's moment, as an input handed on late): where it is at each of
/// `looks`, and when it ends.
fn sent_back(ahead : Double) -> (Array[Double], Double) {
  let t = @ui.Tester::new(fn(_c) {  })
  let w = @motion.Way::new(0.0)
  w.go(1.0, @motion.tween(way_ms, ease=Linear), at=set_out_at)
  if ahead >= 0.0 {
    t.frame_at(ahead)
    // (read where that frame has it)
    w.get() |> ignore
  }
  w.go(0.0, @motion.tween(way_ms, ease=Linear), at=back_at)
  (looks.map(fn(at) { w.value_at(at) }), w.ends_at())
}

///|
test "a way sent back at a moment before a frame drawn ahead of it: from where it was then, the same as with no frame" {
  let none = sent_back(-1.0)
  assert_eq(sent_back(set_out_at + 300.0), none)
  assert_eq(sent_back(set_out_at + 50.0), none)
  // (sent back at 1100, halfway: from 0.5, 200 ms on to 0)
  assert_eq(none, ([0.5, 0.25, 0.0, 0.0], back_at + way_ms))
}

///|
/// The way's length, when it set out and when it was sent back, and the moments looked at.
let way_ms : Double = 200.0

///|
let set_out_at : Double = 1000.0

///|
let back_at : Double = 1100.0

///|
let looks : Array[Double] = [1100.0, 1200.0, 1300.0, 1400.0]

///|
test "a way of a length and a delay not whole: at its end and after, exactly where it was sent, still" {
  let _ = @ui.Tester::new(fn(_c) {  })
  let w = @motion.Way::new(0.0)
  w.go(1.0, @motion.tween(odd_ms, ease=Linear, delay=odd_delay), at=set_out_at)
  let end = w.end()
  assert_eq((w.at(end), w.at(end + 1000.0)), ((1.0, 0.0), (1.0, 0.0)))
  // (short of it: not there yet)
  assert_true(w.value_at(end - 2.0) < 1.0)
}

///|
/// A length and a delay not whole.
let odd_ms : Double = 200.5

///|
let odd_delay : Double = 10.25

///|
test "a way set out a fraction into a ms: its time counted from that moment in whole ms, as an Anim's (way_anim_test): its end its length after it" {
  // (set out at 1000.7: from there, ending its length after; read at a moment a fraction into a ms of its own time, where
  // it is at that ms's start, as an Anim told at 1000.7 is)
  let w = @motion.Way::new(0.0)
  w.go(1.0, @motion.tween(way_ms, ease=Linear), at=1000.7)
  assert_eq(
    (w.starts_at(), w.ends_at(), [w.value_at(1050.7), w.value_at(1051.3), w.value_at(1050.6), w.value_at(w.ends_at() - 0.4)]),
    (1000.7, 1000.7 + way_ms, [0.25, 0.25, 49.0 / way_ms, (way_ms - 1.0) / way_ms]),
  )
}

///|
/// A window drawn by `make`, which reads way `w` (or not); `w` set out from 0 to 1 over `way_ms` at a moment between
/// frames, then a frame drawn at each of `at` (ms after it set out), `then` done before each: whether the app asked its
/// host for the next display frame as that frame ended (Tester::frames_on: what draws a motion on a device), and
/// whether it asks for one at all (Tester::wanted_after 0).
fn asked_on(
  make : (@motion.Way) -> @ui.Tester,
  at : Array[Double],
  then? : (Double) -> Unit = fn(_ms) {  },
) -> Array[(Bool, Bool)] {
  let w = @motion.Way::new(0.0)
  let t = make(w)
  t.draw()
  let t0 = t.time()
  w.go(1.0, @motion.tween(way_ms, ease=Linear), at=t0)
  at.map(fn(ms) {
    then(ms)
    let before = t.frames_on()
    t.frame_at(t0 + ms)
    (t.frames_on() > before, t.wanted_after() == 0.0)
  })
}

///|
/// Asked for while it goes, none once it is at its end.
let going_then_end : Array[Double] = [a_frame_ms, halfway_ms, way_ms + a_frame_ms]

///|
/// A display frame's length, and the way's middle.
let a_frame_ms : Double = 16.0

///|
let halfway_ms : Double = 100.0

///|
let asked_going : Array[(Bool, Bool)] = [(true, true), (true, true), (false, false)]

///|
/// A box as wide as the way says, built from it.
fn built_from(w : @motion.Way) -> @ui.Tester {
  @ui.Tester::new(fn(c) { c.box(w=Px(10.0 + 100.0 * w.get()), h=Px(10.0), fn() {  }) |> ignore })
}

///|
test "a way read as the view is built: each frame while it goes asks the host for the next, none once it is at its end" {
  assert_eq(asked_on(built_from, going_then_end), asked_going)
}

///|
test "a way read as the view is painted alone (a look worked out as it is painted): the same" {
  let painted = fn(w : @motion.Way) {
    @ui.Tester::new(fn(c) {
      let i = c.box(w=Px(10.0), h=Px(10.0), bg=0x3366CCFFL, fn() {  })
      c.look_by(i, fn() { @ui.look(dx=100.0 * w.get()) })
    })
  }
  assert_eq(asked_on(painted, going_then_end), asked_going)
}

///|
test "a way read by an old view kept in the window's tree, its parts kept as their nodes: the same" {
  let island = fn(w : @motion.Way) {
    let t = @ui.Tester::new(fn(_c) {  })
    t.keep_parts(true)
    @ui.set_view_app(fn(root) {
      root.box(fn(v) {
        @ui.old(v, fn(c) { c.box(w=Px(10.0 + 100.0 * w.get()), h=Px(10.0), fn() {  }) |> ignore }).grow(Is(1.0))
        |> ignore
      })
      |> ignore
    })
    t
  }
  assert_eq(asked_on(island, going_then_end), asked_going)
}

///|
test "a way read by a binding of the window's tree at the moment its frame is drawn: the same" {
  let bound = fn(w : @motion.Way) {
    let t = @ui.Tester::new(fn(_c) {  })
    @ui.set_view_app(fn(root) {
      root.box(fn(v) {
        v
        .width(Is(Some(10.0)))
        .height(Is(Some(10.0)))
        .ground(Is(0x3366CCFFL))
        .alpha(
          By(fn() {
            w.said()
            let now = v.logic_at()
            w.value_at(if w.goes_at(now) { v.drawn_at() } else { @double.infinity })
          }),
        )
        |> ignore
      })
      |> ignore
    })
    t
  }
  assert_eq(asked_on(bound, going_then_end), asked_going)
}

///|
test "a way going read by nothing, or by what is let go as it goes: no frame asked for once nothing reads it" {
  assert_eq(
    asked_on(fn(_w) { @ui.Tester::new(fn(_c) {  }) }, [a_frame_ms, halfway_ms]),
    [(false, false), (false, false)],
  )
  let shown = @signals.signal(true)
  let let_go = asked_on(
    fn(w) {
      @ui.Tester::new(fn(c) {
        if shown.get() {
          c.box(w=Px(10.0 + 100.0 * w.get()), h=Px(10.0), fn() {  }) |> ignore
        }
      })
    },
    [a_frame_ms, halfway_ms, halfway_ms + a_frame_ms],
    then=fn(ms) { if ms == halfway_ms { shown.set(false) } },
  )
  assert_eq(let_go, [(true, true), (false, false), (false, false)])
}
