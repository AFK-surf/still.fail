///|
/// A 400 × 300 window of the tree whose one box, 14 points square, `make` gives its motion; drawn once, then a
/// frame at each of a 120 Hz display's next `n`: the rate each frame said what moves on by the clock needs
/// (Tester::frames_paced, 0 the display's every frame).
fn paced_by(make : (@view.View) -> Unit, n~ : Int) -> Array[Double] {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, tree=fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(14.0))).height(Is(Some(14.0))).ground(Is(0x3366CCFFL)) |> ignore
      make(v)
    })
    |> ignore
  })
  t.draw()
  let t0 = t.time()
  Array::makei(n, fn(i) {
    t.frame_at(t0 + (i + 1).to_double() * 1000.0 / 120.0)
    t.frames_paced()
  })
}

///|
test "a 14-point box turning once in 800 ms: its corners 78 points a second, 2 a frame at 40 Hz, falling to it a rate a frame" {
  let rates = paced_by(n=6, fn(v) {
    v.turn(By(fn() { v.cycle(800.0) * 2.0 * 3.141592653589793 }), drawn=true) |> ignore
  })
  // (the window drawn, its last frame by the clock alone: the next falls from the display's every frame a rate)
  assert_eq(rates, [60.0, 40.0, 40.0, 40.0, 40.0, 40.0])
}

///|
test "a slow fade, none to whole in 6 s: 1/255 of it in 24 ms, 3 a frame at 15 Hz" {
  let rates = paced_by(n=7, fn(v) { v.alpha(By(fn() { v.cycle(6000.0) })) |> ignore })
  assert_eq(rates, [60.0, 40.0, 30.0, 20.0, 15.0, 15.0, 15.0])
}

///|
test "a fast fade, none to whole in 300 ms: drawn at every frame" {
  let rates = paced_by(n=4, fn(v) { v.alpha(By(fn() { v.cycle(300.0) })) |> ignore })
  assert_eq(rates, [0.0, 0.0, 0.0, 0.0])
}

///|
test "a 14-point box turning once in 100 ms, its corners 620 points a second: drawn at every frame" {
  let rates = paced_by(n=4, fn(v) {
    v.turn(By(fn() { v.cycle(100.0) * 2.0 * 3.141592653589793 }), drawn=true) |> ignore
  })
  assert_eq(rates, [0.0, 0.0, 0.0, 0.0])
}

///|
test "a slow turn, then a change of its colour: the frame of the change at the display's next, the frames after falling again" {
  let word = @signals.signal(false)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, tree=fn(root) {
    root.box(fn(v) {
      v
      .width(Is(Some(14.0)))
      .height(Is(Some(14.0)))
      .ground(By(fn() { if word.get() { 0xCC3366FFL } else { 0x3366CCFFL } }))
      .turn(By(fn() { v.cycle(8000.0) * 2.0 * 3.141592653589793 }), drawn=true)
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let t0 = t.time()
  let at = fn(i : Int) {
    t.frame_at(t0 + i.to_double() * 1000.0 / 120.0)
    t.frames_paced()
  }
  let before = [at(1), at(2), at(3)]
  word.set(true)
  let changed = [at(4), at(5), at(6)]
  assert_eq((before, changed), ([60.0, 40.0, 30.0], [0.0, 60.0, 40.0]))
}

///|
test "a list flung gently, its rows moved by their header: drawn at every frame to the end of its glide, however slowly it goes" {
  let s = @view.Scroll::list()
  let t = Tester::new(fn(_c) {  }, platform=2, w=400.0, h=600.0)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col
      .width(Is(Some(400.0)))
      .height(Is(Some(600.0)))
      .scrolls(s, fn(body) {
        for i in 0..<40 {
          body.box(fn(row) { row.height(Is(Some(48.0))).ground(Is(if i % 2 == 0 { 0x3366CCFFL } else { 0xEEEEEEFFL })) |> ignore })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drag(200.0, 400.0, 200.0, 340.0, steps=4)
  let end = s.glides_till().unwrap()
  let t0 = t.time()
  // (its last 200 ms too, where it moves under a point a frame)
  let rates = []
  let mut i = 1
  while t0 + i.to_double() * 1000.0 / 120.0 < end {
    t.frame_at(t0 + i.to_double() * 1000.0 / 120.0)
    rates.push(t.frames_paced())
    i = i + 1
  }
  assert_true(rates.length() > 30, msg="\{rates.length()} frames")
  assert_true(!list_heads.is_empty(), msg="the list said by its group's header")
  assert_eq(rates.filter(fn(r) { r > 0.0 }), [])
}
