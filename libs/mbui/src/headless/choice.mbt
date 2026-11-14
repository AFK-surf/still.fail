// The choice: an option among choices (a choice row, a radio dot, an offer row), read out its kind (Button or Radio)
// called by its label and selected while `chosen` says so. Pressed as the button is (a tap or a click on it, Enter or
// Space while it has the keyboard's focus, a screen reader's Activate: all of them its on_press), taking a press (and
// the focus unless `focusable` is false, as for an offer list whose input field keeps the keyboard) only while it is
// not disabled. Controlled (headless.mbt, State): `chosen` is its caller's; `choose` is given the node once a press,
// never while disabled.

///|
/// What a choice is to a screen reader: a choice button (selected or not) or a radio option (selected or not).
#derive(Eq, Debug)
pub(all) enum ChoiceKind {
  Button
  Radio
}

///|
/// A choice as its look reads it: each a reading, followed where a binding reads it.
pub struct Choice {
  priv node : @view.View
  priv now : () -> Bool
  priv off : () -> Bool
}

///|
/// Whether it is the one chosen now (as its caller says).
pub fn Choice::chosen(self : Choice) -> Bool {
  (self.now)()
}

///|
/// Whether it is disabled: it takes no press and no focus (as its caller says).
pub fn Choice::disabled(self : Choice) -> Bool {
  (self.off)()
}

///|
/// Whether a finger or the pointer is held on it now (View::pressed).
pub fn Choice::pressed(self : Choice) -> Bool {
  self.node.pressed()
}

///|
/// Whether a pointer rests over it now (View::pointed): a mouse's, never a finger's (Button::hovered says the rest).
pub fn Choice::hovered(self : Choice) -> Bool {
  self.node.pointed()
}

///|
/// Whether it has the keyboard's focus and that shows (it came by the keyboard: View::focus_shown).
pub fn Choice::focus_shown(self : Choice) -> Bool {
  self.node.focus_shown()
}

///|
/// Pressed now, for what a look adds that ends in a press (a gesture of its own): asked of the tree as a press
/// delivered to the node (View::press), so none where the hand's would be none, and outside any tracking, as one
/// change. Called from a handler, never as something is drawn.
pub fn Choice::press(self : Choice) -> Unit {
  self.node.press() |> ignore
}

///|
/// A choice of `kind` in `parent`, called `label` (what a screen reader says, as it changes), selected while `chosen`
/// says so; `choose` done as it is pressed, given the choice's node; `disabled` while it cannot be pressed; `focusable`
/// false where another control keeps the keyboard while the choices are up (an input field's offers). `look` is run
/// once as it is made, given its node and what it reads of it: all that is drawn of it, and how it is laid out. Its
/// node is made at `loc` (`made_for` where a library's part over it was asked for), as the button's is. The node.
#callsite(autofill(loc))
pub fn choice(
  parent : @view.View,
  kind : ChoiceKind,
  label : () -> String,
  chosen : () -> Bool,
  choose : (@view.View) -> Unit,
  look : (@view.View, Choice) -> Unit,
  disabled? : () -> Bool = fn() { false },
  focusable? : Bool = true,
  made_for? : SourceLoc,
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(loc~, made_for=made_for.unwrap_or(loc), fn(v) {
    let able = fn() { !disabled() }
    look(v, { node: v, now: chosen, off: disabled })
    let role : @view.Role = match kind {
      Button => Button
      Radio => Radio
    }
    v
    .presses(By(able))
    .says(By(fn() { Some(@view.said(role, label=label(), selected=chosen())) }))
    .on_press(fn() {
      if !disabled() {
        choose(v)
      }
    })
    |> ignore
    if focusable {
      v.focusable(By(able)) |> ignore
    }
  })
}
