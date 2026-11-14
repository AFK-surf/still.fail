// A box said to be gone_empty (View::gone_empty) takes no room while it holds nothing laid out: no padding, margins or
// gap before it in what holds it, at either end of it or between. Down a column, as the first of what it holds comes
// from nothing or the last goes to nothing, its padding, margins and that gap open or close with that one's way, as
// much of them as it is there; called back half way, they turn with it; at once, at once; one picked in another's
// place leaves them be. The old view's (ui's gone_empty_wbtest): 18 above, 24 below, 4 of margin.

///|
/// The word drawn `w`'s top (y), as the tree is drawn now; none: -1.
fn ge_y(t : @view.Tree, w : String) -> Double {
  let found = t.drawn().filter(fn(d) { d.words == w })
  if found.length() == 0 {
    -1.0
  } else {
    found[0].y
  }
}

///|
/// 上 (20 tall), a box gone_empty (padding 18 above and 24 below, margin 4 above) holding 里 (40 tall) while `on` says
/// so, 下 (20 tall), 10 apart.
fn ge_tree(on : @signals.Signal[Bool], at_once? : Bool = false) -> @view.Tree {
  @view.Tree::new(fn(root) {
    root.gap(Is(10.0)) |> ignore
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("上")) |> ignore }) |> ignore
    root.box(fn(b) {
      b.gone_empty(Is(true)).padding(Is((0.0, 18.0, 0.0, 24.0))).margin(Is((0.0, 4.0, 0.0, 0.0))) |> ignore
      b.show(at_once~, fn() { on.get() }, fn(v) { v.height(Is(Some(40.0))).words(Is("里")) |> ignore })
    })
    |> ignore
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
  })
}

///|
/// 下's top at each frame of 120 a second from `from` to `to` ms (both drawn).
fn ge_frames(t : @view.Tree, from : Double, to : Double) -> Array[Double] {
  let out = []
  let mut k = 0
  while true {
    let ms = from + k.to_double() * 1000.0 / 120.0
    let ms = if ms > to { to } else { ms }
    t.at(ms)
    t.frame(390.0, 844.0) |> ignore
    out.push(ge_y(t, "下"))
    if ms >= to {
      break
    }
    k = k + 1
  }
  out
}

///|
/// The most `ys` moves from one frame to the next.
fn ge_most_step(ys : Array[Double]) -> Double {
  let mut most = 0.0
  for i in 1..<ys.length() {
    let d = (ys[i] - ys[i - 1]).abs()
    if d > most {
      most = d
    }
  }
  most
}

///|
fn ge_near(a : Double, b : Double) -> Bool {
  (a - b).abs() < 0.01
}

///|
test "gone_empty holding nothing: none of its room, padding, margins or the gap before it; all of it holding something" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let t = ge_tree(on, at_once=true)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(ge_y(t, "下"), 30.0)
  t.event(100.0, fn() { on.set(true) })
  t.at(100.0)
  t.frame(390.0, 844.0) |> ignore
  // (20 + 10 of gap + 4 of margin + 18 of padding; under it 40 + 24 + 10)
  assert_eq(ge_y(t, "里"), 52.0)
  assert_eq(ge_y(t, "下"), 126.0)
  // (at once: at once again as it goes)
  t.event(200.0, fn() { on.set(false) })
  t.at(200.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(ge_y(t, "下"), 30.0)
  assert_false(t.clock_read())
}

///|
test "gone_empty holding nothing at either end of what holds it: no gap left there either" {
  let t = @view.Tree::new(fn(root) {
    root.box(fn(col) {
      col.gap(Is(10.0)) |> ignore
      col.box(fn(b) { b.gone_empty(Is(true)).pad(Is(12.0)) |> ignore }) |> ignore
      col.box(fn(b) { b.height(Is(Some(20.0))).words(Is("上")) |> ignore }) |> ignore
      col.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
      col.box(fn(b) {
        b.gone_empty(Is(true)).pad(Is(12.0)) |> ignore
        // (holding only what is laid out nowhere, or a box gone_empty holding nothing: as empty)
        b.box(fn(n) { n.height(Is(Some(30.0))).laid_nowhere(Is(true)) |> ignore }) |> ignore
        b.box(fn(n) { n.gone_empty(Is(true)).pad(Is(5.0)) |> ignore }) |> ignore
      })
      |> ignore
    })
    |> ignore
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("尾")) |> ignore }) |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  assert_eq(ge_y(t, "上"), 0.0)
  assert_eq(ge_y(t, "下"), 30.0)
  assert_eq(ge_y(t, "尾"), 50.0)
}

