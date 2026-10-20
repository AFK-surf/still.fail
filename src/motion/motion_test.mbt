// Motion's arithmetic against Compose's (its curves and springs, worked out
// from their formulas, still.fail's apps/mbui/docs/stillfail-motion.md), and the motion layer frame
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
    (@motion.Standard, [0.025863015, 0.23658736, 0.775561311, 0.959367737, 0.994353929]),
    (@motion.Arrive, [0.396693549, 0.767284301, 0.946079462, 0.991108187, 0.998830259]),
    (@motion.Out, [0.359122765, 0.727373396, 0.929578821, 0.987468037, 0.998286622]),
    (@motion.Flight, [0.010913674, 0.095832729, 0.70468533, 0.956226683, 0.994219017]),
    (@motion.Css, [0.094796306, 0.408510591, 0.802403388, 0.960458978, 0.994316477]),
  ]
  for w in want {
    let (curve, ys) = w
    for i, t in ts {
      assert_true(near(curve.at(t), ys[i], 1.0e-6), msg="\{curve} at \{t}: \{curve.at(t)} not \{ys[i]}")
    }
  }
  assert_eq(@motion.Standard.at(0.0), 0.0)
  assert_eq(@motion.Standard.at(1.0), 1.0)
}

///|
test "springs are Compose's SpringSimulation, in closed form" {
  // critically damped: (d + (v + ωd)t)e^(−ωt)
  let w = 1500.0.sqrt()
  for t in [0.0, 0.01, 0.05, 0.1, 0.3] {
    let (x, _) = @motion.spring_at(1.0, 1500.0, 1.0, 0.0, t)
    let want = (1.0 + w * t) * 2.718281828459045.pow(-w * t)
    assert_true(near(x, want, 1.0e-12))
  }
  // under-damped: Sheet.kt's menu spring, motionSpring(.24, bounce .08)
  match @motion.menu_spring {
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
  // under-damped, by its envelope: the menu from .9 to 1
  match @motion.menu_spring {
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
  let s = @motion.tween(300.0, ease=Standard, delay=100.0)
  let dur = s.duration(0.0, 10.0, 0.0)
  assert_eq(dur, 400.0)
  let (x0, _) = s.value_at(50.0, dur, 0.0, 10.0, 0.0)
  assert_eq(x0, 0.0)
  let (x1, _) = s.value_at(250.9, dur, 0.0, 10.0, 0.0)
  assert_true(near(x1, 10.0 * @motion.Standard.at(150.0 / 300.0), 1.0e-9))
  let (x2, v2) = s.value_at(400.0, dur, 0.0, 10.0, 0.0)
  assert_eq((x2, v2), (10.0, 0.0))
}

///|
test "an animated value starts the frame after it is asked, and follows its target" {
  let shown = Ref::new(false)
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
      spec=@motion.tween(160.0, ease=Linear),
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
  // asked this frame: still where it was
  assert_eq(seen[seen.length() - 1], 0.0)
  t.frame()
  // its first frame: its start
  assert_eq(seen[seen.length() - 1], 0.0)
  t.frame()
  assert_true(near(seen[seen.length() - 1], 0.1, 1.0e-9))
  t.frame(ms=64.0)
  assert_true(near(seen[seen.length() - 1], 0.5, 1.0e-9))
  // turned back mid-way: from where it is (the frame it is told in still
  // moves it on, as Compose's: 0.6)
  shown.val = false
  t.frame()
  t.frame()
  let back = seen[seen.length() - 1]
  assert_true(near(back, 0.6, 1.0e-9), msg="\{back}")
  t.frame()
  assert_true(seen[seen.length() - 1] < back)
  // on its way still, to its own end
  let end = kept.val.unwrap().ends_at()
  assert_true(end > t.time())
  t.run_for(end - t.time())
  assert_eq(seen[seen.length() - 1], 0.0)
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
  for _ in 0..<6 {
    t.frame()
  }
  let a = seen[seen.length() - 2]
  let b = seen[seen.length() - 1]
  to.val = 200.0
  t.frame()
  t.frame()
  let c1 = seen[seen.length() - 1]
  t.frame()
  let d = seen[seen.length() - 1]
  // no stop: the step after is at least as long as the one before
  assert_true(d - c1 >= (b - a) * 0.9, msg="\{a} \{b} \{c1} \{d}")
  // the spring's own end, asked
  t.run_for(kept.val.unwrap().ends_at() - t.time())
  assert_eq(seen[seen.length() - 1], 200.0)
  t.assert_idle()
}

///|
test "a keyed node moved by its layout is drawn from where it was, then goes there" {
  let before = Ref::new(true)
  let mut id = 0
  let t = @ui.Tester::new(fn(c) {
    id = c.id("moved")
    c.column(fn() {
      if before.val {
        c.box(w=Px(50.0), h=Px(40.0), fn() {  }) |> ignore
      }
      let i = c.box(w=Px(50.0), h=Px(20.0), bg=0xFF0000FFL, id~, fn() {  })
      @motion.layout(c, i, "moved", listed=false)
    })
    |> ignore
  })
  let y0 = drawn_y(t, 0xFF0000FFL)
  assert_eq(y0, 40.0)
  before.val = false
  t.frame()
  // laid out at 0, drawn at 40 still; tapped where it is laid out
  assert_eq(drawn_y(t, 0xFF0000FFL), 40.0)
  assert_eq(t.ctx().rect_of(id).unwrap().1, 0.0)
  t.frame()
  assert_eq(drawn_y(t, 0xFF0000FFL), 40.0)
  t.frame()
  let y2 = drawn_y(t, 0xFF0000FFL)
  assert_true(y2 < 40.0 && y2 > 0.0, msg="\{y2}")
  assert_eq(t.ctx().rect_of(id).unwrap().1, 0.0)
  // its move's own end (its spring's), asked by its key
  t.run_for(@motion.layout_rest("moved") - t.time())
  assert_eq(drawn_y(t, 0xFF0000FFL), 0.0)
  t.assert_idle()
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
      @motion.layout(c, i, "moved", listed=false)
    })
    |> ignore
  })
  assert_eq(@motion.layout_rest("moved"), -1.0)
  assert_eq(@motion.layout_rest("nothing of that name"), -1.0)
  before.val = false
  // the frame that moves it, and the one after it (its spring's first), at this moment
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
  let enter = @motion.trans(fade=0.0, scale=0.6, dy=18.0, spec=@motion.tween(220.0), fade_spec=@motion.tween(180.0, ease=Css))
  let exit = @motion.trans(fade=0.0, scale=0.6, dy=18.0, spec=@motion.tween(180.0), fade_spec=@motion.tween(150.0, ease=Css))
  let t = @ui.Tester::new(fn(c) { looks.push(@motion.presence(c, "pill", shown.val, enter~, exit~)) })
  assert_eq(looks[looks.length() - 1], None)
  shown.val = true
  t.frame()
  t.frame()
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
  // the frame after (the exit's first, at this moment), then the exit's own length
  t.draw()
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
          exit=@motion.trans(fade=0.0, scale=0.9, spec=@motion.tween(200.0, ease=CssOut)),
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
  // (the frame after: their motions' first, at this moment) to the end of e's entrance and of a's move
  t.draw()
  let e_end = @motion.layout_rest("row/e")
  let a_end = @motion.layout_rest("row/a")
  t.run_for((if e_end > a_end { e_end } else { a_end }) - t.time())
  assert_eq(t.drawn_of("a").unwrap().1, 40.0)
  // one going ahead of the others is lifted over them
  keys.val = ["d", "e", "a", "c"]
  t.frame()
  let lifted_at = t.time()
  assert_true(@motion.lifted(t.ctx(), t.ctx().id("rows"), "row/d") >= 0.0)
  // (the frame after: its move's first) to the end of d's move
  t.draw()
  t.run_for(@motion.layout_rest("row/d") - t.time())
  assert_eq(t.drawn_of("d").unwrap().1, 0.0)
  // and of its lift over the others
  t.run_for(lifted_at + @motion.lift_ms - t.time())
  t.assert_idle()
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
    (@motion.menu_spring, 0.9, 1.0, 0.0, 276.0, [0.9, 0.9049251, 0.9167734, 0.9309648, 0.9673801, 0.98751396, 0.9960531, 1.0]),
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
    (@motion.tween(300.0), [0.0, 0.0066127195, 0.08510549, 0.4572519, 0.7755618, 0.92077625, 0.9833588, 1.0, 1.0]),
    (@motion.tween(240.0, ease=Out, delay=100.0), [0.0, 0.0, 0.0, 0.0, 0.6550595, 0.888813, 0.9670928, 0.9949123, 1.0]),
    (@motion.tween(180.0, ease=Css), [0.0, 0.07842861, 0.46823442, 0.852283, 0.9834744, 1.0, 1.0, 1.0, 1.0]),
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
    match @motion.presence(c, "sheet", shown.val, enter=@motion.trans(fade=0.0, spec=@motion.tween(300.0))) {
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
  shown.val = false
  t.frame()
  t.frame()
  // still drawn, going
  assert_eq(t.drawn_rects().filter(fn(r) { r.4 == 0x445566FFL }).length(), 1)
  t.tap_once(100.0, 50.0)
  t.frame()
  assert_eq((over.val, under.val), (1, 1))
  t.draw()
  assert_eq(t.drawn_rects().filter(fn(r) { r.4 == 0x445566FFL }).length(), 0)
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
      v.animate(100.0, @motion.tween(fade_ms))
      kept.val = Some(v)
      if ask {
        // not yet started: no end to say
        if v.ends_at() <= 1.0e300 {
          abort("an Anim not started yet said an end")
        }
      }
    }
    ignore(v.get())
  })
}

