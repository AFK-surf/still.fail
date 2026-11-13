// Comma's Checkbox and Toggle (clients/packages/ui checkbox/CheckboxBase, toggle/ToggleBase) as nodes of the window's
// tree, made once: each turned by a press (a tap, a click, Space or Enter with the keyboard's focus, a screen reader's
// Activate), its brand fill coming over Comma's state change, the toggle's knob going across over its feedback-in on
// surface-smooth-out; the brand focus ring while the keyboard's focus is on it.

///|
/// The size of a checkbox or a toggle (Comma's "sm" | "md").
#derive(Eq, Debug)
pub(all) enum ControlSize {
  ControlSm
  ControlMd
}

///|
/// Comma's checkbox in `parent`, on as `on` says: 16 across (Md 20) on the main panel's ground in the menu's edge with
/// the xs shadow, brand-solid with a white tick while on; the disabled colours while `disabled`. Pressed, `turn` is
/// told what it becomes. Read out a checkbox named `label`, on or off. The node.
#callsite(autofill(loc))
pub fn check_node(
  parent : @view.View,
  on : () -> Bool,
  turn : (Bool) -> Unit,
  label : () -> String,
  size? : ControlSize = ControlSm,
  disabled? : () -> Bool = fn() { false },
  loc~ : SourceLoc,
) -> @view.View {
  let side = if size == ControlSm { 16.0 } else { 20.0 }
  let corner = if size == ControlSm { radius_xs } else { radius_md }
  parent.box(made_for=loc, fn(b) {
    let fill = eased_by(b, on, ms_state_change, ease_surface_smooth_out)
    b
    .width(Is(Some(side)))
    .height(Is(Some(side)))
    .shrink(Is(0.0))
    .radius(Is(corner))
    .ground(By(fn() {
      let c = colors()
      if disabled() {
        c.bg_disabled
      } else {
        mix(c.bg_brand_solid, fill.shown(b), c.main_panel_bg)
      }
    }))
    .edge(By(fn() {
      let c = colors()
      if disabled() {
        (1.0, c.border_disabled)
      } else {
        (1.0, mix(alpha(c.border_menu_primary, 0.0), fill.shown(b), c.border_menu_primary))
      }
    }))
    .shadow(By(fn() { if is_dark() { shadow_dark_xs } else { shadow_xs } }))
    .says(By(fn() { Some(@view.said(Checkbox, label=label(), check=if on() { On } else { Off })) }))
    |> ignore
    presses_node(b, fn() { turn(!@signals.untracked(on)) }, on=fn() { !disabled() })
    // (the tick: Comma's check-large in the box's middle, 12.5% in from its sides, at the design's 1.67 stroke)
    b.box(fn(t) {
      let k = side / 16.0
      t
      .over(Is(true))
      .lines(By(fn() {
        let c = colors()
        let ink = if disabled() { c.fg_disabled } else { c.fg_white }
        [@ui.line([(4.5 * k, 8.2 * k), (6.8 * k, 10.5 * k), (11.5 * k, 5.5 * k)], width=1.67, color=alpha(ink, fill.shown(b)))]
      }))
      |> ignore
    })
    |> ignore
    ring_node(b, fn() { corner })
  })
}

///|
/// Comma's toggle in `parent`, on as `on` says: a track (Sm 36 × 20, Md 44 × 24) in the toggle's grey, brand-solid while
/// on, darkened under the pointer; its white knob (16, Md 20, 2 in from its ends, the sm shadow) going to the end it is
/// turned to; half seen while `disabled`. Pressed, `turn` is told what it becomes. Read out a switch named `label`, on
/// or off. The node.
#callsite(autofill(loc))
pub fn toggle_node(
  parent : @view.View,
  on : () -> Bool,
  turn : (Bool) -> Unit,
  label : () -> String,
  size? : ControlSize = ControlSm,
  disabled? : () -> Bool = fn() { false },
  loc~ : SourceLoc,
) -> @view.View {
  let (w, h, knob) = if size == ControlSm { (36.0, 20.0, 16.0) } else { (44.0, 24.0, 20.0) }
  let inset = space_xxs
  parent.box(made_for=loc, fn(b) {
    let live = fn() { !disabled() }
    let across = eased_by(b, on, ms_feedback_in, ease_surface_smooth_out)
    let fill = eased_by(b, on, ms_state_change, ease_surface_smooth_out)
    let hand = eased_by(b, fn() { lit(b, live) }, ms_state_change, ease_surface_smooth_out)
    b
    .width(Is(Some(w)))
    .height(Is(Some(h)))
    .shrink(Is(0.0))
    .radius(Is(h / 2.0))
    .row(Is(true))
    .lines_up(Is(Some(Middle)))
    .padding(Is((inset, 0.0, inset, 0.0)))
    .ground(By(fn() {
      let c = colors()
      let track = mix(c.bg_brand_solid, fill.shown(b), c.bg_toggle)
      // (the hover's black at 10% laid over whichever colour the track has)
      mix(0x000000FFL, 0.1 * hand.shown(b), track)
    }))
    .alpha(By(fn() { if disabled() { 0.5 } else { 1.0 } }))
    .says(By(fn() { Some(@view.said(Switch, label=label(), check=if on() { On } else { Off })) }))
    |> ignore
    presses_node(b, fn() { turn(!@signals.untracked(on)) }, on=live)
    b.box(fn(k) {
      k
      .width(Is(Some(knob)))
      .height(Is(Some(knob)))
      .shrink(Is(0.0))
      .radius(Is(knob / 2.0))
      // (to the far end as it is turned on: a move drawn, never laid out again)
      .offset(By(fn() { ((w - knob - 2.0 * inset) * across.shown(b), 0.0) }))
      .ground(By(fn() {
        let c = colors()
        if disabled() {
          c.toggle_button_fg_disabled
        } else {
          c.fg_white
        }
      }))
      .shadow(By(fn() { if is_dark() { shadow_dark_sm } else { shadow_sm } }))
      |> ignore
    })
    |> ignore
    ring_node(b, fn() { h / 2.0 })
  })
}