///|
test "gone_empty, the first of what it holds coming: its padding, margin and gap open with that one's way, no step" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let t = ge_tree(on)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(ge_y(t, "下"), 30.0)
  t.event(100.0, fn() { on.set(true) })
  let first = ge_frames(t, 100.0, 180.0)
  // (half way: its padding, margin and the gap before it as much as what it holds is there)
  let inner = ge_y(t, "里")
  let k = (inner - 20.0) / 32.0
  assert_true(k > 0.2 && k < 0.95, msg="on its way: \{k}")
  let under = ge_y(t, "下")
  assert_true((under - inner - (64.0 * k + 10.0)).abs() < 0.05, msg="padding below with it: \{inner} \{under} \{k}")
  let ys = first + ge_frames(t, 180.0, 900.0)
  assert_eq(ys[0], 30.0)
  assert_eq(ys[ys.length() - 1], 126.0)
  for i in 1..<ys.length() {
    assert_true(ys[i] >= ys[i - 1], msg="opens only: \{Repr(ys)}")
  }
  let most = ge_most_step(ys)
  assert_true(most < 12.0, msg="no step: the most a frame \{most}, \{Repr(ys)}")
  t.at(900.0)
  t.frame(390.0, 844.0) |> ignore
  assert_false(t.clock_read())
}

///|
test "gone_empty, the last of what it holds going: its padding, margin and gap close with that one's way, then none" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let t = ge_tree(on)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(ge_y(t, "下"), 126.0)
  t.event(100.0, fn() { on.set(false) })
  let ys = ge_frames(t, 100.0, 900.0)
  assert_eq(ys[0], 126.0)
  assert_eq(ys[ys.length() - 1], 30.0)
  for i in 1..<ys.length() {
    assert_true(ys[i] <= ys[i - 1], msg="closes only: \{Repr(ys)}")
  }
  let most = ge_most_step(ys)
  assert_true(most < 12.0, msg="no step: the most a frame \{most}, \{Repr(ys)}")
  assert_eq(ge_y(t, "里"), -1.0)
  assert_false(t.clock_read())
}

///|
test "gone_empty, what it holds called back as it goes: its padding turns with it, no step" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let t = ge_tree(on)
  t.frame(390.0, 844.0) |> ignore
  t.event(100.0, fn() { on.set(false) })
  let going = ge_frames(t, 100.0, 180.0)
  let low = going[going.length() - 1]
  assert_true(low > 30.0 && low < 126.0, msg="half way: \{low}")
  t.event(180.0, fn() { on.set(true) })
  let back = ge_frames(t, 180.0, 300.0)
  // (where it is, its padding with it: as much of it as what it holds is there)
  let inner = ge_y(t, "里")
  let k = (inner - 20.0) / 32.0
  let under = ge_y(t, "下")
  assert_true(k > 0.05 && k < 0.95, msg="on its way back: \{k}")
  assert_true((under - inner - (64.0 * k + 10.0)).abs() < 0.05, msg="padding below with it: \{inner} \{under} \{k}")
  let back = back + ge_frames(t, 300.0, 1000.0)
  assert_eq(back[0], low)
  assert_eq(back[back.length() - 1], 126.0)
  let all = going + back
  let most = ge_most_step(all)
  assert_true(most < 12.0, msg="no step as it turns: the most a frame \{most}, \{Repr(all)}")
  t.at(1000.0)
  t.frame(390.0, 844.0) |> ignore
  assert_false(t.clock_read())
}

///|
test "gone_empty, what it holds coming and going on its way: the same at a moment however many frames were drawn" {
  let at_moments = fn(every : Double) -> Array[Double] {
    let on = @signals.signal(false, same=fn(a, b) { a == b })
    let t = ge_tree(on)
    t.frame(390.0, 844.0) |> ignore
    t.event(100.0, fn() { on.set(true) })
    let out = []
    let ms = Ref(100.0)
    // (frames every `every` ms on the way to `to`, then one there: 0, none between)
    let step_to = fn(to : Double) {
      if every > 0.0 {
        while ms.val + every < to {
          ms.val = ms.val + every
          t.at(ms.val)
          t.frame(390.0, 844.0) |> ignore
        }
      }
      ms.val = to
      t.at(to)
      t.frame(390.0, 844.0) |> ignore
      out.push(ge_y(t, "下"))
    }
    step_to(160.0)
    step_to(230.0)
    step_to(330.0)
    t.event(330.0, fn() { on.set(false) })
    step_to(400.0)
    step_to(470.0)
    step_to(900.0)
    out
  }
  let jumped = at_moments(0.0)
  let at_120 = at_moments(1000.0 / 120.0)
  let at_7 = at_moments(1000.0 / 7.0)
  for i in 0..<jumped.length() {
    assert_true(ge_near(jumped[i], at_120[i]) && ge_near(jumped[i], at_7[i]), msg="\{Repr(jumped)} \{Repr(at_120)} \{Repr(at_7)}")
  }
}

