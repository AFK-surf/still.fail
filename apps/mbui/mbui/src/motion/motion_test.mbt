// Motion's arithmetic against Compose's (its curves and springs, worked out
// from their formulas), and the motion layer frame
// by frame in a Tester.

///|
fn near(a : Double, b : Double, eps : Double) -> Bool {
  (a - b).abs() <= eps
}

///|
test "the named curves are CSS's cubic-beziers (Compose's CubicBezierEasing)" {
  let ts = [0.1, 0.25, 0.5, 0.75, 0.9]
  // worked out by bisection on the curves' own polynomials
  let want = [
    (@ui.Out, [0.359122765, 0.727373396, 0.929578821, 0.987468037, 0.998286622]),
    (@ui.Flight, [0.010913674, 0.095832729, 0.70468533, 0.956226683, 0.994219017]),
  ]
  for w in want {
    let (curve, ys) = w
    for i, t in ts {
      assert_true(near(curve.at(t), ys[i], 1.0e-6), msg="\{curve} at \{t}: \{curve.at(t)} not \{ys[i]}")
    }
  }
  assert_eq(@ui.Out.at(0.0), 0.0)
  assert_eq(@ui.Out.at(1.0), 1.0)
}

///|
test "a Move is a critically damped spring's way from rest, ending at 1" {
  // a critically damped spring at rest (within 0.5%) at its length: ωT = 7.4
  let len = @ui.move_ms(390.0) / 1000.0
  let w = 7.4 / len
  let (rest, _) = @motion.spring_at(1.0, w * w, 1.0, 0.0, len)
  for t in [0.05, 0.1, 0.25, 0.5, 0.75, 0.9] {
    let (left, _) = @motion.spring_at(1.0, w * w, 1.0, 0.0, t * len)
    let want = (1.0 - left) / (1.0 - rest)
    assert_true(near(@ui.Move.at(t), want, 1.0e-3), msg="at \{t}: \{@ui.Move.at(t)} not \{want}")
  }
  assert_eq(@ui.Move.at(0.0), 0.0)
  assert_eq(@ui.Move.at(1.0), 1.0)
  // no step in its first frame (120 Hz): under 1% of the way
  // (a far one's: across a window)
  assert_true(@ui.Move.at(8.4 / @ui.move_ms(1000.0)) < 0.01)
}

///|
test "a Move takes as long as its way is far: the further the longer, not in proportion, 200 to 500 ms" {
  // a phone's page width about as a page's push was; nothing far, the least; across anything, the most
  assert_eq(@ui.move_ms(390.0), 350.0)
  assert_eq(@ui.move_ms(0.0), 200.0)
  assert_eq(@ui.move_ms(1.0e6), @ui.move_most_ms)
  let mut was = 0.0
  for d in [0.0, 4.0, 20.0, 64.0, 200.0, 390.0, 700.0, 1000.0, 2000.0, 4000.0] {
    let ms = @ui.move_ms(d)
    assert_true(ms >= was && ms >= @ui.move_least_ms && ms <= @ui.move_most_ms, msg="\{d}: \{ms}")
    was = ms
  }
  // a line's way well under a window's
  assert_true(@ui.move_ms(24.0) < @ui.move_ms(1000.0) - 150.0)
}

///|
test "a Move told on from a way under way leaves as fast as it went, and is there at its end" {
  let dur = @ui.move_ms(300.0)
  // from rest: Ease::Move's way
  for t in [0.0, 0.1, 0.3, 0.5, 0.8] {
    let (x, _) = @ui.move_path(300.0, 0.0, t * dur, dur)
    assert_true(near(x, 300.0 * (1.0 - @ui.Move.at(t)), 1.0e-6), msg="at \{t}: \{x}")
  }
  // going 2 points a ms away from its end as it sets out: that fast at first, on away a while, then back, there at the end
  let (x0, v0) = @ui.move_path(100.0, 2.0, 0.0, dur)
  assert_eq((x0, v0), (100.0, 2.0))
  let (_, v) = @ui.move_path(100.0, 2.0, 0.01, dur)
  assert_true(near(v, 2.0, 0.01), msg="\{v}")
  let (x, _) = @ui.move_path(100.0, 2.0, 20.0, dur)
  assert_true(x > 100.0)
  assert_eq(@ui.move_path(100.0, 2.0, dur, dur), (0.0, 0.0))
  let (near_end, _) = @ui.move_path(100.0, 2.0, dur - 1.0, dur)
  assert_true(near_end.abs() < 0.5, msg="\{near_end}")
  // an Anim told anew mid-way: on from where it is as fast as it went, as long as what is left of its way
  let a = @motion.Anim::new(0.0)
  let s = @motion.move()
  assert_eq(s.duration(0.0, 400.0, 0.0), @ui.move_ms(400.0))
  assert_eq(s.duration(380.0, 400.0, 0.0), @ui.move_ms(20.0))
  let (x1, v1) = s.value_at(0.0, s.duration(380.0, 400.0, 900.0), 380.0, 400.0, 900.0)
  assert_eq((x1, v1), (380.0, 900.0))
  ignore(a)
  // a progress of 0 to 1 over 300 points: as long as those
  assert_eq(@motion.move(points=300.0).duration(0.0, 1.0, 0.0), @ui.move_ms(300.0))
  assert_eq(@motion.move(over=40.0).duration(0.0, 1.0, 0.0), @ui.move_ms(40.0))
}

///|
test "springs are Compose's SpringSimulation, in closed form" {
  // critically damped: (d + (v + ωd)t)e^(−ωt)
  let w = 1500.0.sqrt()
  for t in [0.0, 0.01, 0.05, 0.1, 0.3] {
    let (x, _) = @motion.spring_at(1.0, 1500.0, 1.0, 0.0, t)
    let want = (1.0 + w * t) * @dmath.pow(2.718281828459045, -w * t)
    assert_true(near(x, want, 1.0e-12))
  }
  // under-damped: Sheet.kt's menu spring, motionSpring(.24, bounce .08)
  match @motion.motion_spring(0.24, bounce=0.08, threshold=0.001) {
    Spring(ratio, k, _, _) => {
      assert_true(near(ratio, 0.92, 1.0e-12))
      assert_true(near(k, 475.9647184167322, 1.0e-9))
      let (x, _) = @motion.spring_at(ratio, k, 1.0, 0.0, 0.05)
      assert_true(near(x, 0.690351422335188, 1.0e-9))
    }
    _ => fail("a spring")
  }
  // over-damped, ζ 1.5 at stiffness 400
  let (x, _) = @motion.spring_at(1.5, 400.0, 1.0, 0.0, 0.1)
  assert_true(near(x, 0.5444956660098628, 1.0e-9))
  // the velocity is the displacement's derivative
  for p in [(0.6, 300.0), (1.0, 350.0), (1.8, 200.0)] {
    let (ratio, k) = p
    let (x0, v) = @motion.spring_at(ratio, k, 1.0, 3.0, 0.08)
    let (x1, _) = @motion.spring_at(ratio, k, 1.0, 3.0, 0.08 + 1.0e-6)
    assert_true(near((x1 - x0) / 1.0e-6, v, 1.0e-3))
  }
}

///|
test "springs end as Compose reckons their duration" {
  // spring() from 0 to 1: critically damped at 1500, within .01: 171 ms
  assert_eq(@motion.spring_duration(1.0, 1500.0, 1.0, 0.0, 0.01), 171.0)
  // a row 100 px off its place on ListMotion's spring (350, within a pixel)
  assert_eq(@motion.spring_duration(1.0, 350.0, 100.0, 0.0, 1.0), 354.0)
  assert_eq(@motion.spring_duration(1.0, 350.0, -66.0, 0.0, 1.0), 329.0)
  // Motion.kt's MOVE (2π / .336)², within half a pixel
  match @motion.move_spring {
    Spring(_, k, thr, _) => {
      assert_true(near(k, 349.68836455106845, 1.0e-9))
      assert_eq(@motion.spring_duration(1.0, k, 66.0, 0.0, thr), 372.0)
    }
    _ => fail("a spring")
  }
  // under-damped, by its envelope: Sheet.kt's menu from .9 to 1
  match @motion.motion_spring(0.24, bounce=0.08, threshold=0.001) {
    Spring(ratio, k, thr, _) =>
      assert_eq(@motion.spring_duration(ratio, k, -0.1, 0.0, thr), 276.0)
    _ => fail("a spring")
  }
  // at rest already
  assert_eq(@motion.spring_duration(1.0, 350.0, 0.0, 0.0, 1.0), 0.0)
  match @motion.sheet_spring {
    Spring(_, k, _, _) => assert_true(near(k, 267.73015410941184, 1.0e-9))
    _ => fail("a spring")
  }
}

