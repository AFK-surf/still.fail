// The toggle: what is on or off, turned by a press. A checkbox or a switch (its kind: what a screen reader calls it),
// pressed as the button is (a tap or a click on it, Enter or Space while it has the keyboard's focus, a screen
// reader's Activate: the framework's, all of them its on_press). The component's: that it says it is its kind, called
// by its label, on or off as its caller says; that it takes a press and the focus only while it is not disabled (the
// focus let go of at the cause that disables it, Tab passing it by, read out disabled then); that a press, however it
// came, tells its caller what it is to be (the other of what it is then), once, and never while it is disabled; and
// what its look reads of it. Its look's: everything else (a knob's slide, a tick, a felt tap).
//
// Controlled (headless.mbt, State): `on` is its caller's, read as it is pressed; `turn` is told what it is to be and
// writes it, `on` following. Nothing of on or off is kept here.

///|
/// What a toggle is to a screen reader: a checkbox (ticked or not), a switch (on or off), or a toggle button
/// (pressed or not).
#derive(Eq, Debug)
pub(all) enum ToggleKind {
  Checkbox
  Switch
  Button
}

///|
/// A toggle as its look reads it: each a reading, followed where a binding reads it.
pub struct Toggle {
  priv node : @view.View
  priv now : () -> Bool
  priv off : () -> Bool
}

///|
/// Whether it is on now (as its caller says).
pub fn Toggle::on(self : Toggle) -> Bool {
  (self.now)()
}

///|
/// Whether it is disabled: it takes no press and no focus (as its caller says).
pub fn Toggle::disabled(self : Toggle) -> Bool {
  (self.off)()
}

///|
/// Whether a finger or the pointer is held on it now (View::pressed).
pub fn Toggle::pressed(self : Toggle) -> Bool {
  self.node.pressed()
}

///|
/// Whether a pointer rests over it now (View::pointed): a mouse's, never a finger's (Button::hovered says the rest).
pub fn Toggle::hovered(self : Toggle) -> Bool {
  self.node.pointed()
}

///|
/// Whether it has the keyboard's focus and that shows (it came by the keyboard: View::focus_shown).
pub fn Toggle::focus_shown(self : Toggle) -> Bool {
  self.node.focus_shown()
}

///|
/// Pressed now, for what a look adds that ends in a press (a gesture of its own): asked of the tree as a press
/// delivered to the node (View::press), so none where the hand's would be none, and outside any tracking, as one
/// change. Called from a handler, never as something is drawn.
pub fn Toggle::press(self : Toggle) -> Unit {
  self.node.press() |> ignore
}

///|
/// A toggle of `kind` in `parent`, called `label` (what a screen reader says, as it changes), on or off as `on` says;
/// pressed, `turn` told what it is to be (not `on()` as it is pressed); `disabled` while it cannot be pressed. `look`
/// is run once as it is made, given its node and what it reads of it: all that is drawn of it, and how it is laid
/// out. Its node is made at `loc` (`made_for` where a library's part over it was asked for), as the button's is. The
/// node.
#callsite(autofill(loc))
pub fn toggle(
  parent : @view.View,
  kind : ToggleKind,
  label : () -> String,
  on : () -> Bool,
  turn : (Bool) -> Unit,
  look : (@view.View, Toggle) -> Unit,
  disabled? : () -> Bool = fn() { false },
  made_for? : SourceLoc,
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(loc~, made_for=made_for.unwrap_or(loc), fn(v) {
    let able = fn() { !disabled() }
    look(v, { node: v, now: on, off: disabled })
    // (its own words of the node, said after its look, as the button's)
    v
    .presses(By(able))
    .focusable(By(able))
    .says(By(fn() {
      let now = on()
      Some(
        match kind {
          Checkbox => @view.said(Checkbox, label=label(), check=if now { On } else { Off })
          Switch => @view.said(Switch, label=label(), check=if now { On } else { Off })
          Button => @view.said(Button, label=label(), pressed=now)
        },
      )
    }))
    // (what it is to be read as it is pressed, not as it was drawn: a press on its way as `on` changed, as one change;
    // never while disabled, the tree not yet told)
    .on_press(fn() {
      if !disabled() {
        turn(!on())
      }
    })
    |> ignore
  })
}
