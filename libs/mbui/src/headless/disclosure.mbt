// The disclosure: a button that opens or closes something (a collapsible section, a menu, a picker), read out a button
// called by its label and expanded while what it opens is open (`open`). Pressed as the button is (a tap or a click on
// it, Enter or Space while it has the keyboard's focus, a screen reader's Activate: all of them its on_press), taking
// a press and the focus only while it is not disabled. Controlled (headless.mbt, State): `open` is its caller's;
// `press` is given the disclosure's node (where what it opens goes beside it) once a press, never while disabled.

///|
/// A disclosure as its look reads it: each a reading, followed where a binding reads it.
pub struct Disclosure {
  priv node : @view.View
  priv now : () -> Bool
  priv off : () -> Bool
}

///|
/// Whether what it opens is open now (as its caller says).
pub fn Disclosure::open(self : Disclosure) -> Bool {
  (self.now)()
}

///|
/// Whether it is disabled: it takes no press and no focus (as its caller says).
pub fn Disclosure::disabled(self : Disclosure) -> Bool {
  (self.off)()
}

///|
/// Whether a finger or the pointer is held on it now (View::pressed).
pub fn Disclosure::pressed(self : Disclosure) -> Bool {
  self.node.pressed()
}

///|
/// Whether a pointer rests over it now (View::pointed): a mouse's, never a finger's (Button::hovered says the rest).
pub fn Disclosure::hovered(self : Disclosure) -> Bool {
  self.node.pointed()
}

///|
/// Whether it has the keyboard's focus and that shows (it came by the keyboard: View::focus_shown).
pub fn Disclosure::focus_shown(self : Disclosure) -> Bool {
  self.node.focus_shown()
}

///|
/// Pressed now, for what a look adds that ends in a press (a gesture of its own): asked of the tree as a press
/// delivered to the node (View::press), so none where the hand's would be none, and outside any tracking, as one
/// change. Called from a handler, never as something is drawn.
pub fn Disclosure::press(self : Disclosure) -> Unit {
  self.node.press() |> ignore
}

///|
/// A disclosure in `parent`, called `label` (what a screen reader says, as it changes), expanded while `open` says so;
/// `press` done as it is pressed, given the disclosure's node (where what it opens goes beside); `disabled` while it
/// cannot be pressed. `look` is run once as it is made, given its node and what it reads of it: all that is drawn of
/// it, and how it is laid out. Its node is made at `loc` (`made_for` where a library's part over it was asked for), as
/// the button's is. The node.
#callsite(autofill(loc))
pub fn disclosure(
  parent : @view.View,
  label : () -> String,
  open : () -> Bool,
  press : (@view.View) -> Unit,
  look : (@view.View, Disclosure) -> Unit,
  disabled? : () -> Bool = fn() { false },
  made_for? : SourceLoc,
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(loc~, made_for=made_for.unwrap_or(loc), fn(v) {
    let able = fn() { !disabled() }
    look(v, { node: v, now: open, off: disabled })
    v
    .presses(By(able))
    .focusable(By(able))
    .says(By(fn() { Some(@view.said(Button, label=label(), expanded=open())) }))
    .on_press(fn() {
      if !disabled() {
        press(v)
      }
    })
    |> ignore
  })
}
