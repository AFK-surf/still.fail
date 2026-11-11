///|
/// A frame no one asked for is one a host never presents: the frame after it, asked for, is said against what the host
/// shows (the last frame asked for), what it changed and the parts it hands the host both, not against the frame between.
test "a frame no one asked for that drew something else: the next asked for said against what the host shows" {
  let word = Ref("before")
  let t = Tester::new(fn(c) { c.text(word.val, wrap=false) |> ignore })
  t.draw()
  t.record_host()
  // (what is no signal changed and drawn, in a frame no host would draw)
  word.val = "after"
  test_stepped()
  host_asked_next.val = false
  t.frame()
  // (the next frame, asked for, drawing the same as the one between)
  t.frame()
  let frames = t.host_frames()
  assert_eq(frames.map(fn(f) { (f.asked, f.changed) }), [(false, true), (true, true)], msg="\{Repr(frames)}")
  assert_eq(frames[0].damage, [], msg="\{Repr(frames)}")
  assert_true(frames[1].damage.length() > 0, msg="\{Repr(frames)}")
}

///|
/// How far apart two moments may be for the same, the one worked out on the host's clock from the other (a sum of
/// fractions of a ms).
let wake_near_ms : Double = 1.0e-6

///|
/// The fake host's wake is at `at` (as near as a sum of doubles comes).
fn assert_wake(t : Tester, at : Double) -> Unit raise {
  let d = t.fake.wake - at
  assert_true(d < wake_near_ms && d > -wake_near_ms, msg="woken at \{t.fake.wake}, not \{at}")
}

///|
/// How long a Tester runs before timers are set between its frames.
let timers_after_ms : Double = 200.0

///|
/// A timer set between frames (a host's callback, a test's) is told the host at once, its moment (on the runtime's clock,
/// the host's in whole ms) as the host's wake is: the first frame at or after it, no frame drawn for it first (a host
/// idle draws nothing till it is woken); one set later than it leaves it as it is, one set earlier wakes it earlier.
test "a timer set between frames: the host told its moment then, the earliest kept" {
  let t = Tester::new(fn(c) { c.text("still", wrap=false) |> ignore })
  t.run_for(timers_after_ms)
  let frames = t.frames
  assert_true(t.fake.wake < 0.0, msg="woken for \{t.fake.wake} before any timer")
  let at = runtime().now().to_double()
  assert_eq(at, whole_ms(t.fake.time))
  runtime().after(50, fn() {  })
  assert_wake(t, at + 50.0)
  runtime().after(80, fn() {  })
  assert_wake(t, at + 50.0)
  runtime().after(30, fn() {  })
  assert_wake(t, at + 30.0)
  assert_eq(t.frames, frames)
}

///|
/// How far short of a whole ms the host's clock is when the timer below is set: the timer, 1 ms on from the runtime's
/// clock (the ms before), due that much after the host's.
let short_of_whole_ms : Double = 0.1

///|
/// How far past the host's clock the frame looked for below is at least: room for the host's clock to be put before it.
let tick_room_ms : Double = 2.0

///|
/// A timer set between frames due less than a ms after the host's clock (the host's clock 0.1 short of a whole ms, the
/// runtime's the ms before, a timer 1 ms on), a host frame's time at or past that whole ms but short of a ms after the
/// host's clock: the host woken for the moment itself, not a ms from its clock, so that frame is the one it draws and
/// the timer runs in (woken a ms from its clock, a host skips that frame, iOS's tick by its target, the fake's by its
/// grid, and draws the next).
test "a timer due less than a ms after the host's clock: the host woken for its moment, its first frame at or past it drawn" {
  let t = Tester::new(fn(c) { c.text("still", wrap=false) |> ignore })
  t.run_for(timers_after_ms)
  t.advance(idle_ms)
  let tick = t.tick_after(t.time() + tick_room_ms)
  let due = whole_ms(tick)
  t.advance(due - short_of_whole_ms - t.time())
  assert_eq(runtime().now().to_double(), due - 1.0)
  let fired : Array[Double] = []
  runtime().after(1, fn() { fired.push(runtime().now().to_double()) })
  assert_wake(t, due)
  t.record_host()
  t.run_as_host(timers_fired_ms, skip_unasked=true)
  assert_eq(fired, [due])
  let frames = t.host_frames()
  assert_true(frames.length() > 0, msg="no frame drawn for it")
  assert_eq(frames[0].at, tick, msg="\{Repr(frames.map(f => (f.at, f.asked, f.changed)))}")
}

