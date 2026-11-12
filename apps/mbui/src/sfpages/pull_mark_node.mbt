// A pull request's mark and its menu where a part of nodes names one (a chat's info on 中屏 and 大屏: chat_info_node).

///|
/// A pull request's mark (pull_mark's, as a node) in `parent`, `side` square, as `pull` says it now: GitHub's octicon for
/// how it stands, in its state's colour, grey until its card is read.
#callsite(autofill(loc))
pub fn pull_mark_node(parent : @view.View, pull : () -> Json?, side : Double, loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(g) {
    g
    .width(Is(Some(side)))
    .height(Is(Some(side)))
    .shapes(By(fn() {
      let state = text(pull(), "state")
      let (ink, _) = state_colours(state)
      match pr_glyph(state) {
        Some(d) => @ui.vector_shapes(glyph_of(d, ink), side, g.pixel_scale())
        None => []
      }
    }))
    |> ignore
  })
  |> ignore
}

///|
/// A thing's menu (thing_menu's) at `x`, `y` in the window, for one a node holds (menu_presses_node's): 在对话中查看
/// (`away` to message `seq`), then a link's copy (`url`).
pub fn thing_menu_node_at(x : Double, y : Double, seq : Double, url : String, away : (Double) -> Unit) -> Unit {
  thing_menu_at(x, y, seq, url, away)
}
