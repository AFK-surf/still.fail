///|
test "grid_columns: column count and width from room, min_col_w, gap, and max_cols" {
  assert_eq(@view.grid_columns(100.0, 120.0, 10.0), (1, 100.0))
  assert_eq(@view.grid_columns(250.0, 120.0, 10.0), (2, 120.0))
  assert_eq(@view.grid_columns(379.0, 120.0, 10.0), (2, 184.5))
  assert_eq(@view.grid_columns(380.0, 120.0, 10.0), (3, 120.0))
  assert_eq(@view.grid_columns(600.0, 120.0, 10.0, max_cols=3), (3, 193.33333333333334))
}

///|
test "View::grid: lays out cells in responsive columns in one pass and aligns partial last row" {
  let count = @signals.signal(5)
  let cells : Array[@view.NodeId] = []
  let t = @view.Tree::new(
    fn(root) {
      root.grid(
        fn() { count.get() },
        min_col_w=100.0,
        gap=10.0,
        row_gap=12.0,
        fn(slot, _i) {
          cells.push(slot.id())
          slot.height(Is(Some(20.0))).ground(Is(0xFF0000FFL)) |> ignore
        },
      )
      |> ignore
    },
    time=fn() { 0.0 },
  )
  let computes = t.work().computes
  // 320 wide: 3 columns of 100 with 10 gap -> 5 items in 2 rows (3 + 2, with 1 spacer in row 2)
  t.frame(320.0, 200.0) |> ignore
  assert_eq(t.work().computes - computes, 1)
  assert_eq(cells.length(), 5)
  assert_eq(t.drawn_of(cells[0]).map(fn(d) { (d.x, d.y, d.w) }), Some((0.0, 0.0, 100.0)))
  assert_eq(t.drawn_of(cells[2]).map(fn(d) { (d.x, d.y, d.w) }), Some((220.0, 0.0, 100.0)))
  // Row 2 has 2 items aligned with columns 0 and 1 (width 100 each, not stretched to 155)
  assert_eq(t.drawn_of(cells[3]).map(fn(d) { (d.x, d.y, d.w) }), Some((0.0, 32.0, 100.0)))
  assert_eq(t.drawn_of(cells[4]).map(fn(d) { (d.x, d.y, d.w) }), Some((110.0, 32.0, 100.0)))
  // Narrow to 210 wide -> 2 columns of 100 in 3 rows (2 + 2 + 1)
  cells.clear()
  let computes2 = t.work().computes
  t.frame(210.0, 200.0) |> ignore
  assert_eq(t.work().computes - computes2, 1)
  assert_eq(cells.length(), 5)
  assert_eq(t.drawn_of(cells[2]).map(fn(d) { (d.x, d.y, d.w) }), Some((0.0, 32.0, 100.0)))
  assert_eq(t.drawn_of(cells[4]).map(fn(d) { (d.x, d.y, d.w) }), Some((0.0, 64.0, 100.0)))
}