///|
/// How far short of what it was woken for a frame the host draws (iOS's tick, Android's, the web's: a frame's time
/// within 0.5 ms short of the wake counts as at it), here 0.3 ms.
let drawn_short_ms : Double = 0.3

///|
/// A host draws, for a timer's wake, a frame a little short of the timer's moment (within its tolerance): the timer is
/// not due in it and does not run (the runtime's clock is that frame's whole ms, the ms before), it changes nothing on
/// the screen and is not built whole, the host is woken again (the frame's end, Ctx's wake: a ms from the frame at the
/// least), and the timer runs once, in the first frame drawn at or past its moment, built whole, what it changed shown.
/// A frame for nothing, not a timer run early or late. `compare`: the frames of looks alone built whole again to be
/// compared (the Tester's default) or not (a host's frames alone, check_looks(false)).
fn frame_short_of_timer(compare : Bool) -> Unit raise {
  let said = @signals.signal("before")
  let t = Tester::new(fn(c) { c.text(said.get(), wrap=false) |> ignore })
  t.check_looks(compare)
  t.run_for(timers_after_ms)
  t.advance(idle_ms)
  let fired : Array[Double] = []
  runtime().after(50, fn() {
    fired.push(runtime().now().to_double())
    said.set("after")
  })
  let due = runtime().now().to_double() + 50.0
  assert_wake(t, due)
  t.record_host()
  host_asked_next.val = true
  t.fake.wake = -1.0
  t.frame_at(due - drawn_short_ms)
  assert_eq(fired, [])
  assert_eq(t.built_why(), "", msg="the frame short of the timer built whole")
  let early = t.host_frames()
  assert_eq(early.map(f => f.changed), [false], msg="\{Repr(early.map(f => (f.at, f.asked, f.changed, f.why)))}")
  assert_true(t.fake.wake >= due && t.fake.wake <= due - drawn_short_ms + 1.0, msg="woken again at \{t.fake.wake}")
  t.run_as_host(timers_fired_ms, skip_unasked=true)
  assert_eq(fired, [due])
  let frames = t.host_frames()
  let shown = frames.map(f => (f.at, f.asked, f.changed, f.why))
  assert_true(frames.length() > 0 && whole_ms(frames[0].at) >= due, msg="\{Repr(shown)}")
  assert_true(frames[0].changed && frames[0].why != "", msg="\{Repr(shown)}")
  for f in frames {
    assert_true(f.asked, msg="an unasked frame drawn at \{f.at}")
  }
}

///|
test "a host drawing a frame short of a timer's moment, within its tolerance: the timer not run in it, run in the next" {
  frame_short_of_timer(true)
}

///|
test "a host drawing a frame short of a timer's moment, no frame built again to compare: the same" {
  frame_short_of_timer(false)
}

///|
/// How long a Tester stays idle, no frame drawn, before a timer is set (a host's callback come long after the last frame).
let idle_ms : Double = 1000.0

///|
/// A frame drawn by another input before a timer is due.
let input_frame_after_ms : Double = 20.0

///|
/// How long a Tester runs for every timer below to have fired.
let timers_fired_ms : Double = 300.0

///|
/// A Tester idle `idle_ms` after `timers_after_ms` drawn: the moment timers are then set from, and the callbacks' moments
/// on the runtime's clock as they run.
fn idle_tester() -> (Tester, Double, Array[Double]) {
  let t = Tester::new(fn(c) { c.text("still", wrap=false) |> ignore })
  t.run_for(timers_after_ms)
  t.advance(idle_ms)
  (t, whole_ms(t.time()), [])
}

///|
/// A timer set between frames long after the last is due from its own moment (the host's clock then, Ctx::moment), not
/// from the last frame's: a frame another input draws before it is due does not run it, and it runs once, at its moment.
test "a timer set long after the last frame: due from its own moment, a frame between not running it" {
  let (t, start, fired) = idle_tester()
  runtime().after(50, fn() { fired.push(runtime().now().to_double()) })
  t.advance(input_frame_after_ms)
  t.stepped()
  t.frame()
  assert_eq(fired, [], msg="ran before its moment, set at \{start}")
  t.run_for(timers_fired_ms)
  assert_eq(fired, [start + 50.0])
}

///|
/// A timer its own callback sets again runs from the callback's moment: each once, 50 ms apart.
test "a timer set long after the last frame, its callback setting it again: each at its own moment" {
  let (t, start, fired) = idle_tester()
  fn tick() {
    fired.push(runtime().now().to_double())
    if fired.length() < 2 {
      runtime().after(50, tick)
    }
  }
  runtime().after(50, tick)
  t.run_for(timers_fired_ms)
  assert_eq(fired, [start + 50.0, start + 100.0])
}

