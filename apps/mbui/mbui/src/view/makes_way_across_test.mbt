// What a structure makes or lets go along a row, said `along_row` (along_row.mbt): its way across, the same way a
// column's is down (makes_way_test.mbt), on its width.

///|
/// The word drawn `w`'s left (x) and width, as the tree is drawn now; None where it is not drawn.
fn across_at(t : @view.Tree, w : String) -> (Double, Double)? {
  let d = t.drawn().filter(fn(d) { d.words == w })
  if d.length() == 0 {
    None
  } else {
    Some((d[0].x, d[0].w))
  }
}

///|
/// The word drawn `w`'s left (x).
fn across_x(t : @view.Tree, w : String) -> Double {
  across_at(t, w).unwrap().0
}

///|
/// Within half a point (a layout's pixel, where it is set on them) of `want`.
fn across_near(got : Double, want : Double, msg : String) -> Unit raise {
  assert_true((got - want).abs() <= 0.5, msg="\{msg}: \{got}, not \{want}")
}

///|
/// A row: 左 (20 wide), what `on` shows along it (旁, 30 wide), 右 (20 wide); under it a column's 下.
fn across_row(on : @signals.Signal[Bool], along_row? : Bool = true) -> @view.Tree {
  @view.Tree::new(fn(root) {
    root.box(fn(r) {
      r.row(Is(true)) |> ignore
      r.box(fn(b) { b.width(Is(Some(20.0))).words(Is("左")) |> ignore }) |> ignore
      r.show(along_row~, fn() { on.get() }, fn(v) { v.width(Is(Some(30.0))).words(Is("旁")) |> ignore })
      r.box(fn(b) { b.width(Is(Some(20.0))).words(Is("右")) |> ignore }) |> ignore
    })
    |> ignore
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
  })
}

///|
test "shown along a row, said so: it opens its way across as a Move as far as it is wide, what is after it going with it" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let t = across_row(on)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(across_x(t, "右"), 20.0)
  t.event(100.0, fn() { on.set(true) })
  for m in [100.0, 130.0, 175.0, 225.0, 300.0] {
    t.at(m)
    t.frame(390.0, 844.0) |> ignore
    let (way, _) = @flex.come_way(0.0, 0.0, 30.0, m - 100.0)
    across_near(across_x(t, "右"), 20.0 + way, "右 at \{m}")
    across_near(across_at(t, "旁").unwrap().1, way, "旁's width at \{m}")
    // (what is under the row: where it was, the row as tall all along)
    assert_eq(t.drawn().filter(fn(d) { d.words == "下" })[0].y, 0.0 + t.drawn().filter(fn(d) { d.words == "左" })[0].h)
  }
  // (a Move over 30: as long as move_ms says, there then, and nothing reads the clock)
  t.at(100.0 + @flex.move_ms(30.0))
  t.frame(390.0, 844.0) |> ignore
  assert_eq(across_x(t, "右"), 50.0)
  assert_eq(across_at(t, "旁").unwrap().1, 30.0)
  assert_false(t.clock_read())
}

///|
test "let go along a row, said so: it closes its way across, drawn as it was, let go once it is shut" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let t = across_row(on)
  t.frame(390.0, 844.0) |> ignore
  let gone = t.root().kids()[0].kids()[1].kids()[0]
  assert_eq(across_x(t, "右"), 50.0)
  t.event(100.0, fn() { on.set(false) })
  for m in [130.0, 175.0, 225.0] {
    t.at(m)
    t.frame(390.0, 844.0) |> ignore
    let (way, _) = @flex.come_way(30.0, 0.0, 0.0, m - 100.0)
    across_near(across_x(t, "右"), 20.0 + way, "右 at \{m}")
    assert_true(gone.alive())
  }
  t.at(100.0 + @flex.move_ms(30.0) + 1.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(across_x(t, "右"), 20.0)
  assert_false(gone.alive())
  assert_false(t.clock_read())
}