///|
test "a tween goes by whole milliseconds on its curve, after its delay" {
  let s = @motion.tween(300.0, ease=Out, delay=100.0)
  let dur = s.duration(0.0, 10.0, 0.0)
  assert_eq(dur, 400.0)
  let (x0, _) = s.value_at(50.0, dur, 0.0, 10.0, 0.0)
  assert_eq(x0, 0.0)
  let (x1, _) = s.value_at(250.9, dur, 0.0, 10.0, 0.0)
  assert_true(near(x1, 10.0 * @ui.Out.at(150.0 / 300.0), 1.0e-9))
  let (x2, v2) = s.value_at(400.0, dur, 0.0, 10.0, 0.0)
  assert_eq((x2, v2), (10.0, 0.0))
}

///|
test "an animated value starts the frame it is asked in, and follows its target" {
  let shown = Ref::new(false)
  // the tween's length
  let tween_ms = 160.0
  let seen : Array[Double] = []
  let kept : Ref[@motion.Anim?] = Ref(None)
  let t = @ui.Tester::new(fn(c) {
    let v = @motion.animate(
      c,
      "k",
      if shown.val {
        1.0
      } else {
        0.0
      },
      spec=@motion.tween(tween_ms, ease=Linear),
    )
    seen.push(v)
    // (the Anim it plays, to ask its end)
    kept.val = Some(@motion.anim(c, "k", 0.0))
    c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore
  })
  // at its target the first time, without motion
  assert_eq(seen[seen.length() - 1], 0.0)
  shown.val = true
  t.frame()
  // asked this frame: it starts here, at its start
  assert_eq(seen[seen.length() - 1], 0.0)
  let start = t.time()
  // (where a linear tween is at a frame: the whole ms since it started, of its length)
  let linear = fn() { (t.time() - start).floor() / tween_ms }
  t.run_for(tween_ms / 10.0)
  assert_true(near(seen[seen.length() - 1], linear(), 1.0e-9))
  t.run_for(start + tween_ms / 2.0 - t.time())
  assert_true(near(seen[seen.length() - 1], linear(), 1.0e-9))
  // turned back mid-way: from where it is in the frame it is told in, back from there on
  shown.val = false
  t.run_for(tween_ms / 10.0)
  let back = seen[seen.length() - 1]
  assert_true(near(back, linear(), 1.0e-9), msg="\{back}")
  t.run_for(tween_ms / 10.0)
  assert_true(seen[seen.length() - 1] < back)
  // on its way still, to its own end
  let end = kept.val.unwrap().ends_at()
  assert_true(end > t.time())
  t.run_for(end - t.time())
  assert_eq(seen[seen.length() - 1], 0.0)
  t.assert_idle()
}

///|
test "a frame built again for an animated value going says which: its key and the place that told it, not the motion package's" {
  let shown = Ref(false)
  // the tween's length
  let tween_ms = 400.0
  let t = @ui.Tester::new(fn(c) {
    let v = @motion.animate(c, "slide", if shown.val { 1.0 } else { 0.0 }, spec=@motion.tween(tween_ms, ease=Linear))
    c.box(w=Px(10.0 + 10.0 * v), h=Px(10.0), fn() {  }) |> ignore
  })
  shown.val = true
  t.frame()
  t.run_for(tween_ms / 8.0)
  let why = t.built_why()
  assert_true(why.has_prefix("the clock read at a motion of Anim \"slide\", told at "), msg=why)
  assert_true(why.contains("motion_test.mbt"), msg=why)
  t.run_for(tween_ms)
  t.assert_idle()
}

///|
test "a spring told anew mid-way goes on as fast as it went" {
  let to = Ref::new(0.0)
  let seen : Array[Double] = []
  let kept : Ref[@motion.Anim?] = Ref(None)
  let t = @ui.Tester::new(fn(c) {
    seen.push(@motion.animate(c, "s", to.val, spec=@motion.row_spring))
    // (the Anim it plays, to ask its end)
    kept.val = Some(@motion.anim(c, "s", 0.0))
    c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore
  })
  to.val = 100.0
  // asked, and its first frame, at this moment
  t.draw()
  let span = kept.val.unwrap().ends_at() - t.time()
  // a step: a twentieth of its way
  let step = span / 20.0
  // a quarter of its way: going fast
  t.run_for(span / 4.0 - step)
  let a = seen[seen.length() - 1]
  t.run_for(step)
  let b = seen[seen.length() - 1]
  to.val = 200.0
  // told at this moment, from where it is
  t.draw()
  t.run_for(step)
  let c1 = seen[seen.length() - 1]
  t.run_for(step)
  let d = seen[seen.length() - 1]
  // no stop: the step after is at least as long as the one before
  assert_true(d - c1 >= (b - a) * 0.9, msg="\{a} \{b} \{c1} \{d}")
  // the spring's own end, asked
  t.run_for(kept.val.unwrap().ends_at() - t.time())
  assert_eq(seen[seen.length() - 1], 200.0)
  t.assert_idle()
}

///|
test "a keyed node moved for its cause is drawn from where it was, then goes there" {
  let before = Ref::new(true)
  let mut id = 0
  let t = @ui.Tester::new(fn(c) {
    id = c.id("moved")
    c.column(fn() {
      if before.val {
        c.box(w=Px(50.0), h=Px(40.0), fn() {  }) |> ignore
      }
      let i = c.box(w=Px(50.0), h=Px(20.0), bg=0xFF0000FFL, id~, fn() {  })
      @motion.layout(c, i, "moved", by="\{before.val}")
    })
    |> ignore
  })
  let y0 = drawn_y(t, 0xFF0000FFL)
  assert_eq(y0, 40.0)
  before.val = false
  t.frame()
  // laid out at 0, drawn at 40 still (its move starts here); tapped where it is laid out
  assert_eq(drawn_y(t, 0xFF0000FFL), 40.0)
  assert_eq(t.ctx().rect_of(id).unwrap().1, 0.0)
  t.frame()
  let y2 = drawn_y(t, 0xFF0000FFL)
  assert_true(y2 < 40.0 && y2 > 0.0, msg="\{y2}")
  assert_eq(t.ctx().rect_of(id).unwrap().1, 0.0)
  // said moving by its key, as layout_rest asks of it
  assert_true(t.moving().iter().any(fn(m) { m.contains("Anim \"layout moved\"") }), msg=t.moving().join("; "))
  // its move's own end (its spring's), asked by its key
  t.run_for(@motion.layout_rest("moved") - t.time())
  assert_eq(drawn_y(t, 0xFF0000FFL), 0.0)
  t.assert_idle()
}

///|
test "a keyed node moved by what holds it, its cause the same, is in its new place at once" {
  let above = Ref::new(40.0)
  let t = @ui.Tester::new(fn(c) {
    c.column(fn() {
      c.box(w=Px(50.0), h=Px(above.val), fn() {  }) |> ignore
      let i = c.box(w=Px(50.0), h=Px(20.0), bg=0xFF0000FFL, fn() {  })
      @motion.layout(c, i, "held", by="its words")
    })
    |> ignore
  })
  assert_eq(drawn_y(t, 0xFF0000FFL), 40.0)
  // what is over it shrinks (a window resized, a keyboard): nothing it moves for changed
  above.val = 0.0
  t.frame()
  assert_eq(drawn_y(t, 0xFF0000FFL), 0.0)
  assert_eq(@motion.layout_rest("held"), -1.0)
  t.assert_idle()
}

///|
/// A move told for its cause (its tween's length), and a moment within it.
let caused_ms : Double = 200.0

///|
let caused_midway_ms : Double = 100.0

///|
test "a keyed node on its way, moved by what holds it, goes on with its own move from its new place" {
  let above = Ref::new(40.0)
  let words = Ref::new("one line")
  let t = @ui.Tester::new(fn(c) {
    c.column(fn() {
      c.box(w=Px(50.0), h=Px(above.val), fn() {  }) |> ignore
      let i = c.box(w=Px(50.0), h=Px(20.0), bg=0xFF0000FFL, fn() {  })
      @motion.layout(c, i, "both", spec=@motion.tween(caused_ms, ease=Linear), by=words.val)
    })
    |> ignore
  })
  // moved up 40 for its cause: drawn where it was, then on its way
  above.val = 0.0
  words.val = "two lines"
  t.frame()
  assert_eq(drawn_y(t, 0xFF0000FFL), 40.0)
  t.run_for(caused_midway_ms)
  let mid = drawn_y(t, 0xFF0000FFL)
  assert_true(mid > 0.0 && mid < 40.0, msg="\{mid}")
  let end = @motion.layout_rest("both")
  // what holds it puts it 10 lower, its cause the same: those 10 at once, the rest of its own move as it was (neither
  // started again nor put at its end)
  above.val = 10.0
  t.frame()
  let off = drawn_y(t, 0xFF0000FFL) - 10.0
  assert_true(off > 0.0 && off <= mid, msg="\{off} \{mid}")
  assert_eq(@motion.layout_rest("both"), end)
  t.run_for(end - t.time())
  assert_eq(drawn_y(t, 0xFF0000FFL), 10.0)
  t.assert_idle()
}