///|
/// How long after the first the second timer is set.
let second_timer_after_ms : Double = 40.0

///|
/// Two timers set between frames 40 ms apart, each 100 ms on, run 40 ms apart: each from the moment it was set.
test "timers set between frames at different moments: each from its own" {
  let (t, start, fired) = idle_tester()
  runtime().after(100, fn() { fired.push(runtime().now().to_double()) })
  t.advance(second_timer_after_ms)
  runtime().after(100, fn() { fired.push(runtime().now().to_double()) })
  t.run_for(timers_fired_ms)
  assert_eq(fired, [start + 100.0, start + 140.0])
}

///|
/// Timers set between frames long after the last, with only the frames the app asked for drawn (an idle host draws no
/// other): the host told is what brings them, each callback at its own moment, once, and no frame drawn unasked.
test "timers set between frames, only frames asked for drawn: each callback at its own moment" {
  let (t, start, fired) = idle_tester()
  t.record_host()
  fn tick() {
    fired.push(runtime().now().to_double())
    if fired.length() < 2 {
      runtime().after(50, tick)
    }
  }
  runtime().after(50, tick)
  t.run_as_host(timers_fired_ms, skip_unasked=true)
  assert_eq(fired, [start + 50.0, start + 100.0])
  let frames = t.host_frames()
  assert_true(frames.length() > 0 && frames.all(fn(f) { f.asked }), msg="\{Repr(frames)}")
}

///|
/// A timer a message's handler sets, the message posted long after the last frame: due from the frame that hands the
/// message on (its handler runs as that frame begins, before the runtime is brought to the frame's time), not from the
/// frame before.
test "a timer set by a message's handler long after the last frame: due from the frame that took the message" {
  let (t, start, fired) = idle_tester()
  let taken : Array[Double] = []
  on_message("test.timer_from_message", fn(_, _) {
    taken.push(runtime().now().to_double())
    runtime().after(50, fn() { fired.push(runtime().now().to_double()) })
  })
  t.post("test.timer_from_message", "{}")
  t.frame()
  assert_eq(taken, [whole_ms(t.time())], msg="set at \{start}")
  assert_eq(fired, [], msg="ran as the frame that took it began")
  t.run_for(timers_fired_ms)
  assert_eq(fired, [taken[0] + 50.0])
}

///|
/// What a Tester idle after `timers_after_ms` drawn shows: nothing that moves or reads the clock, so a frame not built
/// whole draws only its looks.
fn still_view(c : Ctx) -> Unit {
  c.text("still", wrap=false) |> ignore
}

///|
/// A timer a message's said handler sets (taken as it comes, at the moment it is posted, between frames), the message
/// posted long after the last frame and the view still: due from that moment, and only the frames asked for drawn, the
/// host woken for it.
test "a timer set by a message's said handler, the view still: due from the moment it was posted, the host woken" {
  let (t, _, fired) = idle_tester()
  let taken : Array[Double] = []
  on_message_said("test.timer_said", fn(_, _) {
    taken.push(runtime().now().to_double())
    runtime().after(50, fn() { fired.push(runtime().now().to_double()) })
    true
  })
  t.record_host()
  let first = whole_ms(t.time())
  t.post("test.timer_said", "{}")
  t.run_as_host(timers_fired_ms, skip_unasked=true)
  assert_eq(taken, [first])
  assert_eq(fired, [first + 50.0])
  let frames = t.host_frames()
  assert_true(frames.all(fn(f) { f.asked }), msg="\{Repr(frames)}")
}

///|
/// The same, the said handler setting only a signal and an effect of it setting the timer.
test "a timer set by an effect of a signal a message's said handler set: due from the moment it was posted" {
  let (t, _, fired) = idle_tester()
  let taken : Array[Double] = []
  let came = @signals.signal(0)
  let stop = @signals.effect(fn() {
    if came.get() > 0 {
      taken.push(runtime().now().to_double())
      runtime().after(50, fn() { fired.push(runtime().now().to_double()) })
    }
  })
  on_message_said("test.timer_said_signal", fn(_, _) {
    came.set(1)
    true
  })
  t.record_host()
  let first = whole_ms(t.time())
  t.post("test.timer_said_signal", "{}")
  t.run_as_host(timers_fired_ms, skip_unasked=true)
  stop()
  assert_eq(taken, [first])
  assert_eq(fired, [first + 50.0])
  let frames = t.host_frames()
  assert_true(frames.all(fn(f) { f.asked }), msg="\{Repr(frames)}")
}

