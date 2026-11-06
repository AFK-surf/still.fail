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
  fill_chip_node(
    parent,
    fn() { 100 - chip_left(m()) },
    fn() { chip_str(m(), "level") },
    fn() { chip_str(m(), "short") },
    fn() { meter_words(m(), brief) },
    small=brief,
    said=fn() { meter_said(m()) },
    tips?,
  )
}
