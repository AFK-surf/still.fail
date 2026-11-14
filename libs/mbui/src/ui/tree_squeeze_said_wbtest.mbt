// Words of the window tree on one line in a column narrower than they are: the framework holds them to the column's
// width (Tree::capped_applied) and cuts them with an ellipsis, which says nothing of whether the app meant them to be
// cut (Tree::allows_ellipsis: only what the app said).

///|
/// How these tests' words are set: 10 points, one line.
let unsaid_cut_look : @view.WordsLook = {
  size: 10.0,
  weight: 400,
  line: 14.0,
  wrap: false,
  tracking: @view.letters_own,
  balance: false,
  max_lines: 0,
}

///|
/// A column 60 wide (a row: `row`) holding `words` on one line, nothing said of their width; `say` says what else of
/// them, `holder` of what holds them.
fn unsaid_cut_tester(
  words : String,
  say : (@view.View) -> Unit,
  row? : Bool = false,
  holder? : (@view.View) -> Unit = fn(_v) {  },
) -> Tester {
  Tester::new(fn(_c) {  }, w=400.0, h=100.0, tree=fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(60.0))).row(Is(row)) |> ignore
      holder(col)
      col.box(fn(v) {
        v.words(Is(words), look=unsaid_cut_look) |> ignore
        say(v)
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// Whether `words` were drawn cut: as wide on one line as they are, wider by half a point than they were laid out.
fn unsaid_cut_drawn(words : String) -> Bool {
  let drawn = view_tree().unwrap().drawn().filter(fn(d) { d.words == words })
  let c = g()
  let full = layout_text(words, c.sp(10.0), 400, 1.0e9, false, line=c.sp(14.0), style=view_words_style())
  drawn.length() == 1 && full.w > drawn[0].w + 0.5
}

///|
/// Words much wider than the column of 60 they are in.
let unsaid_cut_long : String = "words much wider than their column"

///|
test "a window tree's words cut to their column, nothing said, are cut short without saying they may be" {
  let t = unsaid_cut_tester(unsaid_cut_long, fn(_v) {  })
  t.draw()
  assert_true(unsaid_cut_drawn(unsaid_cut_long))
  let faults = t.squeeze_faults()
  assert_eq(faults.length(), 1, msg=faults.join("\n"))
  assert_true(faults[0].contains("cut short without saying they may be"), msg=faults[0])
  // (and what of them shows)
  assert_true(faults[0].contains("(showing ‘words") && faults[0].contains("…’)"), msg=faults[0])
}

///|
test "a window tree's words cut to their column, said to end in an ellipsis, are no fault" {
  let t = unsaid_cut_tester(unsaid_cut_long, fn(v) { v.allow_ellipsis(Is(true)) |> ignore })
  t.draw()
  assert_true(unsaid_cut_drawn(unsaid_cut_long))
  assert_eq(t.squeeze_faults(), [])
}

///|
test "a window tree's words said to give way along their row, cut, are no fault" {
  let t = unsaid_cut_tester(unsaid_cut_long, fn(v) { v.shrink(Is(1.0)) |> ignore }, row=true)
  t.draw()
  assert_true(unsaid_cut_drawn(unsaid_cut_long))
  assert_eq(t.squeeze_faults(), [])
}

///|
test "a window tree's words cut to their column, in a column that gives way down (as a scroll does), are a fault" {
  let t = unsaid_cut_tester(unsaid_cut_long, fn(_v) {  }, holder=fn(col) { col.shrink(Is(1.0)) |> ignore })
  t.draw()
  assert_true(unsaid_cut_drawn(unsaid_cut_long))
  let faults = t.squeeze_faults()
  assert_eq(faults.length(), 1, msg=faults.join("\n"))
}

///|
test "a window tree's words held to a width said, are no fault" {
  let t = unsaid_cut_tester(unsaid_cut_long, fn(v) { v.max_width(Is(Some(40.0))) |> ignore })
  t.draw()
  assert_true(unsaid_cut_drawn(unsaid_cut_long))
  assert_eq(t.squeeze_faults(), [])
}

///|
test "a window tree's words that fit their column are no fault" {
  let t = unsaid_cut_tester("fits", fn(_v) {  })
  t.draw()
  assert_false(unsaid_cut_drawn("fits"))
  assert_eq(t.squeeze_faults(), [])
}

///|
/// A row 60 wide holding a box that gives way along it (`shrink(1)`, as narrow as nothing), the words on one line in
/// that box, nothing said of them; `outer` says what else of the box.
fn unsaid_cut_in_giving(outer : (@view.View) -> Unit) -> Tester {
  Tester::new(fn(_c) {  }, w=400.0, h=100.0, tree=fn(root) {
    root.box(fn(row) {
      row.width(Is(Some(60.0))).row(Is(true)) |> ignore
      row.box(fn(o) {
        o.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
        outer(o)
        o.box(fn(v) { v.words(Is(unsaid_cut_long), look=unsaid_cut_look) |> ignore }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
}

///|
test "a window tree's words in a box that gives way along its row, nothing said of them, cut: a fault" {
  let t = unsaid_cut_in_giving(fn(_o) {  })
  t.draw()
  assert_true(unsaid_cut_drawn(unsaid_cut_long))
  let faults = t.squeeze_faults()
  assert_eq(faults.length(), 1, msg=faults.join("\n"))
  assert_true(faults[0].contains("cut short without saying they may be"), msg=faults[0])
}

///|
test "a window tree's words in a box said to be cut short (View::cuts), cut: no fault" {
  let t = unsaid_cut_in_giving(fn(o) { o.cuts(Is(true)) |> ignore })
  t.draw()
  assert_true(unsaid_cut_drawn(unsaid_cut_long))
  assert_eq(t.squeeze_faults(), [])
}
