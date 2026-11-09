// The size words of a node of the window's tree are drawn at, said by the node itself (View::words_scale: the system's
// size of words where its tree is drawn), for what a node lays out round words it measures by hand, as an old view's
// Ctx::sp and Ctx::sp_of are.

///|
/// What words (or a line, a letter spacing said with them) of size `size` are drawn at in node `v`'s tree, at the
/// system's size of words there, followed as it changes (View::words_scale): an old view's Ctx::sp.
pub fn node_sp(v : @view.View, size : Double) -> Double {
  @ui.sp_at(v.words_scale(), size)
}

///|
/// The size words are said at to be drawn `px` in node `v`'s tree (node_sp's way back): an old view's Ctx::sp_of.
pub fn node_sp_of(v : @view.View, px : Double) -> Double {
  @ui.sp_from(v.words_scale(), px)
}
