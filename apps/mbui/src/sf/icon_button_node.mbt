// The library's icon button (icon_button's) as a node of the window's tree, made once: round, `size` across, its icon
// in its middle; where the hand is on it (or the keyboard's focus shows) its ground the ink's hover tint as far as that
// has eased (dur_ms, eased out, from the moment it changed), its icon the ink's once that is past half, the muted ink's
// before; named by its label (read out a button, its tip shown by it); pressed as an old view's box with an id is.

///|
/// The icon button in `parent` showing icon `icon`, `size` across (round), its icon `icon_size`; named `label` (read
/// out, and its tip in `tips`); `press` done as it is pressed. While `disabled()`, faded (icon_button's: 0.45), taking
/// no press nor the focus. The node.
pub fn icon_button_node(
  parent : @view.View,
  icon : String,
  label : () -> String,
  press : () -> Unit,
  tips? : TipLayer,
  size? : Double = icon_button_side,
  icon_size? : Double = 16.0,
  icon_now? : () -> String,
  disabled? : () -> Bool = fn() { false },
) -> @view.View {
  icon_button_by(parent, icon, label, fn(_) { press() }, tips, size, icon_size, icon_now, disabled)
}

///|
/// icon_button_node's button that opens what goes beside it (a menu under it): `open` given the button itself as it is
/// pressed, where it is placed then.
pub fn icon_button_opens_node(parent : @view.View, icon : String, label : () -> String, open : (@view.View) -> Unit) -> @view.View {
  icon_button_by(parent, icon, label, open, None, icon_button_side, 16.0, None, fn() { false })
}

///|
/// icon_button_node's button, `press` given the button itself as it is pressed (what opens beside it: its menu).
fn icon_button_by(
  parent : @view.View,
  icon : String,
  label : () -> String,
  press : (@view.View) -> Unit,
  tips : TipLayer?,
  size : Double,
  icon_size : Double,
  icon_now : (() -> String)?,
  disabled : () -> Bool,
) -> @view.View {
  let live = fn() { !disabled() }
  parent.box(fn(v) {
    let press = fn() {
      if @signals.untracked(live) {
        press(v)
      }
    }
    // (the hand on it: a mouse over it or pressing it, a finger pressing it; the keyboard's focus shown on it)
    let lit = fn() {
      v.focus_shown() ||
      (match @ui.pointing() {
        Mouse => v.pointed() || v.pressed()
        Finger => v.pressed()
      })
    }
    let hand = EdgeWay::new(0.0)
    v.reacts(lit, fn(on) { hand.go(v, if on { 1.0 } else { 0.0 }, dur_ms) })
    let pad = (size - icon_size) / 2.0
    v
    .width(Is(Some(size)))
    .height(Is(Some(size)))
    .padding(Is((pad, pad, pad, pad)))
    .radius(Is(size / 2.0))
    .presses(By(live))
    .focusable(By(live))
    .alpha(By(fn() { if disabled() { icon_button_disabled_alpha } else { 1.0 } }))
    // (the page's hover, as a tint of the ink it sits with: icon_button's)
    .ground(By(fn() { alpha(theme().p.text, 0.065 * hand.shown(v)) }))
    .says(By(fn() { Some(@view.said(Button, label=label())) }))
    .on_press(press)
    |> ignore
    icon_node(v, icon, icon_size, By(fn() { if hand.shown(v) > 0.5 { theme().p.text } else { theme().p.muted } }), name_now?=icon_now)
    |> ignore
    let tip = match tips {
      Some(t) => Some(tip_node(t, v, label, side=Bottom))
      None => None
    }
    let held = Ref(false)
    let on_it = fn(d : @view.Drag) { v.finger_target(d.wx, d.wy) }
    v.gesture(
      @ui.touch_slop(),
      tap=fn(d) { if on_it(d) { press() } },
      hold=(
        @ui.long_press_ms,
        fn(_) {
          held.val = true
          if @ui.pointing() is Finger {
            match tip {
              Some(h) => (h.hold)()
              None => ()
            }
          }
        },
      ),
      drag=fn(d) {
        if !held.val {
          // (a mouse's moved on it past the slop: still a press as it is let go on it, as a click is)
          if d.kind == Up && @ui.pointing() is Mouse && on_it(d) {
            press()
          }
        } else if d.kind == Up || d.kind == Off {
          held.val = false
          match (tip, d.kind) {
            (Some(h), Off) => (h.cancel)()
            (Some(h), Up) if @ui.pointing() is Finger => (h.lift)()
            (_, Up) if @ui.pointing() is Mouse && on_it(d) => press()
            _ => ()
          }
        }
      },
    )
    |> ignore
  })
}

///|
/// How far a disabled icon button is seen (icon_button's `disabled`).
let icon_button_disabled_alpha : Double = 0.45
