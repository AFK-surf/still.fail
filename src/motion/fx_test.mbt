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
  // forked in the first frame (at 1016), run in the frame it owes at that moment (where it starts: seen[1]); every
  // frame after reads where the spring is 16 ms more on
  let g = @motion.spring_generator(0.0, 100.0, stiffness=300.0, damping=20.0)
  run_frames(t, 20)
  for k in 0..=20 {
    assert_true(same(seen[k + 1], g.next(16.0 * k.to_double()).value), msg="frame \{k}: \{seen[k + 1]}")
  }
  // and it stops asking for frames once it is there: at the spring's own end
  t.run_for(x.val.ends_at() - t.time())
  assert_eq(x.val.get(), 100.0)
  assert_true(!x.val.is_animating())
  assert_true(!t.ctx().wants_frame)
  t.assert_idle()
}

///|
test "Value::ends_at: its start and its length, as it was told; -1 when nothing moves it" {
  let tween_ms = 200.0
  let x = Ref(@motion.Value::new(0.0))
  let go = Ref(true)
  let t = @ui.Tester::new(fn(c) {
    x.val = @motion.value(c, "x", 0.0)
    if go.val {
      go.val = false
      ignore(x.val.start(100.0, @motion.tween_to(duration=tween_ms, ease=@motion.linear)))
    }
  })
  // told in the first frame, at its moment
  let end = x.val.ends_at()
  assert_eq(end, t.time() + tween_ms)
  // asked again half-way, the same
  t.run_for(tween_ms / 2.0)
  assert_eq(x.val.ends_at(), end)
  t.run_for(end - t.time())
  assert_eq(x.val.get(), 100.0)
  assert_eq(x.val.ends_at(), -1.0)
  t.assert_idle()
}

///|
test "a timeline: each animation awaited in turn; the next starts the frame the last one ends" {
  let log : Array[String] = []
  let x_ms = 64.0
  let y_ms = 32.0
  let t = @ui.Tester::new(fn(c) {
    let x = @motion.value(c, "x", 0.0)
    let y = @motion.value(c, "y", 0.0)
    c.effect("seq", async fn(_s) {
      ignore(x.animate(10.0, @motion.tween_to(duration=x_ms, ease=@motion.linear)))
      log.push("x there at \{@effect.now()}")
      ignore(y.animate(10.0, @motion.tween_to(duration=y_ms, ease=@motion.linear)))
      log.push("y there at \{@effect.now()}")
    })
    log.push("\{x.get()} \{y.get()}")
  })
  // the timeline's own length: x's, then y's (told at its first frame's moment, 1016: the frame it owes there starts
  // it)
  t.run_for(x_ms + y_ms)
  assert_eq(log, [
    "0 0", "0 0", "2.5 0", "5 0", "7.5 0", "x there at 1080", "10 0", "10 5", "y there at 1112",
    "10 10",
  ])
  t.assert_idle()
}

///|
test "in parallel (all) both move from the same frame; staggered, each `each` ms after the last" {
  let starts : Array[(Int, Int64)] = []
  let n = 4
  let each = 50
  let tween_ms = 100.0
  let values : Ref[Array[@motion.Value]] = Ref([])
  let t = @ui.Tester::new(fn(c) {
    let vs = Array::makei(n, i => @motion.value(c, "v\{i}", 0.0))
    values.val = vs
    c.effect("go", async fn(_s) {
      @motion.stagger(n, each, i => {
        starts.push((i, @effect.now()))
        ignore(vs[i].animate(1.0, @motion.tween_to(duration=tween_ms)))
      })
      ignore(
        @effect.all([
          () => vs[0].animate(0.0, @motion.spring_to()),
          () => vs[1].animate(0.0, @motion.spring_to()),
        ]),
      )
    })
  })
  // the stagger's own length: its last start, `each` ms after each other, and that one's tween
  t.run_for(((n - 1) * each).to_double() + tween_ms)
  starts.sort_by_key(s => s.0)
  assert_eq(starts, [(0, 1016L), (1, 1066L), (2, 1116L), (3, 1166L)])
  // then the two springs at once, told as the stagger ended: to their own ends
  let vs = values.val
  assert_true(vs[0].is_animating() && vs[1].is_animating())
  let springs_end = if vs[0].ends_at() > vs[1].ends_at() { vs[0].ends_at() } else { vs[1].ends_at() }
  t.run_for(springs_end - t.time())
  t.assert_idle()
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
  let xv = Ref(@motion.Value::new(0.0))
  let t = @ui.Tester::new(
    fn(c) {
      let x = @motion.value(c, "x", 0.0)
      xv.val = x
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
  // to the first spring's own end: the one back took it over at frame k, well before
  t.run_for(xv.val.ends_at() - t.time())
  if xv.val.target() != 0.0 {
    abort("the spring back had not taken over by the first one's end")
  }
  // to the spring back's own end
  t.run_for(xv.val.ends_at() - t.time())
  t.assert_idle()
  // from the frame they start in (the one the first frame owes, at its moment: the fibers forked in it run there)
  seen[1:].to_array()
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
  let xv = Ref(@motion.Value::new(0.0))
  let t = @ui.Tester::new(fn(c) {
    let x = @motion.value(c, "x", 0.0)
    xv.val = x
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
  // b took it over as the tap was taken: to b's own end
  assert_eq(xv.val.target(), 0.0)
  t.run_for(xv.val.ends_at() - t.time())
  assert_eq(got, ["a false", "b true"])
  t.assert_idle()
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
  // a change made outside the view asks for no frame by itself: the frames it causes drawn (the enter forked, then
  // run), then the enter to its own end
  t.draw()
  t.run_for(alpha.val.ends_at() - t.time())
  assert_eq(alpha.val.get(), 1.0)
  assert_true(t.find("sheet") is Some(_))
  shown.val = false
  t.frame()
  // the frame it was hidden it is still built; the exit runs from the next
  t.frame()
  assert_true(alpha.val.get() < 1.0)
  assert_eq(built[built.length() - 1], true)
  // the exit to its own end
  t.run_for(alpha.val.ends_at() - t.time())
  assert_eq(alpha.val.get(), 0.0)
  assert_eq(built[built.length() - 1], false)
  assert_eq(t.find("sheet"), None)
  t.assert_idle()
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
  // (the enter forked in the first frame runs at the next: the frame owed), then to its own end
  t.draw()
  t.run_for(o.val.ends_at() - t.time())
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
  // the enter again, to its own end
  t.run_for(o.val.ends_at() - t.time())
  assert_eq(o.val.get(), 1.0)
  assert_true(t.find("menu") is Some(_))
  t.assert_idle()
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
  // the spring the hover told, to its own end
  t.run_for(s.val.ends_at() - t.time())
  assert_true(same(s.val.get(), 1.2))
  t.move(300.0, 300.0)
  t.frame()
  t.frame()
  assert_true(s.val.get() < 1.2)
  // the spring back, to its own end
  t.run_for(s.val.ends_at() - t.time())
  assert_true(same(s.val.get(), 1.0))
  t.assert_idle()
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
  // the momentum, to its own end
  t.run_for(x.val.ends_at() - t.time())
  assert_true(x.val.get() > let_go)
  assert_true(x.val.get() <= 200.0 + 1.0)
  t.assert_idle()
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
  t.draw()
  assert_true(same(t.drawn_of("card").unwrap().1, y0 + 200.0))
}
