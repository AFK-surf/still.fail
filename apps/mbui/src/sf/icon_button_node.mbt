// The library's icon button (icon_button's) as a node of the window's tree, made once: round, `size` across, its icon
// in its middle; where the hand is on it (or the keyboard's focus shows) its ground the ink's hover tint as far as that
// has eased (dur_ms, eased out, from the moment it changed), its icon the ink's once that is past half, the muted ink's
// before; named by its label (read out a button, its tip shown by it); pressed as an old view's box with an id is.
// Its look over mbui's headless button (@headless.button), as button_node's.

///|
/// The icon button in `parent` showing icon `icon`, `size` across (round), its icon `icon_size`; named `label` (read
/// out, and its tip in `tips`); `press` done as it is pressed. While `disabled()`, faded (icon_button's: 0.45), taking
/// no press nor the focus. `linked`: its corner where that comes from, as it is worked out where it stands now (a bar's
/// buttons' at the window's corner: @sf.bar_keys_link; icon_button's `linked`), else round. `shortcut`: the action that
/// does what it does, its keys said in its tip after its label (icon_button's). The node.
#callsite(autofill(loc))
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
  linked? : () -> @ui.CornerOf?,
  shortcut? : String = "",
  loc~ : SourceLoc,
) -> @view.View {
  icon_button_by(loc~, parent, icon, label, fn(_) { press() }, tips, size, icon_size, icon_now, disabled, linked?=linked, shortcut~)
}

///|
/// icon_button_node's button that opens what goes beside it (a menu under it): `open` given the button itself as it is
/// pressed, where it is placed then.
#callsite(autofill(loc))
pub fn icon_button_opens_node(
  parent : @view.View,
  icon : String,
  label : () -> String,
  open : (@view.View) -> Unit,
  loc~ : SourceLoc,
) -> @view.View {
  icon_button_by(loc~, parent, icon, label, open, None, icon_button_side, 16.0, None, fn() { false })
}

///|
/// icon_button_node's button, `press` given the button itself as it is pressed (what opens beside it: its menu).
#callsite(autofill(loc))
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
  linked? : () -> @ui.CornerOf?,
  shortcut? : String = "",
  loc~ : SourceLoc,
) -> @view.View {
  // (what it is to the keyboard and a screen reader is mbui's headless button's: read out a button called by its
  // label, pressed and focused only while not disabled. Here, its look; and, with it, a debt: its tip held up by a
  // finger's long press is this library's alone, but to have it the look takes the pointer itself (View::gesture, so
  // the pointer's press never reaches the button's own) and says again below when a pointer's press counts (a finger's
  // a tap, not once held long; a mouse's let go on it, moved or held or not), ending each in the button's press
  // (Button::press: taken by the tree as a press on it is). When a press counts is the component's (mbui's
  // headless.mbt, the hand): paid once the button can be given a hold beside its press)
  @headless.button(made_for=loc, parent, label, press, disabled~, fn(v, b) {
    let press = fn() { b.press() }
    // (the hand on it: a pointer over it, a finger or the pointer held on it; the keyboard's focus shown on it)
    let lit = fn() { b.focus_shown() || b.hovered() || b.pressed() }
    let hand = EdgeWay::new(0.0)
    v.reacts(lit, fn(on) { hand.go(v, if on { 1.0 } else { 0.0 }, dur_ms) })
    let pad = (size - icon_size) / 2.0
    v
    .width(Is(Some(size)))
    .height(Is(Some(size)))
    .padding(Is((pad, pad, pad, pad)))
    .radius(
      match linked {
        Some(f) =>
          By(fn() {
            match f() {
              Some(link) => link.radius(@ui.tree_corner_roots_now())
              None => size / 2.0
            }
          })
        None => Is(size / 2.0)
      },
    )
    .alpha(By(fn() { if disabled() { icon_button_disabled_alpha } else { 1.0 } }))
    // (the page's hover, as a tint of the ink it sits with: icon_button's)
    .ground(By(fn() { alpha(theme().p.text, 0.065 * hand.shown(v)) }))
    |> ignore
    icon_node(v, icon, icon_size, By(fn() { if hand.shown(v) > 0.5 { theme().p.text } else { theme().p.muted } }), name_now?=icon_now)
    |> ignore
    let tip = match tips {
      Some(t) => Some(tip_node(t, v, label, side=Bottom, shortcut~))
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
