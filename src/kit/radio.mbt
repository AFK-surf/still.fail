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
/// A radio item's look by its sizes (still.fail's): a circle `size` across edged in `edge` (the theme's control edge;
/// darker pointed at), when chosen edged in `on_color` (its words' colour) round a dot `dot` across of it; its words
/// after it.
pub fn radio_look_of(
  size? : Double = 18.0,
  dot? : Double = 8.0,
  on_color? : Int64,
  edge? : Int64,
) -> (@ui.Ctx, RadioState) -> Unit {
  fn(c, s) {
    let t = c.theme()
    let ink = on_color.unwrap_or(t.fg)
    let line = if s.on {
      ink
    } else if s.hovered && !s.disabled {
      t.field_hover
    } else {
      edge.unwrap_or(t.border)
    }
    c.box(dir=Row, gap=8.0, align=ACenter, opacity=if s.disabled { 0.45 } else { 1.0 }, fn() {
      c.box(
        w=Px(size),
        h=Px(size),
        radius=size / 2.0,
        bg=t.bg,
        border=1.5,
        border_color=line,
        align=ACenter,
        justify=JCenter,
        fn() {
          if s.on {
            c.box(w=Px(dot), h=Px(dot), radius=dot / 2.0, bg=ink, fn() {  }) |> ignore
          }
        },
      )
      |> ignore
      c.text(s.label, size=t.font, wrap=false) |> ignore
      focus_ring(c, s.focus_shown, s.rect, 6.0)
    })
    |> ignore
  }
}

///|
/// The default look: an 18 circle, a dot in the words' colour when chosen, its words beside it.
pub let radio_look : (@ui.Ctx, RadioState) -> Unit = radio_look_of()
