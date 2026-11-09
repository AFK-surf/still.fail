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
test "shown again as it closes its way: the same node, its way made again from as tall as it is" {
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
  t.at(300.0)
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