///|
/// How long after a Tester's last frame an offscreen frame is drawn at, the host's clock gone on further (idle_ms).
let offscreen_after_ms : Double = 100.0

///|
/// A timer an offscreen frame's view sets is due from the frame's `t`, whatever the host's clock says, and asks the
/// host for nothing (frame_offscreen: no frame is asked for).
test "a timer set by an offscreen frame's view: due from its t, the host not woken" {
  let t = Tester::new(still_view)
  t.draw()
  let at = whole_ms(t.time()) + offscreen_after_ms
  t.advance(idle_ms)
  let set_at : Array[Double] = []
  let view = fn(c : Ctx) {
    if set_at.is_empty() {
      set_at.push(runtime().now().to_double())
      runtime().after(50, fn() {  })
    }
    still_view(c)
  }
  let wake = t.fake.wake
  frame_offscreen(view, 100.0, 100.0, 1.0, at) |> ignore
  assert_eq(set_at, [at], msg="the host's clock at \{t.time()}")
  assert_eq(runtime().next_timer(), Some((at + 50.0).to_int64()))
  assert_eq(t.fake.wake, wake)
}

///|
/// How long after the last frame a timer set then is due, before the fibers below are forked.
let earlier_timer_ms : Int = 900

///|
/// A fiber forked between frames long after the last runs from the moment it was forked, after a timer due before
/// then and not before it; what it waits for (a sleep) starts from there: only the frames asked for drawn, each at its
/// moment.
test "a fiber forked long after the last frame: runs at its moment, after a timer due before, its sleep from there" {
  let t = Tester::new(still_view)
  t.run_for(timers_after_ms)
  let at0 = whole_ms(t.time())
  let said : Array[(String, Double)] = []
  runtime().after(earlier_timer_ms, fn() { said.push(("timer", runtime().now().to_double())) })
  t.advance(idle_ms)
  let start = whole_ms(t.time())
  runtime().fork(async fn() {
    said.push(("fiber", @effect.now().to_double()))
    @effect.sleep(50)
    said.push(("slept", @effect.now().to_double()))
  })
  |> ignore
  t.record_host()
  t.run_as_host(timers_fired_ms, skip_unasked=true)
  assert_eq(said, [
    ("timer", at0 + earlier_timer_ms.to_double()),
    ("fiber", start),
    ("slept", start + 50.0),
  ])
  let frames = t.host_frames()
  assert_true(frames.all(fn(f) { f.asked }), msg="\{Repr(frames)}")
}

///|
/// A fiber a message's handler forks, the message posted long after the last frame: runs at the frame that took it,
/// its sleep from there.
test "a fiber forked by a message's handler long after the last frame: from the frame that took it" {
  let (t, _, _) = idle_tester()
  let said : Array[(String, Double)] = []
  on_message("test.fork_from_message", fn(_, _) {
    runtime().fork(async fn() {
      said.push(("fiber", @effect.now().to_double()))
      @effect.sleep(50)
      said.push(("slept", @effect.now().to_double()))
    })
    |> ignore
  })
  t.record_host()
  let first = whole_ms(t.tick_after(t.time()))
  t.post("test.fork_from_message", "{}")
  t.run_as_host(timers_fired_ms, skip_unasked=true)
  assert_eq(said, [("fiber", first), ("slept", first + 50.0)])
}

///|
/// A fiber forked between frames long after the last is ready at once, as any (only a frame's turn runs it at its own
/// moment): the runtime not idle, wanting a frame, the host asked for one, and run_ready runs it.
test "a fiber forked long after the last frame: ready at once, run by run_ready" {
  let (t, _, _) = idle_tester()
  let rt = runtime()
  let ran = Ref(0)
  t.fake.wants = false
  rt.fork(fn() { ran.val += 1 }) |> ignore
  assert_true(!rt.idle())
  assert_true(rt.wants_frame())
  assert_true(t.fake.wants)
  ignore(rt.run_ready())
  assert_eq(ran.val, 1)
  assert_true(rt.idle())
}

///|
/// A scope closed between frames long after the last: its fiber cut and its finalizer run by run_ready, as ever.
test "a scope closed long after the last frame: its fiber cut, its finalizer run, by run_ready" {
  let (_, _, _) = idle_tester()
  let rt = runtime()
  let said : Array[String] = []
  let scope = rt.root().child()
  scope.add_finalizer(fn() { said.push("finalized") })
  scope.fork(async fn() {
    @effect.sleep(timers_fired_ms.to_int() * 10)
    said.push("slept")
  })
  |> ignore
  ignore(rt.run_ready())
  scope.close_now()
  ignore(rt.run_ready())
  assert_eq(said, ["finalized"])
  assert_true(rt.idle())
}

