// A layout's motions in a frame built again (an old view's read set as the frame is built: ui's kept_nodes.mbt): told
// once all of them are worked out, only where a motion's way came out otherwise. Two old views side by side in the
// window's tree: A, a box pushed down by `top` and moved there (layout), and under it a ground as tall as `top` more,
// reshaped by the same cause, how far over its place it is drawn read as A is built (reshaped_over: as a chat's list
// reads its composer's), reading `poked`; B, which sets what it is told to as it is built (after A), built for it by
// `b_go`, which it follows.

///|
priv struct Laid {
  t : @ui.Tester
  top : @signals.Signal[Double]
  poked : @signals.Signal[Int]
  in_b : Ref[(() -> Unit)?]
  b_go : @signals.Signal[Int]
  done_in_b : Ref[Int]
  builds_a : Ref[Int]
}

///|
/// `spec`: what the box moves by, said as A is built; `two`: a second box under it pushed down twice as far by the same
/// cause, a Move each (moved together: as long as the furthest).
fn laid_islands(spec? : () -> Spec = fn() { tween(push_ms, ease=Linear) }, two? : Bool = false) -> Laid {
  let top = @signals.signal(0.0, same=fn(a, b) { a == b })
  let poked = @signals.signal(0, same=fn(a, b) { a == b })
  let in_b : Ref[(() -> Unit)?] = Ref(None)
  let b_go = @signals.signal(0, same=fn(a, b) { a == b })
  let done_in_b = Ref(0)
  let builds_a = Ref(0)
  let view_a = fn(c : @ui.Ctx) {
    builds_a.val = builds_a.val + 1
    poked.get() |> ignore
    c.column(fn() {
      c.box(h=Px(top.get()), fn() {  }) |> ignore
      let n = c.box(w=Fill(1.0), h=Px(40.0), fn() { c.text("a box") |> ignore })
      layout(c, n, "laid/a", by="\{top.get()}", spec=if two { move() } else { spec() })
      if two {
        c.box(h=Px(top.get()), fn() {  }) |> ignore
        let m = c.box(w=Fill(1.0), h=Px(40.0), fn() { c.text("a second box") |> ignore })
        layout(c, m, "laid/b", by="\{top.get()}", spec=move())
      }
      // (its ground, and how far over its place it is drawn, read here: what reads it built again as it goes)
      let over = reshaped_over(c, "laid/ground")
      let g = c.box(w=Fill(1.0), h=Px(40.0 + top.get()), bg=0x3366CCFFL, fn() { c.text("over \{over.round()}") |> ignore })
      reshape(c, g, "laid/ground", by="\{top.get()}", spec=if two { move() } else { spec() })
    })
    |> ignore
  }
  let view_b = fn(c : @ui.Ctx) {
    b_go.get() |> ignore
    match in_b.val {
      Some(f) => {
        in_b.val = None
        done_in_b.val = done_in_b.val + 1
        f()
      }
      None => ()
    }
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {  }) |> ignore
  }
  let t = @ui.Tester::new(fn(_c) {  }, w=300.0, h=400.0)
  t.keep_parts(true)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.box(fn(v) {
      v.width(Is(Some(150.0))) |> ignore
      @ui.old(v, view_a).grow(Is(1.0)) |> ignore
    })
    |> ignore
    root.box(fn(v) {
      v.grow(Is(1.0)) |> ignore
      @ui.old(v, view_b).grow(Is(1.0)) |> ignore
    })
    |> ignore
  })
  t.draw()
  frame_by_clock(t)
  { t, top, poked, in_b, b_go, done_in_b, builds_a }
}

///|
/// `f` done by B as it is built in the next frame (built for it: b_go).
fn in_b(l : Laid, f : () -> Unit) -> Unit {
  l.in_b.val = Some(f)
  l.b_go.set(l.b_go.get() + 1)
}

///|
/// The display's next frame, its clock alone: no input of the test's (Tester::frame says a step of the test came, every
/// old view built for it).
fn frame_by_clock(t : @ui.Tester) -> Unit {
  t.frame_at(t.next_frame_time())
}

///|
/// Each frame drawn from now while `run` runs: its builds (FramePerf's passes).
fn passes_of(l : Laid, run : () -> Unit) -> Array[Int] {
  let out = []
  l.t.each_frame(Some(fn() { out.push(l.t.frame_perf().passes) }))
  run()
  l.t.each_frame(None)
  out
}