///|
test "a keyed node driven to its place, moved again on the way, goes on from where it is drawn" {
  let above = Ref::new(40.0)
  let drive = Ref::new(-1.0)
  let t = @ui.Tester::new(fn(c) {
    c.column(fn() {
      c.box(w=Px(50.0), h=Px(above.val), fn() {  }) |> ignore
      let i = c.box(w=Px(50.0), h=Px(20.0), bg=0xFF0000FFL, fn() {  })
      @motion.layout(c, i, "driven", drive=drive.val)
    })
    |> ignore
  })
  assert_eq(drawn_y(t, 0xFF0000FFL), 40.0)
  // put up by 40: drawn where it was, half way there as the app's progress goes
  above.val = 0.0
  drive.val = 0.0
  t.frame()
  assert_eq(drawn_y(t, 0xFF0000FFL), 40.0)
  drive.val = 0.5
  t.frame()
  assert_eq(drawn_y(t, 0xFF0000FFL), 20.0)
  // its place moves down 10 on the way (what is over it grown back a little): drawn where it was, not put by the move
  // as if it began there
  above.val = 10.0
  t.frame()
  assert_eq(drawn_y(t, 0xFF0000FFL), 20.0)
  // the rest of its way to its new place by what is left of the progress
  drive.val = 0.75
  t.frame()
  assert_eq(drawn_y(t, 0xFF0000FFL), 15.0)
  drive.val = 1.0
  t.frame()
  assert_eq(drawn_y(t, 0xFF0000FFL), 10.0)
}

///|
test "layout_rest: a keyed node's move ends when its spring says, the same whenever asked; -1 at rest" {
  let before = Ref::new(true)
  let t = @ui.Tester::new(fn(c) {
    c.column(fn() {
      if before.val {
        c.box(w=Px(50.0), h=Px(40.0), fn() {  }) |> ignore
      }
      let i = c.box(w=Px(50.0), h=Px(20.0), bg=0xFF0000FFL, fn() {  })
      @motion.layout(c, i, "moved", by="\{before.val}")
    })
    |> ignore
  })
  assert_eq(@motion.layout_rest("moved"), -1.0)
  assert_eq(@motion.layout_rest("nothing of that name"), -1.0)
  before.val = false
  // the frame that moves it (its spring starts there)
  t.draw()
  let end = @motion.layout_rest("moved")
  assert_true(end > t.time() && end < 1.0e300, msg="\{end}")
  t.run_for((end - t.time()) / 2.0)
  assert_eq(@motion.layout_rest("moved"), end)
  t.run_for(end - t.time())
  assert_eq(drawn_y(t, 0xFF0000FFL), 0.0)
  assert_eq(@motion.layout_rest("moved"), -1.0)
  t.assert_idle()
}

///|
test "shown and hidden: in by its enter, out by its exit, then gone" {
  let shown = Ref::new(false)
  let looks : Array[@ui.Look?] = []
  let enter = @motion.trans(fade=0.0, scale=0.6, dy=18.0, spec=@motion.tween(220.0, ease=Out), fade_spec=@motion.tween(180.0, ease=Out))
  let exit = @motion.trans(fade=0.0, scale=0.6, dy=18.0, spec=@motion.tween(180.0, ease=Out), fade_spec=@motion.tween(150.0, ease=Out))
  let t = @ui.Tester::new(fn(c) { looks.push(@motion.presence(c, "pill", shown.val, enter~, exit~)) })
  assert_eq(looks[looks.length() - 1], None)
  shown.val = true
  t.frame()
  // told this frame: it starts here
  match looks[looks.length() - 1] {
    Some(l) => assert_eq((l.alpha, l.sx, l.dy), (0.0, 0.6, 18.0))
    None => fail("shown")
  }
  // from its first frame, just drawn: the enter's own length
  t.run_for(trans_ms(enter))
  match looks[looks.length() - 1] {
    Some(l) => assert_eq(l, @ui.look(ox=0.5, oy=0.5))
    None => fail("shown")
  }
  shown.val = false
  t.frame()
  assert_true(looks[looks.length() - 1] is Some(_))
  // from the frame it is told in, the exit's own length
  t.run_for(trans_ms(exit))
  assert_eq(looks[looks.length() - 1], None)
  t.assert_idle()
}

///|
/// How long a transition takes: the longer of its fade's and its move's (their specs' own lengths).
fn trans_ms(tr : @motion.Trans) -> Double {
  let f = tr.fade_spec.duration(0.0, 1.0, 0.0)
  let m = tr.spec.duration(0.0, 1.0, 0.0)
  if f > m {
    f
  } else {
    m
  }
}

///|
test "a list's row gone leaves by a copy; the rest close over it, late" {
  let keys = Ref::new(["a", "b", "c", "d"])
  let ids : Map[String, Int] = {}
  let t = @ui.Tester::new(
    fn(c) {
      let ks = keys.val
      @motion.list_keys(c, "rows", ks.map(fn(k) { "row/" + k })) |> ignore
      c.list("rows", ks.length(), 40.0, fn(i) {
        let k = ks[i]
        let id = c.id("row/" + k)
        ids[k] = id
        let n = c.box(w=Fill(1.0), h=Px(40.0), bg=0x202020FFL, id~, fn() {
          c.text(k) |> ignore
        })
        @motion.layout(
          c,
          n,
          "row/" + k,
          enter=@motion.trans(fade=0.0, scale=0.9, spec=@motion.tween(240.0, ease=Out, delay=100.0)),
          exit=@motion.trans(fade=0.0, scale=0.9, spec=@motion.tween(200.0, ease=Leave)),
        )
      })
      |> ignore
    },
    w=200.0,
    h=400.0,
  )
  let before = t.instances()
  keys.val = ["a", "c", "d"]
  t.frame()
  // the copy of b drawn as the rest: more drawn than the three rows
  assert_true(t.instances() > before - 1, msg="\{t.instances()} \{before}")
  t.frame()
  t.frame()
  t.frame()
  // c waits 100 ms before it closes over b (still at 80 after three frames)
  let c_y = t.drawn_of("c").unwrap().1
  assert_eq(c_y, 80.0)
  // tapped where it is laid out already
  assert_eq(t.ctx().rect_of(ids["c"]).unwrap().1, 40.0)
  // c's own close over b, to its end (d's the same; b's copy gone before)
  t.run_for(@motion.layout_rest("row/c") - t.time())
  assert_eq(t.drawn_of("c").unwrap().1, 40.0)
  assert_eq(@motion.layout_rest("row/d"), -1.0)
  // a row new to the list comes in
  keys.val = ["e", "a", "c", "d"]
  t.frame()
  // (their motions start in that frame) to the end of e's entrance and of a's move
  let e_end = @motion.layout_rest("row/e")
  let a_end = @motion.layout_rest("row/a")
  t.run_for((if e_end > a_end { e_end } else { a_end }) - t.time())
  assert_eq(t.drawn_of("a").unwrap().1, 40.0)
  // one going ahead of the others goes from where it was and comes in where it is, never across them: drawn at its
  // place from the first frame (coming in there), a copy of it leaving where it was
  keys.val = ["d", "e", "a", "c"]
  t.frame()
  assert_eq(@motion.lifted(t.ctx(), t.ctx().id("rows"), "row/d"), -1.0)
  // (its copy leaving and its coming in, by its key)
  assert_true(@motion.layout_rest("row/d") > t.time())
  // (half way in: at its place, never on its way across)
  t.run_for((@motion.layout_rest("row/d") - t.time()) / 2.0)
  assert_eq(t.drawn_of("d").unwrap().1, 0.0)
  // (to the end of its coming in, of the rest making room and closing up, and of its copy leaving)
  t.run_for(@motion.layout_rest("row/d") - t.time())
  for k in ["e", "a", "c"] {
    let end = @motion.layout_rest("row/" + k)
    if end > t.time() {
      t.run_for(end - t.time())
    }
  }
  assert_eq(t.drawn_of("d").unwrap().1, 0.0)
  t.assert_idle()
}

