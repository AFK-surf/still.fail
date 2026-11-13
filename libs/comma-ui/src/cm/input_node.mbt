// Comma's input (clients/packages/ui input/InputBase) as a node of the window's tree: a line to type in on the page's
// ground, rounded, its edge the primary border with the xs shadow; while it is written in, its edge the brand's, two
// wide, and the brand's ring round it; the error's while `invalid`; faded on the disabled ground while `disabled`. What
// it edits is mbui's field (ui's tree_field.mbt: its words, the input method, what is picked, undo, the focus, Enter).

///|
/// Comma's input in `parent` editing `field`, of `size` (Sm 36 high, Md 40): `placeholder` while empty; `label` what a
/// screen reader calls it; Enter gives its words to `submitted`; `invalid` while what is in it is wrong; `disabled`
/// while it cannot be written in. The field's node (what the focus is given to).
#callsite(autofill(loc))
pub fn input_node(
  parent : @view.View,
  field : @ui.Field,
  placeholder? : String = "",
  label? : String = "",
  size? : ControlSize = ControlMd,
  invalid? : () -> Bool = fn() { false },
  disabled? : () -> Bool = fn() { false },
  submitted? : (String) -> Unit = fn(_) {  },
  loc~ : SourceLoc,
) -> @view.View {
  let (height, px) = if size == ControlSm { (36.0, space_lg) } else { (40.0, 14.0) }
  let typed : Ref[@view.View?] = Ref(None)
  parent.box(made_for=loc, fn(f) {
    f
    .row(Is(true))
    .lines_up(Is(Some(Middle)))
    .min_height(Is(Some(height)))
    .padding(Is((px, space_md, px, space_md)))
    .radius(Is(radius_md))
    .ground(By(fn() {
      let c = colors()
      if disabled() {
        c.bg_disabled
      } else {
        c.bg_primary
      }
    }))
    .shadow(By(fn() { if is_dark() { shadow_dark_xs } else { shadow_xs } }))
    .alpha(By(fn() { if disabled() { 0.6 } else { 1.0 } }))
    |> ignore
    let t = @ui.field(
      f,
      field,
      placeholder~,
      label~,
      max_lines=1,
      enter_sends=true,
      submitted~,
      size_by=fn() { type_small.size },
      line=type_small.line,
      colors_by=fn() {
        let c = colors()
        (if disabled() { c.text_disabled } else { c.text_primary }, c.text_placeholder, c.fg_brand_primary)
      },
    )
    .grow(Is(1.0))
    .basis(Is(Some(0.0)))
    .shrink(Is(1.0))
    typed.val = Some(t)
    let writing = fn() { t.focused() && !disabled() }
    f
    .edge(By(fn() {
      let c = colors()
      match (invalid(), writing()) {
        (true, true) => (2.0, c.border_error_solid)
        (true, false) => (1.0, c.border_error)
        (false, true) => (2.0, c.border_brand)
        (false, false) => (1.0, c.border_primary)
      }
    }))
    |> ignore
    // (written in: the brand's ring round it, or the error's)
    f.show(writing, fn(r) {
      r
      .over(Is(true))
      .margin(Is((-ring_w, -ring_w, -ring_w, -ring_w)))
      .radius(Is(radius_md + ring_w))
      .edge(By(fn() { (ring_w, if invalid() { focus_error.1 } else { focus_brand.1 }) }))
      |> ignore
    })
  })
  |> ignore
  match typed.val {
    Some(t) => t
    None => @halt.saying("cm.input_node: its field was not made")
  }
}
