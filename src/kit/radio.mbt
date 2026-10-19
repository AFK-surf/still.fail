// A radio group (Radix's RadioGroup): one of its items checked, the value the view's. A roving group: Tab lands on
// the checked item (else the first), the arrows move along it and check what they reach, Space checks the focused
// one (not Enter, as WAI-ARIA has it); a tap or a click checks one, as the Activate action does.

///|
/// What a radio item's look is given.
pub(all) struct RadioState {
  label : String
  on : Bool
  hovered : Bool
  pressed : Bool
  focus_shown : Bool
  disabled : Bool
  rect : (Double, Double, Double, Double)
}

///|
/// A radio group (see the file's head) of `items`, the one of `value` checked (its id `key`'s), named `label` for
/// the semantics tree; one under the other unless `orientation` is Horizontal. What is checked now, and what happened.
pub fn radio_group(
  c : @ui.Ctx,
  key : String,
  items : Array[Item],
  value : String,
  orientation? : @ui.Orientation = Vertical,
  wrap? : Bool = true,
  disabled? : Bool = false,
  label? : String = "",
  gap? : Double = 10.0,
  look? : (@ui.Ctx, RadioState) -> Unit = radio_look,
) -> @ui.Changed[String] {
  let id = c.id(key)
  let mut now = value
  let mut any = @ui.Response::none()
  let current = match items.search_by(fn(it) { it.value == value }) {
    Some(k) => part_id(id, k)
    None => 0
  }
  let gi = c.box(dir=if orientation == Horizontal { Row } else { Column }, gap~, fn() {
    c.roving(key, orientation~, wrap~, current~, fn() {
      for k, it in items {
        let iid = part_id(id, k)
        let off = disabled || it.disabled
        let r = c.interact(iid, disabled=off, keys=@ui.press_space)
        if r.clicked || (!off && c.focus_roved_to(iid)) {
          any = r
          now = it.value
          c.roving_prefer(iid)
        }
        let st = {
          label: it.label,
          on: now == it.value,
          hovered: r.hovered,
          pressed: r.pressed,
          focus_shown: r.focus_shown,
          disabled: off,
          rect: r.rect,
        }
        let i = c.box(id=if off { 0 } else { iid }, fn() { look(c, st) })
        c.semantics(i, Radio, id=iid, label=it.label, check=if st.on { On } else { Off }, disabled=off, actions=pick(
          off,
          [],
          [Activate],
        ))
      }
    })
  })
  c.semantics(gi, RadioGroup, label~, disabled~)
  { value: now, response: { ..any, id, changed: now != value } }
}

///|
/// A radio item's look by its sizes: a circle `size` across, edged in `edge` (the theme's border) when off, filled
/// with `on_color` (its accent) round a dot of `dot` (its on_accent) when on; its words after it.
pub fn radio_look_of(
  size? : Double = 20.0,
  on_color? : Int64,
  dot? : Int64,
  edge? : Int64,
) -> (@ui.Ctx, RadioState) -> Unit {
  fn(c, s) {
    let t = c.theme()
    c.box(
      dir=Row,
      gap=8.0,
      align=ACenter,
      opacity=if s.disabled { disabled_alpha } else { 1.0 },
      fn() {
        let ground = if s.on { on_color.unwrap_or(t.accent) } else { t.surface }
        c.box(
          w=Px(size),
          h=Px(size),
          radius=size / 2.0,
          bg=tinted(c, ground, s.hovered && !s.disabled, s.pressed && !s.disabled),
          border=if s.on { 0.0 } else { 1.5 },
          border_color=edge.unwrap_or(t.border),
          align=ACenter,
          justify=JCenter,
          fn() {
            if s.on {
              let d = size * 0.4
              c.box(w=Px(d), h=Px(d), radius=d / 2.0, bg=dot.unwrap_or(t.on_accent), fn() {  }) |> ignore
            }
          },
        )
        |> ignore
        c.text(s.label, size=t.font, wrap=false) |> ignore
        focus_ring(c, s.focus_shown, s.rect, 6.0)
      },
    )
    |> ignore
  }
}

///|
/// The default look: a 20 circle, filled with the accent round a dot when checked, its words beside it.
pub let radio_look : (@ui.Ctx, RadioState) -> Unit = radio_look_of()
