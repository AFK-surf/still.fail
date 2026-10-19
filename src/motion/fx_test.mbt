// Motion done the Effect way (fx.mbt), frame by frame on the Tester's clock: each value as the view reads it at frame
// n is its transition's generator at n frames; timelines, parallels, staggers, interruptions carrying velocity,
// presence, gestures and layout; where the order fibers run in could matter, over seeds.

///|
fn same(a : Double, b : Double) -> Bool {
  (a - b).abs() <= 1.0e-9
}

///|
/// Frames drawn until `n` frames have passed, `v` read by the view in each.
fn run_frames(t : @ui.Tester, n : Int) -> Unit {
  for _ in 0..<n {
    t.frame()
  }
}

///|
test "animate: the value the view reads at frame n is the transition's generator at n frames" {
  let seen : Array[Double] = []
  let x = Ref(@motion.Value::new(0.0))
  let spec = @motion.spring_to(stiffness=300.0, damping=20.0)
  let t = @ui.Tester::new(fn(c) {
    x.val = @motion.value(c, "x", 0.0)
    c.effect("go", async fn(_s) { ignore(x.val.animate(100.0, spec)) })
    seen.push(x.val.get())
  })
  // forked in the first frame (at 1016); every frame after reads where the spring is 16 ms more on
  let g = @motion.spring_generator(0.0, 100.0, stiffness=300.0, damping=20.0)
  run_frames(t, 20)
  for k in 1..=20 {
    assert_true(same(seen[k], g.next(16.0 * k.to_double()).value), msg="frame \{k}: \{seen[k]}")
  }
  // and it stops asking for frames once it is there
  ignore(t.settle())
  assert_eq(x.val.get(), 100.0)
  assert_true(!x.val.is_animating())
  assert_true(!t.ctx().wants_frame)
}

///|
test "a timeline: each animation awaited in turn; the next starts the frame the last one ends" {
  let log : Array[String] = []
  let t = @ui.Tester::new(fn(c) {
    let x = @motion.value(c, "x", 0.0)
    let y = @motion.value(c, "y", 0.0)
    c.effect("seq", async fn(_s) {
      ignore(x.animate(10.0, @motion.tween_to(duration=64.0, ease=@motion.linear)))
      log.push("x there at \{@effect.now()}")
      ignore(y.animate(10.0, @motion.tween_to(duration=32.0, ease=@motion.linear)))
      log.push("y there at \{@effect.now()}")
    })
    log.push("\{x.get()} \{y.get()}")
  })
  ignore(t.settle())
  assert_eq(log, [
    "0 0", "2.5 0", "5 0", "7.5 0", "x there at 1080", "10 0", "10 5", "y there at 1112",
    "10 10",
  ])
}

///|
test "in parallel (all) both move from the same frame; staggered, each `each` ms after the last" {
  let starts : Array[(Int, Int64)] = []
  let t = @ui.Tester::new(fn(c) {
    let vs = Array::makei(4, i => @motion.value(c, "v\{i}", 0.0))
    c.effect("go", async fn(_s) {
      @motion.stagger(4, 50, i => {
        starts.push((i, @effect.now()))
        ignore(vs[i].animate(1.0, @motion.tween_to(duration=100.0)))
      })
      ignore(
        @effect.all([
          () => vs[0].animate(0.0, @motion.spring_to()),
          () => vs[1].animate(0.0, @motion.spring_to()),
        ]),
      )
    })
  })
  ignore(t.settle())
  starts.sort_by_key(s => s.0)
  assert_eq(starts, [(0, 1016L), (1, 1066L), (2, 1116L), (3, 1166L)])
  // from the centre: the middle first, the ends last
  let from_centre : Array[(Int, Int64)] = []
  let t2 = @ui.Tester::new(fn(c) {
    c.effect("go", async fn(_s) {
      @motion.stagger(5, 10, from=Center, i => from_centre.push((i, @effect.now())))
    })
  })
  // nothing here asks for frames; its sleeps are timers, so frames are drawn past the last of them
  for _ in 0..<4 {
    t2.frame()
  }
  from_centre.sort_by_key(s => s.0)
  assert_eq(from_centre, [(0, 1036L), (1, 1026L), (2, 1016L), (3, 1026L), (4, 1036L)])
}

