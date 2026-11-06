// The library's checkbox as a node: the same look and keyboard contract as @kit.checkbox.

///|
/// A checkbox at `checked()`, named `label()` for a screen reader. A click, a tap, Space or Activate calls `toggle`;
/// Enter does not. The caller owns the value and publishes its change through `checked`. Disabled boxes say so and
/// take neither a press nor focus. The tree gives the 18-point mark a full press's room around it.
pub fn checkbox_node(
  parent : @view.View,
  label : () -> String,
  checked : () -> @view.Check,
  toggle : () -> Unit,
  disabled? : () -> Bool = fn() { false },
) -> @view.View {
  parent.box(fn(box) {
    let live = fn() { !disabled() }
    box
    .row(Is(true))
    .width(Is(Some(18.0)))
    .height(Is(Some(18.0)))
    .shrink(Is(0.0))
    .lies_along(Is(Middle))
    .lines_up(Is(Some(Middle)))
    .radius(Is(6.0))
    .ground(By(fn() { let t = @ui.tree_theme(); if checked() is Off { t.bg } else { t.primary } }))
    .edge(By(fn() {
      let t = @ui.tree_theme()
      (1.0, if checked() is Off { if live() && box.pointed() { t.field_hover } else { t.border } } else { t.primary })
    }))
    .alpha(By(fn() { if disabled() { 0.45 } else { 1.0 } }))
    .presses(By(live))
    .focusable(By(live), keys=@view.focus_space)
    .says(By(fn() { Some(@view.said(Checkbox, label=label(), check=checked())) }))
    .on_press(fn() { if @signals.untracked(live) { toggle() } })
    |> ignore
    box.show(fn() { checked() is On }, fn(mark) {
      mark
      .words(Is("✓"))
      .words_look(Is({ size: 12.6, weight: 700, line: 18.0, wrap: false, tracking: @view.letters_own, balance: false }))
      .ink(By(fn() { @ui.tree_theme().on_primary }))
      |> ignore
    })
    box.show(fn() { checked() is Mixed }, fn(mark) {
      mark.width(Is(Some(9.0))).height(Is(Some(2.0))).radius(Is(1.0)).ground(By(fn() { @ui.tree_theme().on_primary })) |> ignore
    })
    box.show(fn() { box.focus_shown() }, fn(ring) {
      let out = fn() { let t = @ui.tree_theme(); t.focus_gap + t.focus_w }
      ring
      .over(Is(true))
      .margin(By(fn() { (-out(), -out(), -out(), -out()) }))
      .radius(By(fn() { 6.0 + out() }))
      .edge(By(fn() { let t = @ui.tree_theme(); (t.focus_w, t.focus) }))
      |> ignore
    })
  })
}
