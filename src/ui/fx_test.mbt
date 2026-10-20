// The window's runtime on the frames' clock (fx.mbt): fibers, timers, lifetimes and the frames that run them, all
// on the Tester's clock; where order matters, over seeds.

///|
test "the runtime's clock is the frames' clock: a sleep wakes in the frame its time falls in" {
  let woke : Array[Int64] = []
  let t = @ui.Tester::new(fn(c) {
    c.effect("timer", async fn(_s) {
      @effect.sleep(100)
      woke.push(@effect.now())
    })
  })
  // the first frame (1016) forked it; it first ran at the start of the second, at the time it was forked (what is
  // ready at a time runs at that time, before the clock moves on), and sleeps until 1116
  t.frame()
  assert_eq(@ui.runtime().now(), 1032L)
  assert_eq(woke, [])
  for _ in 0..<5 {
    t.frame()
  }
  // frame at 1112: not yet
  assert_eq(woke, [])
  t.frame()
  // frame at 1128: the timer fired at its own time, before the frame's
  assert_eq(woke, [1116L])
  assert_eq(@ui.runtime().now().to_double(), t.time())
}

///|
test "a frame's handler forks; the fiber first runs at the start of the next frame, before the view" {
  let log : Array[String] = []
  let shown = Ref("idle")
  let t = @ui.Tester::new(fn(c) {
    log.push("view \{shown.val}")
    if c.button("Go") {
      ignore(
        c.fork(async fn() {
          log.push("fiber at \{@effect.now()}")
          shown.val = "busy"
          @effect.sleep(32)
          shown.val = "done"
        }),
      )
    }
  })
  log.clear()
  let (x, y) = t.find("Go").unwrap()
  t.touch(0, x, y)
  t.touch(2, x, y)
  // 1032: the handler forks; 1048: the fiber runs first (at 1032, when it was forked), then the view; it sleeps
  // until 1064
  for _ in 0..<4 {
    t.frame()
  }
  assert_eq(log, ["view idle", "fiber at 1032", "view busy", "view done", "view done"])
}

///|
test "next_frame steps a fiber once a frame, at the frame's time" {
  let times : Array[Int64] = []
  let t = @ui.Tester::new(fn(c) {
    c.effect("frames", async fn(_s) {
      for _ in 0..<4 {
        times.push(@effect.now())
        @effect.next_frame()
      }
    })
  })
  // frames keep coming while it waits for them (four frames' time: a frame each 16 ms, a 60 Hz display's, as a
  // drag's moves come), and stop when it is done
  t.run_for(4.0 * @ui.drag_step_ms)
  assert_eq(times, [1016L, 1032L, 1048L, 1064L])
  assert_true(!t.ctx().wants_frame)
  t.assert_idle()
}

///|
test "while nothing waits for a frame, the window sleeps until the next timer" {
  let t = @ui.Tester::new(fn(c) {
    c.effect("slow", async fn(_s) { @effect.sleep(5000) })
  })
  t.frame()
  // the fiber sleeps: no frames asked for, a wake at its time
  assert_false(t.ctx().wants_frame)
  assert_false(@ui.runtime().wants_frame())
  assert_eq(t.ctx().wake_at, 1016.0 + 5000.0)
}

///|
test "a lifetime ends the first frame its key is not built: its fibers interrupted, its finalizers run" {
  let shown = Ref(true)
  let log : Array[String] = []
  let t = @ui.Tester::new(fn(c) {
    if shown.val {
      c.effect("panel", async fn(s) {
        s.add_finalizer(async fn() { log.push("finalizer at \{@effect.now()}") })
        defer log.push("fiber ended at \{@effect.now()}")
        log.push("started at \{@effect.now()}")
        @effect.never()
      })
    }
  })
  t.frame()
  t.frame()
  shown.val = false
  t.frame()
  // 1064: not built, its life ends (closed at the start of the next frame, at 1064)
  assert_eq(log, ["started at 1016"])
  t.frame()
  assert_eq(log, ["started at 1016", "fiber ended at 1064", "finalizer at 1064"])
  // built again: a new life
  shown.val = true
  t.frame()
  t.frame()
  assert_eq(log.length(), 4)
  assert_eq(log[3], "started at 1096")
}

///|
test "a host's callback that answers a fiber between frames asks for a frame" {
  let answer : Ref[((Result[String, Error]) -> Unit)?] = Ref(None)
  let got = Ref("")
  let t = @ui.Tester::new(fn(c) {
    c.effect("fetch", async fn(_s) {
      got.val = @effect.host_call(done => answer.val = Some(done))
    })
  })
  t.frame()
  // nothing asks for a frame while the fiber waits for the host
  assert_false(t.ctx().wants_frame)
  assert_false(@ui.runtime().wants_frame())
  // the host answers outside a frame: a frame is asked for (the runtime's), and in it the fiber goes on
  (answer.val.unwrap())(Ok("hello"))
  assert_true(@ui.runtime().wants_frame())
  t.draw()
  assert_eq(got.val, "hello")
  t.assert_idle()
}

///|
/// Two fibers forked in one frame, each writing what it saw: the seed says which runs first; a seed replays its run.
fn race_dump(seed : Int) -> String {
  let order : Array[String] = []
  let t = @ui.Tester::new(
    fn(c) {
      c.effect("a", async fn(_s) {
        order.push("a1")
        @effect.pause()
        order.push("a2")
      })
      c.effect("b", async fn(_s) {
        order.push("b1")
        @effect.pause()
        order.push("b2")
      })
      c.text(order.join(" ")) |> ignore
    },
    seed~,
  )
  t.frame()
  t.frame()
  t.dump()
}

///|
test "with a seed, the order ready fibers run in is drawn from it, and a seed replays it" {
  let seen : Map[String, Int] = Map::new()
  @effect.for_seeds(count=30, s => {
    let d = race_dump(s)
    assert_eq(race_dump(s), d)
    seen[d] = s
  })
  // more than one interleaving was tried
  assert_true(seen.length() > 1)
}