///|
test "a list held at its end, a row gone: what is over it comes down over its place, what is under it stays" {
  let keys = Ref::new(Array::makei(20, fn(i) { i }))
  let t = @ui.Tester::new(
    fn(c) {
      let ks = keys.val
      @motion.list_keys(c, "rows", ks.map(fn(k) { "row/\{k}" })) |> ignore
      c.list("rows", ks.length(), 40.0, fn(i) {
        let k = ks[i]
        let n = c.box(w=Fill(1.0), h=Px(40.0), bg=0x202020FFL, id=c.id("row/\{k}"), fn() {
          c.text("<\{k}>") |> ignore
        })
        @motion.layout(
          c,
          n,
          "row/\{k}",
          exit=@motion.trans(fade=0.0, scale=0.9, spec=@motion.tween(200.0, ease=Leave)),
        )
      })
      |> ignore
    },
    w=200.0,
    h=400.0,
  )
  t.scroll_to_end()
  t.frame()
  t.frame()
  assert_eq(t.drawn_of("<19>").unwrap().1, 360.0)
  assert_eq(t.drawn_of("<14>").unwrap().1, 160.0)
  // 15 goes: the list's foot stays where it is, so what is under 15 stays, and what is over it comes down to close
  // over its place (late, as rows close over one gone), never all of it put a row down at once
  keys.val = keys.val.filter(fn(k) { k != 15 })
  t.frame()
  assert_eq(t.drawn_of("<14>").unwrap().1, 160.0)
  assert_eq(t.drawn_of("<16>").unwrap().1, 240.0)
  assert_eq(t.drawn_of("<19>").unwrap().1, 360.0)
  // (9, come into view over them, comes down with them from out of view)
  assert_eq(t.drawn_of("<9>").unwrap().1, -40.0)
  t.run_for(@motion.layout_rest("row/14") - t.time())
  assert_eq(t.drawn_of("<9>").unwrap().1, 0.0)
  assert_eq(t.drawn_of("<14>").unwrap().1, 200.0)
  assert_eq(t.drawn_of("<13>").unwrap().1, 160.0)
  assert_eq(t.drawn_of("<16>").unwrap().1, 240.0)
}

///|
test "a list's rows alike at its start and its end are none of its change: only those between come, go and go ahead" {
  let keys = Ref::new(["p", "q", "x", "y", "r", "s"])
  let t = @ui.Tester::new(
    fn(c) {
      let ks = keys.val
      @motion.list_keys(c, "rows", ks.map(fn(k) { "row/" + k })) |> ignore
      c.list("rows", ks.length(), 40.0, fn(i) {
        let k = ks[i]
        let n = c.box(w=Fill(1.0), h=Px(40.0), bg=0x202020FFL, id=c.id("row/" + k), fn() {
          c.text(k) |> ignore
        })
        @motion.layout(
          c,
          n,
          "row/" + k,
          enter=@motion.trans(fade=0.0, scale=0.9, spec=@motion.tween(240.0, ease=Out)),
          exit=@motion.trans(fade=0.0, scale=0.9, spec=@motion.tween(200.0, ease=Leave)),
        )
      })
      |> ignore
    },
    w=200.0,
    h=400.0,
  )
  let list = t.ctx().id("rows")
  // y goes ahead of x: it alone comes in anew where it is (at its place at once, never across x), x alone moves; none
  // before them nor after
  keys.val = ["p", "q", "y", "x", "r", "s"]
  t.frame()
  assert_true(@motion.layout_rest("row/x") > t.time())
  for k in ["p", "q", "r", "s"] {
    assert_eq(@motion.layout_rest("row/" + k), -1.0, msg=k)
    assert_eq(@motion.lifted(t.ctx(), list, "row/" + k), -1.0, msg=k)
  }
  // (to the end of x's move, y's coming in and its copy's leaving)
  let x_end = @motion.layout_rest("row/x")
  let y_end = @motion.layout_rest("row/y")
  t.run_for((y_end - t.time()) / 2.0)
  assert_eq(t.drawn_of("y").unwrap().1, 80.0)
  t.run_for((if x_end > y_end { x_end } else { y_end }) - t.time())
  t.assert_idle()
  // between them x goes and n comes: n comes in, x's copy leaves, the rest stay where they are
  keys.val = ["p", "q", "y", "n", "r", "s"]
  t.frame()
  assert_true(@motion.layout_rest("row/n") > t.time())
  assert_true(@motion.layout_rest("row/x") > t.time())
  for k in ["p", "q", "y", "r", "s"] {
    assert_eq(@motion.layout_rest("row/" + k), -1.0, msg=k)
  }
}

///|
test "a node flown from a rect is drawn there first, then at its place" {
  let p = Ref::new(0.0)
  let mut id = 0
  let t = @ui.Tester::new(fn(c) {
    id = c.id("flown")
    c.column(fn() {
      c.box(h=Px(100.0), fn() {  }) |> ignore
      let i = c.box(w=Px(30.0), h=Px(10.0), id~, bg=0x00FF00FFL, fn() {  })
      @motion.fly(c, i, 5.0, 300.0, px=p.val, py=p.val)
    })
    |> ignore
  })
  let (x, y) = drawn_xy(t, 0x00FF00FFL)
  assert_eq((x, y), (5.0, 300.0))
  // tapped where it is laid out, not where it flies
  let (lx, ly, _, _) = t.ctx().rect_of(id).unwrap()
  assert_eq((lx, ly), (0.0, 100.0))
  p.val = 0.5
  t.frame()
  let (x2, y2) = drawn_xy(t, 0x00FF00FFL)
  assert_eq((x2, y2), (2.5, 200.0))
  p.val = 1.0
  t.frame()
  let (x3, y3) = drawn_xy(t, 0x00FF00FFL)
  assert_eq((x3, y3), (0.0, 100.0))
}

///|
/// A spring's value `ms` into it, as an Anim plays it.
fn spring_value(spec : @motion.Spec, from : Double, to : Double, v : Double, ms : Double) -> Double {
  let dur = spec.duration(from, to, v)
  spec.value_at(ms, dur, from, to, v).0
}

///|
test "springs match Compose's own FloatSpringSpec, frame for frame" {
  // printed by Compose's animation-core 1.10.1 itself (scripts/compose_ref.sh)
  let move = 2.0 * 3.141592653589793 / (1.2 * 0.28)
  let sheet = 2.0 * 3.141592653589793 / (1.2 * 0.32)
  let cases : Array[(@motion.Spec, Double, Double, Double, Double, Array[Double])] = [
    (@motion.spring(), 0.0, 1.0, 0.0, 171.0, [0.0, 0.12842241, 0.3653931, 0.57653147, 0.8986603, 0.9795784, 1.0, 1.0]),
    (@motion.row_spring, 100.0, 0.0, 0.0, 354.0, [100.0, 96.32119, 87.23453, 75.95016, 44.20961, 23.001738, 11.24473, 2.414866]),
    (@motion.Spring(1.0, move * move, 0.5, 0.0), 66.0, 0.0, 0.0, 372.0, [66.0, 63.573936, 57.58083, 50.137196, 29.194187, 15.195139, 7.4312854, 1.597196]),
    (@motion.motion_spring(0.24, bounce=0.08, threshold=0.001), 0.9, 1.0, 0.0, 276.0, [0.9, 0.9049251, 0.9167734, 0.9309648, 0.9673801, 0.98751396, 0.9960531, 1.0]),
    (@motion.Spring(1.0, sheet * sheet, 0.5, 0.0), 600.0, 0.0, 0.0, 576.0, [600.0, 582.698, 538.4667, 481.358, 307.9814, 178.07419, 97.186775, 26.170254]),
    (@motion.Spring(1.0, sheet * sheet, 0.5, 0.0), 300.0, 600.0, 3000.0, 476.0, [300.0, 345.59494, 388.46097, 425.50986, 504.42215, 549.62573, 574.1537, 593.5585]),
    (@motion.Spring(1.5, 400.0, 0.01, 0.0), 1.0, 0.0, 0.0, 623.0, [1.0, 0.9622028, 0.8795778, 0.7866456, 0.54449564, 0.3721823, 0.25406164, 0.118352056]),
    (@motion.Spring(0.5, 300.0, 0.01, 0.0), 0.0, 1.0, 0.0, 548.0, [0.0, 0.03486575, 0.13268787, 0.2702275, 0.72800976, 1.0488173, 1.1607358, 1.0576857]),
    (@motion.Spring(1.0, 300.0, 1.0, 0.0), 80.0, 0.0, 0.0, 368.0, [80.0, 77.4407, 70.98931, 62.79101, 38.668617, 21.420528, 11.178508, 2.7450595]),
  ]
  let at = [0.0, 16.0, 33.0, 50.0, 100.0, 150.0, 200.0, 300.0]
  for k in cases {
    let (spec, from, to, v, dur, want) = k
    assert_eq(spec.duration(from, to, v), dur)
    for i, ms in at {
      let got = spring_value(spec, from, to, v, ms)
      // Compose's are floats
      let eps = 2.0e-6 * dmax2(from.abs(), to.abs()) + 1.0e-6
      assert_true(near(got, want[i], eps), msg="\{spec} at \{ms}: \{got} not \{want[i]}")
    }
  }
}

