// One allowance window as a node of the window's tree (quota_chip's), following the window as it changes.

///|
/// One allowance window in `parent`, as quota_chip draws it: its mark where `marked`, its remaining percentage and
/// its level's fill. `small` and `compact` have the same sizes as quota_chip. The window and its words are followed as
/// they change; `said` overrides the default quota_said, and `tips` holds its tip when supplied. The node.
pub fn quota_chip_node(
  parent : @view.View,
  w : () -> Json?,
  small? : Bool = false,
  compact? : Bool = false,
  marked? : Bool = true,
  said? : () -> String,
  tips? : TipLayer,
) -> @view.View {
  let said = match said {
    Some(f) => f
    None => fn() { quota_said(w()) }
  }
  fill_chip_node(
    parent,
    fn() { chip_left(w()) },
    fn() { chip_str(w(), "level") },
    fn() { if marked { chip_str(w(), "mark") } else { "" } },
    fn() { chip_left(w()).to_string() + "%" },
    small~,
    compact~,
    said~,
    tips?,
  )
}