///|
/// 旁 (30 wide, along a row) shown (`showing`: let go of, else shown) at 100, then the other way at 105; a frame drawn
/// between the two (`between`) or none: where 右 is at each of the moments after.
fn across_turned(showing : Bool, between : Bool) -> Array[Double] {
  let on = @signals.signal(showing, same=fn(a, b) { a == b })
  let t = across_row(on)
  t.frame(390.0, 844.0) |> ignore
  t.event(100.0, fn() { on.set(!showing) })
  if between {
    t.at(102.0)
    t.frame(390.0, 844.0) |> ignore
  }
  t.event(105.0, fn() { on.set(showing) })
  [110.0, 140.0, 200.0, 300.0, 450.0, 900.0].map(fn(m) {
    t.at(m)
    t.frame(390.0, 844.0) |> ignore
    across_x(t, "右")
  })
}

///|
test "along a row, called back 5 ms later: the same way whether a frame was drawn between or not, there at the end" {
  let none = across_turned(true, false)
  assert_eq(none, across_turned(true, true))
  assert_eq(none[none.length() - 1], 50.0)
  let back = across_turned(false, false)
  assert_eq(back, across_turned(false, true))
  assert_eq(back[back.length() - 1], 20.0)
}

///|
test "shown again along a row as it closes its way: the same node, on from as fast as it closed, then back" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let t = across_row(on)
  t.frame(390.0, 844.0) |> ignore
  t.event(100.0, fn() { on.set(false) })
  t.at(175.0)
  t.frame(390.0, 844.0) |> ignore
  let low = across_x(t, "右")
  t.event(175.0, fn() { on.set(true) })
  t.frame(390.0, 844.0) |> ignore
  assert_eq(across_x(t, "右"), low)
  t.at(185.0)
  t.frame(390.0, 844.0) |> ignore
  let on_down = across_x(t, "右")
  assert_true(on_down < low && on_down >= 20.0, msg="on from its speed: \{low} → \{on_down}")
  t.at(1000.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(across_x(t, "右"), 50.0)
  assert_false(t.clock_read())
}

