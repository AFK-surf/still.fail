// The library's icon button (icon_button's) as a node of the window's tree, made once: round, `size` across, its icon
// in its middle; where the hand is on it (or the keyboard's focus shows) its ground the ink's hover tint as far as that
// has eased (dur_ms, eased out, from the moment it changed), its icon the ink's once that is past half, the muted ink's
// before; named by its label (read out a button, its tip shown by it); pressed as an old view's box with an id is.

///|
/// The icon button in `parent` showing icon `icon`, `size` across (round), its icon `icon_size`; named `label` (read
/// out, and its tip in `tips`); `press` done as it is pressed; its corners linked where `linked` says (icon_button's
/// `linked`: a bar's key at the window's corner following it, bar_keys_link), round where it says None. `disabled`
/// keeps it from taking a press or focus and fades it. `on`, when supplied, says it is a toggle and gives it the old
/// icon_button's chosen ground and ink. `ink` and `quiet` override the theme's text and muted inks as they change;
/// `shortcut` names the action whose keys its tip says. `selected_alpha` and `hover_alpha` set the two grounds as
/// shares of `ink`; `drag_through` hands a move past the slop to a drag area beneath the button, while a tap and a
/// long press remain the button's (for a draggable Screen tools button).
/// The node.
pub fn icon_button_node(
  parent : @view.View,
  icon : String,
  label : () -> String,
  press : () -> Unit,
  tips? : TipLayer,
  size? : Double = icon_button_side,
  icon_size? : Double = 16.0,
  icon_now? : () -> String,
  linked? : () -> @ui.CornerOf?,
  disabled? : () -> Bool = fn() { false },
  on? : () -> Bool,
  ink? : () -> Int64,
  quiet? : () -> Int64,
  shortcut? : () -> String = fn() { "" },
  selected_alpha? : Double = 0.08,
  hover_alpha? : Double = 0.065,
  drag_through? : Bool = false,
) -> @view.View {
  let live = fn() { !disabled() }
  let chosen = fn() { match on { Some(f) => f(); None => false } }
  let full_ink = match ink { Some(f) => f; None => fn() { theme().p.text } }
  let quiet_ink = match quiet { Some(f) => f; None => fn() { theme().p.muted } }
  parent.box(fn(v) {
    // (the hand on it: a mouse over it or pressing it, a finger pressing it; the keyboard's focus shown on it)
    let lit = fn() {
      live() && (v.focus_shown() ||
      (match @ui.pointing() {
        Mouse => v.pointed() || v.pressed()
        Finger => v.pressed()
      }))
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
    .alpha(By(fn() { if disabled() { 0.35 } else { 1.0 } }))
    // (the chosen ground or the hand's hover, as a tint of the ink it sits with: icon_button's)
    .ground(By(fn() { alpha(full_ink(), if chosen() { selected_alpha } else { hover_alpha * hand.shown(v) }) }))
    .says(By(fn() { Some(@view.said(Button, label=label(), pressed?=on.map(fn(f) { f() }))) }))
    .on_press(fn() { if @signals.untracked(live) { press() } })
    |> ignore
    // (linked as an old view's box is: drawn following it, and the corner rule taking its corners as following it)
    match linked {
      Some(l) => @ui.tree_corners_linked(v, fn() { l().map(fn(k) { FixedArray::make(4, k) }) })
      None => ()
    }
    icon_node(v, icon, icon_size, By(fn() { if chosen() || hand.shown(v) > 0.5 { full_ink() } else { quiet_ink() } }), name_now?=icon_now)
    |> ignore
    let tip = match tips {
      Some(t) => Some(tip_node(t, v, label, side=Bottom, shortcut~))
      None => None
    }
    let held = Ref(false)
    let on_it = fn(d : @view.Drag) { v.finger_target(d.wx, d.wy) }
    v.gesture(
      @ui.touch_slop(),
      tap=fn(d) { if on_it(d) && @signals.untracked(live) { press() } },
      hold=(
        @ui.long_press_ms,
        fn(_) {
          held.val = true
          if @ui.pointing() is Finger && @signals.untracked(live) {
            match tip {
              Some(h) => (h.hold)()
              None => ()
            }
          }
        },
      ),
      held_first=fn(_) { drag_through },
      drag=fn(d) {
        if !held.val {
          // (a mouse's moved on it past the slop: still a press as it is let go on it, as a click is)
          if d.kind == Up && @ui.pointing() is Mouse && on_it(d) && @signals.untracked(live) {
            press()
          }
        } else if d.kind == Up || d.kind == Off {
          held.val = false
          match (tip, d.kind) {
            (Some(h), Off) => (h.cancel)()
            (Some(h), Up) if @ui.pointing() is Finger => (h.lift)()
            (_, Up) if @ui.pointing() is Mouse && on_it(d) && @signals.untracked(live) => press()
            _ => ()
          }
        }
      },
    )
    |> ignore
  })
}
