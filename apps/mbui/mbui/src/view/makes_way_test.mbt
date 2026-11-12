///|
/// The word drawn `w`'s top (y), as the tree is drawn now.
fn word_y(t : @view.Tree, w : String) -> Double {
  t.drawn().filter(fn(d) { d.words == w })[0].y
}

///|
test "shown down a column: it opens its way as a Move as far as it is tall, what is under it going with it; there, nothing reads the clock" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.show(fn() { on.get() }, fn(v) { v.height(Is(Some(40.0))).words(Is("出")) |> ignore })
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  assert_eq(word_y(t, "下"), 0.0)
  t.event(100.0, fn() { on.set(true) })
  t.at(100.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(word_y(t, "下"), 0.0)
  assert_true(t.clock_read())
  // (a Move over 40: 250 ms, nine tenths of the way at half of it)
  t.at(225.0)
  t.frame(390.0, 844.0) |> ignore
  let half = word_y(t, "下")
  assert_true(half > 34.0 && half < 37.0, msg="half way: \{half}")
  t.at(350.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(word_y(t, "下"), 40.0)
  assert_false(t.clock_read())
}

///|
test "let go down a column: it closes its way as a Move as far as it is tall, drawn as it was, let go once it is shut" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let runs = Ref(0)
  let said = @signals.signal("出", same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.show(fn() { on.get() }, fn(v) {
      v
      .height(Is(Some(40.0)))
      .words(By(fn() {
        runs.val = runs.val + 1
        said.get()
      }))
      |> ignore
    })
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  let gone = t.root().kids()[0].kids()[0]
  assert_eq(word_y(t, "下"), 40.0)
  t.event(100.0, fn() { on.set(false) })
  t.at(225.0)
  t.frame(390.0, 844.0) |> ignore
  let half = word_y(t, "下")
  assert_true(half > 3.0 && half < 6.0, msg="half way: \{half}")
  assert_true(gone.alive())
  // (at rest as it closes: what it read changed runs nothing of it)
  let before = runs.val
  said.set("改")
  t.frame(390.0, 844.0) |> ignore
  assert_eq(runs.val, before)
  t.at(350.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(word_y(t, "下"), 0.0)
  assert_false(gone.alive())
  assert_false(t.clock_read())
}

///|
test "shown again as it closes its way: the same node, its way made again from as tall as it is, on from as fast as it closed" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.show(fn() { on.get() }, fn(v) { v.height(Is(Some(40.0))).words(Is("出")) |> ignore })
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  let first = t.root().kids()[0].kids()[0]
  t.event(100.0, fn() { on.set(false) })
  t.at(225.0)
  t.frame(390.0, 844.0) |> ignore
  let low = word_y(t, "下")
  t.event(225.0, fn() { on.set(true) })
  t.frame(390.0, 844.0) |> ignore
  assert_true(first.alive())
  assert_eq(t.root().kids()[0].kids()[0].id(), first.id())
  assert_eq(word_y(t, "下"), low)
  // (on from as fast as it closed, slowing to rest a little further (flex's come_way), then back)
  t.at(250.0)
  t.frame(390.0, 844.0) |> ignore
  let on_down = word_y(t, "下")
  assert_true(on_down < low && on_down >= 0.0, msg="on from its speed: \{low} → \{on_down}")
  t.at(450.0)
  t.frame(390.0, 844.0) |> ignore
  let up = word_y(t, "下")
  assert_true(up > low && up < 40.0, msg="on its way back: \{low} → \{up}")
  t.at(800.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(word_y(t, "下"), 40.0)
  assert_false(t.clock_read())
}

///|
test "picked anew down a column: the new one's way from as tall as the one before to as tall as it is" {
  let tall = @signals.signal(false, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.pick(fn() { tall.get() }, fn(v, k) { v.height(Is(Some(if k { 60.0 } else { 20.0 }))) |> ignore })
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  assert_eq(word_y(t, "下"), 20.0)
  t.event(100.0, fn() { tall.set(true) })
  t.at(100.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(word_y(t, "下"), 20.0)
  t.at(180.0)
  t.frame(390.0, 844.0) |> ignore
  let mid = word_y(t, "下")
  assert_true(mid > 20.0 && mid < 60.0, msg="on its way: \{mid}")
  t.at(600.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(word_y(t, "下"), 60.0)
  assert_false(t.clock_read())
}

///|
test "picked anew down a column with a gap: the gap before it there all along, what is under it set out from where it was" {
  // (the one before had the gap, the new one in its place has it from the first: only what comes from nothing or goes to
  // it opens or closes its gap (flex's gap_share))
  let tall = @signals.signal(false, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.gap(Is(12.0)) |> ignore
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("上")) |> ignore }) |> ignore
    root.pick(fn() { tall.get() }, fn(v, k) { v.height(Is(Some(if k { 60.0 } else { 20.0 }))) |> ignore })
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  assert_eq(word_y(t, "下"), 64.0)
  t.event(100.0, fn() { tall.set(true) })
  t.at(100.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(word_y(t, "下"), 64.0)
  t.at(104.0)
  t.frame(390.0, 844.0) |> ignore
  let first = word_y(t, "下")
  assert_true(first >= 64.0 && first < 66.0, msg="set out from where it was: \{first}")
  t.at(600.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(word_y(t, "下"), 104.0)
}

///|
test "at once, along a row, or made with what holds it: no way made" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let across = @signals.signal(false, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.show(at_once=true, fn() { on.get() }, fn(v) { v.height(Is(Some(40.0))).words(Is("出")) |> ignore })
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
    root.box(fn(r) {
      r.row(Is(true)) |> ignore
      r.show(fn() { across.get() }, fn(v) { v.width(Is(Some(30.0))).words(Is("旁")) |> ignore })
      r.box(fn(b) { b.width(Is(Some(20.0))).words(Is("右")) |> ignore }) |> ignore
    })
    |> ignore
    root.show(fn() { true }, fn(v) { v.height(Is(Some(10.0))).words(Is("早")) |> ignore })
  })
  t.frame(390.0, 844.0) |> ignore
  assert_false(t.clock_read())
  t.event(100.0, fn() {
    on.set(true)
    across.set(true)
  })
  t.at(100.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(word_y(t, "下"), 40.0)
  assert_eq(t.drawn().filter(fn(d) { d.words == "右" })[0].x, 30.0)
  assert_false(t.clock_read())
}

///|
/// 出 (40 tall, over 下) shown (`showing`: let go of, else shown) at 100, then the other way at 105; a frame drawn
/// between the two (`between`) or none: where 下 is at each of the moments after.
fn turned_in_a_frame(showing : Bool, between : Bool) -> Array[Double] {
  let on = @signals.signal(showing, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.show(fn() { on.get() }, fn(v) { v.height(Is(Some(40.0))).words(Is("出")) |> ignore })
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
  })
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
    word_y(t, "下")
  })
}

///|
test "let go of and shown again 5 ms later: the same way whether a frame was drawn between the two or not" {
  let none = turned_in_a_frame(true, false)
  let one = turned_in_a_frame(true, true)
  assert_eq(none, one)
  assert_eq(none[none.length() - 1], 40.0)
}

///|
test "shown and let go of again 5 ms later: the same way whether a frame was drawn between the two or not" {
  let none = turned_in_a_frame(false, false)
  let one = turned_in_a_frame(false, true)
  assert_eq(none, one)
  assert_eq(none[none.length() - 1], 0.0)
}

///|
/// A column 120 wide, 30 in from either side, holding 上, what shows (words wrapping at its 60: as tall as its width
/// makes it) and 下; what shows set on and off at each of `turns` (ms; shown first), a frame drawn half way between each
/// two (`between`) or none: where 下 is at each of the moments after.
fn turned_padded(turns : Array[Double], between : Bool) -> Array[Double] {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(120.0))).padding(Is((30.0, 0.0, 30.0, 0.0))) |> ignore
      col.box(fn(b) { b.height(Is(Some(20.0))).words(Is("上")) |> ignore }) |> ignore
      col.show(fn() { on.get() }, fn(v) { v.words(Is("一段会折成好几行的字，放在有内边距的列里")) |> ignore })
      col.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  for i, at in turns {
    if between && i > 0 {
      t.at((turns[i - 1] + at) / 2.0)
      t.frame(390.0, 844.0) |> ignore
    }
    t.event(at, fn() { on.set(i % 2 == 0) })
  }
  let last = turns[turns.length() - 1]
  [5.0, 30.0, 90.0, 180.0, 300.0, 900.0].map(fn(m) {
    t.at(last + m)
    t.frame(390.0, 844.0) |> ignore
    word_y(t, "下")
  })
}