///|
test "a box pushed down and A built again in that frame for what B set as it was built: the same layout again, its move told once, the frame built twice; drawn from where it was to its new place" {
  let l = laid_islands()
  let was = l.t.drawn_of("a box").unwrap()
  l.top.set(40.0)
  in_b(l, fn() { l.poked.set(1) })
  let passes = passes_of(l, fn() { frame_by_clock(l.t) })
  assert_eq(l.done_in_b.val, 1, msg="B did it once")
  assert_eq(passes, [2], msg="the frame the push is told in")
  assert_eq(l.t.drawn_of("a box"), Some(was))
  l.t.run_for(push_midway_ms)
  let y = l.t.drawn_of("a box").unwrap().1
  assert_true(y > was.1 && y < was.1 + 40.0, msg="on its way: \{y}")
  l.t.run_for(layout_rest("laid/a") - l.t.time())
  assert_eq(l.t.drawn_of("a box").unwrap().1, was.1 + 40.0)
}

///|
test "a box pushed down by what B set as it was built, after A was: A built again with it, the move told then, drawn from where it was to its new place" {
  let l = laid_islands()
  let was = l.t.drawn_of("a box").unwrap()
  in_b(l, fn() { l.top.set(40.0) })
  let passes = passes_of(l, fn() { frame_by_clock(l.t) })
  assert_eq(l.done_in_b.val, 1, msg="B did it once")
  // (built with the old top; again with the new, the move told; again for it, the same way: none told)
  assert_eq(passes, [3], msg="the frame B set it in: \{passes}")
  assert_eq(l.t.drawn_of("a box"), Some(was))
  l.t.run_for(push_midway_ms)
  let y = l.t.drawn_of("a box").unwrap().1
  assert_true(y > was.1 && y < was.1 + 40.0, msg="on its way: \{y}")
  l.t.run_for(layout_rest("laid/a") - l.t.time())
  assert_eq(l.t.drawn_of("a box").unwrap().1, was.1 + 40.0)
}

///|
test "a box moving, then the frames as it goes and the one it gets to its end in: none built twice (its way stepped by the clock, nothing of it told again)" {
  let l = laid_islands()
  let was = l.t.drawn_of("a box").unwrap()
  l.top.set(40.0)
  frame_by_clock(l.t)
  let ys : Array[Double] = []
  let passes : Array[Int] = []
  l.t.each_frame(
    Some(fn() {
      passes.push(l.t.frame_perf().passes)
      ys.push(l.t.drawn_of("a box").unwrap().1)
    }),
  )
  // (each frame drawn, one after another to the first after its end)
  let end = layout_rest("laid/a")
  while l.t.time() <= end {
    frame_by_clock(l.t)
  }
  l.t.each_frame(None)
  assert_true(passes.length() > 2, msg="\{passes}")
  // (going all the way: drawn lower each frame till it is there)
  assert_true(ys.iter().any(fn(y) { y > was.1 && y < was.1 + 40.0 }), msg="on its way: \{ys}")
  assert_eq(ys[ys.length() - 1], was.1 + 40.0, msg="\{ys}")
  // (a frame painted alone, nothing built: none)
  assert_eq(passes.filter(fn(p) { p > 1 }), [], msg="\{passes}")
}

///|
test "a box moved by one of Motion's transitions, said anew as A is built, and A built again in that frame: its move told once, the frame built twice; drawn from where it was to its new place" {
  let l = laid_islands(spec=fn() { spring_to(duration=200.0, bounce=0.0) })
  let was = l.t.drawn_of("a box").unwrap()
  l.top.set(40.0)
  in_b(l, fn() { l.poked.set(1) })
  let passes = passes_of(l, fn() { frame_by_clock(l.t) })
  assert_eq(l.done_in_b.val, 1, msg="B did it once")
  assert_eq(passes, [2], msg="the frame the push is told in")
  assert_eq(l.t.drawn_of("a box"), Some(was))
  l.t.run_for(layout_rest("laid/a") - l.t.time())
  assert_eq(l.t.drawn_of("a box").unwrap().1, was.1 + 40.0)
}

