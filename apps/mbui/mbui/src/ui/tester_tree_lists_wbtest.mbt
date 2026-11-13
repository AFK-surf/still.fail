// What a Tester reads of a list (Tester::rows, row, visible, at_end, list_row_boxes, check_rows, scroll_to,
// scroll_to_end, list_offset) says the same of an old view's list and of a page's list of the window's tree
// (View::scrolls_window) showing the same rows; and the words each draws (Tester::text_runs, rich_of).

///|
/// 40 rows 40 high, 300 wide, in a window 300 by 200: an old view's list where `tree` is false, else a page's list of
/// the window's tree, each row's words "row i".
fn rows_tester(tree : Bool) -> Tester {
  if !tree {
    let t = Tester::new(fn(c) {
      c.list("l", 40, 40.0, fn(i) {
        c.box(h=Px(40.0), w=Fill(1.0), fn() { c.text("row \{i}", wrap=false) |> ignore }) |> ignore
      })
      |> ignore
    }, w=300.0, h=200.0)
    t.check_looks(false)
    t.draw()
    return t
  }
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  t.check_looks(false)
  let s = @view.Scroll::list()
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.height(Is(Some(200.0))).width(Is(Some(300.0))) |> ignore
      page.scrolls_window(s, fn() { Array::makei(40, fn(i) { i }) }, est=40.0, fn(b, i) {
        b.box(fn(r) {
          r.height(Is(Some(40.0))).words(Is("row \{i}")) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  t
}

///|
/// What a Tester reads of its list now: the rows in sight (item, y, height), the first and last, at its end.
fn rows_read(t : Tester) -> (Array[(Int, Double, Double)], (Int, Int), Bool) {
  (t.rows(), t.visible(), t.at_end())
}

///|
test "an old view's list and a page's list of the tree with the same rows: the same rows read in sight, where, the first and last, at its end or not; brought to a row, to its end, the same again" {
  let old = rows_tester(false)
  let at_top = rows_read(old)
  let old_row = old.row(2)
  old.check_rows(0.0, 200.0)
  old.scroll_to(10)
  old.frame()
  let at_ten = rows_read(old)
  old.scroll_to_end()
  old.frame()
  let at_end = rows_read(old)
  let tree = rows_tester(true)
  assert_eq(rows_read(tree), at_top)
  assert_eq(at_top.1, (0, 4))
  assert_eq(tree.row(2).map(fn(r) { (r.1, r.3) }), old_row.map(fn(r) { (r.1, r.3) }))
  assert_eq(tree.list_row_boxes().length(), 1)
  assert_eq(tree.list_row_boxes()[0].length(), 5)
  tree.check_rows(0.0, 200.0)
  assert_eq(tree.list_offset(), 0.0)
  tree.scroll_to(10)
  tree.frame()
  assert_eq(rows_read(tree), at_ten)
  assert_eq(tree.list_offset(), 400.0)
  tree.scroll_to_end()
  tree.frame()
  assert_eq(rows_read(tree), at_end)
  assert_true(at_end.2, msg="at its end")
}

///|
test "the words a page's list of the tree draws read as lines of words drawn (Tester::text_runs) as an old view's are; a node's words in pieces as a rich paragraph (Tester::rich_of)" {
  // (each read before the next is made: a Tester reads the frame of the one made last)
  for tree in [false, true] {
    let t = rows_tester(tree)
    let runs = t.text_runs()
    assert_true(runs.iter().any(fn(r) { r.text == "row 3" }), msg="\{tree}: \{Repr(runs.map(fn(r) { r.text }))}")
    assert_false(runs.iter().any(fn(r) { r.text == "row 9" }), msg="\{tree}: row 9 drawn")
  }
  let tree = rows_tester(true)
  let r3 = tree.text_runs().filter(fn(r) { r.text == "row 3" })[0]
  assert_true(r3.top >= 120.0 && r3.bottom <= 160.0, msg="\{Repr(r3)}")
  // (a node's words in pieces: laid out as it draws them, where it is drawn)
  let t = tree_picked_tester(true)
  match t.rich_of("wide") {
    Some((lay, x, y)) => {
      assert_true(lay.text.contains("hello wide world"), msg=lay.text)
      let (wx, wy, _, _) = t.run_rects("wide")[0]
      let a = lay.text.find("wide").unwrap()
      let r = lay.rects(a, a + 4)[0]
      assert_true((x + r.0 - wx).abs() < 0.01 && (y + r.1 - wy).abs() < 0.01, msg="\{Repr((x, y, r))} \{Repr((wx, wy))}")
    }
    None => fail("no rich paragraph of the tree's")
  }
}
