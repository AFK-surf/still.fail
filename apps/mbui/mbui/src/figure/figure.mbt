// A small canvas for social graphics. The frame and every panel are mbui boxes: their corners and their nesting are
// drawn by the same renderer as an app's, not by another graphics library's rounded rectangles.

///|
/// A fixed-size canvas. The drawing closure may place boxes and words with `panel` and `words`, and may use any other
/// mbui views or app components inside it.
pub fn canvas(c : @ui.Ctx, w : Double, h : Double, ground : Int64, body : () -> Unit) -> Unit {
  c.box(w=Px(w), h=Px(h), bg=ground, body) |> ignore
}

///|
/// A panel at (`x`, `y`) within its parent, with mbui's smooth corner of `radius`. Its children are positioned from
/// this panel's own top left. A zero ground leaves it transparent.
pub fn panel(
  c : @ui.Ctx,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  ground : Int64,
  radius : Double,
  body : () -> Unit,
) -> Unit {
  c.box(left=x, top=y, w=Px(w), h=Px(h), bg=ground, radius~, body) |> ignore
}

///|
/// A panel as wide as `w`, whose height follows its contents. Like `panel`, its children are positioned within it.
pub fn auto_panel(
  c : @ui.Ctx,
  x : Double,
  y : Double,
  w : Double,
  ground : Int64,
  radius : Double,
  body : () -> Unit,
) -> Unit {
  c.box(left=x, top=y, w=Px(w), bg=ground, radius~, body) |> ignore
}

///|
/// Words at (`x`, `y`) within their parent. With a positive `width` they wrap within it; otherwise they stay on one
/// line. The caller chooses ink and size so graphics can have their own visual hierarchy without changing app themes.
pub fn words(
  c : @ui.Ctx,
  x : Double,
  y : Double,
  s : String,
  size : Double,
  ink : Int64,
  weight? : Int = 400,
  width? : Double = 0.0,
  line? : Double = 0.0,
) -> Unit {
  c.box(left=x, top=y, w=if width > 0.0 { Px(width) } else { Auto }, fn() {
    c.text(s, size~, weight~, color=ink, wrap=width > 0.0, line=if line > 0.0 { line } else { size * 1.25 }) |> ignore
  })
  |> ignore
}
