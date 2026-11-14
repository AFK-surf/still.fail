// A checkbox (mbui kit's checkbox, in still.fail's look: checkbox_look) as a node of the window's tree, made once: its
// look over mbui's headless toggle (@headless.toggle), whose it is that it is read out a checkbox, on or off, pressed
// and focused only while not disabled.

///|
/// A checkbox in `parent`, on or off as `on` says: 18 square, its corner 6, on the page's ground edged in the theme's
/// control edge (darker under the pointer), filled with the primary ink while on, its tick in the ink on that; faded
/// while `disabled`. Pressed (a tap, a click, Space or Enter with the keyboard's focus, a screen reader's Activate),
/// `turn` told what it becomes; a ring round it while the keyboard's focus is on it. Read out a checkbox named `label`,
/// on or off.
#callsite(autofill(loc))
pub fn check_node(
  parent : @view.View,
  on : () -> Bool,
  turn : (Bool) -> Unit,
  label : () -> String,
  disabled? : () -> Bool = fn() { false },
  loc~ : SourceLoc,
) -> Unit {
  @headless.toggle(made_for=loc, parent, Checkbox, label, on, turn, disabled~, fn(b, _) {
    b
    .width(Is(Some(check_side)))
    .height(Is(Some(check_side)))
    .radius(Is(check_corner))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    .ground(By(fn() {
      let t = @ui.tree_theme()
      if on() { t.primary } else { t.bg }
    }))
    .edge(By(fn() {
      let t = @ui.tree_theme()
      let line = if on() {
        t.primary
      } else if b.pointed() && !disabled() {
        t.field_hover
      } else {
        t.border
      }
      (1.0, line)
    }))
    .alpha(By(fn() { if disabled() { check_disabled_alpha } else { 1.0 } }))
    |> ignore
    b.show(on, fn(m) {
      m
      .words(Is("✓"))
      .words_look(Is({ size: check_side * 0.7, weight: 700, line: check_side, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }))
      .ink(By(fn() { @ui.tree_theme().on_primary }))
      |> ignore
    })
    // (the keyboard's focus on it: a ring round it, its gap and width the theme's: focus_ring's)
    b.show(fn() { b.focus_shown() }, fn(ring) {
      let out = fn() {
        let t = @ui.tree_theme()
        t.focus_gap + t.focus_w
      }
      ring
      .over(Is(true))
      .margin(By(fn() { (-out(), -out(), -out(), -out()) }))
      .radius(By(fn() { check_corner + out() }))
      .edge(By(fn() { (@ui.tree_theme().focus_w, @ui.tree_theme().focus) }))
      |> ignore
    })
  })
  |> ignore
}

///|
/// A checkbox's side and corner (checkbox_look's 18 and 6), how faded it is while it may not be turned (0.45).
let check_side : Double = 18.0

///|
let check_corner : Double = 6.0

///|
let check_disabled_alpha : Double = 0.45