///|
/// A fiber forked between frames on a host's clock ahead of an offscreen frame drawn after it: not run by that frame
/// (earlier than its moment), still ready, run by the frame that comes to its moment, at it.
test "a fiber forked between frames, an offscreen frame drawn earlier than its moment: run by a frame at it" {
  let t = Tester::new(still_view)
  t.draw()
  let at = whole_ms(t.time()) + offscreen_after_ms
  t.advance(idle_ms)
  let since = whole_ms(t.time())
  let ran : Array[Double] = []
  runtime().fork(fn() { ran.push(@effect.now().to_double()) }) |> ignore
  assert_true(t.fake.wants, msg="the host not asked for a frame as it was forked")
  t.fake.wants = false
  frame_offscreen(still_view, 100.0, 100.0, 1.0, at) |> ignore
  assert_eq(ran, [], msg="ran at the offscreen frame's \{at}")
  assert_true(runtime().wants_frame())
  assert_true(!t.fake.wants, msg="the offscreen frame asked the host for a frame")
  t.frame()
  assert_eq(ran, [since])
}

///|
/// How far into its whole ms a frame of the display is at the least, for the clock put at that ms to share its moment.
let before_tick_ms : Double = 0.1

///|
/// A fiber forked and a timer set due at the same moment between frames: what was set first goes first, either way
/// round, whether a frame at that moment came before them, between them, before and again after them, or not at all
/// (the frames between do not matter).
test "a fiber forked and a timer due at the same moment: the first set first, whatever frames at that moment" {
  for fork_first in [true, false] {
    for frame_at in ["none", "before", "between", "before and again"] {
      let t = Tester::new(still_view)
      t.run_for(timers_after_ms)
      t.advance(idle_ms)
      // (at the whole ms a frame of the display comes within: a frame now is at this moment)
      let mut tick = t.tick_after(t.time())
      while whole_ms(tick) >= tick - before_tick_ms {
        tick = t.tick_after(tick)
      }
      t.advance(whole_ms(tick) - t.time())
      let start = whole_ms(t.time())
      if frame_at == "before" || frame_at == "before and again" {
        t.frame()
        assert_eq(whole_ms(t.time()), start)
      }
      let said : Array[(String, Double)] = []
      let fork = fn() {
        runtime().fork(fn() { said.push(("fiber", @effect.now().to_double())) }) |> ignore
      }
      let timer = fn() { runtime().after(0, fn() { said.push(("timer", runtime().now().to_double())) }) }
      if fork_first {
        fork()
      } else {
        timer()
      }
      if frame_at == "between" {
        t.frame()
        assert_eq(whole_ms(t.time()), start)
      }
      if fork_first {
        timer()
      } else {
        fork()
      }
      if frame_at == "before and again" {
        // (a frame again at the moment of the last, the runtime's clock there already)
        t.frame_at(t.time())
      }
      t.run_for(timers_fired_ms)
      let first = if fork_first { "fiber" } else { "timer" }
      let second = if fork_first { "timer" } else { "fiber" }
      assert_eq(said, [(first, start), (second, start)], msg="fork first: \{fork_first}, a frame: \{frame_at}")
    }
  }
}

///|
/// A task a frame's turn runs at its moment while one made ready between frames at a later moment waits: that one is
/// said ready to it (idle, wants_frame, holding), as it is before and after the turn.
test "a task run at its moment, one made ready at a later moment waiting: that one said ready to it" {
  let t = Tester::new(still_view)
  t.draw()
  let at = whole_ms(t.time()) + offscreen_after_ms
  let seen : Array[(Bool, Bool, Int)] = []
  runtime().fork(async fn() {
    @effect.sleep(50)
    let rt = runtime()
    seen.push((rt.idle(), rt.wants_frame(), rt.holding().1))
  })
  |> ignore
  // (run to its sleep, at the last frame's time)
  ignore(runtime().run_ready())
  t.advance(idle_ms)
  runtime().fork(fn() {  }) |> ignore
  frame_offscreen(still_view, 100.0, 100.0, 1.0, at) |> ignore
  assert_eq(seen, [(false, true, 1)])
  assert_eq(runtime().holding().1, 1)
}

