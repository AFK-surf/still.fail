// A checkbox (Radix's Checkbox): off, on, or neither (some of what it stands for is on), the value the view's. A
// tap, a click, Space with the focus (not Enter, as WAI-ARIA has it), the Activate action turn it on, or off when it
// is on; neither turns on.

///|
/// What a checkbox's look is given.
pub(all) struct CheckboxState {
  check : @ui.Check
  hovered : Bool
  pressed : Bool
  focus_shown : Bool
  disabled : Bool
  rect : (Double, Double, Double, Double)
}

///|
/// A checkbox at `checked` (its id `key`'s), named `label` for the semantics tree. What it became, and what happened
/// to it.
pub fn checkbox(
  c : @ui.Ctx,
  key : String,
  checked : @ui.Check,
  label? : String = "",
  disabled? : Bool = false,
  look? : (@ui.Ctx, CheckboxState) -> Unit = checkbox_look,
) -> @ui.Changed[@ui.Check] {
  let id = c.id(key)
  let r = c.interact(id, disabled~, keys=@ui.press_space)
  let now : @ui.Check = if r.clicked {
    match checked {
      On => Off
      _ => On
    }
  } else {
    checked
  }
  let st = {
    check: now,
    hovered: r.hovered,
    pressed: r.pressed,
    focus_shown: r.focus_shown,
    disabled,
    rect: r.rect,
  }
  let i = c.box(id=if disabled { 0 } else { id }, fn() { look(c, st) })
  c.semantics(i, Checkbox, id~, label~, check=now, disabled~, actions=pick(disabled, [], [Activate]))
  { value: now, response: r.changed_to(now != checked) }
}

///|
/// A checkbox's look by its sizes: `size` square, its corner `radius`, on in `on_color` (the theme's accent) with
/// its mark in `mark` (its on_accent), off edged in `edge` (its border).
pub fn checkbox_look_of(
  size? : Double = 20.0,
  radius? : Double = 6.0,
  on_color? : Int64,
  mark? : Int64,
  edge? : Int64,
) -> (@ui.Ctx, CheckboxState) -> Unit {
  fn(c, s) {
    let t = c.theme()
    let on = s.check != Off
    let fill = on_color.unwrap_or(t.accent)
    let ground = if on { fill } else { t.surface }
    c.box(
      w=Px(size),
      h=Px(size),
      radius~,
      bg=tinted(c, ground, s.hovered && !s.disabled, s.pressed && !s.disabled),
      border=if on { 0.0 } else { 1.5 },
      border_color=edge.unwrap_or(t.border),
      align=ACenter,
      justify=JCenter,
      opacity=if s.disabled { disabled_alpha } else { 1.0 },
      fn() {
        match s.check {
          On =>
            c.text("✓", size=size * 0.7, weight=700, color=mark.unwrap_or(t.on_accent), wrap=false, line=size)
            |> ignore
          Mixed =>
            c.box(w=Px(size * 0.5), h=Px(2.0), radius=1.0, bg=mark.unwrap_or(t.on_accent), fn() {  })
            |> ignore
          Off => ()
        }
        focus_ring(c, s.focus_shown, s.rect, radius)
      },
    )
    |> ignore
  }
}

///|
/// The default look: 20 square, its corner 6, filled with the accent when on.
pub let checkbox_look : (@ui.Ctx, CheckboxState) -> Unit = checkbox_look_of()
