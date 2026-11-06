// What a page made once can say of the frame's bar over it, while the page is alive.

///|
/// The frame's way to let a page override the back of its outside bar. The frame lends it to the page it makes; a
/// page outside such a frame is given none. The frame owns the visibility of back, separately from this override.
// kept across runs: the key for what a frame lends, let go with the frame's node
pub let page_bar_back_lent : @view.Lent[(@view.View, () -> String?, () -> Unit) -> Unit] = @view.Lent::new()

///|
/// Override the words and action of the frame's outside-bar back while `v` is alive. `label` is read as its signals
/// change; `None` restores the frame's own words and action. The frame decides whether there is a visible back at all.
/// The page handles system back separately. Where there is no outside bar, this does nothing.
pub fn page_bar_back(v : @view.View, label : () -> String?, go_back : () -> Unit) -> Unit {
  match v.lent(page_bar_back_lent) {
    Some(register) => register(v, label, go_back)
    None => ()
  }
}
