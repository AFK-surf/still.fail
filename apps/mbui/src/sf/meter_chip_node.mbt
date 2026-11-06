// A machine's meter (quota_chip.mbt's meter_chip) as a node: its mark, remaining amount, fill and tip follow its
// reading, in the same full or brief look as the old view.

///|
/// A station's CPU, memory or disk in `parent`. The fill is how much is used; `brief` shows the large figure with its
/// unit's first letter in a smaller chip. Its name, value and note are shown in `tips` when supplied. The returned node
/// can be told how it gives way or is dropped by its containing row.
pub fn meter_chip_node(
  parent : @view.View,
  m : () -> Json?,
  brief? : Bool = false,
  tips? : TipLayer,
) -> @view.View {
  let chip = fill_chip_node(
    parent,
    fn() { 100 - chip_left(m()) },
    fn() { chip_str(m(), "level") },
    fn() { chip_str(m(), "short") },
    fn() { meter_words(m(), brief) },
    small=brief,
    said=fn() { meter_said(m()) },
    tips?,
  )
  // A station's row can be a named button, whose ordinary child words are not read separately. Say the figure and
  // its detail explicitly, without making the chip another control in the row's keyboard order.
  chip.says(By(fn() {
    let mark = chip_str(m(), "short")
    let words = meter_words(m(), brief)
    let visible = if mark == "" { words } else if words == "" { mark } else { mark + " " + words }
    let detail = meter_said(m())
    let label = if detail == "" || detail == visible { visible } else if visible == "" { detail } else { visible + " · " + detail }
    Some(@view.said(Text, label~))
  })) |> ignore
  chip
}

///|
/// A station's meters in a single line, 4 apart. When there is not room, non-alert readings leave from the end first;
/// amber and red readings stay, and a figure is never squeezed. The meters and their details follow `meters`.
pub fn meter_chips_node(
  parent : @view.View,
  meters : () -> Array[Json],
  brief? : Bool = false,
  tips? : TipLayer,
) -> Unit {
  parent.box(fn(row) {
    row.row(Is(true)).grow(Is(1.0)).basis(Is(Some(0.0))).shrink(Is(1.0)).min_width(Is(Some(0.0)))
    .gap(Is(4.0)).lines_up(Is(Some(Middle))).fits(Is(true)) |> ignore
    row.each(
      fn() {
        let readings = meters()
        let plenty = readings.filter(fn(m) { !(chip_str(Some(m), "level") is ("amber" | "red")) }).length()
        let seen : Map[String, Int] = Map([])
        let mut k = 0
        readings.map(fn(m) {
          let short = chip_str(Some(m), "short")
          let nth = seen.get(short).unwrap_or(0)
          seen[short] = nth + 1
          let low = chip_str(Some(m), "level") is ("amber" | "red")
          if !low { k += 1 }
          (short, nth, m, if low { 0 } else { plenty - k + 1 })
        })
      },
      fn(item) { (item.0, item.1) },
      fn(slot, item) {
        slot.shrink(Is(0.0)).drops(By(fn() { item.get().3 })) |> ignore
        meter_chip_node(slot, fn() { Some(item.get().2) }, brief~, tips?) |> ignore
      },
    )
  }) |> ignore
}
