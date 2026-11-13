// Words picked in a page's list's rows (View::scrolls_window) are known by the rows' keys (View::row_place, its list
// and its key's number there), not by the nodes the rows are made in: what the list makes again where a row was (its
// slot let go as it is far out of sight, made again as it comes back) shows the same words picked, copied in the same
// order (tree_select.mbt's tree_place: a row's place among the list's keys, View::row_order).

///|
/// A page 300 wide and 200 high of `n` blocks of words in pieces picked with the mouse, the second words of each bold.
fn row_picked_tester(n : Int) -> (Tester, @view.Scroll) {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  t.check_looks(false)
  let s = @view.Scroll::list()
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.height(Is(Some(200.0))).width(Is(Some(300.0))) |> ignore
      words_picked(page)
      page.scrolls_window(s, fn() { Array::makei(n, fn(i) { i }) }, est=22.0, fn(b, i) {
        b.box(fn(w) {
          w
          .words_runs(Is([plain("第 \{i} 段 "), bold("hello")]), ink=0x333333FFL, look={ size: 15.0, weight: 400, line: 22.0, wrap: true, tracking: @view.letters_own, balance: false, max_lines: 0 })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  (t, s)
}

///|
/// The first two rows' words picked, from the first's start to the second's end: what is copied of them.
fn row_picked_two(t : Tester) -> String {
  let next = dragged_at(t, 1.0, 11.0, 1.0 + 299.0 * 6.0 / 5.0, 11.0 + 26.0 * 6.0 / 5.0, t.time(), true)
  t.frame_at(next)
  t.ctx().selected_text()
}

///|
test "words picked in a page's list, scrolled three screens away and back (the rows made again where they were): picked as they were, drawn picked under the same words" {
  let (t, _) = row_picked_tester(40)
  let said = row_picked_two(t)
  assert_true(said.contains("第 0 段") && said.contains("第 1 段 hello"), msg="\{said}")
  let drawn = picked_drawn(t)
  assert_true(drawn.length() >= 2, msg="drawn picked: \{Repr(drawn)}")
  t.wheel(150.0, 100.0, 600.0)
  t.run_for(move_most_ms)
  assert_eq(picked_drawn(t).length(), 0, msg="none shows")
  t.wheel(150.0, 100.0, -600.0)
  t.run_for(move_most_ms)
  assert_eq(t.ctx().selected_text(), said)
  assert_eq(picked_drawn(t), drawn)
}

///|
test "words picked over two rows of a page's list, scrolled a thousand rows away and back: the same words picked, copied in the same order, drawn picked under the same words" {
  let (t, s) = row_picked_tester(1200)
  let said = row_picked_two(t)
  let first = said.find("第 0 段").unwrap_or(-1)
  let second = said.find("第 1 段 hello").unwrap_or(-1)
  assert_true(first >= 0 && second > first, msg="copied: \{said}")
  let drawn = picked_drawn(t)
  // (a thousand rows down, 22 each, then back to its top)
  t.wheel(150.0, 100.0, 22000.0)
  t.run_for(move_most_ms)
  match view_app.val {
    Some(tree) => assert_true(s.at(tree) > 20000.0, msg="at \{s.at(tree)}")
    None => fail("no window's tree")
  }
  t.wheel(150.0, 100.0, -22000.0)
  t.run_for(move_most_ms)
  assert_eq(t.ctx().selected_text(), said)
  assert_eq(picked_drawn(t), drawn)
}

///|
/// A page as row_picked_tester's whose blocks are all of one kind another may take (`reused`): each put by as it no
/// more shows and taken by the next to show, given that one's key (answering.mbt), its words by its key.
fn row_picked_reused_tester(n : Int, made : Ref[Int]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  t.check_looks(false)
  let s = @view.Scroll::list()
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.height(Is(Some(200.0))).width(Is(Some(300.0))) |> ignore
      words_picked(page)
      page.scrolls_window(
        s,
        fn() { Array::makei(n, fn(i) { i }) },
        est=22.0,
        fn(_, _) { @halt.saying("every block is of a kind another may take") },
        reused=fn(_) { Some(0) },
        make_reused=fn(b, key) {
          made.val = made.val + 1
          b.box(fn(w) {
            w
            .words_runs(By(fn() { [plain("第 \{key()} 段 "), bold("hello")] }), ink=0x333333FFL, look={ size: 15.0, weight: 400, line: 22.0, wrap: true, tracking: @view.letters_own, balance: false, max_lines: 0 })
            |> ignore
          })
          |> ignore
        },
      )
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  t
}

///|
test "words picked in a page's list's row, its block put by and taken for another key: nothing drawn picked on that one; back to the first key's row, drawn picked there as they were" {
  let made = Ref(0)
  let t = row_picked_reused_tester(40, made)
  let said = row_picked_two(t)
  assert_true(said.contains("第 0 段") && said.contains("第 1 段 hello"), msg="\{said}")
  let drawn = picked_drawn(t)
  assert_true(drawn.length() >= 2, msg="drawn picked: \{Repr(drawn)}")
  // (down so far that the blocks of 0 and 1 are put by and taken by rows come into sight)
  t.wheel(150.0, 100.0, 400.0)
  t.run_for(move_most_ms)
  // (as many blocks made as show at once, and a few: those of 0 and 1 taken by rows come into sight)
  assert_true(made.val < 18, msg="blocks made: \{made.val}")
  assert_eq(picked_drawn(t), [], msg="drawn picked on the rows that took their blocks: \{Repr(picked_drawn(t))}, made \{made.val}, \{Repr(t.drawn_words_found().map(fn(d) { (d.3, d.0.y) }))}")
  assert_eq(t.ctx().selected_text(), said)
  // (back: the first keys' rows show again, in whatever blocks, the same words drawn picked)
  t.wheel(150.0, 100.0, -400.0)
  t.run_for(move_most_ms)
  assert_eq(t.ctx().selected_text(), said)
  assert_eq(picked_drawn(t), drawn)
}
