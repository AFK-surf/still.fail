// A mark on the first line (first_line.mbt, Tester::first_line_faults): an icon centred on the two lines of words
// beside it found (a terminal's row, 2026-11-14), one on their first line not, nor one beside a single line, nor an
// avatar larger than a mark.

///|
/// The rule's faults on a row of a mark `size` big beside words in a column `wide` wide, the row lining what it holds
/// up by `along` (None: the mark at the row's top).
fn first_line_row(along : @view.Along?, wide : Double, size? : Double = 16.0) -> Array[String] {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0, platform=0, corners_held=false)
  set_view_app(fn(root) {
    root.box(fn(row) {
      row.row(Is(true)).gap(Is(8.0)).lines_up(Is(along)) |> ignore
      row.box(fn(m) {
        m.width(Is(Some(size))).height(Is(Some(size))).ground(Is(0x3366FFFFL)).radius(Is(4.0)) |> ignore
      })
      |> ignore
      row.box(fn(col) {
        col.width(Is(Some(wide))) |> ignore
        col.box(fn(w) { w.words(Is("ssh studio terminal session")) |> ignore }) |> ignore
        col.box(fn(w) { w.words(Is("12 min")) |> ignore }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.first_line_faults()
}

///|
test "first line: a mark centred on two lines beside it found; on the first line nothing" {
  let off = first_line_row(Some(Middle), 300.0)
  assert_eq(off.length(), 1, msg=off.join("\n"))
  assert_true(off[0].contains("16×16") && off[0].contains("of the 2 lines"), msg=off[0])
  assert_eq(first_line_row(Some(Start), 300.0), [])
}

///|
test "first line: an avatar larger than a mark is none of it; words wrapped on lines count as lines" {
  assert_eq(first_line_row(Some(Middle), 300.0, size=40.0), [])
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0, platform=0, corners_held=false)
  set_view_app(fn(root) {
    root.box(fn(row) {
      row.row(Is(true)).gap(Is(8.0)).lines_up(Is(Some(Middle))) |> ignore
      row.box(fn(m) { m.width(Is(Some(16.0))).height(Is(Some(16.0))).ground(Is(0x3366FFFFL)) |> ignore }) |> ignore
      row.box(fn(w) {
        w.width(Is(Some(80.0))).words(Is("a long line of words wrapped on several lines")) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let off = t.first_line_faults()
  assert_eq(off.length(), 1, msg=off.join("\n"))
}