///|
/// An offscreen frame whose view forks a fiber asks the host for nothing (frame_offscreen), though a fiber ready as a
/// frame ends owes one (fx_frame_end): the fiber ready, run by the next frame of the window.
test "an offscreen frame's view forking a fiber: the host asked for nothing" {
  let t = Tester::new(still_view)
  t.draw()
  let at = whole_ms(t.time()) + offscreen_after_ms
  t.advance(idle_ms)
  let ran = Ref(0)
  let forked = Ref(false)
  let view = fn(c : Ctx) {
    if !forked.val {
      forked.val = true
      c.fork(fn() { ran.val += 1 }) |> ignore
    }
    still_view(c)
  }
  t.fake.wants = false
  let wake = t.fake.wake
  frame_offscreen(view, 100.0, 100.0, 1.0, at) |> ignore
  assert_true(forked.val)
  assert_true(!t.fake.wants, msg="the offscreen frame asked the host for a frame")
  assert_eq(t.fake.wake, wake)
  assert_eq(ran.val, 0)
  t.frame()
  assert_eq(ran.val, 1)
}

///|
/// A timer's callback that runs what is ready (Runtime::run_ready) while a task made ready after the timer was set, at
/// the same moment, waits: that task run by it, once, and the frame's turn going on with what is left.
test "a timer's callback running what is ready, a task made ready after it at the same moment waiting" {
  let (t, _, _) = idle_tester()
  let said : Array[String] = []
  runtime().after(0, fn() {
    said.push("timer")
    ignore(runtime().run_ready())
  })
  runtime().fork(fn() { said.push("fiber") }) |> ignore
  t.frame()
  assert_eq(said, ["timer", "fiber"])
  assert_true(runtime().idle())
}

///|
/// A runtime made with a seed, fibers forked one after the other between frames at one moment (each in a host's
/// callback of its own, a frame of that moment able to come between any two: the first run in it before the second
/// was): they run in the order they were forked for every seed, a frame at that moment between each or none (the
/// frames between do not matter). The children one of them forks in its turn, ready together, run in an order drawn
/// from the seed: the same seed the same, another seed another, whatever frames.
test "fibers forked between frames at one moment, a seed: in their order; their children's drawn from the seed" {
  let forked_n = 4
  let order = fn(seed : Int, frames : Bool) {
    let t = Tester::new(still_view, seed~)
    t.run_for(timers_after_ms)
    t.advance(idle_ms)
    let ran : Array[String] = []
    for i in 0..<forked_n {
      runtime().fork(fn() {
        ran.push("fiber \{i}")
        if i == 0 {
          for j in 0..<forked_n {
            runtime().fork(fn() { ran.push("child \{j}") }) |> ignore
          }
        }
      })
      |> ignore
      if frames {
        t.frame_at(t.time())
      }
    }
    t.frame()
    ran
  }
  let children : Array[Array[String]] = []
  for seed in 1..=8 {
    let o = order(seed, false)
    let fibers = o.filter(r => r.has_prefix("fiber"))
    assert_eq(fibers, ["fiber 0", "fiber 1", "fiber 2", "fiber 3"], msg="seed \{seed}: \{Repr(o)}")
    assert_eq(o.length(), 2 * forked_n)
    assert_eq(order(seed, false), o, msg="seed \{seed} twice")
    assert_eq(order(seed, true), o, msg="seed \{seed}, a frame between each")
    let c = o.filter(r => r.has_prefix("child"))
    if !children.contains(c) {
      children.push(c)
    }
  }
  assert_true(children.length() > 1, msg="one order of the children for eight seeds: \{Repr(children)}")
}

///|
/// How far ahead of the host's clock a frame is drawn for, as a host draws for the vsync to come (iOS's
/// `targetTimestamp`): the runtime's clock then ahead of the host's till the next frame.
let shown_ahead_ms : Double = 6.0

