// A height on its way inside a row of a page's list on a host's pixels (Style's come_grid, as the view sets it under a
// list on a grid: 2, 2.75, 3 and 3.5 a point) is laid on the grid where it is worked out, toward where it goes and never
// past its rest: so the row that holds it, put up on the grid as every row is, goes one way with it and is at its rest
// before the way ends, whatever lies beside it; and what lies under it in the row goes one way against the row's top,
// never back. A part closing (26 to 0, 26 to 18.3, 61.37 to 0) in a column beside a box along a row, the row an item
// of a rows_grid column; beside a taller box, nothing moves. Looked at every 10 ms.

///|
/// A row along a rows_grid column on grid `g`: a box `beside` tall, and a column of a part closing from `from` to `rest`
/// (laid on the grid as it goes, come_grid) over words 20 tall. The row, the part, the words, what is under the row.
fn rh_case(g : Double, from : Double, rest : Double, beside : Double) -> (@flex.Node, @flex.Node, @flex.Node, @flex.Node, @flex.Node) {
  let row = @flex.Node::new()
  row.style.direction = Row
  row.style.shrink = 0.0
  let side = @flex.Node::new()
  side.style.set_width(Pt(36.0))
  side.style.set_height(Pt(beside))
  side.style.shrink = 0.0
  let body = @flex.Node::new()
  body.style.grow = 1.0
  let part = rw_way(rest, from, if rest > 0.0 { 1.0 } else { 0.0 })
  part.style.come_grid = g
  let words = @flex.Node::new()
  words.style.set_height(Pt(20.0))
  words.style.shrink = 0.0
  body.add(part)
  body.add(words)
  row.add(side)
  row.add(body)
  let (col, under) = rw_column(g, [row])
  (col, row, part, words, under)
}

///|
test "a part closing in a column beside a shorter box along a row of a page's list on a host's grid: the row one way, at its rest before its way ends; what is under the part one way against the row's top; beside a taller box nothing moves" {
  for g in rw_grids {
    for way in [(26.0, 0.0), (26.0, 18.3), (61.37, 0.0)] {
      let (from, rest) = way
      let (col, row, part, words, _) = rh_case(g, from, rest, 10.0)
      let row_rest = rw_up(rest + 20.0, g)
      let mut was = 1.0e9
      let mut words_was = 1.0e9
      let mut t = 0.0
      while t <= 700.0 {
        rw_at(col, [part], t, g)
        let h = row.height
        let at = "grid \{g}, \{from} to \{rest}, at \{t} ms"
        let px = h * g
        assert_true((px - px.round()).abs() < 0.001, msg="\{at}: the row \{h}, not on the grid")
        assert_true(h <= was + 0.001, msg="\{at}: the row up from \{was} to \{h}")
        assert_true(h >= row_rest - 0.001, msg="\{at}: the row \{h} under its rest \{row_rest}")
        // (what is under the part, against the row's top: one way, never back)
        let words_at = words.top
        assert_true(words_at <= words_was + 0.001, msg="\{at}: the words under the part back down from \{words_was} to \{words_at}")
        // (at its rest once less than a pixel of the part's way is left, before the way ends)
        match @flex.come_state(part.style, t) {
          Some((tall, _)) if tall - rest < 1.0 / g - 0.001 && tall - rest > 0.0 =>
            assert_true((h - row_rest).abs() < 0.001, msg="\{at}: the row \{h} with \{tall - rest} of the part's way left, its rest \{row_rest}")
          _ => ()
        }
        was = h
        words_was = words_at
        t = t + 10.0
      }
      assert_true((was - row_rest).abs() < 0.001, msg="grid \{g}, \{from} to \{rest}: the row \{was} at its last look, its rest \{row_rest}")
      // (beside a box taller than all of it: the row as tall as that box all along, nothing under it moving)
      let (col, _, part, _, under) = rh_case(g, from, rest, 100.0)
      let mut first : Double? = None
      let mut t = 0.0
      while t <= 700.0 {
        rw_at(col, [part], t, g)
        match first {
          None => first = Some(under.top)
          Some(top) =>
            assert_true(
              (under.top - top).abs() < 0.001,
              msg="grid \{g}, \{from} to \{rest}: at \{t} ms the row under it at \{under.top}, \{top} at first",
            )
        }
        t = t + 10.0
      }
    }
  }
}

///|
test "a part closing with a gap before it in a column with a gap, beside a box along a row of a page's list on a host's grid, the row's other content on the grid: the row at its rest before its way ends" {
  for g in rw_grids {
    for from in [26.0, 61.37] {
      // (words 20 over a gap of 8 and the part: the gap the part's share of it, its way's, at rest gone with it)
      let row = @flex.Node::new()
      row.style.direction = Row
      row.style.shrink = 0.0
      let side = @flex.Node::new()
      side.style.set_width(Pt(36.0))
      side.style.set_height(Pt(10.0))
      side.style.shrink = 0.0
      let body = @flex.Node::new()
      body.style.grow = 1.0
      body.style.set_gap_row(Pt(8.0))
      let words = @flex.Node::new()
      words.style.set_height(Pt(20.0))
      words.style.shrink = 0.0
      let part = rw_way(0.0, from, 0.0)
      part.style.come_grid = g
      body.add(words)
      body.add(part)
      row.add(side)
      row.add(body)
      let (col, _) = rw_column(g, [row])
      let mut was = 1.0e9
      let mut t = 0.0
      while t <= 700.0 {
        rw_at(col, [part], t, g)
        let h = row.height
        let at = "grid \{g}, \{from}, at \{t} ms"
        assert_true(h <= was + 0.001, msg="\{at}: the row up from \{was} to \{h}")
        assert_true(h >= 20.0 - 0.001, msg="\{at}: the row \{h} under its rest 20")
        match @flex.come_state(part.style, t) {
          Some((tall, _)) if tall < 1.0 / g - 0.001 && tall > 0.0 =>
            assert_true((h - 20.0).abs() < 0.001, msg="\{at}: the row \{h} with \{tall} of the part's way left, its rest 20")
          _ => ()
        }
        was = h
        t = t + 10.0
      }
      assert_true((was - 20.0).abs() < 0.001, msg="grid \{g}, \{from}: the row \{was} at its last look")
    }
  }
}
