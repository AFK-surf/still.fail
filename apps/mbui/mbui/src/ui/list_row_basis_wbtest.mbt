// A page's list's block measured as its layout lays it out (flex's measured_height, list_window.mbt's fill): a lane (a
// row, 24 in from either side, what it holds in its middle) holding a column that grows and gives way to at most a
// width, holding a row with a gap of 12, a mark 16 wide and a column growing from nothing (flex: 1 0 0) holding words
// that wrap, the row not as wide as the mark, the gap and the words on one line (a wide page's card of rows, 设置 › 安全's
// pending changes with a finger's words). Measured, the capped column's width is not known: the row counts its column
// at its words, comes out as wide as the cap, and once that is known its column flexes from nothing to what the row
// leaves it, as the layout lays it out; the words on two lines there, the block counted as tall as they are.

///|
/// A page's list `w` wide of two blocks: the lane, its column at most `cap` (its row's column growing from nothing while
/// `from_none`, else as wide as its words), and one 30 tall under it. The Tester.
fn row_basis_case(w : Double, cap : Double, words : String, from_none~ : Bool) -> Tester {
  let t = Tester::new(fn(_c) {  }, w~, h=400.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(w))).height(Is(Some(300.0))) |> ignore
      col.scrolls_window(@view.Scroll::list(), fn() { [0, 1] }, est=40.0, fn(b, k) {
        if k == 0 {
          b.box(fn(lane) {
            lane.row(Is(true)).padding(Is((24.0, 0.0, 24.0, 0.0))).lies_along(Is(Middle)) |> ignore
            lane.box(fn(capped) {
              capped.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))).max_width(Is(Some(cap))) |> ignore
              capped.box(fn(r) {
                r.row(Is(true)).gap(Is(12.0)) |> ignore
                r.box(fn(m) { m.width(Is(Some(16.0))).height(Is(Some(18.0))).ground(Is(0x445566FFL)) |> ignore })
                |> ignore
                r.box(fn(c) {
                  if from_none {
                    c.grow(Is(1.0)).basis(Is(Some(0.0))) |> ignore
                  }
                  c.shrink(Is(0.0)).min_width(Is(Some(0.0))) |> ignore
                  c.box(fn(x) { x.words(Is(words)) |> ignore }) |> ignore
                })
                |> ignore
              })
              |> ignore
            })
            |> ignore
          })
          |> ignore
        } else {
          b.height(Is(Some(30.0))).ground(Is(0x112233FFL)) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "a page's list's block of a row whose column grows from nothing, its words on one line wider than the row leaves them: counted as tall as its layout lays it out, the next block under its words" {
  let words = "words long enough to come near the width of the list"
  // (as wide as its words: on one line)
  let alone = row_basis_case(2000.0, 2000.0, words, from_none=false)
  let (_, _, one_w, one_h) = alone.rect_of(words).unwrap()
  let said = []
  // (the capped column as wide as the mark, the gap and the words less 2 and less 18: the words wrap in what the row
  // leaves them)
  for less in [2.0, 18.0] {
    let cap = 16.0 + 12.0 + one_w - less
    let w = cap + 300.0
    let t = row_basis_case(w, cap, words, from_none=true)
    let (_, wy, ww, wh) = t.rect_of(words).unwrap()
    let next = t.drawn_rects().filter(fn(r) { r.4 == 0x112233FFL }).map(fn(r) { r.1 })
    if !(wh > one_h + 0.5 && next.length() == 1 && next[0] >= wy + wh - 0.5) {
      said.push(
        "list \{w}, its column at most \{cap}: words at \{wy} \{ww} x \{wh} (on one line \{one_w} x \{one_h}), the next block at \{Repr(next)}",
      )
    }
  }
  assert_true(said.is_empty(), msg=said.join("; "))
}
