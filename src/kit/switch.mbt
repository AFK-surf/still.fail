// A switch (Radix's Switch): on or off, the value the view's. A tap, a click, Space or Enter with the focus, the
// Activate action turn it; it reports what it became (the view keeps it, or not). Its knob slides by a spring.

///|
/// What a switch's look is given: on, how far its knob is across (0 off … 1 on, moving), pointed at, held, focus
/// shown, disabled, where it was last frame.
pub(all) struct SwitchState {
  on : Bool
  t : Double
  hovered : Bool
  pressed : Bool
  focus_shown : Bool
  disabled : Bool
  rect : (Double, Double, Double, Double)
}

///|
/// A switch, `checked` or not (its id `key`'s), named `label` for the semantics tree. What it became, and what
/// happened to it.
pub fn switch(
  c : @ui.Ctx,
  key : String,
  checked : Bool,
  label? : String = "",
  disabled? : Bool = false,
  look? : (@ui.Ctx, SwitchState) -> Unit = switch_look,
) -> @ui.Changed[Bool] {
  let id = c.id(key)
  let r = c.interact(id, disabled~)
  let on = if r.clicked { !checked } else { checked }
  let t = animate(c, key + "/knob", if on { 1.0 } else { 0.0 })
  let st = {
    on,
    t,
    hovered: r.hovered,
    pressed: r.pressed,
    focus_shown: r.focus_shown,
    disabled,
    rect: r.rect,
  }
  let i = c.box(id=if disabled { 0 } else { id }, fn() { look(c, st) })
  c.semantics(i, Switch, id~, label~, check=if on { On } else { Off }, disabled~, actions=pick(
    disabled,
    [],
    [Activate],
  ))
  { value: on, response: r.changed_to(on != checked) }
}

///|
/// A switch's look by its sizes: `w` by `h`, its knob `inset` in from the edge, on in `on_color` (the theme's
/// positive), off in `off_color` (its faint), the knob in `knob` (its thumb) with a shadow unless not `shadow`.
pub fn switch_look_of(
  w? : Double = 51.0,
  h? : Double = 31.0,
  inset? : Double = 2.0,
  on_color? : Int64,
  off_color? : Int64,
  knob? : Int64,
  shadow? : Bool = true,
) -> (@ui.Ctx, SwitchState) -> Unit {
  fn(c, s) {
    let t = c.theme()
    let d = h - 2.0 * inset
    let travel = w - 2.0 * inset - d
    let k = if c.rtl() { 1.0 - s.t } else { s.t }
    c.box(
      w=Px(w),
      h=Px(h),
      radius=h / 2.0,
      bg=blend(off_color.unwrap_or(t.faint), on_color.unwrap_or(t.positive), s.t),
      justify=JCenter,
      align=AStart,
      opacity=if s.disabled { disabled_alpha } else { 1.0 },
      fn() {
        c.box(
          w=Px(d),
          h=Px(d),
          radius=d / 2.0,
          bg=knob.unwrap_or(t.thumb),
          shadow=if shadow { 4.0 } else { 0.0 },
          shadow_color=0x00000040L,
          shadow_y=1.5,
          tx=inset + travel * k,
          fn() {  },
        )
        |> ignore
        focus_ring(c, s.focus_shown, s.rect, h / 2.0)
      },
    )
    |> ignore
  }
}

///|
/// The default look: iOS's switch, 51 by 31, green when on.
pub let switch_look : (@ui.Ctx, SwitchState) -> Unit = switch_look_of()