///|
/// A frame drawn for a moment ahead of the host's clock (a host's vsync to come), then a timer set between frames before
/// the host's clock gets there: it is due from the runtime's clock (the frame's, ahead), the host woken for that moment
/// (its wake the first frame at or after its clock now and what it is told, on the frames' clock: told the moment less
/// its own clock, not less the runtime's), and with only asked frames drawn it runs at its moment in the first frame
/// drawn, at or after it.
test "a timer set between frames with the frame's time ahead of the host's: due and woken from the runtime's clock" {
  let said = @signals.signal("before")
  let t = Tester::new(fn(c) { c.text(said.get(), wrap=false) |> ignore })
  t.run_for(timers_after_ms)
  t.advance(idle_ms)
  let host = t.time()
  t.frame_shown_at(host, host + shown_ahead_ms)
  assert_eq(t.time(), host)
  let from = whole_ms(host + shown_ahead_ms)
  assert_eq(runtime().now().to_double(), from)
  let fired : Array[Double] = []
  runtime().after(50, fn() {
    fired.push(runtime().now().to_double())
    said.set("after")
  })
  let due = from + 50.0
  // (the host woken for the moment itself: not 50 ms from its own clock, a frame before it is due)
  assert_wake(t, due)
  t.record_host()
  t.run_as_host(timers_fired_ms, skip_unasked=true)
  let frames = t.host_frames()
  assert_eq(fired, [due])
  let changed = frames.filter(f => f.changed).map(f => f.at)
  assert_eq(changed.length(), 1, msg="\{Repr(frames.map(f => (f.at, f.asked, f.changed)))}")
  assert_true(whole_ms(changed[0]) >= due, msg="shown at \{changed[0]}, due \{due}")
  // (the first frame drawn the one it runs in: none drawn before it for nothing)
  assert_eq(frames[0].at, changed[0], msg="\{Repr(frames.map(f => (f.at, f.asked, f.changed)))}")
  for f in frames {
    assert_true(f.asked, msg="an unasked frame drawn at \{f.at}")
  }
}

///|
/// How long after the frame drawn ahead a frame of its looks alone is drawn, before the timer below is due.
let looks_frame_after_ms : Double = 20.0

///|
/// As above with no frame built whole again to be compared (looks_check off: a host's frames alone): the frame drawn
/// ahead built whole for a test's step, a frame of its looks alone drawn before the timer is due not running it, and the
/// timer run at its moment in the first frame drawn at or after it, built whole for it (a moment it waits for came).
/// The host is woken by the runtime's distance, so never after that frame: a frame it draws before the moment (woken
/// early where the frames' clock is ahead of its own) is of its looks alone, nothing built or run.
test "a timer set between frames with the frame's time ahead, no frame built again to compare: run in a built frame" {
  let said = @signals.signal("before")
  let t = Tester::new(fn(c) { c.text(said.get(), wrap=false) |> ignore })
  t.check_looks(false)
  t.run_for(timers_after_ms)
  t.advance(idle_ms)
  let host = t.time()
  t.stepped()
  t.frame_shown_at(host, host + shown_ahead_ms)
  assert_true(t.built_why() != "", msg="the frame drawn ahead not built whole")
  let from = whole_ms(host + shown_ahead_ms)
  assert_eq(runtime().now().to_double(), from)
  let fired : Array[Double] = []
  runtime().after(50, fn() {
    fired.push(runtime().now().to_double())
    said.set("after")
  })
  let due = from + 50.0
  assert_wake(t, due)
  // (a frame of its looks alone before it is due: it runs nothing)
  t.advance(looks_frame_after_ms)
  t.frame_at(t.time())
  assert_eq(t.built_why(), "", msg="the frame between built whole")
  assert_eq(fired, [])
  t.record_host()
  t.run_as_host(timers_fired_ms, skip_unasked=true)
  let frames = t.host_frames()
  assert_eq(fired, [due])
  let changed = frames.filter(f => f.changed)
  assert_eq(changed.length(), 1, msg="\{Repr(frames.map(f => (f.at, f.asked, f.changed, f.why)))}")
  assert_true(whole_ms(changed[0].at) >= due, msg="shown at \{changed[0].at}, due \{due}")
  assert_true(changed[0].why != "", msg="run in a frame not built whole at \{changed[0].at}")
  // (the first frame drawn the one it runs in: none drawn before it for nothing)
  assert_eq(frames[0].at, changed[0].at, msg="\{Repr(frames.map(f => (f.at, f.asked, f.changed, f.why)))}")
  for f in frames {
    assert_true(f.asked, msg="an unasked frame drawn at \{f.at}")
  }
}

///|
/// A device's frames' clock counts from its start (an iPhone's, CACurrentMediaTime: days on, 4 for #4589's): the
/// display's frames on their period from a moment of days are each a period after the one before, as from a second's.
let device_clock_ms : Double = 4.0 * 24.0 * 3600.0 * 1000.0

///|
test "the display's frames on their period on a device's clock of days: each a period after the one before" {
  let t = Tester::new(fn(c) { c.text("still", wrap=false) |> ignore }, time=device_clock_ms)
  t.set_frame_period(1000.0 / 60.0)
  let start = t.time()
  for k in 1..=4 {
    t.frame_at(t.next_frame_time())
    let d = t.time() - start - k.to_double() * t.frame_period()
    assert_true(d < wake_near_ms && d > -wake_near_ms, msg="frame \{k} at \{t.time() - start} ms on")
  }
}

