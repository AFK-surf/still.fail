// An old view's popover (kit's) beside what opened it as the presenters have it (Beside): an old box by its id, a node
// of the window's tree, a rectangle of the window. Beside a node it stands where that node is placed as each frame
// draws it (the presenters' anchor_of), following it as it moves (the window, the bar it is in), a press on it none
// outside, the focus going back as it closes as kit's does; the node gone, drawn beside nothing (none of it drawn).

///|
/// Popover `key` of an old view, `open`, beside `from` on `side`, lined up `along` it (kit's popover, its `look` and
/// `body`). Whether it is open as the hand left it.
pub fn popover_from(
  c : @ui.Ctx,
  key : String,
  open : Bool,
  from : Beside,
  side? : @ui.Side = Bottom,
  along? : @ui.Along = Middle,
  look? : (@ui.Ctx, @kit.PopState, () -> Unit) -> Unit = @kit.popover_look,
  body : () -> Unit,
) -> @ui.Changed[Bool] {
  match from {
    Of(id) => @kit.popover(c, key, open, id, side~, along~, look~, body)
    // (where the node is placed now, as the presenters' anchor_of reads it)
    Node(v) => {
      let at = if v.alive() { Some(v.placed_window_now()) } else { None }
      @kit.popover(c, key, open, 0, side~, along~, at?, anchor_node=v, look~, body)
    }
    At(x, y, w, h) => @kit.popover(c, key, open, 0, side~, along~, at=(x, y, w, h), look~, body)
  }
}