///|
test "gone_empty, one picked in another's place: its padding stays, only the one in it making its way" {
  let tall = @signals.signal(false, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.gap(Is(10.0)) |> ignore
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("上")) |> ignore }) |> ignore
    root.box(fn(b) {
      b.gone_empty(Is(true)).padding(Is((0.0, 18.0, 0.0, 24.0))) |> ignore
      b.pick(fn() { tall.get() }, fn(v, k) {
        v.height(Is(Some(if k { 60.0 } else { 20.0 }))).words(Is(if k { "乙" } else { "甲" })) |> ignore
      })
    })
    |> ignore
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  assert_eq(ge_y(t, "甲"), 48.0)
  assert_eq(ge_y(t, "下"), 102.0)
  t.event(100.0, fn() { tall.set(true) })
  let ys = ge_frames(t, 100.0, 180.0)
  // (its padding above as it was all the way: what is in it where it stood)
  assert_eq(ge_y(t, "乙"), 48.0)
  let ys = ys + ge_frames(t, 180.0, 800.0)
  for i in 1..<ys.length() {
    assert_true(ys[i] >= ys[i - 1], msg="grows only: \{Repr(ys)}")
  }
  assert_eq(ys[ys.length() - 1], 142.0)
  assert_eq(ge_y(t, "乙"), 48.0)
}

///|
/// The word drawn `w`'s left (x), as the tree is drawn now; none: -1.
fn ge_x(t : @view.Tree, w : String) -> Double {
  let found = t.drawn().filter(fn(d) { d.words == w })
  if found.length() == 0 {
    -1.0
  } else {
    found[0].x
  }
}

///|
test "gone_empty in gone_empty: what the innermost holds coming, called back and going, both open and close with it, no step" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.gap(Is(10.0)) |> ignore
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("上")) |> ignore }) |> ignore
    root.box(fn(outer) {
      outer.gone_empty(Is(true)).padding(Is((0.0, 6.0, 0.0, 8.0))) |> ignore
      outer.box(fn(inner) {
        inner.gone_empty(Is(true)).padding(Is((0.0, 18.0, 0.0, 24.0))) |> ignore
        inner.show(fn() { on.get() }, fn(v) { v.height(Is(Some(40.0))).words(Is("里")) |> ignore })
      })
      |> ignore
    })
    |> ignore
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  assert_eq(ge_y(t, "下"), 30.0)
  // (both its own as much as the innermost's is there: above it 10 + 6 + 18 of it, under it 24 + 8, then 10)
  let both = fn(at : String) -> Double raise {
    let inner = ge_y(t, "里")
    let k = (inner - 20.0) / 34.0
    let under = ge_y(t, "下")
    assert_true((under - inner - (72.0 * k + 10.0)).abs() < 0.05, msg="\{at}: \{inner} \{under} \{k}")
    k
  }
  t.event(100.0, fn() { on.set(true) })
  let ys = ge_frames(t, 100.0, 180.0)
  let k = both("coming")
  assert_true(k > 0.2 && k < 0.95, msg="on its way: \{k}")
  // (called back as it comes: both turn with it)
  t.event(180.0, fn() { on.set(false) })
  let ys = ys + ge_frames(t, 180.0, 260.0)
  let k2 = both("turned")
  assert_true(k2 > 0.0 && k2 < 0.95, msg="on its way back: \{k2}")
  let ys = ys + ge_frames(t, 260.0, 1000.0)
  assert_eq(ys[ys.length() - 1], 30.0)
  assert_eq(ge_y(t, "里"), -1.0)
  let most = ge_most_step(ys)
  assert_true(most < 12.0, msg="no step: the most a frame \{most}, \{Repr(ys)}")
  // (again, all the way in)
  t.event(1000.0, fn() { on.set(true) })
  let ys = ge_frames(t, 1000.0, 1800.0)
  assert_eq(ys[ys.length() - 1], 136.0)
  assert_eq(ge_y(t, "里"), 54.0)
  assert_true(ge_most_step(ys) < 12.0, msg="no step: \{Repr(ys)}")
  assert_false(t.clock_read())
}

