// A button (not one of Radix's: what every component that acts is pressed through, shadcn's Button): pressed by a
// tap, a click, Enter or Space while it has the focus, the Activate action. Its kinds of look: Solid (the thing to
// do, in the accent), Soft (on the quiet ground), Outline (a line round it), Ghost (words alone, a ground when pointed
// at), Danger (what cannot be undone).

///|
pub(all) enum Variant {
  Solid
  Soft
  Outline
  Ghost
  Danger
} derive(Eq, Show, Debug)

///|
/// What a button's look is given.
pub(all) struct ButtonState {
  label : String
  variant : Variant
  hovered : Bool
  pressed : Bool
  focus_shown : Bool
  disabled : Bool
  /// where it was last frame (for the focus ring)
  rect : (Double, Double, Double, Double)
}

///|
/// A button labelled `label` (its id `key`'s, else its label's): what happened to it (Response::clicked). `look`
/// draws it (button_look by default).
pub fn button(
  c : @ui.Ctx,
  label : String,
  key? : String = "",
  variant? : Variant = Solid,
  disabled? : Bool = false,
  w? : @ui.Size = Auto,
  look? : (@ui.Ctx, ButtonState) -> Unit = button_look,
) -> @ui.Response {
  let id = c.id(if key == "" { "\u{2}button/" + label } else { key })
  let r = c.interact(id, disabled~)
  let st = {
    label,
    variant,
    hovered: r.hovered,
    pressed: r.pressed,
    focus_shown: r.focus_shown,
    disabled,
    rect: r.rect,
  }
  let i = c.box(w~, id=if disabled { 0 } else { id }, fn() { look(c, st) })
  c.semantics(i, Button, id~, label~, disabled~, actions=if disabled { [] } else { [Activate] })
  r
}

///|
/// The default look (still.fail's buttons): a pill the theme's control height; Solid in the primary ink (lighter
/// pointed at), Outline on the page's ground with a line round it, Soft on the faint ground, Ghost its words alone,
/// Danger solid in the danger colour; faded when disabled, ringed when it has the focus by the keyboard.
pub fn button_look(c : @ui.Ctx, s : ButtonState) -> Unit {
  let t = c.theme()
  let live = !s.disabled
  let lit = if live && s.pressed {
    2.0
  } else if live && s.hovered {
    1.0
  } else {
    0.0
  }
  // a solid ground pointed at: a step towards the page
  let solid = fn(g : Int64) { blend(g, t.bg, 0.12 * lit) }
  let tint = if lit == 2.0 {
    doubled(t.hover)
  } else if lit == 1.0 {
    t.hover
  } else {
    0L
  }
  let (ground, ink, line) = match s.variant {
    Solid => (solid(t.primary), t.on_primary, 0L)
    Danger => (solid(t.danger), t.on_danger, 0L)
    Soft => (@ui.over(t.faint, tint), t.fg, 0L)
    Outline => (@ui.over(t.bg, tint), t.fg, t.border)
    Ghost => (tint, t.fg, 0L)
  }
  let h = t.control_h
  c.box(
    dir=Row,
    h=Px(h),
    padx=16.0,
    gap=6.0,
    align=ACenter,
    justify=JCenter,
    bg=ground,
    radius=h / 2.0,
    border=if line != 0L { 1.0 } else { 0.0 },
    border_color=line,
    opacity=if s.disabled { 0.45 } else { 1.0 },
    fn() {
      c.text(s.label, size=t.font, weight=500, color=ink, wrap=false) |> ignore
      focus_ring(c, s.focus_shown, s.rect, h / 2.0)
    },
  )
  |> ignore
}
