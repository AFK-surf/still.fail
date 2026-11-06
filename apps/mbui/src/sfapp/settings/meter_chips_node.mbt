// The station's meter chips (stations.mbt's meter_chips) as nodes: the readings, and which are alerts, followed as the
// host changes. Each chip and its tip belong to the row for as long as its reading is shown.

///|
/// A station's CPU, memory and disk, in a 20-high row, 8 apart. With `alerts`, only readings whose level is not `ok`;
/// otherwise all readings, in their original order. Their details are shown in the window's `tips` layer.
pub fn meter_chips_node(
  parent : @view.View,
  meters : () -> Array[Json],
  tips~ : @sf.TipLayer,
  alerts? : Bool = false,
) -> Unit {
  parent.box(fn(row) {
    row.row(Is(true)).height(Is(Some(20.0))).gap(Is(8.0)).lines_up(Is(Some(Middle))) |> ignore
    // Key by the mark, as meter_chip does, so inserting or reordering readings cannot give an open tip to another one.
    // Count equal marks before filtering, so a repeated mark still has its own node as other levels change.
    row.each(
      fn() {
        let seen : Map[String, Int] = Map([])
        let visible : Array[(String, Int, Json)] = []
        for m in meters() {
          let short = text(Some(m), "short")
          let nth = seen.get(short).unwrap_or(0)
          seen[short] = nth + 1
          if !alerts || text(Some(m), "level") != "ok" {
            visible.push((short, nth, m))
          }
        }
        visible
      },
      fn(item) { (item.0, item.1) },
      fn(chip, item) { @sf.meter_chip_node(chip, fn() { Some(item.get().2) }, tips~) |> ignore },
    )
  }) |> ignore
}