///|
/// A spring to 100 interrupted at frame `k` by one back to 0, told from a fiber that runs in the same frame as the
/// spring's own: the values the view reads, frame by frame.
fn interrupted(seed : Int, k : Int) -> Array[Double] {
  let seen : Array[Double] = []
  let t = @ui.Tester::new(
    fn(c) {
      let x = @motion.value(c, "x", 0.0)
      c.effect("go", async fn(_s) { ignore(x.animate(100.0, @motion.spring_to(stiffness=200.0, damping=15.0))) })
      c.effect("back", async fn(_s) {
        for _ in 0..<k {
          @effect.next_frame()
        }
        ignore(x.animate(0.0, @motion.spring_to(stiffness=200.0, damping=15.0)))
      })
      seen.push(x.get())
    },
    seed~,
  )
  ignore(t.settle())
  seen
}

///|
test "interrupted, an animation hands on where the value is and how fast it goes, whichever fiber ran first" {
  let k = 6
  let base = interrupted(1, k)
  // over seeds: the same values, frame for frame (the new one samples the old at that instant)
  @effect.for_seeds(count=30, s => assert_eq(interrupted(s, k), base))
  // and they are Motion's: the second spring starts where the first was at frame k, with its velocity
  let g1 = @motion.spring_generator(0.0, 100.0, stiffness=200.0, damping=15.0)
  let at = 16.0 * k.to_double()
  let x0 = g1.next(at).value
  let v0 = g1.velocity(at)
  let g2 = @motion.spring_generator(x0, 0.0, stiffness=200.0, damping=15.0, velocity=v0)
  for j in 1..=10 {
    assert_true(same(base[k + j], g2.next(16.0 * j.to_double()).value), msg="frame \{k + j}")
  }
  // it went on upwards first (velocity carried), then came back
  assert_true(base[k + 1] > base[k])
  assert_eq(base[base.length() - 1], 0.0)
}

///|
test "the animation taken over says so: animate gives false, the new one true" {
  let got : Array[String] = []
  let t = @ui.Tester::new(fn(c) {
    let x = @motion.value(c, "x", 0.0)
    c.effect("a", async fn(_s) {
      let ok = x.animate(100.0, @motion.tween_to(duration=200.0))
      got.push("a \{ok}")
    })
    if c.button("back") {
      ignore(
        c.fork(async fn() {
          let ok = x.animate(0.0, @motion.tween_to(duration=50.0))
          got.push("b \{ok}")
        }),
      )
    }
  })
  run_frames(t, 3)
  t.tap_text("back")
  ignore(t.settle())
  assert_eq(got, ["a false", "b true"])
}

///|
test "interrupting the fiber that awaits an animation stops it where it is" {
  let shown = Ref(true)
  let x = Ref(@motion.Value::new(0.0))
  let t = @ui.Tester::new(fn(c) {
    x.val = @motion.value(c, "x", 0.0)
    if shown.val {
      c.effect("panel", async fn(_s) { ignore(x.val.animate(100.0, @motion.tween_to(duration=300.0))) })
    }
  })
  run_frames(t, 5)
  shown.val = false
  run_frames(t, 3)
  let stopped = x.val.get()
  assert_true(stopped > 0.0 && stopped < 100.0)
  assert_true(!x.val.is_animating())
  run_frames(t, 30)
  assert_eq(x.val.get(), stopped)
}

///|
test "presence: enter as it comes; hidden, its exit runs in its scope's finalizer while it is still drawn, then it is gone" {
  let shown = Ref(false)
  let built : Array[Bool] = []
  let alpha = Ref(@motion.Value::new(0.0))
  let t = @ui.Tester::new(fn(c) {
    let o = @motion.value(c, "o", 0.0)
    alpha.val = o
    let b = @motion.animate_presence(
      c,
      "sheet",
      shown.val,
      enter=async fn() { ignore(o.animate(1.0, @motion.tween_to(duration=64.0, ease=@motion.linear))) },
      exit=async fn() { ignore(o.animate(0.0, @motion.tween_to(duration=64.0, ease=@motion.linear))) },
      fn() { c.text("sheet") |> ignore },
    )
    built.push(b)
  })
  assert_eq(t.find("sheet"), None)
  shown.val = true
  // a change made outside the view asks for no frame by itself: one is drawn, then the enter's run out
  t.frame()
  ignore(t.settle())
  assert_eq(alpha.val.get(), 1.0)
  assert_true(t.find("sheet") is Some(_))
  shown.val = false
  t.frame()
  // the frame it was hidden it is still built; the exit runs from the next
  t.frame()
  assert_true(alpha.val.get() < 1.0)
  assert_eq(built[built.length() - 1], true)
  ignore(t.settle())
  assert_eq(alpha.val.get(), 0.0)
  assert_eq(built[built.length() - 1], false)
  assert_eq(t.find("sheet"), None)
}