///|
test "picked anew along a row, said so: the new one's way from as wide as the one before to as wide as it is" {
  let wide = @signals.signal(false, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.box(fn(r) {
      r.row(Is(true)) |> ignore
      r.pick(along_row=true, fn() { wide.get() }, fn(v, k) {
        v.width(Is(Some(if k { 60.0 } else { 30.0 }))).words(Is(if k { "宽" } else { "窄" })) |> ignore
      })
      r.box(fn(b) { b.width(Is(Some(20.0))).words(Is("右")) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  assert_eq(across_x(t, "右"), 30.0)
  t.event(100.0, fn() { wide.set(true) })
  for m in [100.0, 150.0, 200.0] {
    t.at(m)
    t.frame(390.0, 844.0) |> ignore
    let (way, _) = @flex.come_way(30.0, 0.0, 60.0, m - 100.0)
    across_near(across_x(t, "右"), way, "右 at \{m}")
    // (the new one laid out whole at its width, cut at the way's)
    across_near(across_at(t, "宽").unwrap().1, way, "宽's width at \{m}")
  }
  t.at(100.0 + @flex.move_ms(30.0))
  t.frame(390.0, 844.0) |> ignore
  assert_eq(across_x(t, "右"), 60.0)
  assert_false(t.clock_read())
}

///|
test "shown along a row beside a grown one: the grown one gives way as the way goes, all of the row taken all along" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.box(fn(r) {
      r.row(Is(true)) |> ignore
      r.box(fn(b) { b.grow(Is(1.0)).words(Is("长")) |> ignore }) |> ignore
      r.show(along_row=true, fn() { on.get() }, fn(v) { v.width(Is(Some(40.0))).words(Is("钮")) |> ignore })
    })
    |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  assert_eq(across_at(t, "长").unwrap().1, 390.0)
  t.event(100.0, fn() { on.set(true) })
  for m in [100.0, 150.0, 200.0, 250.0] {
    t.at(m)
    t.frame(390.0, 844.0) |> ignore
    let (way, _) = @flex.come_way(0.0, 0.0, 40.0, m - 100.0)
    across_near(across_at(t, "长").unwrap().1, 390.0 - way, "长's width at \{m}")
    across_near(across_x(t, "钮"), 390.0 - way, "钮 at \{m}")
  }
  t.at(100.0 + @flex.move_ms(40.0))
  t.frame(390.0, 844.0) |> ignore
  assert_eq(across_at(t, "长").unwrap().1, 350.0)
}

///|
test "shown along a row with a gap: the gap before it opens with it, what is after it set out from where it was" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.box(fn(r) {
      r.row(Is(true)).gap(Is(10.0)) |> ignore
      r.box(fn(b) { b.width(Is(Some(20.0))).words(Is("左")) |> ignore }) |> ignore
      r.show(along_row=true, fn() { on.get() }, fn(v) { v.width(Is(Some(30.0))).words(Is("旁")) |> ignore })
      r.box(fn(b) { b.width(Is(Some(20.0))).words(Is("右")) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  assert_eq(across_x(t, "右"), 30.0)
  t.event(100.0, fn() { on.set(true) })
  t.at(100.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(across_x(t, "右"), 30.0)
  t.at(150.0)
  t.frame(390.0, 844.0) |> ignore
  let mid = across_x(t, "右")
  assert_true(mid > 30.0 && mid < 70.0, msg="on its way: \{mid}")
  t.at(100.0 + @flex.move_ms(30.0))
  t.frame(390.0, 844.0) |> ignore
  assert_eq(across_x(t, "右"), 70.0)
}

///|
test "one shown and one let go along a row at one moment: one way, their widths together as wide all along" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.box(fn(r) {
      r.row(Is(true)) |> ignore
      r.box(fn(b) { b.width(Is(Some(20.0))).words(Is("左")) |> ignore }) |> ignore
      r.show(along_row=true, fn() { on.get() }, fn(v) { v.width(Is(Some(30.0))).words(Is("进")) |> ignore })
      r.box(fn(b) { b.width(Is(Some(20.0))).words(Is("中")) |> ignore }) |> ignore
      r.show(along_row=true, fn() { !on.get() }, fn(v) { v.width(Is(Some(30.0))).words(Is("出")) |> ignore })
      r.box(fn(b) { b.width(Is(Some(20.0))).words(Is("右")) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  assert_eq(across_x(t, "右"), 70.0)
  t.event(100.0, fn() { on.set(true) })
  for m in [100.0, 140.0, 180.0, 230.0] {
    t.at(m)
    t.frame(390.0, 844.0) |> ignore
    let come = across_at(t, "进").unwrap().1
    let go = across_at(t, "出").unwrap().1
    across_near(come + go, 30.0, "both at \{m}: \{come} + \{go}")
    across_near(across_x(t, "右"), 70.0, "右 at \{m}")
  }
  t.at(100.0 + @flex.move_ms(30.0))
  t.frame(390.0, 844.0) |> ignore
  assert_eq(across_at(t, "进").unwrap().1, 30.0)
  assert_true(across_at(t, "出") is None)
  assert_false(t.clock_read())
}

///|
/// Where 右 (after 旁 along a row) is at each of a few moments after 旁 is shown at 100, `below` shown down the column at
/// the same moment too.
fn across_beside_column(below : Bool) -> Array[Double] {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.box(fn(r) {
      r.row(Is(true)) |> ignore
      r.box(fn(b) { b.width(Is(Some(20.0))).words(Is("左")) |> ignore }) |> ignore
      r.show(along_row=true, fn() { on.get() }, fn(v) { v.width(Is(Some(30.0))).words(Is("旁")) |> ignore })
      r.box(fn(b) { b.width(Is(Some(20.0))).words(Is("右")) |> ignore }) |> ignore
    })
    |> ignore
    root.show(fn() { below && on.get() }, fn(v) { v.height(Is(Some(120.0))).words(Is("下")) |> ignore })
  })
  t.frame(390.0, 844.0) |> ignore
  t.event(100.0, fn() { on.set(true) })
  [100.0, 130.0, 180.0, 250.0, 700.0].map(fn(m) {
    t.at(m)
    t.frame(390.0, 844.0) |> ignore
    across_x(t, "右")
  })
}

///|
test "a way along a row and one down its column at one moment: each its own, the row's as were it alone" {
  assert_eq(across_beside_column(true), across_beside_column(false))
}

///|
test "not said, at once, in a row that wraps, or alone in its row: no way made along it" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.box(fn(r) {
      r.row(Is(true)) |> ignore
      r.show(fn() { on.get() }, fn(v) { v.width(Is(Some(30.0))).words(Is("甲")) |> ignore })
      r.box(fn(b) { b.width(Is(Some(20.0))).words(Is("甲右")) |> ignore }) |> ignore
    })
    |> ignore
    root.box(fn(r) {
      r.row(Is(true)).wraps(Is(Some(0.0))) |> ignore
      r.show(along_row=true, fn() { on.get() }, fn(v) { v.width(Is(Some(30.0))).words(Is("乙")) |> ignore })
      r.box(fn(b) { b.width(Is(Some(20.0))).words(Is("乙右")) |> ignore }) |> ignore
    })
    |> ignore
    root.box(fn(r) {
      r.row(Is(true)) |> ignore
      r.show(along_row=true, fn() { on.get() }, fn(v) { v.width(Is(Some(30.0))).words(Is("丙")) |> ignore })
    })
    |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  t.event(100.0, fn() { on.set(true) })
  t.at(100.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(across_x(t, "甲右"), 30.0)
  assert_eq(across_x(t, "乙右"), 30.0)
  assert_eq(across_at(t, "丙").unwrap().1, 30.0)
  assert_false(t.clock_read())
}

///|
/// `f` run as an app's run on a host runs (a fault told, not stopping the run); what was told said back.
fn across_faults(f : () -> Unit) -> Array[String] {
  let told : Array[String] = []
  @view.faults_stop.val = false
  @view.fault_told.val = Some(fn(said) { told.push(said) })
  f()
  @view.faults_stop.val = true
  @view.fault_told.val = None
  told
}

///|
test "along_row said with at_once, or where a column lays it out: a fault, said where it was asked for" {
  let told = across_faults(fn() {
    let t = @view.Tree::new(fn(root) {
      root.box(fn(r) {
        r.row(Is(true)) |> ignore
        r.show(along_row=true, at_once=true, fn() { true }, fn(v) { v.words(Is("甲")) |> ignore })
      })
      |> ignore
      root.pick(along_row=true, fn() { 0 }, fn(v, _) { v.words(Is("乙")) |> ignore })
    })
    t.frame(390.0, 844.0) |> ignore
  })
  assert_eq(told.length(), 2, msg="\{Repr(told)}")
  assert_true(told[0].contains("along_row=true and at_once=true said together"), msg=told[0])
  assert_true(told[0].contains("makes_way_across_test.mbt"), msg=told[0])
  assert_true(told[1].contains("View::pick") && told[1].contains("no row"), msg=told[1])
}

///|
test "along a row said: a frame at rest does nothing, and a change beside it as much as were it not said" {
  let work_of = fn(along_row : Bool) {
    let on = @signals.signal(false, same=fn(a, b) { a == b })
    let said = @signals.signal("左", same=fn(a, b) { a == b })
    let t = @view.Tree::new(fn(root) {
      root.box(fn(r) {
        r.row(Is(true)) |> ignore
        r.box(fn(b) { b.width(Is(Some(20.0))).words(By(fn() { said.get() })) |> ignore }) |> ignore
        r.show(along_row~, fn() { on.get() }, fn(v) { v.width(Is(Some(30.0))).words(Is("旁")) |> ignore })
        r.box(fn(b) { b.width(Is(Some(20.0))).words(Is("右")) |> ignore }) |> ignore
      })
      |> ignore
    })
    t.frame(390.0, 844.0) |> ignore
    let w0 = t.work()
    t.at(50.0)
    t.frame(390.0, 844.0) |> ignore
    let w1 = t.work()
    let rest = w1 == w0
    t.event(60.0, fn() { said.set("改") })
    t.at(60.0)
    t.frame(390.0, 844.0) |> ignore
    let w2 = t.work()
    (rest, w2.computes - w1.computes, w2.laid - w1.laid, w2.visited - w1.visited, w2.measured - w1.measured, w2.bound - w1.bound)
  }
  let said = work_of(true)
  assert_true(said.0, msg="a frame at rest did something")
  assert_eq(said, work_of(false))
}
