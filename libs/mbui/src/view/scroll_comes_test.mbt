// What scrolls, held by what a pick or a show makes down a column (View::comes): it makes its way in as anything does,
// from as tall as the one before it was, what is under it going with it; what it holds laid out once at the size it
// comes to (its room, how far it can go, its blocks) all the way. A page or a pane (grown, as tall as the column leaves
// it) comes at once.

///|
/// Word `w`'s top (y), as the tree is drawn now.
fn scroll_word_y(t : @view.Tree, w : String) -> Double {
  t.drawn().filter(fn(d) { d.words == w })[0].y
}

///|
test "picked anew down a column, what scrolls in it: the new one's way from as tall as the one before, what it holds laid out once as it comes to" {
  let many = @signals.signal(false, same=fn(a, b) { a == b })
  let scroll = @view.Scroll::new()
  let t = @view.Tree::new(fn(root) {
    root.pick(fn() { many.get() }, fn(v, k) {
      if k {
        // (no taller than 120, holding 400: it scrolls, 280 to go)
        v.box(fn(c) {
          c.max_height(Is(Some(120.0))) |> ignore
          c.scrolls(scroll, fn(held) {
            for i in 0..<10 {
              held.box(fn(r) { r.height(Is(Some(40.0))).words(Is("行\{i}")) |> ignore }) |> ignore
            }
          })
          |> ignore
        })
        |> ignore
      } else {
        v.box(fn(b) { b.height(Is(Some(80.0))).words(Is("少")) |> ignore }) |> ignore
      }
    })
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  assert_eq(scroll_word_y(t, "下"), 80.0)
  t.event(100.0, fn() { many.set(true) })
  t.at(100.0)
  t.frame(390.0, 844.0) |> ignore
  // (from as tall as the one before, at once laid out as it comes to: 120 shown of 400)
  assert_eq(scroll_word_y(t, "下"), 80.0)
  assert_eq(scroll.reach(), 280.0)
  let mut last = 80.0
  let mut at = 100.0
  while at < 600.0 {
    at = at + 1000.0 / 60.0
    t.at(at)
    t.frame(390.0, 844.0) |> ignore
    let y = scroll_word_y(t, "下")
    assert_true(y >= last && y <= 120.0, msg="下 at \{at}: \{last} -> \{y}")
    // (what it holds as it comes to all the way: how far it can go the same)
    assert_eq(scroll.reach(), 280.0, msg="its reach at \{at}")
    last = y
  }
  assert_eq(scroll_word_y(t, "下"), 120.0)
}

///|
test "picked anew down a column, a list that holds its blocks only while they show in it: its blocks made once, as many as show at its size" {
  let many = @signals.signal(false, same=fn(a, b) { a == b })
  let scroll = @view.Scroll::list()
  let made : Array[Int] = []
  let t = @view.Tree::new(fn(root) {
    root.pick(fn() { many.get() }, fn(v, k) {
      if k {
        v.box(fn(c) {
          c.max_height(Is(Some(120.0))) |> ignore
          c.scrolls_window(scroll, fn() { Array::makei(20, fn(i) { i }) }, est=40.0, fn(b, i) {
            made.push(i)
            b.height(Is(Some(40.0))) |> ignore
          })
          |> ignore
        })
        |> ignore
      } else {
        v.box(fn(b) { b.height(Is(Some(40.0))) |> ignore }) |> ignore
      }
    })
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  t.event(100.0, fn() { many.set(true) })
  t.at(100.0)
  t.frame(390.0, 844.0) |> ignore
  let first = made.copy()
  let mut at = 100.0
  while at < 600.0 {
    at = at + 1000.0 / 60.0
    t.at(at)
    t.frame(390.0, 844.0) |> ignore
  }
  assert_eq(scroll_word_y(t, "下"), 120.0)
  // (made as it set out, none made again or more on its way: as many as its size at rest shows)
  assert_eq(made, first)
  let at_rest = made.length()
  assert_true(at_rest > 0 && at_rest <= 6, msg="made: \{Repr(made)}")
}

///|
test "picked anew down a column, a page that scrolls (as tall as the column leaves it): at once" {
  let other = @signals.signal(false, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.box(fn(col) {
      col.height(Is(Some(400.0))) |> ignore
      col.pick(fn() { other.get() }, fn(v, k) {
        v.grow(Is(1.0)) |> ignore
        v.scrolls(@view.Scroll::new(), fn(held) {
          let n = if k { 3 } else { 12 }
          for i in 0..<n {
            held.box(fn(r) { r.height(Is(Some(40.0))).words(Is(if i == 0 { "顶" } else { "行" })) |> ignore }) |> ignore
          }
        })
        |> ignore
      })
      col.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  assert_eq(scroll_word_y(t, "下"), 380.0)
  t.event(100.0, fn() { other.set(true) })
  t.at(100.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(scroll_word_y(t, "下"), 380.0)
  assert_false(t.clock_read())
}

///|
test "picked anew down a column, what scrolls in it holding less on its way: laid out as it comes to now, how far it can go with it, what is under it one way" {
  let many = @signals.signal(false, same=fn(a, b) { a == b })
  let rows = @signals.signal(10, same=fn(a, b) { a == b })
  let scroll = @view.Scroll::new()
  let t = @view.Tree::new(fn(root) {
    root.pick(fn() { many.get() }, fn(v, k) {
      if k {
        // (no taller than 200, holding 40 a row: ten, 400, 200 to go; four, 160, none; let go of at once)
        v.box(fn(c) {
          c.max_height(Is(Some(200.0))) |> ignore
          c.scrolls(scroll, fn(held) {
            held.each(at_once=true, fn() { Array::makei(rows.get(), fn(i) { i }) }, fn(i) { i }, fn(r, _) {
              r.height(Is(Some(40.0))) |> ignore
            })
          })
          |> ignore
        })
        |> ignore
      } else {
        v.box(fn(b) { b.height(Is(Some(40.0))) |> ignore }) |> ignore
      }
    })
    root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  t.event(100.0, fn() { many.set(true) })
  t.at(100.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(scroll.reach(), 200.0)
  t.event(110.0, fn() { rows.set(4) })
  let mut last = scroll_word_y(t, "下")
  let mut at = 110.0
  while at < 700.0 {
    t.at(at)
    t.frame(390.0, 844.0) |> ignore
    let y = scroll_word_y(t, "下")
    assert_true(y >= last - 0.001, msg="下 at \{at}: \{last} -> \{y}")
    assert_eq(scroll.reach(), 0.0, msg="its reach at \{at}")
    last = y
    at = at + 1000.0 / 60.0
  }
  assert_eq(scroll_word_y(t, "下"), 160.0)
}
