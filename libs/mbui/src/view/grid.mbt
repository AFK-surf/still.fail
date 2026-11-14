// A multi-column grid laid out by the room it is given (View::by_room): how many columns of `min_col_w` at least,
// `gap` apart, fit across its width (grid_columns), and a box whose items (`count`) are laid out in rows of that many
// columns in the same layout pass (View::grid). While its width stays within the same column count, flex shares the
// row's width across the columns with nothing made again; when the width crosses a column boundary or `count` changes,
// the rows are remade in that layout pass.

///|
/// How many columns of at least `min_col_w`, `gap` apart (`max_cols` at most where > 0; at least 1), fit in `room_w`,
/// and how wide each column is at `room_w`.
pub fn grid_columns(
  room_w : Double,
  min_col_w : Double,
  gap : Double,
  max_cols? : Int = 0,
) -> (Int, Double) {
  let step = min_col_w + gap
  let raw = if step > 0.0 && room_w > min_col_w {
    ((room_w + gap) / step).floor().to_int()
  } else {
    1
  }
  let cols = if raw < 1 {
    1
  } else if max_cols > 0 && raw > max_cols {
    max_cols
  } else {
    raw
  }
  let col_w = dmax(0.0, (room_w - (cols - 1).to_double() * gap) / cols.to_double())
  (cols, col_w)
}

///|
/// A grid in `self` of `count()` cells (0 ..< count()), laid out in as many columns of at least `min_col_w` (`gap`
/// apart across, `row_gap` apart down, or `gap` where `row_gap` is omitted; at most `max_cols` columns where > 0) as
/// fit the room `self` is given. Each cell's box is handed to `cell(box, index)` with equal column width across its
/// row, trailing empty column slots in the last row keeping partial rows aligned with the columns above.
#callsite(autofill(loc))
pub fn View::grid(
  self : View,
  count : () -> Int,
  min_col_w~ : Double,
  gap? : Double = 0.0,
  row_gap? : Double,
  max_cols? : Int = 0,
  cell : (View, Int) -> Unit,
  loc~ : SourceLoc,
) -> View {
  let vgap = row_gap.unwrap_or(gap)
  self.by_room(loc~, fn(held, room) {
    held.gap(Is(vgap)) |> ignore
    held.pick(
      at_once=true,
      fn() {
        let (cols, _) = grid_columns(room.width(), min_col_w, gap, max_cols~)
        (cols, count())
      },
      fn(v, spec) {
        let (cols, total) = spec
        v.gap(Is(vgap)) |> ignore
        let mut i = 0
        while i < total {
          let row_start = i
          v.box(loc~, fn(r) {
            r.row(Is(true)).gap(Is(gap)) |> ignore
            for c in 0..<cols {
              let idx = row_start + c
              r.box(loc~, fn(slot) {
                slot.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
                if idx < total {
                  cell(slot, idx)
                }
              })
              |> ignore
            }
          })
          |> ignore
          i = i + cols
        }
      },
    )
  })
}
