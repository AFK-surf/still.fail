// A page's list whose blocks are put by and taken for other keys (View::scrolls_window's `reused`), a block's words bound
// to its key: a wheel's turn that moves the window by many rows in one go takes blocks as the frame lays the column out
// (its fill), and what binds their key is told there. Each is drawn with its new key's words by that frame, not left
// with the words of the key it was put by with (a binding told in a frame's layout, view's Tree::laid_out).

///|
/// The rows' numbers drawn in sight, top down.
fn reused_words_drawn(t : Tester) -> Array[Int] {
  let rows = t
    .drawn_words_found()
    .filter(fn(d) { d.3.has_prefix("row ") && d.0.y + d.0.h > 0.0 && d.0.y < 200.0 })
    .map(fn(d) { (d.0.y, d.3) })
  rows.sort_by(fn(a, b) { a.0.compare(b.0) })
  rows.map(fn(r) {
    let mut n = 0
    for c in r.1.exact_view(start=4) {
      n = n * 10 + (c.to_int() - '0'.to_int())
    }
    n
  })
}

///|
/// Whether the rows drawn are the list's, one after another (none drawn with the words of a key its block had before).
fn reused_words_in_order(rows : Array[Int], least : Int) -> Bool {
  rows.length() > 0 &&
  rows[0] >= least &&
  rows.iter().zip(rows[1:].iter()).all(fn(p) { p.1 == p.0 + 1 })
}

///|
test "a page's list's blocks taken for other keys as a frame lays it out draw their new keys' words in that frame" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  // (as a device draws it: no pass built whole beside it)
  t.check_looks(false)
  let s = @view.Scroll::list()
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.height(Is(Some(200.0))).width(Is(Some(300.0))) |> ignore
      page.scrolls_window(
        s,
        fn() { Array::makei(40, fn(i) { i }) },
        est=22.0,
        fn(_, _) { @halt.saying("every block is of a kind another may take") },
        reused=fn(_) { Some(0) },
        make_reused=fn(b, key) { b.box(fn(w) { w.words(By(fn() { "row \{key()}" })) |> ignore }) |> ignore },
      )
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  let first = reused_words_drawn(t)
  // (one turn of 400: the window 18 rows down, the blocks of rows 0 to 3 taken for rows 18 to 21)
  t.wheel(150.0, 100.0, 400.0)
  let by_the_wheel = reused_words_drawn(t)
  t.run_for(move_most_ms)
  let after = reused_words_drawn(t)
  assert_eq(
    (
      reused_words_in_order(first, 0),
      reused_words_in_order(by_the_wheel, 17),
      reused_words_in_order(after, 17),
    ),
    (true, true, true),
    msg="first \{Repr(first)}, by the wheel's frame \{Repr(by_the_wheel)}, after \{Repr(after)}",
  )
}
