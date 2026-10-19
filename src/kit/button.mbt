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
/// The default look: the theme's control height and corner, its accent (or what the variant says), tinted when
/// pointed at and held, faded when disabled, ringed when it has the focus by the keyboard.
pub fn button_look(c : @ui.Ctx, s : ButtonState) -> Unit {
  let t = c.theme()
  let (ground, ink, line) = match s.variant {
    Solid => (t.accent, t.on_accent, 0L)
    Soft => (t.faint, t.fg, 0L)
    Outline => (0L, t.fg, t.border)
    Ghost => (0L, t.fg, 0L)
    Danger => (t.danger, t.on_danger, 0L)
  }
  let live = !s.disabled
  let bg = if ground == 0L {
    if live && s.pressed {
      doubled(t.hover)
    } else if live && s.hovered {
      t.hover
    } else {
      0L
    }
  } else {
    tinted(c, ground, live && s.hovered, live && s.pressed)
  }
  c.box(
    dir=Row,
    h=Px(t.control_h),
    padx=14.0,
    align=ACenter,
    justify=JCenter,
    bg~,
    radius=t.radius,
    border=if line != 0L { 1.0 } else { 0.0 },
    border_color=line,
    opacity=if s.disabled { disabled_alpha } else { 1.0 },
    fn() {
      c.text(s.label, size=t.font, weight=600, color=ink, wrap=false) |> ignore
      focus_ring(c, s.focus_shown, s.rect, t.radius)
    },
  )
  |> ignore
}
