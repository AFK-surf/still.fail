// A choice among a few (parts.mbt select's) as a node of the window's tree, made once: bound to what it says now,
// its options through the presenters (@sf.pick) beside it.

///|
/// A choice among a few in `parent` (select's, as a node): closed, a capsule as a one-line field is (the theme's
/// control height, body words), what is chosen in it (`value` among `options`: each value and its words) cut short,
/// a chevron at its end; its line the field's hover grey while the hand is on it or it has the focus. Pressed (Enter,
/// Space, a screen reader's press), its options through the presenters (@sf.pick) beside it, the chosen checked;
/// `choose` given the one chosen. `whole`: never narrower than what is chosen in it says (what is beside it gives way);
/// else `select_w` at most. While `disabled()`, at 55% and taking no press. Read out a button, `label` and its choice.
#callsite(autofill(loc))
pub fn select_node(
  parent : @view.View,
  value : () -> String,
  options : () -> Array[(String, String)],
  choose : (String) -> Unit,
  label? : () -> String = fn() { "" },
  disabled? : () -> Bool = fn() { false },
  whole? : Bool = false,
  loc~ : SourceLoc,
) -> Unit {
  let words = fn() {
    match options().iter().find_first(fn(o) { o.0 == value() }) {
      Some(o) => o.1
      None => ""
    }
  }
  let live = fn() { !disabled() }
  let opener = Opener::new()
  parent.box(made_for=loc, fn(b) {
    let press = fn() {
      let (x, y, w, h) = b.placed_window_now()
      let now = @signals.untracked(value)
      pick(
        @signals.untracked(label),
        @signals.untracked(options).map(fn(o) { choice(o.0, o.1) }),
        now,
        choose,
        from=At(x, y, w, h),
      )
      opener.mark()
    }
    presses_node(b, press, on=live)
    b
    .row(Is(true))
    .gap(Is(select_gap))
    .padding(Is((select_x, select_y, select_x, select_y)))
    .min_height(By(fn() { Some(theme().control_h) }))
    .radius(Is(1.0e6))
    .lines_up(Is(Some(Middle)))
    .ground(By(fn() { @ui.tree_theme().color(Surface) }))
    .edge(By(fn() { (1.0, @ui.tree_theme().color(if live() && lit_node(b) { FieldHover } else { Border })) }))
    .alpha(By(fn() { if disabled() { select_disabled_alpha } else { 1.0 } }))
    .says(By(fn() {
      let l = label()
      Some(@view.said(Button, label=if l == "" { words() } else { l + ": " + words() }, expanded=opener.open()))
    }))
    |> ignore
    if !whole {
      b.max_width(Is(Some(select_w))) |> ignore
    }
    // (its words taking what the chevron leaves, the chevron at its end: select_box's JBetween)
    b.box(fn(w) {
      w.grow(Is(1.0)) |> ignore
      if !whole {
        w.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
      }
      words_node(w, words, fn() { select_words }) |> ignore
    })
    |> ignore
    icon_node(b, "chevron-down", select_chevron, By(fn() { theme().p.muted })) |> ignore
  })
  |> ignore
}

///|
/// select_box's room (px=S4, py=S1_5, gap=S2) and its look while it cannot be pressed (disabled{opacity=O55}).
let select_x : Double = 16.0

///|
let select_y : Double = 6.0

///|
let select_gap : Double = 8.0

///|
let select_disabled_alpha : Double = 0.55