///|
test "presence: shown again while it leaves, it comes back from where the exit had it" {
  let shown = Ref(true)
  let o = Ref(@motion.Value::new(0.0))
  let t = @ui.Tester::new(fn(c) {
    o.val = @motion.value(c, "o", 0.0)
    let v = o.val
    ignore(
      @motion.animate_presence(
        c,
        "menu",
        shown.val,
        enter=async fn() { ignore(v.animate(1.0, @motion.tween_to(duration=160.0, ease=@motion.linear))) },
        exit=async fn() { ignore(v.animate(0.0, @motion.tween_to(duration=160.0, ease=@motion.linear))) },
        fn() { c.text("menu") |> ignore },
      ),
    )
  })
  ignore(t.settle())
  shown.val = false
  run_frames(t, 4)
  let mid = o.val.get()
  assert_true(mid > 0.0 && mid < 1.0)
  shown.val = true
  t.frame()
  let a = o.val.get()
  t.frame()
  let b = o.val.get()
  t.frame()
  let c = o.val.get()
  // on its way back up from where the exit had it, never down to 0
  assert_true(a > 0.5 && a <= mid, msg="\{a} \{mid}")
  assert_true(b > a && c > b, msg="\{a} \{b} \{c}")
  ignore(t.settle())
  assert_eq(o.val.get(), 1.0)
  assert_true(t.find("menu") is Some(_))
}

///|
test "hover and press start and interrupt the value's animation" {
  let s = Ref(@motion.Value::new(1.0))
  let t = @ui.Tester::new(fn(c) {
    let id = c.id("card")
    s.val = @motion.value(c, "scale", 1.0)
    c.box(id~, w=Px(100.0), h=Px(100.0), fn() {  }) |> ignore
    @motion.while_hover(c, id, s.val, rest=1.0, to=1.2)
  })
  t.move(50.0, 50.0)
  ignore(t.settle())
  assert_true(same(s.val.get(), 1.2))
  t.move(300.0, 300.0)
  t.frame()
  t.frame()
  assert_true(s.val.get() < 1.2)
  ignore(t.settle())
  assert_true(same(s.val.get(), 1.0))
}

///|
test "drag: the value follows the finger, then goes on by momentum and is caught at its bounds" {
  let x = Ref(@motion.Value::new(0.0))
  let t = @ui.Tester::new(fn(c) {
    let id = c.id("knob")
    x.val = @motion.value(c, "x", 0.0)
    c.drag_area(id, axis=Horizontal, w=Px(390.0), h=Px(100.0), fn() {  }) |> ignore
    @motion.drag_value(c, id, x.val, min=0.0, max=200.0)
  })
  t.drag(50.0, 50.0, 150.0, 50.0, steps=5)
  // let go moving right: momentum takes it further
  let let_go = x.val.get()
  assert_true(let_go > 60.0)
  assert_true(x.val.is_animating())
  ignore(t.settle())
  assert_true(x.val.get() > let_go)
  assert_true(x.val.get() <= 200.0 + 1.0)
}

///|
test "layout: a node that moves is drawn from where it was, and goes to its new place over frames" {
  let top = Ref(true)
  let t = @ui.Tester::new(fn(c) {
    c.column(w=Fill(1.0), h=Fill(1.0), fn() {
      if !top.val {
        c.box(h=Px(200.0), fn() {  }) |> ignore
      }
      let i = c.box(fn() { c.text("card") |> ignore })
      @motion.animate_layout(c, i, "card", spec=@motion.tween_to(duration=160.0, ease=@motion.linear))
    })
    |> ignore
  })
  let (_, y0) = t.drawn_of("card").unwrap()
  top.val = false
  t.frame()
  // laid out 200 lower, drawn where it was
  let (_, y1) = t.drawn_of("card").unwrap()
  assert_true(same(y1, y0))
  let ys : Array[Double] = []
  for _ in 0..<10 {
    t.frame()
    ys.push(t.drawn_of("card").unwrap().1)
  }
  // 20 px a frame (linear over 160 ms), there at the end
  for k, y in ys {
    assert_true(same(y, y0 + 20.0 * (k + 1).to_double()), msg="frame \{k}: \{y}")
  }
  ignore(t.settle())
  assert_true(same(t.drawn_of("card").unwrap().1, y0 + 200.0))
}
