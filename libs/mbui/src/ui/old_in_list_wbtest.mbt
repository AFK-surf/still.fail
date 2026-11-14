// An old view hosted among the rows of a page's list (View::scrolls with Scroll::list) moves with them as the list
// scrolls, as far as they do: drawn in the list's instances, moved by the column's offset once (Ctx::island_in_list;
// before it, twice: its old frame built where the window has it, and moved again as the list ended).

///|
/// A list the window's whole: 20 high of nothing, an old view as tall as its words, then 30 rows 50 high with theirs.
fn old_in_list() -> (Tester, @view.Scroll) {
  let s = @view.Scroll::list()
  let t = Tester::new(fn(_c) {  }, platform=0)
  set_view_app(fn(root) {
    root.width(Is(Some(390.0))).height(Is(Some(844.0))).scrolls(s, fn(body) {
      body.box(fn(gap) { gap.height(Is(Some(20.0))) |> ignore }) |> ignore
      body.box(fn(o) {
        old(o, fn(c) { c.text("old words", size=13.0, line=18.0) |> ignore }, natural=true, unlaid=fn() { 844.0 }) |> ignore
      })
      |> ignore
      for i in 0..<30 {
        body.box(fn(row) {
          row.height(Is(Some(50.0))) |> ignore
          row.box(fn(w) {
            w
            .words(Is("row \{i}"), look={ size: 13.0, weight: 400, line: 18.0, wrap: true, tracking: @view.letters_own, balance: false, max_lines: 0 })
            .ink(By(fn() { tree_theme().color(Fg) }))
            |> ignore
          })
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
  t.draw()
  (t, s)
}

///|
/// The tops of the first glyph of each line as the window draws them, from the top: the old view's, then each row's.
fn line_tops(t : Tester) -> Array[Double] {
  let all = t.glyph_clips().map(fn(g) { (g.0.0, g.0.1) })
  let left = all.fold(init=1.0e9, fn(m, g) { if g.0 < m { g.0 } else { m } })
  let tops = all.filter(fn(g) { g.0 == left }).map(fn(g) { g.1 })
  tops.sort()
  tops
}

///|
test "an old view among a list's rows moves with them as the list scrolls, as far" {
  let (t, s) = old_in_list()
  let before = line_tops(t)
  s.put(15.0)
  t.draw()
  let after = line_tops(t)
  // (the list moved up; the old view by as much as its first row)
  let row = before[1] - after[1]
  assert_true(row > 10.0)
  assert_eq(before[0] - after[0], row)
}
