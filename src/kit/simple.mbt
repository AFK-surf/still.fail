// The simplest of Radix's parts: Label (words that press, or focus, the control they name), Separator (a line,
// read out unless it only decorates), AspectRatio (what it holds at a width over height), AccessibleIcon (an icon
// hidden from the semantics tree, its label in it), VisuallyHidden (words in the tree, not drawn).

///|
/// Words naming a control (Radix's Label): a press on them presses the control `for_id` (a checkbox, a switch: the
/// Activate action), or with `field` gives it the focus (a field). In the theme's words unless `size`, `color`.
pub fn label(
  c : @ui.Ctx,
  text : String,
  for_id? : Int = 0,
  field? : Bool = false,
  size? : Double,
  weight? : Int = 500,
  color? : Int64,
) -> @ui.Response {
  let t = c.theme()
  let id = if for_id == 0 { 0 } else { c.id("\u{2}label/" + text) }
  let r = c.interact(id, focusable=false)
  if r.clicked && for_id != 0 {
    c.ask_action(for_id, if field { Focus } else { Activate })
  }
  c.box(id~, fn() {
    c.text(text, size=size.unwrap_or(t.font), weight~, color=color.unwrap_or(t.fg), wrap=false) |> ignore
  })
  |> ignore
  r
}

///|
/// A line across (or, `vertical`, down) what holds it (Radix's Separator): in the theme's line colour unless `color`,
/// `thickness` thick; `decorative`: hidden from the semantics tree.
pub fn separator(
  c : @ui.Ctx,
  vertical? : Bool = false,
  decorative? : Bool = false,
  thickness? : Double = 1.0,
  color? : Int64,
) -> Unit {
  let t = c.theme()
  let i = c.box(
    w=if vertical { Px(thickness) } else { Fill(1.0) },
    h=if vertical { Fill(1.0) } else { Px(thickness) },
    bg=color.unwrap_or(t.line),
    fn() {  },
  )
  if !decorative {
    c.semantics(i, Separator, value=if vertical { "vertical" } else { "horizontal" })
  }
}

///|
/// What `body` builds, as wide as what holds it and `ratio` (width over height) as tall (Radix's AspectRatio),
/// cut to that.
pub fn aspect_ratio(c : @ui.Ctx, ratio : Double, body : () -> Unit) -> Int {
  c.box(w=Fill(1.0), aspect=ratio, clip=true, body)
}

///|
/// An icon that means something (Radix's AccessibleIcon): what `body` draws hidden from the semantics tree, `label`
/// in it as an image's.
pub fn accessible_icon(c : @ui.Ctx, label : String, body : () -> Unit) -> Unit {
  c.hidden_from_semantics(body)
  c.visually_hidden(label, role=Image)
}

///|
/// Words read out and found by tests, not drawn (Radix's VisuallyHidden).
pub fn visually_hidden(c : @ui.Ctx, text : String) -> Unit {
  c.visually_hidden(text)
}
