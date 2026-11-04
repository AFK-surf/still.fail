// The title keeps its place while a request is pending and moves only when that request answers.

///|
test "title generation paints a moving light and its answer slides into the same line" {
  title_motions.clear()
  title_motions["test"] = { old: "Old title", next: "", at: 0.0, waiting: true }
  let t = @ui.Tester::new(fn(c) {
    row_title(c, "test", "Old title", @ui.text_style(size=Ui, leading=L6, wrap=false))
  })
  t.draw()
  let first = t.drawn_glyphs()
  t.run_for(title_shine_ms / 4.0)
  let later = t.drawn_glyphs()
  assert_true(first != later)
  let at = t.time()
  title_motions["test"] = { old: "Old title", next: "New title", at, waiting: false }
  t.frame()
  let start = t.drawn_glyphs()
  t.run_for(title_swap_ms / 2.0)
  let middle = t.drawn_glyphs()
  assert_true(start != middle)
  t.run_for(title_swap_ms)
  assert_true(t.find("New title") is Some(_))
  title_motions.clear()
}

///|
test "title request waits, ignores a duplicate, and clears on failure or an unchanged answer" {
  title_motions.clear()
  let base = @sffixture.fixture("home")
  let calls : Ref[Int] = Ref(0)
  let answer : Ref[((Result[Json, Json]) -> Unit)?] = Ref(None)
  let src : Source = {
    ..base,
    call: fn(_, _, done) { calls.val += 1; answer.val = Some(done) },
  }
  let t = @ui.Tester::new(fn(c) { row_title(c, "test", "Old", @ui.text_style(size=Ui)) })
  t.draw()
  regenerate_row_title(src, "test", "station", 8.0, "Old")
  assert_true(title_motions.get("test") is Some({ waiting: true, .. }))
  regenerate_row_title(src, "test", "station", 8.0, "Old")
  assert_eq(calls.val, 1)
  (answer.val.unwrap())(Err({ "message": "failed" }))
  assert_true(title_motions.get("test") is None)
  regenerate_row_title(src, "test", "station", 8.0, "Old")
  (answer.val.unwrap())(Ok({ "autoTitle": "Old" }))
  assert_true(title_motions.get("test") is None)
  regenerate_row_title(src, "test", "station", 8.0, "Old")
  (answer.val.unwrap())(Ok({ "autoTitle": "New" }))
  assert_true(title_motions.get("test") is Some({ old: "Old", next: "New", waiting: false, .. }))
  title_motions.clear()
}

///|
test "reduced motion keeps waiting words still and shows the new title at once" {
  title_motions.clear()
  title_motions["test"] = { old: "Old", next: "", at: 0.0, waiting: true }
  let t = @ui.Tester::new(fn(c) { row_title(c, "test", "Old", @ui.text_style(size=Ui, leading=L6)) })
  t.set_reduce_motion(true)
  t.draw()
  let first = t.drawn_glyphs()
  t.run_for(title_shine_ms / 4.0)
  assert_eq(t.drawn_glyphs(), first)
  title_motions["test"] = { old: "Old", next: "New", at: t.time(), waiting: false }
  t.frame()
  assert_true(t.find("New") is Some(_))
  t.set_reduce_motion(false)
  title_motions.clear()
}