///|
/// One of a double's representable steps at a clock of days (from 2^28 ms to 2^29: 2^-24 ms).
let days_step_ms : Double = 1.0 / 16777216.0

///|
/// A moment said on a device's clock of days (run_for), on one of the display's frames, a step of a double before it or
/// after it, at 60, 90 and 120 frames a second: drawn on to the first of the display's frames not before the moment,
/// worked out here from the frames' origin and period, and no further, the frame before it before the moment.
test "a moment said on a device's clock of days: drawn to the first of the display's frames not before it, no further" {
  for period in [1000.0 / 60.0, 1000.0 / 90.0, 1000.0 / 120.0] {
    for off in [-days_step_ms, 0.0, days_step_ms] {
      let t = Tester::new(fn(c) { c.text("still", wrap=false) |> ignore }, time=device_clock_ms)
      t.set_frame_period(period)
      let origin = t.time()
      t.frame_at(t.next_frame_time())
      t.frame_at(t.next_frame_time())
      let frame = origin + 10.0 * period
      // (a step of a double there: the frames 4 days on are between 2^28 ms and 2^29)
      assert_true(frame - (frame - days_step_ms) == days_step_ms && frame + days_step_ms - frame == days_step_ms, msg="\{frame}")
      let ms = frame + off - t.time()
      let target = t.time() + ms
      let mut k = ((target - origin) / period).floor() - 1.0
      while origin + k * period < target {
        k = k + 1.0
      }
      let first = origin + k * period
      let drawn = []
      t.each_frame(Some(fn() { drawn.push(t.time()) }))
      t.run_for(ms)
      t.each_frame(None)
      let n = drawn.length()
      let said = "at \{period} ms a frame, \{off} off the frame: drawn \{Repr(drawn.map(fn(d) { d - origin }))} ms on, for \{target - origin}"
      assert_true(n >= 2 && drawn[n - 1] == first && drawn[n - 2] < target && t.time() == first, msg=said)
    }
  }
}

///|
/// What the fake host is posted is told at the moment it is posted on its clock, between frames, as a device's host
/// tells it (MB_OUTSIDE_POSTED), in the order posted: never as the next frame begins. So a message posted at a moment
/// comes at that moment at any rate of frames (run again at 60, 120, 24 and 7 a second: MBUI_TEST_FPS), and so does
/// what it sets off.
test "what is posted between frames is told at its moment, in its order, at any rate" {
  let (t, start, _) = idle_tester()
  let told : Array[(String, Double)] = []
  on_message_said("test.told_at", fn(json, _) {
    told.push((json, runtime().now().to_double()))
    true
  })
  // (moments on no rate's frame grid: posts between two frames whatever the rate)
  let first_gap_ms = 37.0
  let second_gap_ms = 101.0
  let after_last_ms = 10.0
  t.post("test.told_at", "a")
  t.run_for(first_gap_ms)
  t.post("test.told_at", "b")
  t.post("test.told_at", "c")
  t.run_for(second_gap_ms)
  t.post("test.told_at", "d")
  t.run_for(after_last_ms)
  assert_eq(told, [
    ("a", start),
    ("b", start + first_gap_ms),
    ("c", start + first_gap_ms),
    ("d", start + first_gap_ms + second_gap_ms),
  ])
}

///|
/// What the fake host is to do at a moment of its own (FakeHost::due) is done at that moment, whatever the frames: the
/// clock stops there (run_for at any rate of frames: MBUI_TEST_FPS), several at one moment in the order said, one said
/// for now done before the clock goes on.
test "what the fake host does at a moment of its own: done then, in its order, at any rate" {
  let (t, start, _) = idle_tester()
  let done : Array[(String, Double)] = []
  let at = fn(name : String) { fn() { done.push((name, runtime().now().to_double())) } }
  // (two moments of the fake host's own, neither on any rate's frame grid, and a span past both)
  let first_due_ms = 7.0
  let later_due_ms = 20.0
  let past_both_ms = 100.0
  t.fake.due(start + later_due_ms, "b", at("b"))
  t.fake.due(start + later_due_ms, "c", at("c"))
  t.fake.due(start + first_due_ms, "a", at("a"))
  t.fake.due(start, "now", at("now"))
  t.run_for(past_both_ms)
  assert_eq(done, [
    ("now", start),
    ("a", start + first_due_ms),
    ("b", start + later_due_ms),
    ("c", start + later_due_ms),
  ])
}
