// A toast's look as nodes of the window's tree (toast_look's, made once, for @kit.toaster_node: how each comes, goes,
// keeps its time and is swiped is the toaster's): the primary ink's capsule, its words 13 in its ink, its action a
// capsule in its end, concentric with it; coming in from 8 below, its ground whole by half its way in, its words from
// there; moved across as the toaster says (swiped, put away), pressed and read out where it is drawn.

///|
/// Toast `s` drawn in `b` (@kit.toaster_node's `look`) as toast_look draws it, saying what it says now: its action (its
/// toast's, "" none) a capsule in its end, pressed as the toaster's (ToastNode::action).
pub fn toast_look_node(b : @view.View, s : @kit.ToastNode) -> Unit {
  let theme = fn() { @ui.tree_theme() }
  let action = fn() { s.toast().action }
  // (its action while it is there: going out, none, as toast_look's for one no longer the one said)
  let acting = fn() { action() != "" && s.live() }
  // (its ground whole by half its way in, its words from there: toast_look's)
  let ground = fn() { dmin(1.0, 2.0 * s.t()) }
  let words = fn() {
    let g = ground()
    if g > 0.0 && 2.0 * s.t() > 1.0 {
      (2.0 * s.t() - 1.0) / g
    } else {
      0.0
    }
  }
  b.box(fn(tb) {
    tb
    .row(Is(true))
    .lines_up(Is(Some(Middle)))
    .gap(Is(@ui.Space::px(S3)))
    .padding(By(fn() { (toast_px, toast_action_in, if acting() { toast_action_in } else { toast_px }, toast_action_in) }))
    .max_width(Is(Some(toast_max)))
    .radius(Is(toast_r))
    .ground(By(fn() { theme().color(Primary) }))
    .shadow(By(fn() { (toast_shadow, toast_shadow_y, library_theme().p.shadow) }))
    .alpha(By(ground))
    // (in from below as it comes, moved across as the toaster says: where it is, pressed and read out there too, as
    // toast_look's tx and ty move its box)
    .offset(By(fn() { (s.dx(), (1.0 - s.t()) * toast_rise) }))
    |> ignore
    tb.box(fn(w) {
      w.padding(Is((0.0, toast_py - toast_action_in, 0.0, toast_py - toast_action_in))).shrink(Is(1.0)) |> ignore
      w.box(fn(x) {
        x
        .words(By(fn() { s.toast().title }), look=toast_words_look(Ui, L6, 400, true))
        .ink(By(fn() { theme().color(OnPrimary) }))
        .alpha(By(words))
        |> ignore
      })
      |> ignore
    })
    |> ignore
    // its action: a capsule in its end, concentric with it (toast_button's), while it has one
    tb.show(acting, fn(a) {
      let lit = fn() { a.pointed() || a.pressed() }
      a
      .row(Is(true))
      .height(Is(Some(toast_action_h)))
      .padding(Is((toast_px - toast_action_in, 0.0, toast_px - toast_action_in, 0.0)))
      .radius(Is(toast_action_h / 2.0))
      .lines_up(Is(Some(Middle)))
      .ground(By(fn() { theme().color(A(OnPrimary, if lit() { O5 } else { O15 })) }))
      |> ignore
      s.action(a, action) |> ignore
      a.box(fn(w) {
        // (its words faded in after the ground, as the toast's are; its own ground with the toast's: toast_look's words)
        w
        .words(By(action), look=toast_words_look(Ui, L5, 600, false))
        .ink(By(fn() { theme().color(OnPrimary) }))
        .alpha(By(words))
        |> ignore
      })
      |> ignore
    })
  })
  |> ignore
}

///|
/// A toast's words' look: `size` and `line` as the window's theme has them, `weight`, wrapping or not.
fn toast_words_look(size : @ui.TextSize, line : @ui.Leading, weight : Int, wrap : Bool) -> @view.WordsLook {
  let th = @ui.tree_theme()
  let (px, own) = th.text_size(size)
  { size: px, weight, line: th.leading(line).unwrap_or(own), wrap }
}
