// A switch (Radix's Switch): on or off, the value the view's. A tap, a click, Space or Enter with the focus, the
// Activate action turn it; it reports what it became (the view keeps it, or not). Its knob slides over switch_ms.
// Held by a finger, a look given a lens (`lens`, liquid glass) draws its knob as that lens, wider and larger, the
// track seen through it (iOS 26's switch), back to the knob as it is let go (`held`: switch_held).

///|
/// What a switch's look is given: on, how far its knob is across (0 off … 1 on, moving), pointed at, held (and how far
/// it is in a finger: 0 … 1, switch_held), focus shown, disabled, where it was last frame.
pub(all) struct SwitchState {
  on : Bool
  t : Double
  hovered : Bool
  pressed : Bool
  held : Double
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
  // (held however long, still its press: let go, turned; its knob a lens meanwhile, where its look has one)
  let r = c.interact(id, disabled~, holds=true)
  let on = if r.clicked { !checked } else { checked }
  // turned by a finger: felt, a light tick (as iOS's switch)
  if r.clicked {
    felt_tick(c, key)
  }
  let t = switch_knob(c, key, on)
  let st = {
    on,
    t,
    hovered: r.hovered,
    pressed: r.pressed,
    held: switch_held(c, key, r.pressed),
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
/// accent), off in `off_color` (its control edge), the knob in `knob` (its thumb) with a shadow unless not `shadow`;
/// held by a finger, the knob a `lens` of that glass (none: the knob as it is), `lens_w` as wide and `lens_grow` larger.
pub fn switch_look_of(
  w? : Double = 36.0,
  h? : Double = 22.0,
  inset? : Double = 2.0,
  on_color? : Int64,
  off_color? : Int64,
  knob? : Int64,
  shadow? : Bool = true,
  lens? : @ui.Glass,
  lens_w? : Double = 1.45,
  lens_grow? : Double = knob_lens_grow,
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
      bg=blend(off_color.unwrap_or(t.border), on_color.unwrap_or(t.accent), s.t),
      justify=JCenter,
      align=AStart,
      opacity=if s.disabled { 0.5 } else { 1.0 },
      fn() {
        // (held, the knob a lens: wider and larger about its middle, the knob fading under it; where glass is drawn
        // solid, the knob as it is)
        let held = match lens {
          Some(_) if !c.glass_solid() => s.held
          _ => 0.0
        }
        let knob_at = c.box(
          w=Px(d),
          h=Px(d),
          radius=d / 2.0,
          bg=knob.unwrap_or(t.thumb),
          shadow=if shadow { 2.0 } else { 0.0 },
          shadow_color=0x00000033L,
          shadow_y=1.0,
          tx=inset + travel * k,
          fn() {  },
        )
        match lens {
          Some(g) if held > 0.0 => {
            c.look(knob_at, @ui.look(alpha=1.0 - dmin(1.0, held)))
            let grow = 1.0 + (lens_grow - 1.0) * held
            let lw = d * (1.0 + (lens_w - 1.0) * held) * grow
            let lh = d * grow
            // (its middle where the knob's is, the wider lens kept within the track's ends: it grows in toward the
            // track's middle at either end)
            let mid = inset + d / 2.0 + travel * k
            let x = dmax(0.0, dmin(mid - lw / 2.0, w - lw))
            let y = (h - lh) / 2.0
            let lens_at = c.layer(fn() {
              c.box(style=lens_capsule(lw, lh), glass=g, tx=x, ty=y, fn() {  }) |> ignore
            })
            c.look(lens_at, @ui.look(alpha=dmin(1.0, held)))
          }
          _ => ()
        }
        focus_ring(c, s.focus_shown, s.rect, h / 2.0)
      },
    )
    |> ignore
  }
}

///|
/// The default look: still.fail's switch, 36 by 22, its 18 knob white, the accent when on.
pub let switch_look : (@ui.Ctx, SwitchState) -> Unit = switch_look_of()

///|
/// How far the switch `key`'s knob is across this frame (0 off … 1 on): sliding over switch_ms on the ease-out to the
/// side `on` puts it, from where it is; at that side at once the first time. A switch's look drawn without `switch` (a
/// row around it takes the tap) moves by it as `switch`'s does.
pub fn switch_knob(c : @ui.Ctx, key : String, on : Bool) -> Double {
  animate(c, key + "/knob", if on { 1.0 } else { 0.0 }, transition=@motion.tween(switch_ms, ease=Out))
}

///|
/// How far the switch `key`'s knob is in a finger this frame (0 … 1): `pressed` by one, toward 1 on a spring with a
/// little give, back as it is let go. A switch's look drawn without `switch` (a row around it takes the press) is held
/// as `switch`'s is, by what is pressed there.
pub fn switch_held(c : @ui.Ctx, key : String, pressed : Bool) -> Double {
  let on = pressed && @ui.pointing() is Finger
  animate(c, key + "/held", if on { 1.0 } else { 0.0 }, transition=@motion.motion_spring(0.3, bounce=0.3))
}

///|
/// How long a switch's knob takes to its side (still.fail's: parts.css.ts switchThumb, --dur on the ease-out), its
/// track's colour with it.
pub let switch_ms : Double = 140.0

///|
/// When the switch `key`'s knob is at rest after a turn (the frames' clock; -1: it is, +inf: told, not started).
pub fn switch_rest(key : String) -> Double {
  @ui.rest_of("\u{2}animate/" + key + "/knob")
}

///|
/// A light tick felt for `key`'s control turned by a finger now (a switch turned, a group's other item chosen, a
/// sheet drawn past its top): told once, as the frame's builds are over (Ctx::tell: the build that took the press).
pub fn felt_tick(c : @ui.Ctx, key : String) -> Unit {
  if @ui.pointing() is Finger {
    c.tell("\u{2}tick/" + key, fn() { @ui.haptic(TextHandleMove) })
  }
}

///|
/// A lens `w` by `h`, a capsule (a switch's knob held, a sliding group's thumb under a finger).
fn lens_capsule(w : Double, h : Double) -> @ui.Style {
  @ui.style(w=Fixed(w), h=Fixed(h), radius=Full)
}