///|
test "an Anim's start is its first frame's, whoever asks its end before or between" {
  let fade_ms = 200.0
  let a1 : Ref[@motion.Anim?] = Ref(None)
  let quiet = told_once(false, fade_ms, a1)
  quiet.draw()
  let a2 : Ref[@motion.Anim?] = Ref(None)
  let asked = told_once(true, fade_ms, a2)
  asked.draw()
  let end = fn(r : Ref[@motion.Anim?]) {
    match r.val {
      Some(a) => a.ends_at()
      None => -1.0
    }
  }
  // started at the frame after it was told (drawn at the same moment here): its end from there
  let e = end(a2)
  assert_eq(e, end(a1))
  assert_eq(end(a2), e)
  assert_eq(e, asked.time() + fade_ms)
  // asked again half-way, the same
  asked.run_for(fade_ms / 2.0)
  assert_eq(end(a2), e)
  asked.run_for(e - asked.time())
  asked.assert_idle()
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
        @motion.layout(c, n, "row/" + k, exit=@motion.trans(fade=0.0, scale=0.9, spec=@motion.tween(200.0, ease=CssOut)))
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
      a.animate(0.0, @motion.tween(200.0))
    }
    c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore
  })
  t.run_for(begun.val + shown - t.time())
  let end = fade.val.unwrap().ends_at()
  assert_true(end > t.time() && end < @double.infinity, msg="\{end} at \{t.time()}")
  t.run_for(end - t.time())
  t.assert_idle()
}
