// A page's list's rows down a column on a host's device pixels (Style's rows_grid): each row as tall as whole pixels
// before what is left of the column is worked out, so a row that grows (a short list's spacer over its rows, pinned to
// its foot) is given what is left of whole-pixel rows: the rows' sum is the column's height, never a pixel past it; and
// a row whose height goes on by a fraction (a key on its way), the room under it giving back what it takes on the grid,
// moves nothing over it. On grids of 2, 2.75, 3 and 3.5 pixels a point.

///|
/// The grids looked on.
let rg_grids : Array[Double] = [2.0, 2.75, 3.0, 3.5]

///|
/// `v` on grid `g`, up (as a row's height is put on it).
fn rg_up(v : Double, g : Double) -> Double {
  (v * g - 0.000001).ceil() / g
}

///|
/// A column `h` tall on grid `g`: a spacer that grows, then rows of `rows` heights (off the grid), the room under them
/// `pad`. Laid out; the column and its rows.
fn rg_column(g : Double, h : Double, rows : Array[Double], pad : Double) -> (@flex.Node, Array[@flex.Node]) {
  let col = @flex.Node::new()
  col.style.position = Absolute
  col.style.set_width(Pt(300.0))
  col.style.set_height(Pt(h))
  col.style.rows_grid = g
  col.style.set_padding_bottom(Pt(pad))
  let spacer = @flex.Node::new()
  spacer.style.grow = 1.0
  spacer.style.shrink = 0.0
  col.add(spacer)
  let made = [spacer]
  for r in rows {
    let n = @flex.Node::new()
    n.style.set_height(Pt(r))
    n.style.shrink = 0.0
    col.add(n)
    made.push(n)
  }
  @flex.compute(col, round=false, reuse=true, grid=g)
  (col, made)
}

///|
test "a short list's rows off the grid under a spacer that grows, on a host's pixels: the rows' sum the column's height, the spacer what is left of whole-pixel rows" {
  for g in rg_grids {
    let rows = [40.3, 61.7, 22.1]
    let h = rg_up(300.0, g)
    let (col, made) = rg_column(g, h, rows, 0.0)
    let mut sum = 0.0
    for n in made {
      sum = sum + n.height
    }
    let last = made[made.length() - 1]
    assert_true(
      (sum - col.height).abs() < 0.001,
      msg="grid \{g}: the rows come to \{sum} in a column \{col.height} tall",
    )
    assert_true(
      (last.top + last.height - col.height).abs() < 0.001,
      msg="grid \{g}: the last row's foot at \{last.top + last.height}, the column \{col.height}",
    )
    let mut laid = 0.0
    for r in rows {
      laid = laid + rg_up(r, g)
    }
    assert_true(
      (made[0].height - (h - laid)).abs() < 0.001,
      msg="grid \{g}: the spacer \{made[0].height}, the column less the rows as laid \{h - laid}",
    )
  }
}

///|
test "a row going on by a fraction each look on a host's pixels, the room under it giving back what it takes on the grid: nothing over it moves" {
  for g in rg_grids {
    let h = rg_up(600.0, g)
    let stretch = rg_up(174.5, g)
    let mut first : Double? = None
    for k in [0.0, 1.32, 4.79, 9.8, 15.86, 22.57, 29.66, 36.89, 44.08, 51.11] {
      let laid_k = rg_up(k, g)
      let (_, made) = rg_column(g, h, [90.3, 113.7, k], stretch - laid_k)
      let top = made[1].top
      match first {
        None => first = Some(top)
        Some(t) =>
          assert_true(
            (top - t).abs() < 0.001,
            msg="grid \{g}: the row over it at \{top} with it \{k} (\{laid_k} laid), \{t} before",
          )
      }
    }
  }
}