///|
test "two boxes pushed down, one twice as far, moved together (the nearer as long as the further), A built again in that frame: told once, the frame built twice; both there at one moment" {
  let l = laid_islands(two=true)
  let a = l.t.drawn_of("a box").unwrap()
  let b = l.t.drawn_of("a second box").unwrap()
  l.top.set(40.0)
  in_b(l, fn() { l.poked.set(1) })
  let passes = passes_of(l, fn() { frame_by_clock(l.t) })
  assert_eq(l.done_in_b.val, 1, msg="B did it once")
  assert_eq(passes, [2], msg="the frame the push is told in")
  assert_eq((l.t.drawn_of("a box"), l.t.drawn_of("a second box")), (Some(a), Some(b)))
  // (one way as long as the other's: there at one moment)
  assert_eq(layout_rest("laid/a"), layout_rest("laid/b"))
  l.t.run_for(layout_rest("laid/b") - l.t.time())
  assert_eq((l.t.drawn_of("a box").unwrap().1, l.t.drawn_of("a second box").unwrap().1), (a.1 + 40.0, b.1 + 80.0))
}

///|
test "a row new to A's list coming in, A built again in that frame for what B set: its coming in told once, the frame built twice; drawn coming in, then there" {
  let keys = @signals.signal(["a"], same=fn(x, y) { x == y })
  let poked = @signals.signal(0, same=fn(a, b) { a == b })
  let b_go = @signals.signal(0, same=fn(a, b) { a == b })
  let in_b : Ref[(() -> Unit)?] = Ref(None)
  let t = @ui.Tester::new(fn(_c) {  }, w=300.0, h=400.0)
  t.keep_parts(true)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.box(fn(v) {
      v.width(Is(Some(150.0))) |> ignore
      @ui.old(v, fn(c) {
        poked.get() |> ignore
        let ks = keys.get()
        list_keys(c, "rows", ks.map(fn(k) { "row/" + k })) |> ignore
        c.list("rows", ks.length(), 40.0, fn(i) {
          let n = c.box(w=Fill(1.0), h=Px(40.0), bg=0x202020FFL, fn() { c.text("row " + ks[i]) |> ignore })
          layout(c, n, "row/" + ks[i], enter=trans(fade=0.0, spec=tween(push_ms, ease=Linear)))
        })
        |> ignore
      })
      .grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.box(fn(v) {
      v.grow(Is(1.0)) |> ignore
      @ui.old(v, fn(c) {
        b_go.get() |> ignore
        match in_b.val {
          Some(f) => {
            in_b.val = None
            f()
          }
          None => ()
        }
        c.box(w=Fill(1.0), h=Fill(1.0), fn() {  }) |> ignore
      })
      .grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  frame_by_clock(t)
  keys.set(["a", "b"])
  in_b.val = Some(fn() { poked.set(1) })
  b_go.set(1)
  let passes = []
  t.each_frame(Some(fn() { passes.push(t.frame_perf().passes) }))
  frame_by_clock(t)
  t.each_frame(None)
  assert_true(in_b.val is None, msg="B did it")
  assert_eq(passes, [2], msg="the frame it is told in")
  // (its ground's opacity as drawn: coming in halfway, there at its end)
  let alpha = fn() {
    match t.drawn_rects().filter(fn(r) { r.4 >> 8 == 0x202020L && r.1 >= 39.0 && r.1 < 41.0 }) {
      [r, ..] => (r.4 & 0xFFL).to_int()
      [] => -1
    }
  }
  t.run_for(push_midway_ms)
  let half = alpha()
  assert_true(half > 0 && half < 255, msg="coming in: \{half}")
  t.run_for(layout_rest("row/b") - t.time())
  assert_eq(alpha(), 255)
}

///|
/// Old views A and B side by side: B a box measured as `laid/m`, `mh` tall, `mtop` down; A the size it is measured at,
/// in words, and how many times A was built.
fn measured_islands() -> (@ui.Tester, @signals.Signal[Double], @signals.Signal[Double], Ref[Int]) {
  let mh = @signals.signal(40.0, same=fn(a, b) { a == b })
  let mtop = @signals.signal(0.0, same=fn(a, b) { a == b })
  let builds_a = Ref(0)
  let t = @ui.Tester::new(fn(_c) {  }, w=300.0, h=400.0)
  t.keep_parts(true)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.box(fn(v) {
      v.width(Is(Some(150.0))) |> ignore
      @ui.old(v, fn(c) {
        builds_a.val = builds_a.val + 1
        let h = match measured_size(c, "laid/m") {
          Some((_, h)) => h
          None => -1.0
        }
        c.text("measured \{h}") |> ignore
      })
      .grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.box(fn(v) {
      v.grow(Is(1.0)) |> ignore
      @ui.old(v, fn(c) {
        c.column(fn() {
          c.box(h=Px(mtop.get()), fn() {  }) |> ignore
          let n = c.box(w=Px(60.0), h=Px(mh.get()), fn() {  })
          measure(c, n, "laid/m")
        })
        |> ignore
      })
      .grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  frame_by_clock(t)
  (t, mh, mtop, builds_a)
}

///|
test "a box measured, moved only, its size the same: what reads its size not built again, nothing built twice" {
  let (t, _, mtop, builds_a) = measured_islands()
  assert_true(t.drawn_of("measured 40") is Some(_))
  let builds = builds_a.val
  mtop.set(30.0)
  let passes = []
  t.each_frame(Some(fn() { passes.push(t.frame_perf().passes) }))
  frame_by_clock(t)
  t.each_frame(None)
  assert_eq(passes, [1])
  assert_eq(builds_a.val, builds, msg="A built again for a move: \{builds_a.val - builds} times")
}

///|
test "a box measured, its size changed: what reads its size built again in that frame, drawn with it there" {
  let (t, mh, _, _) = measured_islands()
  mh.set(60.0)
  let passes = []
  t.each_frame(Some(fn() { passes.push(t.frame_perf().passes) }))
  frame_by_clock(t)
  t.each_frame(None)
  assert_eq(passes, [2])
  assert_true(t.drawn_of("measured 60") is Some(_), msg="the frame it changed in")
}

///|
test "one of Motion's transitions: the same said anew the same; another ease, other keyframes, another duration, other" {
  assert_true(tween_to(duration=200.0, ease=ease_in) == tween_to(duration=200.0, ease=ease_in))
  // (an ease said by a function's name: the same function each time it is named)
  assert_true(tween_to(duration=200.0, ease=linear) == tween_to(duration=200.0, ease=linear), msg="linear named twice")
  assert_true(spring_to(duration=200.0, bounce=0.0) == spring_to(duration=200.0, bounce=0.0))
  assert_true(keyframes_to([80.0, 100.0], duration=200.0) == keyframes_to([80.0, 100.0], duration=200.0))
  assert_true(tween_to(duration=200.0, ease=ease_in) != tween_to(duration=200.0, ease=ease_out))
  assert_true(keyframes_to([80.0, 100.0], duration=200.0) != keyframes_to([20.0, 100.0], duration=200.0))
  assert_true(tween_to(duration=200.0, ease=ease_in) != tween_to(duration=300.0, ease=ease_in))
  assert_true(spring_to(duration=200.0, bounce=0.0) != spring_to(duration=200.0, bounce=0.2))
  // (its keyframes its own: what it was said with changed after, it goes as it was said, and is the same as one said so)
  let values = [80.0, 100.0]
  let a = keyframes_to(values, duration=200.0, ease=ease_in)
  values[0] = 20.0
  let b = keyframes_to([80.0, 100.0], duration=200.0, ease=ease_in)
  assert_true(a == b, msg="said with what was changed after")
  let mid = fn(s : Spec) {
    guard s is Motion(tr) else { -1.0 }
    tr.generator(0.0, 100.0, 0.0).next(100.0).value
  }
  assert_eq(mid(a), mid(b), msg="the one said with what was changed after goes as it was said")
  assert_eq(mid(a), 80.0, msg="halfway at the first keyframe, as it was said")
  assert_true(tween_to(duration=200.0, ease=ease_in) != tween_to(duration=200.0, ease=ease_in, delay=50.0))
}

///|
test "a box pushed down, its ease changed by what B set as it was built (the same kind, length and ends): A built again with it, its move told again, drawn on the new ease's way" {
  let curve = @signals.signal(false, same=fn(a, b) { a == b })
  let l = laid_islands(spec=fn() { tween_to(duration=200.0, ease=if curve.get() { ease_in } else { ease_out }) })
  let was = l.t.drawn_of("a box").unwrap()
  l.top.set(40.0)
  in_b(l, fn() { curve.set(true) })
  let passes = passes_of(l, fn() { frame_by_clock(l.t) })
  assert_eq(l.done_in_b.val, 1, msg="B did it once")
  assert_eq(passes, [3], msg="built with the first ease, again with the second (told), again for it: \{passes}")
  l.t.run_for(push_midway_ms)
  // (halfway in time: ease-in not yet half of the way; ease-out past it)
  let y = l.t.drawn_of("a box").unwrap().1
  assert_true(y > was.1 && y < was.1 + 20.0, msg="on ease-in's way: \{y} from \{was.1}")
  l.t.run_for(layout_rest("laid/a") - l.t.time())
  assert_eq(l.t.drawn_of("a box").unwrap().1, was.1 + 40.0)
}

///|
priv struct Lapse {
  t : @ui.Tester
  shown : @signals.Signal[Bool]
  in_c : Ref[(() -> Unit)?]
  c_go : @signals.Signal[Int]
  builds_a : Ref[Int]
}

///|
/// Old views A, B and C side by side: A the size of B's box measured as `laid/lapse` in words (none: -1) and how many
/// times A was built; B the box while `shown`; C doing what it is told to as it is built (after B), built for it by
/// `c_go`.
fn lapse_islands() -> Lapse {
  let shown = @signals.signal(true, same=fn(a, b) { a == b })
  let in_c : Ref[(() -> Unit)?] = Ref(None)
  let c_go = @signals.signal(0, same=fn(a, b) { a == b })
  let builds_a = Ref(0)
  let t = @ui.Tester::new(fn(_c) {  }, w=300.0, h=400.0)
  t.keep_parts(true)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.box(fn(v) {
      v.width(Is(Some(100.0))) |> ignore
      @ui.old(v, fn(c) {
        builds_a.val = builds_a.val + 1
        let h = match measured_size(c, "laid/lapse") {
          Some((_, h)) => h
          None => -1.0
        }
        c.text("lapse \{h}") |> ignore
      })
      .grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.box(fn(v) {
      v.width(Is(Some(100.0))) |> ignore
      @ui.old(v, fn(c) {
        if shown.get() {
          let n = c.box(w=Px(60.0), h=Px(40.0), fn() {  })
          measure(c, n, "laid/lapse")
        }
      })
      .grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.box(fn(v) {
      v.grow(Is(1.0)) |> ignore
      @ui.old(v, fn(c) {
        c_go.get() |> ignore
        match in_c.val {
          Some(f) => {
            in_c.val = None
            f()
          }
          None => ()
        }
        c.box(w=Fill(1.0), h=Fill(1.0), fn() {  }) |> ignore
      })
      .grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  frame_by_clock(t)
  frame_by_clock(t)
  { t, shown, in_c, c_go, builds_a }
}

///|
test "a box measured let go: what reads its size reads it the same in that frame, built once, and none from the next, then still" {
  let l = lapse_islands()
  assert_true(l.t.drawn_of("lapse 40") is Some(_), msg="measured")
  l.shown.set(false)
  let passes = []
  l.t.each_frame(Some(fn() { passes.push(l.t.frame_perf().passes) }))
  frame_by_clock(l.t)
  assert_eq(passes, [1], msg="the frame it is let go in")
  assert_true(l.t.drawn_of("lapse 40") is Some(_), msg="the frame it is let go in: as it was")
  frame_by_clock(l.t)
  assert_true(l.t.drawn_of("lapse -1") is Some(_), msg="the next: none")
  let builds = l.builds_a.val
  frame_by_clock(l.t)
  frame_by_clock(l.t)
  l.t.each_frame(None)
  assert_eq(passes.filter(fn(p) { p > 1 }), [], msg="\{passes}")
  assert_eq(l.builds_a.val, builds, msg="built again after")
  assert_true(l.t.at_rest(), msg=l.t.rest_why())
}

///|
test "a box measured not laid out in a frame's first build and laid out again in its last: what reads its size told nothing, as it was after" {
  let l = lapse_islands()
  let builds = l.builds_a.val
  // (let go as the frame is told; C, built after B, puts it back as it is built: B built again in that frame with it)
  l.shown.set(false)
  l.in_c.val = Some(fn() { l.shown.set(true) })
  l.c_go.set(1)
  let passes = []
  l.t.each_frame(Some(fn() { passes.push(l.t.frame_perf().passes) }))
  frame_by_clock(l.t)
  assert_true(l.in_c.val is None, msg="C did it")
  assert_eq(passes, [2], msg="built again for B")
  frame_by_clock(l.t)
  frame_by_clock(l.t)
  l.t.each_frame(None)
  assert_true(l.t.drawn_of("lapse 40") is Some(_), msg="measured as it was")
  assert_eq(l.builds_a.val, builds, msg="A built again for a measure that never went")
}
