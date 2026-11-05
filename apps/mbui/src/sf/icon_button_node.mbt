// The library's icon button (icon_button's) as a node of the window's tree, made once: round, `size` across, its icon
// in its middle; where the hand is on it (or the keyboard's focus shows) its ground the ink's hover tint as far as that
// has eased (dur_ms, eased out, from the moment it changed), its icon the ink's once that is past half, the muted ink's
// before; named by its label (read out a button, its tip shown by it); pressed as an old view's box with an id is.

///|
/// The icon button in `parent` showing icon `icon`, `size` across (round), its icon `icon_size`; named `label` (read
/// out, and its tip in `tips`); `press` done as it is pressed. `linked`: its corner where that comes from as it says now
/// (a bar's buttons' at the window's corner: window_corner_key), all four alike and the corner rule told so
/// (@ui.tree_corners_linked), as icon_button's `linked` is; round where it says none. The node.
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
) -> @view.View {
  parent.box(fn(v) {
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
    |> ignore
    match linked {
      Some(link) => @ui.tree_corners_linked(v, fn() { link().map(fn(k) { FixedArray::make(4, k) }) })
      None => ()
    }
    v
    .presses(Is(true))
    .focusable(Is(true))
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