///|
fn dmax2(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
test "tweens match Compose's own FloatTweenSpec, frame for frame" {
  // printed by Compose's animation-core 1.10.1 itself (scripts/compose_ref.sh)
  let cases : Array[(@motion.Spec, Array[Double])] = [
    (@motion.tween(240.0, ease=Out, delay=100.0), [0.0, 0.0, 0.0, 0.0, 0.6550595, 0.888813, 0.9670928, 0.9949123, 1.0]),
    (@motion.tween(600.0, ease=Flight), [0.0, 6.85673e-4, 0.0073552486, 0.034629226, 0.09583283, 0.22449233, 0.47193307, 0.7046854, 0.91095346]),
    (@motion.tween(160.0, ease=Linear), [0.0, 0.1, 0.3125, 0.625, 0.9375, 1.0, 1.0, 1.0, 1.0]),
  ]
  let at = [0.0, 16.0, 50.0, 100.0, 150.0, 200.0, 250.0, 300.0, 400.0]
  for k in cases {
    let (spec, want) = k
    let dur = spec.duration(0.0, 1.0, 0.0)
    for i, ms in at {
      let got = spec.value_at(ms, dur, 0.0, 1.0, 0.0).0
      assert_true(near(got, want[i], 2.0e-6), msg="\{spec} at \{ms}: \{got} not \{want[i]}")
    }
  }
}

///|
test "a look moves what is drawn, never where it is tapped" {
  let taps = Ref::new(0)
  let t = @ui.Tester::new(fn(c) {
    c.box(w=Px(200.0), h=Px(100.0), clip=true, fn() {
      c.box(h=Px(40.0), min_h=40.0, fn() {  }) |> ignore
      let id = c.id("button")
      if c.clicked(id) {
        taps.val = taps.val + 1
      }
      let b = c.box(w=Px(200.0), h=Px(30.0), min_h=30.0, bg=0x336699FFL, id~, fn() {  })
      c.look(b, @ui.look(dy=20.0))
    })
    |> ignore
  })
  t.frame()
  // laid out at 40, drawn at 60
  assert_eq(drawn_y(t, 0x336699FFL), 60.0)
  // where it is drawn and not laid out: nothing
  t.tap_once(100.0, 85.0)
  t.frame()
  assert_eq(taps.val, 0)
  // where it is laid out: at once
  t.tap_once(100.0, 50.0)
  t.frame()
  assert_eq(taps.val, 1)
}

///|
test "what is faded to nothing is tapped where it is laid out" {
  let taps = Ref::new(0)
  let t = @ui.Tester::new(fn(c) {
    let id = c.id("faded")
    if c.clicked(id) {
      taps.val = taps.val + 1
    }
    let b = c.box(w=Px(100.0), h=Px(40.0), bg=0x123456FFL, id~, fn() {  })
    c.look(b, @ui.look(alpha=0.0, scale=0.9))
  })
  t.frame()
  assert_eq(t.drawn_rects().filter(fn(r) { r.4 == 0x123456FFL }).length(), 0)
  t.tap_once(50.0, 20.0)
  t.frame()
  assert_eq(taps.val, 1)
}

///|
test "what leaves is drawn, and a tap meanwhile goes to what is under it" {
  // a sheet over a button: shown, the sheet is tapped; let go of, it is drawn while it fades and the button under it
  // is tapped at once
  let shown = Ref::new(true)
  let under = Ref::new(0)
  let over = Ref::new(0)
  let sheet_ms = 300.0
  let t = @ui.Tester::new(fn(c) {
    let u = c.id("under")
    if c.clicked(u) {
      under.val = under.val + 1
    }
    let o = c.id("over")
    if c.clicked(o) {
      over.val = over.val + 1
    }
    c.box(w=Px(200.0), h=Px(100.0), bg=0x112233FFL, id=u, fn() {  }) |> ignore
    match @motion.presence(c, "sheet", shown.val, enter=@motion.trans(fade=0.0, spec=@motion.tween(sheet_ms, ease=Out))) {
      Some(look) => {
        let l = c.layer(fn() {
          let b = c.box(w=Px(200.0), h=Px(100.0), bg=0x445566FFL, id=o, fn() {  })
          c.look(b, look)
        })
        @motion.leaving(c, l, shown.val)
      }
      None => ()
    }
  })
  t.frame()
  t.tap_once(100.0, 50.0)
  t.frame()
  assert_eq((over.val, under.val), (1, 0))
  // the sheet's rect as drawn, however faded (its opacity applied to its colour): not the button's
  let sheet = fn() { t.drawn_rects().filter(fn(r) { r.2 == 200.0 && r.4 != 0x112233FFL }) }
  shown.val = false
  t.frame()
  // still drawn, going from here
  assert_eq(sheet().map(fn(r) { r.4 }), [0x445566FFL])
  t.tap_once(100.0, 50.0)
  t.frame()
  assert_eq((over.val, under.val), (1, 1))
  // drawn fainter as it goes, then gone
  assert_true(sheet().length() == 1 && (sheet()[0].4 & 0xFFL) < 0xFFL)
  t.run_for(sheet_ms)
  assert_eq(sheet().length(), 0)
}

///|
test "what is drawn cut while it opens is tapped whole, where it is laid out" {
  // a box growing up from its foot (the composer's capsule): its line above what is drawn yet is tapped at once
  let taps = Ref::new(0)
  let t = @ui.Tester::new(fn(c) {
    let id = c.id("line")
    if c.clicked(id) {
      taps.val = taps.val + 1
    }
    let b = c.box(w=Px(200.0), fn() {
      c.box(w=Px(200.0), h=Px(40.0), min_h=40.0, bg=0x0A0B0CFFL, id~, fn() {  }) |> ignore
      c.box(w=Px(200.0), h=Px(60.0), min_h=60.0, bg=0x0D0E0FFFL, fn() {  }) |> ignore
    })
    // its bottom 50 drawn: the line, wholly above, not at all
    c.cut_to_bottom(b, 50.0)
  })
  t.frame()
  assert_eq(t.drawn_rects().filter(fn(r) { r.4 == 0x0A0B0CFFL }).length(), 0)
  assert_eq(t.drawn_rects().filter(fn(r) { r.4 == 0x0D0E0FFFL }).length(), 1)
  t.tap_once(100.0, 20.0)
  t.frame()
  assert_eq(taps.val, 1)
}

///|
test "what is moved into a box that cuts it from outside it is drawn there" {
  // a row laid out wholly below the box it is in, a button in it drawn moved up into the box: drawn (its row is not
  // left out for being outside), and tapped where it is laid out (cut away: nowhere)
  let taps = Ref::new(0)
  let t = @ui.Tester::new(fn(c) {
    c.box(w=Px(200.0), h=Px(100.0), clip=true, fn() {
      c.box(h=Px(110.0), min_h=110.0, fn() {  }) |> ignore
      let id = c.id("button")
      if c.clicked(id) {
        taps.val = taps.val + 1
      }
      c.box(dir=Row, h=Px(30.0), min_h=30.0, fn() {
        let b = c.box(w=Px(200.0), h=Px(30.0), min_h=30.0, bg=0x336699FFL, id~, fn() {  })
        c.look(b, @ui.look(dy=-40.0))
      })
      |> ignore
    })
    |> ignore
  })
  t.frame()
  assert_eq(drawn_y(t, 0x336699FFL), 70.0)
  t.tap_once(100.0, 85.0)
  t.frame()
  assert_eq(taps.val, 0)
}

///|
/// The top of the one rect drawn in `color`.
fn drawn_y(t : @ui.Tester, color : Int64) -> Double {
  drawn_xy(t, color).1
}

///|
/// The top left of the one rect drawn in `color`.
fn drawn_xy(t : @ui.Tester, color : Int64) -> (Double, Double) {
  let rs = t.drawn_rects().filter(fn(r) { r.4 == color })
  if rs.is_empty() {
    (-1.0, -1.0)
  } else {
    (rs[0].0, rs[0].1)
  }
}

///|
/// An Anim told to go to 100 in the first frame (kept in `kept`), its end asked in that frame when `ask`.
fn told_once(ask : Bool, fade_ms : Double, kept : Ref[@motion.Anim?]) -> @ui.Tester {
  let go = Ref(true)
  @ui.Tester::new(fn(c) {
    let v = @motion.anim(c, "a", 0.0)
    if go.val {
      go.val = false
      v.animate(100.0, @motion.tween(fade_ms, ease=Out))
      kept.val = Some(v)
      if ask {
        // started here, at this frame's time: its end said at once
        if v.ends_at() != c.now() + fade_ms {
          abort("an Anim told in a frame did not say its end there")
        }
      }
    }
    ignore(v.get())
  })
}

///|
test "an Anim's start is the frame it is told in, whoever asks its end then or between" {
  let fade_ms = 200.0
  let a1 : Ref[@motion.Anim?] = Ref(None)
  let quiet = told_once(false, fade_ms, a1)
  quiet.draw()
  let a2 : Ref[@motion.Anim?] = Ref(None)
  let asked = told_once(true, fade_ms, a2)
  // (told in its first frame)
  let told = asked.time()
  asked.draw()
  let end = fn(r : Ref[@motion.Anim?]) {
    match r.val {
      Some(a) => a.ends_at()
      None => -1.0
    }
  }
  // started at the frame it was told in: its end from there
  let e = end(a2)
  assert_eq(e, end(a1))
  assert_eq(end(a2), e)
  assert_eq(e, told + fade_ms)
  // asked again half-way, the same
  asked.run_for(fade_ms / 2.0)
  assert_eq(end(a2), e)
  asked.run_for(e - asked.time())
  asked.assert_idle()
}

///|
/// A moment just after a list's rows changed (within what was once a window of 150 ms in which any move counted).
let just_after_ms : Double = 50.0

///|
test "a list's row moved by something else just after its rows changed is in its new place at once" {
  let keys = Ref::new(["a", "b", "c"])
  let tall_a = Ref::new(false)
  let t = @ui.Tester::new(
    fn(c) {
      let ks = keys.val
      @motion.list_keys(c, "rows", ks.map(fn(k) { "row/" + k })) |> ignore
      c.list("rows", ks.length(), 40.0, fn(i) {
        let k = ks[i]
        let h = if k == "a" && tall_a.val { 80.0 } else { 40.0 }
        let n = c.box(w=Fill(1.0), h=Px(h), bg=if k == "c" { 0xFF0000FFL } else { 0x202020FFL }, fn() {
          c.text(k) |> ignore
        })
        @motion.layout(c, n, "row/" + k)
      })
      |> ignore
    },
    w=200.0,
    h=400.0,
  )
  assert_eq(drawn_y(t, 0xFF0000FFL), 80.0)
  // b goes: c closes over it, on its way for the list's change
  keys.val = ["a", "c"]
  t.draw()
  t.run_for(@motion.layout_rest("row/c") - t.time())
  assert_eq(drawn_y(t, 0xFF0000FFL), 40.0)
  // the rows change again, and just after a row over c grows (its words came, not the list's change): c is pushed
  // down by those 40 at once
  keys.val = ["a", "c", "d"]
  t.draw()
  t.run_for(just_after_ms)
  tall_a.val = true
  t.frame()
  assert_eq(drawn_y(t, 0xFF0000FFL), 80.0)
  assert_eq(@motion.layout_rest("row/c"), -1.0)
}

///|
test "layout_rest: a list's row gone, when its copy has left; its copy said to move by its key" {
  let keys = Ref::new(["a", "b", "c"])
  let t = @ui.Tester::new(
    fn(c) {
      let ks = keys.val
      @motion.list_keys(c, "rows", ks.map(fn(k) { "row/" + k })) |> ignore
      c.list("rows", ks.length(), 40.0, fn(i) {
        let k = ks[i]
        let n = c.box(w=Fill(1.0), h=Px(40.0), bg=0x202020FFL, id=c.id("row/" + k), fn() {
          c.text(k) |> ignore
        })
        @motion.layout(c, n, "row/" + k, exit=@motion.trans(fade=0.0, scale=0.9, spec=@motion.tween(200.0, ease=Leave)))
      })
      |> ignore
    },
    w=200.0,
    h=400.0,
  )
  assert_eq(@motion.layout_rest("row/b"), -1.0)
  keys.val = ["a", "c"]
  t.draw()
  // its copy's way said as it sets out: the same whenever asked, and as its two Anims say it
  let end = @motion.layout_rest("row/b")
  assert_true(end > t.time() && end < @double.infinity, msg="\{end} at \{t.time()}")
  assert_eq(t.rest_of("row/b leaving"), end)
  assert_true(t.moving().iter().any(fn(m) { m.contains("Anim \"row/b leaving\"") }), msg=t.moving().join("; "))
  // half way
  t.run_for(((end - t.time()) / 2.0).floor())
  assert_eq(@motion.layout_rest("row/b"), end)
  // (its copy drawn beside the two rows)
  let leaving = t.instances()
  // run to it: the copy gone, nothing of b left to wait for
  t.run_for(end - t.time())
  assert_eq(@motion.layout_rest("row/b"), -1.0)
  assert_true(t.instances() < leaving, msg="\{t.instances()} \{leaving}")
}

///|
test "run_for: what its last frame says starts there is drawn at that moment, its end known as run_for returns" {
  let shown = 300.0
  let fade : Ref[@motion.Anim?] = Ref::new(None)
  let begun = Ref::new(-1.0)
  let t = @ui.Tester::new(fn(c) {
    let a = @motion.anim(c, "toast-fade", 1.0)
    fade.val = Some(a)
    if begun.val < 0.0 {
      begun.val = c.now()
    }
    // (a toast's deadline: it goes once shown that long, from the first frame)
    if c.now() >= begun.val + shown && a.target() != 0.0 {
      a.animate(0.0, @motion.tween(200.0, ease=Out))
    }
    c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore
  })
  t.run_for(begun.val + shown - t.time())
  let end = fade.val.unwrap().ends_at()
  assert_true(end > t.time() && end < @double.infinity, msg="\{end} at \{t.time()}")
  t.run_for(end - t.time())
  t.assert_idle()
}

///|
test "a chain of tweens each from the one before's declared end, whichever frame saw it end: as if one" {
  // three of 100, 70 and 130 ms (lengths that are no whole number of frames), each told a frame after the one before
  // was seen at its end
  let lengths = [100.0, 70.0, 130.0]
  let segs : Array[@motion.Anim] = [@motion.Anim::new(0.0), @motion.Anim::new(0.0), @motion.Anim::new(0.0)]
  let k = Ref::new(-1)
  let seen_end = Ref::new(false)
  let seen : Array[(Double, Int, Double)] = []
  let t = @ui.Tester::new(fn(c) {
    let i = k.val
    if i < 0 {
      k.val = 0
      segs[0].animate(1.0, @motion.tween(lengths[0], ease=Linear))
    } else if i < 3 && !segs[i].moving() {
      if !seen_end.val {
        // seen at its end: the next told only the frame after
        seen_end.val = true
      } else if i < 2 {
        seen_end.val = false
        k.val = i + 1
        segs[i + 1].animate(1.0, @motion.tween(lengths[i + 1], ease=Linear), start_at=segs[i].ends())
      }
    }
    let j = k.val
    seen.push((c.now(), j, segs[j].get()))
    c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore
  })
  t.draw()
  let start = segs[0].ends() - lengths[0]
  // the whole chain and a while after it, a frame every look_ms (the moments the test looks at it: the app tells each
  // next segment at the frame after it saw the last one's end)
  let after_ms = 100.0
  let look_ms = 25.0
  let until = t.time() + lengths[0] + lengths[1] + lengths[2] + after_ms
  while t.time() < until {
    t.run_for(if until - t.time() < look_ms { until - t.time() } else { look_ms })
  }
  // each frame: the segment it is in, as far on as the time since the chain's start says (once its segment is told;
  // in whole ms, as a motion's time goes)
  let ends = [start + lengths[0], start + lengths[0] + lengths[1], start + lengths[0] + lengths[1] + lengths[2]]
  for f in seen {
    let (now, j, v) = f
    let from = if j == 0 { start } else { ends[j - 1] }
    let want = if now >= ends[j] { 1.0 } else { (now - from).floor() / lengths[j] }
    assert_true(near(v, want, 1.0e-9), msg="at \{now} segment \{j}: \{v} not \{want}")
  }
  // the last one's end: the three lengths from the first's start, exactly
  assert_true(near(segs[2].ends(), start + lengths[0] + lengths[1] + lengths[2], 1.0e-9))
  t.assert_idle()
}

///|
test "a chain caught up after a while unseen: what is over is there at once, only the one under way said to move" {
  let lengths = [100.0, 70.0, 130.0]
  let segs : Array[@motion.Anim] = [@motion.Anim::new(0.0), @motion.Anim::new(0.0), @motion.Anim::new(0.0)]
  let shown = Ref::new(true)
  let k = Ref::new(-1)
  let t = @ui.Tester::new(fn(c) {
    if k.val < 0 {
      k.val = 0
      segs[0].animate(1.0, @motion.tween(lengths[0], ease=Linear))
    }
    if shown.val {
      // in the same build, each over one followed by the next from its declared end, till one is under way
      while k.val < 2 && !segs[k.val].moving() {
        segs[k.val + 1].animate(1.0, @motion.tween(lengths[k.val + 1], ease=Linear), start_at=segs[k.val].ends())
        k.val += 1
      }
      segs[k.val].get() |> ignore
    }
    c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore
  })
  t.draw()
  let start = segs[0].ends() - lengths[0]
  // unseen a while: nothing asks it on, the first is over long since
  shown.val = false
  // seen again at the display's frame at or past the second's middle: the first over (100), the second under way
  // (170 still to come)
  t.run_for(start + lengths[0] + lengths[1] / 2.0 - 1.0 - t.time())
  shown.val = true
  t.draw()
  assert_eq(k.val, 1)
  assert_true(near(segs[1].get(), (t.time() - (start + lengths[0])).floor() / lengths[1], 1.0e-9))
  assert_false(segs[0].moving())
  assert_true(segs[1].moving())
  // (said to move: only the one under way)
  assert_eq(t.moving().length(), 1)
  // unseen past the whole chain's end, seen again: caught up in one build, at the last one's end, nothing moving
  shown.val = false
  let away_ms = 5000.0
  t.run_for(away_ms)
  shown.val = true
  t.draw()
  assert_eq(k.val, 2)
  assert_eq(segs[2].get(), 1.0)
  assert_false(segs[2].moving())
  assert_true(near(segs[2].ends(), start + lengths[0] + lengths[1] + lengths[2], 1.0e-9))
  t.assert_idle()
}

///|
test "a chain with motion reduced: each there at once, its end the moment it was told, the whole chain in one build" {
  let lengths = [100.0, 70.0, 130.0]
  let segs : Array[@motion.Anim] = [@motion.Anim::new(0.0), @motion.Anim::new(0.0), @motion.Anim::new(0.0)]
  let k = Ref::new(-1)
  let t = @ui.Tester::new(fn(c) {
    if k.val < 0 {
      k.val = 0
      segs[0].animate(1.0, @motion.tween(lengths[0], ease=Linear))
    }
    // each at its end followed by the next from its declared end, in the same build
    while k.val < 2 && !segs[k.val].moving() {
      segs[k.val + 1].animate(1.0, @motion.tween(lengths[k.val + 1], ease=Linear), start_at=segs[k.val].ends())
      k.val += 1
    }
    c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore
  })
  t.set_reduce_motion(true)
  k.val = -1
  t.draw()
  assert_eq(k.val, 2)
  for s in segs {
    assert_eq(s.get(), 1.0)
    assert_false(s.moving())
    assert_true(s.ends() <= t.time())
  }
  t.assert_idle()
}

///|
/// The rect drawn in `color`: x, y, w, h.
fn drawn_box(t : @ui.Tester, color : Int64) -> (Double, Double, Double, Double) {
  let rs = t.drawn_rects().filter(fn(r) { r.4 == color })
  if rs.is_empty() {
    (-1.0, -1.0, -1.0, -1.0)
  } else {
    (rs[0].0, rs[0].1, rs[0].2, rs[0].3)
  }
}

///|
/// A shape changed for its cause (its tween's length), and a moment within it.
let reshape_ms : Double = 200.0

///|
let reshape_midway_ms : Double = 100.0

///|
test "a box reshaped for its cause: what it holds there at once, its ground from the shape it had to the new one" {
  let lines = Ref::new(1)
  let t = @ui.Tester::new(fn(c) {
    c.column(fn() {
      let b = c.box(w=Px(100.0), h=Px(20.0 * lines.val.to_double()), bg=0xFF0000FFL, fn() {
        c.box(w=Px(10.0), h=Px(10.0), bg=0x00FF00FFL, fn() {  }) |> ignore
      })
      @motion.reshape(c, b, "box", by="\{lines.val} lines", spec=@motion.tween(reshape_ms, ease=Linear))
    })
    |> ignore
  })
  assert_eq(drawn_box(t, 0xFF0000FFL), (0.0, 0.0, 100.0, 20.0))
  // a second line: laid out 40 high at once (what it holds where it now is), its ground still 20 as the move sets out
  lines.val = 2
  t.frame()
  assert_eq(drawn_box(t, 0xFF0000FFL).3, 20.0)
  assert_eq(drawn_box(t, 0x00FF00FFL), (0.0, 0.0, 10.0, 10.0))
  t.run_for(reshape_midway_ms)
  let mid = drawn_box(t, 0xFF0000FFL).3
  assert_true(mid > 20.0 && mid < 40.0, msg="\{mid}")
  t.run_for(@motion.layout_rest("box") - t.time())
  assert_eq(drawn_box(t, 0xFF0000FFL).3, 40.0)
  t.assert_idle()
}

///|
/// A box 100 wide gone 100 down for its cause, from 20 high to 60, with (`there`) what it did not hold before in its
/// foot: 10 square at its left, under 50 of room; keyed.
fn moved_box(there : Ref[Bool], carry : Bool) -> @ui.Tester {
  @ui.Tester::new(fn(c) {
    c.column(fn() {
      c.box(w=Px(10.0), h=Px(if there.val { 100.0 } else { 0.0 }), fn() {  }) |> ignore
      let b = c.box(w=Px(100.0), h=Px(if there.val { 60.0 } else { 20.0 }), bg=0xFF0000FFL, fn() {
        if there.val {
          c.box(w=Px(10.0), h=Px(50.0), fn() {  }) |> ignore
          let n = c.box(w=Px(10.0), h=Px(10.0), bg=0x00FF00FFL, fn() {  })
          @motion.layout(c, n, "box/new", spec=@motion.tween(reshape_ms, ease=Linear), by="\{there.val}")
        }
      })
      @motion.reshape(c, b, "box", by="\{there.val}", spec=@motion.tween(reshape_ms, ease=Linear), carry~)
    })
    |> ignore
  })
}

///|
test "a box gone with what it holds (carry): what is new in it carried on its ground, as far from its nearer edges, until it is there" {
  let there = Ref::new(false)
  let t = moved_box(there, true)
  there.val = true
  t.frame()
  // its ground as it was (0, 0, 100 by 20), what is new in it at that ground's foot
  assert_eq(drawn_box(t, 0xFF0000FFL), (0.0, 0.0, 100.0, 20.0))
  assert_eq(drawn_box(t, 0x00FF00FFL), (0.0, 10.0, 10.0, 10.0))
  // half way: the ground 50 down, 40 high; still at its foot
  t.run_for(reshape_midway_ms)
  assert_eq(drawn_box(t, 0xFF0000FFL), (0.0, 50.0, 100.0, 40.0))
  assert_eq(drawn_box(t, 0x00FF00FFL), (0.0, 80.0, 10.0, 10.0))
  assert_true(@motion.layout_rest("box/new") > t.time())
  t.run_for(@motion.layout_rest("box") - t.time())
  assert_eq(drawn_box(t, 0x00FF00FFL), (0.0, 150.0, 10.0, 10.0))
  t.assert_idle()
}

///|
test "a box changed in its place (no carry): what is new in it is in its place from the first" {
  let there = Ref::new(false)
  let t = moved_box(there, false)
  there.val = true
  t.frame()
  assert_eq(drawn_box(t, 0xFF0000FFL), (0.0, 0.0, 100.0, 20.0))
  assert_eq(drawn_box(t, 0x00FF00FFL), (0.0, 150.0, 10.0, 10.0))
  t.run_for(@motion.layout_rest("box") - t.time())
  t.assert_idle()
}

///|
/// The corners of the first plain rectangle of `color` the last frame drew, each its own (top left, then round it).
fn drawn_corners(t : @ui.Tester, color : Int64) -> (Double, Double, Double, Double) {
  let rs = t.drawn_rect_corners().filter(fn(r) { r.4 == color })
  if rs.is_empty() {
    (-1.0, -1.0, -1.0, -1.0)
  } else {
    rs[0].5
  }
}

///|
test "a box reshaped for its cause: each of its ground's corners goes its own way from the shape it had" {
  let lines = Ref::new(1)
  let t = @ui.Tester::new(fn(c) {
    c.column(fn() {
      // (one line: all four 10; two: its foot's corners each its own, as a composer's across a panel's foot)
      let radius : @ui.Radius = if lines.val == 1 { Exact(10.0) } else { Corners(10.0, 10.0, 2.0, 18.0) }
      let b = c.box(
        style=@ui.style(radius~),
        w=Px(100.0),
        h=Px(20.0 * lines.val.to_double()),
        bg=0xFF0000FFL,
        fn() {  },
      )
      @motion.reshape(c, b, "box", by="\{lines.val} lines", spec=@motion.tween(reshape_ms, ease=Linear))
    })
    |> ignore
  })
  assert_eq(drawn_corners(t, 0xFF0000FFL), (10.0, 10.0, 10.0, 10.0))
  lines.val = 2
  t.frame()
  assert_eq(drawn_corners(t, 0xFF0000FFL), (10.0, 10.0, 10.0, 10.0))
  // midway: its top corners as they were, its foot's each on its way to its own, as far along as the other
  t.run_for(reshape_midway_ms)
  let (tl, tr, br, bl) = drawn_corners(t, 0xFF0000FFL)
  assert_eq((tl, tr), (10.0, 10.0))
  assert_true(br > 2.0 && br < 10.0 && bl > 10.0 && bl < 18.0, msg="\{(br, bl)}")
  assert_true((10.0 - br - (bl - 10.0)).abs() < 0.001, msg="\{(br, bl)}")
  t.run_for(@motion.layout_rest("box") - t.time())
  assert_eq(drawn_corners(t, 0xFF0000FFL), (10.0, 10.0, 2.0, 18.0))
  t.assert_idle()
}

///|
test "a box at its page's foot opened from its foot (foot) as a keyboard lifts it in the same frame: its foot there at once, only its growing up on its way" {
  let lines = Ref::new(1)
  // (how far a keyboard has lifted what is at the page's foot: 0 down)
  let lift = Ref::new(0.0)
  let t = @ui.Tester::new(fn(c) {
    c.column(fn() {
      c.box(w=Px(100.0), h=Px(200.0 - lift.val - 20.0 * lines.val.to_double()), fn() {  }) |> ignore
      let b = c.box(w=Px(100.0), h=Px(20.0 * lines.val.to_double()), bg=0xFF0000FFL, fn() {
        let n = c.box(w=Px(10.0), h=Px(10.0), bg=0x00FF00FFL, fn() {  })
        @motion.layout(c, n, "box/part", spec=@motion.tween(reshape_ms, ease=Linear), by="\{lines.val} lines")
      })
      @motion.reshape(c, b, "box", by="\{lines.val} lines", spec=@motion.tween(reshape_ms, ease=Linear), foot=true)
    })
    |> ignore
  })
  assert_eq(drawn_box(t, 0xFF0000FFL), (0.0, 180.0, 100.0, 20.0))
  // opened (two lines) and lifted 50 in the same frame: its foot at 150 at once, its ground as high as it was
  lines.val = 2
  lift.val = 50.0
  t.frame()
  assert_eq(drawn_box(t, 0xFF0000FFL), (0.0, 130.0, 100.0, 20.0))
  // what moves with it as far off its place as it was before the lift, not 50 under it
  assert_eq(drawn_box(t, 0x00FF00FFL), (0.0, 130.0, 10.0, 10.0))
  // midway: grown up from that foot, its foot where it is laid out
  t.run_for(reshape_midway_ms)
  let (_, y, _, h) = drawn_box(t, 0xFF0000FFL)
  assert_true(h > 20.0 && h < 40.0, msg="\{h}")
  assert_eq(y + h, 150.0)
  t.run_for(@motion.layout_rest("box") - t.time())
  assert_eq(drawn_box(t, 0xFF0000FFL), (0.0, 110.0, 100.0, 40.0))
  t.assert_idle()
}

///|
test "a box resized by what holds it, its cause the same, has its ground its new shape at once" {
  let w = Ref::new(100.0)
  let t = @ui.Tester::new(fn(c) {
    c.column(fn() {
      let b = c.box(w=Px(w.val), h=Px(20.0), bg=0xFF0000FFL, fn() {  })
      @motion.reshape(c, b, "box", by="one line", spec=@motion.tween(reshape_ms, ease=Linear))
    })
    |> ignore
  })
  w.val = 60.0
  t.frame()
  assert_eq(drawn_box(t, 0xFF0000FFL), (0.0, 0.0, 60.0, 20.0))
  assert_eq(@motion.layout_rest("box"), -1.0)
  t.assert_idle()
}

///|
test "a measured node tells what reads its corners when they change without changing its size" {
  let radius = @signals.signal(12.0)
  let t = @ui.Tester::new(fn(c) {
    let target = c.box(w=Px(100.0), h=Px(100.0), radius=radius.get(), fn() {  })
    @motion.measure(c, target, "corner-target")
    c.made("corner-reader", fn() {
      @ui.made_box(fn(c) {
        let r = @motion.measured_radii(c, "corner-target").unwrap_or(@motion.MeasuredCorners::uniform(0.0)).each()
        c.text(if r.0 >= 20.0 { "rounder" } else { "round" }) |> ignore
      })
    })
  }, w=300.0, h=200.0)
  t.draw()
  t.frame()
  assert_eq(@motion.measured_radii(t.ctx(), "corner-target").map(fn(r) { r.each() }), Some((12.0, 12.0, 12.0, 12.0)))
  assert_true(t.find("round") is Some(_))
  radius.set(24.0)
  t.draw()
  t.frame()
  assert_eq(@motion.measured_radii(t.ctx(), "corner-target").map(fn(r) { r.each() }), Some((24.0, 24.0, 24.0, 24.0)))
  assert_true(t.find("rounder") is Some(_))
}

///|
test "placed: drawn where what it reads is as this frame lays it out, never a frame behind" {
  let room = Ref::new(0.0)
  let t = @ui.Tester::new(fn(c) {
    c.column(fn() {
      c.box(w=Px(10.0), h=Px(room.val), fn() {  }) |> ignore
      let target = c.box(w=Px(10.0), h=Px(10.0), bg=0xFF0000FFL, fn() {  })
      @motion.measure(c, target, "target")
      c.layer(fn() {
        let b = c.box(w=Px(10.0), h=Px(10.0), bg=0x00FF00FFL, fn() {  })
        // 20 under the target, wherever that is
        @motion.placed(c, b, fn() {
          match @motion.measured_rect(c, "target") {
            Some((x, y, _, _)) => @ui.look(dx=x, dy=y + 20.0)
            None => @ui.look(alpha=0.0)
          }
        })
      })
      |> ignore
    })
    |> ignore
  })
  assert_eq(drawn_box(t, 0x00FF00FFL), (0.0, 20.0, 10.0, 10.0))
  // the target moved by what is over it: in the same frame, where it now is
  room.val = 50.0
  t.frame()
  assert_eq(drawn_box(t, 0xFF0000FFL).1, 50.0)
  assert_eq(drawn_box(t, 0x00FF00FFL), (0.0, 70.0, 10.0, 10.0))
}

///|
test "an Anim is over at the end it declared as it was told, whoever asks and however its frames fall" {
  let a = @motion.Anim::new(0.0)
  let seen : Array[Bool] = []
  let t = @ui.Tester::new(fn(c) {
    ignore(c)
    seen.push(a.over())
    c.box(fn() {  }) |> ignore
  })
  // never told: over
  assert_true(seen[seen.length() - 1])
  // told in a frame: not over till its end (200 ms on), over from then
  let told = Ref::new(false)
  let t2 = @ui.Tester::new(fn(c) {
    if !told.val {
      told.val = true
      a.animate(1.0, @motion.tween(reshape_ms, ease=Linear))
    }
    seen.push(a.over())
    c.box(fn() {  }) |> ignore
  })
  assert_false(seen[seen.length() - 1])
  t2.run_for(reshape_midway_ms)
  assert_false(a.over())
  t2.run_for(reshape_ms - reshape_midway_ms)
  assert_true(a.over())
  ignore(t)
}