///|
test "words wrapping in a padded column shown, then let go of 5 or 100 ms later: the same way whether a frame was drawn between or not" {
  for after in [5.0, 100.0] {
    let none = turned_padded([100.0, 100.0 + after], false)
    let one = turned_padded([100.0, 100.0 + after], true)
    assert_eq(none, one, msg="let go of \{after} ms on")
    assert_eq(none[none.length() - 1], 20.0)
  }
}

///|
test "words wrapping in a padded column shown, let go of and shown again, no frame between, or one between each two: the same way" {
  let none = turned_padded([100.0, 130.0, 160.0], false)
  let one = turned_padded([100.0, 130.0, 160.0], true)
  assert_eq(none, one)
  assert_true(none[none.length() - 1] > 40.0, msg="shown again, wrapped: \{Repr(none)}")
}

///|
test "a show let go of and its opposite shown down a column at once: one in the other's place next to it, each its own way with something between them" {
  // (next to each other: the one shown in the other's place, from as tall as it was, what is under them going so)
  let a_on = @signals.signal(true, same=fn(a, b) { a == b })
  let c_on = @signals.signal(false, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.show(fn() { a_on.get() }, fn(v) { v.height(Is(Some(40.0))).words(Is("A")) |> ignore })
    root.show(fn() { c_on.get() }, fn(v) { v.height(Is(Some(60.0))).words(Is("C")) |> ignore })
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  t.event(100.0, fn() {
    a_on.set(false)
    c_on.set(true)
  })
  t.at(100.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(word_y(t, "C"), 0.0)
  assert_eq(word_y(t, "下"), 40.0)
  // (B between them: A closes its way over B, C opens its own under B, from nothing; B never put up at once)
  let a_on = @signals.signal(true, same=fn(a, b) { a == b })
  let c_on = @signals.signal(false, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.show(fn() { a_on.get() }, fn(v) { v.height(Is(Some(40.0))).words(Is("A")) |> ignore })
    root.box(fn(b) { b.height(Is(Some(40.0))).words(Is("B")) |> ignore }) |> ignore
    root.show(fn() { c_on.get() }, fn(v) { v.height(Is(Some(60.0))).words(Is("C")) |> ignore })
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  assert_eq(word_y(t, "B"), 40.0)
  t.event(100.0, fn() {
    a_on.set(false)
    c_on.set(true)
  })
  t.at(100.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(word_y(t, "B"), 40.0)
  assert_eq(word_y(t, "C"), 80.0)
  assert_eq(word_y(t, "下"), 80.0)
  // (a Move over 40, half of it: nine tenths closed; C's over 60 as far)
  t.at(225.0)
  t.frame(390.0, 844.0) |> ignore
  let b = word_y(t, "B")
  assert_true(b > 3.0 && b < 6.0, msg="B half way: \{b}")
  t.at(600.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(word_y(t, "B"), 0.0)
  assert_eq(word_y(t, "C"), 40.0)
  assert_eq(word_y(t, "下"), 100.0)
}

///|
/// A pick down a column from a box 20 tall to one as tall as `tall` says, picked at 100, `tall` set to `then` at
/// `at` (none: never): where what is under it is drawn, every 10 ms from 100 to 600.
fn grown_on_way(then : Double, at : Double) -> Array[Double] {
  let picked = @signals.signal(false, same=fn(a, b) { a == b })
  let tall = @signals.signal(60.0, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.pick(fn() { picked.get() }, fn(v, k) {
      if k {
        v.box(fn(b) { b.height(By(fn() { Some(tall.get()) })) |> ignore }) |> ignore
      } else {
        v.height(Is(Some(20.0))) |> ignore
      }
    })
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  t.event(100.0, fn() { picked.set(true) })
  let out = []
  let mut ms = 100.0
  while ms <= 600.0 {
    if ms == at {
      t.event(at, fn() { tall.set(then) })
    }
    t.at(ms)
    t.frame(390.0, 844.0) |> ignore
    out.push(word_y(t, "下"))
    ms = ms + 10.0
  }
  out
}

///|
test "what comes in another's place grown of its own on its way: its way the same, only its end moved, by as much as its Move has got" {
  // (60 all the way, and 60 till 180 then 220 at once, what it holds grown of its own: no cause of this way's. Its way
  // as long and turned as it was said at 100; from then, as far on to the new end as to the old: as tall as from 20 by
  // the same share of 200 as of 40)
  let steady = grown_on_way(60.0, -1.0)
  let grown = grown_on_way(220.0, 180.0)
  for i, y in steady {
    let ms = 100.0 + i.to_double() * 10.0
    let share = (y - 20.0) / 40.0
    let expect = if ms < 180.0 { y } else { 20.0 + 200.0 * share }
    assert_true((grown[i] - expect).abs() < 0.001, msg="at \{ms}: \{grown[i]}, as far on as \{expect}")
  }
  assert_eq(grown[grown.length() - 1], 220.0)
}
