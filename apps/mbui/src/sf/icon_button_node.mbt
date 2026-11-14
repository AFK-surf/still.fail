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
  // (what it is to the hand, the keyboard and a screen reader is mbui's headless button's: read out a button called by
  // its label, pressed and focused only while not disabled, its tip held up by a finger's long press via Hold. Here,
  // its look)
  let tip : Ref[TipHand?] = Ref(None)
  @headless.button(
    made_for=loc,
    parent,
    label,
    press,
    disabled~,
    hold=@headless.Hold::new(
      @ui.touch_slop(),
      @ui.long_press_ms,
      fn() { @ui.pointing() is Finger },
      on_hold=fn() { if tip.val is Some(h) { (h.hold)() } },
      on_lift=fn() { if tip.val is Some(h) { (h.lift)() } },
      on_cancel=fn() { if tip.val is Some(h) { (h.cancel)() } },
    ),
    fn(v, b) {
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
      tip.val = match tips {
        Some(t) => Some(tip_node(t, v, label, side=Bottom, shortcut~))
        None => None
      }
    },
  )
}

///|
/// How far a disabled icon button is seen (icon_button's `disabled`).
let icon_button_disabled_alpha : Double = 0.45