///|
test "gone_empty along a row: none of its room, padding or gap in the frame it holds nothing, all of it in the frame it holds something" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.box(fn(r) {
      r.row(Is(true)).gap(Is(10.0)) |> ignore
      r.box(fn(b) { b.width(Is(Some(20.0))).words(Is("甲")) |> ignore }) |> ignore
      r.box(fn(b) {
        // (a row itself: what it holds comes and goes at once, along it)
        b.row(Is(true)).gone_empty(Is(true)).padding(Is((7.0, 0.0, 9.0, 0.0))) |> ignore
        b.show(fn() { on.get() }, fn(v) { v.width(Is(Some(30.0))).words(Is("中")) |> ignore })
      })
      |> ignore
      r.box(fn(b) { b.width(Is(Some(20.0))).words(Is("乙")) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  // (20 + 10 + 7 + 30 + 9 + 10)
  assert_eq(ge_x(t, "乙"), 86.0)
  t.event(100.0, fn() { on.set(false) })
  t.at(100.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(ge_x(t, "乙"), 30.0)
  t.event(200.0, fn() { on.set(true) })
  t.at(200.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(ge_x(t, "乙"), 86.0)
  assert_false(t.clock_read())
}

///|
/// As ge_tree, what the box holds a pick: 里 (40 tall) where `on` says so, else a case that makes nothing.
fn ge_pick_tree(on : @signals.Signal[Bool], at_once? : Bool = false) -> @view.Tree {
  @view.Tree::new(fn(root) {
    root.gap(Is(10.0)) |> ignore
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("上")) |> ignore }) |> ignore
    root.box(fn(b) {
      b.gone_empty(Is(true)).padding(Is((0.0, 18.0, 0.0, 24.0))).margin(Is((0.0, 4.0, 0.0, 0.0))) |> ignore
      b.pick(at_once~, fn() { on.get() }, fn(v, k) {
        if k {
          v.height(Is(Some(40.0))).words(Is("里")) |> ignore
        }
      })
    })
    |> ignore
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
  })
}

///|
test "gone_empty holding a pick of a case that makes nothing: none of its room; the other case, all of it" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let t = ge_pick_tree(on, at_once=true)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(ge_y(t, "下"), 30.0)
  t.event(100.0, fn() { on.set(true) })
  t.at(100.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(ge_y(t, "里"), 52.0)
  assert_eq(ge_y(t, "下"), 126.0)
  t.event(200.0, fn() { on.set(false) })
  t.at(200.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(ge_y(t, "下"), 30.0)
}

///|
test "gone_empty, a pick changed to a case that makes nothing: its padding, margin and gap close with the one before's way, then none" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let t = ge_pick_tree(on)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(ge_y(t, "下"), 126.0)
  t.event(100.0, fn() { on.set(false) })
  let ys = ge_frames(t, 100.0, 900.0)
  assert_eq(ys[0], 126.0)
  assert_eq(ys[ys.length() - 1], 30.0)
  for i in 1..<ys.length() {
    assert_true(ys[i] <= ys[i - 1], msg="closes only: \{Repr(ys)}")
  }
  let most = ge_most_step(ys)
  assert_true(most < 12.0, msg="no step: the most a frame \{most}, \{Repr(ys)}")
  assert_eq(ge_y(t, "里"), -1.0)
  assert_false(t.clock_read())
}

///|
test "gone_empty, a pick changed from a case that makes nothing: its padding, margin and gap open with the new one's way" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let t = ge_pick_tree(on)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(ge_y(t, "下"), 30.0)
  t.event(100.0, fn() { on.set(true) })
  let ys = ge_frames(t, 100.0, 900.0)
  assert_eq(ys[0], 30.0)
  assert_eq(ys[ys.length() - 1], 126.0)
  for i in 1..<ys.length() {
    assert_true(ys[i] >= ys[i - 1], msg="opens only: \{Repr(ys)}")
  }
  let most = ge_most_step(ys)
  assert_true(most < 12.0, msg="no step: the most a frame \{most}, \{Repr(ys)}")
  assert_false(t.clock_read())
}

///|
test "gone_empty, a pick changed to nothing and back half way: its padding turns with the way, no step" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let t = ge_pick_tree(on)
  t.frame(390.0, 844.0) |> ignore
  t.event(100.0, fn() { on.set(false) })
  let going = ge_frames(t, 100.0, 160.0)
  t.event(160.0, fn() { on.set(true) })
  let ys = going + ge_frames(t, 160.0, 900.0)
  assert_eq(ys[ys.length() - 1], 126.0)
  let most = ge_most_step(ys)
  assert_true(most < 12.0, msg="no step: the most a frame \{most}, \{Repr(ys)}")
}

///|
test "gone_empty holding a box the app says that holds nothing: that is something, all of its room there" {
  let t = @view.Tree::new(fn(root) {
    root.gap(Is(10.0)) |> ignore
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("上")) |> ignore }) |> ignore
    root.box(fn(b) {
      b.gone_empty(Is(true)).padding(Is((0.0, 18.0, 0.0, 24.0))) |> ignore
      b.box(fn(_) {  }) |> ignore
    })
    |> ignore
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  // (20 + 10 + 18 + 0 + 24 + 10)
  assert_eq(ge_y(t, "下"), 82.0)
}
