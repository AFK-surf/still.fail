// The button: what is pressed to do one thing. Pressed by a tap or a click on it, by Enter or Space while it has the
// keyboard's focus, by a screen reader's Activate: the framework's, all of them its on_press. The component's: that it
// says it is a button called by its label; that it takes a press and the focus only while it is not disabled, the
// focus on it let go of at the cause that disables it and Tab passing it by, read out disabled then; that its press is
// done once a press, however it came, and never while it is disabled; and what its look reads of it. Its look's:
// everything else, a state only the eye is told among it (at work: headless.mbt, State).
//
// The app's buttons that say more than a name are not this one's: on or off is a toggle's (toggle.mbt: a checkbox, a
// switch, a toggle button), expanded what opens something's (disclosure.mbt: a disclosure, a menu's button), selected
// an option's of a choice (choice.mbt). Each is a component of its own, not a parameter here.

///|
/// A finger's long press beside a control's press, and what a press's look hears of the pointer (`down`, `tapped`):
/// `slop` how far a finger may move while still a tap, `ms` how long a finger is held before `on_hold` runs (`finger`
/// whether the hand now is a finger's). Under a finger, once `on_hold` has run the press is no tap: `on_lift` runs as
/// the finger is let go, `on_cancel` if the hold is called off (`Off`). Under a mouse, a press let go on the node
/// counts whether it moved past `slop` or was held past `ms`.
pub(all) struct Hold {
  slop : Double
  ms : Double
  finger : () -> Bool
  on_hold : () -> Unit
  on_lift : () -> Unit
  on_cancel : () -> Unit
  down : ((@view.Drag) -> Unit)?
  tapped : ((@view.Drag) -> Unit)?
}

///|
/// A `Hold` of `slop`, `ms` and `finger`, with what runs on the finger's hold, lift and cancel and what a press's
/// look hears of the pointer (`down`, `tapped`).
pub fn Hold::new(
  slop : Double,
  ms : Double,
  finger : () -> Bool,
  on_hold? : () -> Unit = fn() {  },
  on_lift? : () -> Unit = fn() {  },
  on_cancel? : () -> Unit = fn() {  },
  down? : (@view.Drag) -> Unit,
  tapped? : (@view.Drag) -> Unit,
) -> Hold {
  { slop, ms, finger, on_hold, on_lift, on_cancel, down, tapped }
}

///|
/// Attach `hold` to `v`: its gesture ending in `v.press()` where a press counts, and calling `hold`'s callbacks.
fn attach_hold(v : @view.View, hold : Hold) -> Unit {
  let held = Ref(false)
  let on_it = fn(d : @view.Drag) { v.finger_target(d.wx, d.wy) }
  v.gesture(
    hold.slop,
    press?=hold.down,
    tap=fn(d) {
      if hold.tapped is Some(f) {
        f(d)
      }
      if on_it(d) {
        v.press() |> ignore
      }
    },
    hold=(
      hold.ms,
      fn(_) {
        held.val = true
        if (hold.finger)() {
          (hold.on_hold)()
        }
      },
    ),
    drag=fn(d) {
      if !held.val {
        if d.kind == Up && !(hold.finger)() && on_it(d) {
          v.press() |> ignore
        }
      } else if d.kind == Up || d.kind == Off {
        held.val = false
        match d.kind {
          Off => (hold.on_cancel)()
          Up if (hold.finger)() => (hold.on_lift)()
          Up if !(hold.finger)() && on_it(d) => v.press() |> ignore
          _ => ()
        }
      }
    },
  )
  |> ignore
}

///|
/// A button as its look reads it: each a reading, followed where a binding reads it.
pub struct Button {
  priv node : @view.View
  priv off : () -> Bool
}

///|
/// Whether it is disabled: it takes no press and no focus (as its caller says).
pub fn Button::disabled(self : Button) -> Bool {
  (self.off)()
}

///|
/// Whether a finger or the pointer is held on it now (View::pressed).
pub fn Button::pressed(self : Button) -> Bool {
  self.node.pressed()
}

///|
/// Whether a pointer rests over it now (View::pointed): a mouse's or a trackpad's, never a finger's, which points at
/// nothing. That is the tree's host's to hold, not asked again here: it takes the pointer off the tree as an event
/// comes by a finger, once that event is taken (so in the handlers of the one event that turns the hand from a mouse
/// to a finger this still says the mouse's; no frame is drawn of it).
pub fn Button::hovered(self : Button) -> Bool {
  self.node.pointed()
}

///|
/// Whether it has the keyboard's focus and that shows (it came by the keyboard: where a focus ring is drawn,
/// View::focus_shown).
pub fn Button::focus_shown(self : Button) -> Bool {
  self.node.focus_shown()
}

///|
/// Pressed now, for what a look adds that ends in a press (a gesture of its own): asked of the tree, which takes it
/// as a press delivered to the node (View::press), so none where the hand's would be none (disabled, leaving, under a
/// modal layer, in what takes no press), and outside any tracking, as one change. Called from a handler (a gesture's
/// word, a moment, a reaction), never as something is drawn.
pub fn Button::press(self : Button) -> Unit {
  self.node.press() |> ignore
}

///|
/// A button in `parent`, called `label` (what a screen reader says, as it changes; its look draws it or not), `press`
/// done as it is pressed, given the button's node (where what it opens goes beside); `disabled` while it cannot be
/// pressed. `look` is run once as it is made, given its node and what it reads of it: all that is drawn of it, and how
/// it is laid out. Its node is made at `loc`, the line that says it; where that is a library's part with a look (a
/// part of a part), `made_for` is where that part was asked for, its own `loc~` handed on, so what is found in the
/// button is traced to the look's line and to the line that asked for it (source.mbt). The node.
#callsite(autofill(loc))
pub fn button(
  parent : @view.View,
  label : () -> String,
  press : (@view.View) -> Unit,
  look : (@view.View, Button) -> Unit,
  disabled? : () -> Bool = fn() { false },
  hold? : Hold,
  made_for? : SourceLoc,
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(loc~, made_for=made_for.unwrap_or(loc), fn(v) {
    let able = fn() { !disabled() }
    look(v, { node: v, off: disabled })
    if hold is Some(h) {
      attach_hold(v, h)
    }
    // (its own words of the node, said after its look: what the look said of these four as it ran does not stand;
    // headless.mbt says what that does and does not hold. The keyboard's focus while it can be pressed, Enter and Space
    // pressing it)
    v
    .presses(By(able))
    .focusable(By(able))
    .says(By(fn() { Some(@view.said(Button, label=label())) }))
    // (the tree's to run, however the press came (View::on_press: outside any tracking, as one change); never while
    // disabled: a press on its way as that changed, the tree not yet told)
    .on_press(fn() {
      if !disabled() {
        press(v)
      }
    })
    |> ignore
  })
}
