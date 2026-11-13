// Comma's icons (Central Icons, icons_made.mbt) as nodes of the window's tree: each layer's path, in a 24 grid, drawn
// `side` across; a stroke as round-capped lines at Comma's one stroke width on the screen (iconStrokeWidth, 1.5 for a
// glyph's own 2; its finer strokes in proportion), whatever the icon's size, as Comma's non-scaling stroke draws it; a
// fill as its outline filled; a cut in what the icon lies on.

///|
/// One layer of an icon: its path data in a 24 grid, filled or stroked (how wide in the grid), and whether it is a cut
/// (what Central's mask holds back) rather than the icon.
pub(all) struct IconLayer {
  d : String
  fill : Bool
  width : Double
  cut : Bool
}

///|
/// Comma's stroke for a glyph's 2 (its tokens' iconStrokeWidth), in points on the screen at any size.
pub let icon_stroke : Double = 1.5

///|
/// Comma's icon `layers` in `parent`, `side` across, in `ink` (`ground`: what a cut shows, the colour it lies on).
/// Read out as an image named `label` where it says something ("" none: a part's own mark); `stroke`: its glyph's 2
/// drawn so wide (a checkbox's tick: 1.67). The node.
#callsite(autofill(loc))
pub fn icon_node(
  parent : @view.View,
  layers : Array[IconLayer],
  side : Double,
  ink : () -> Int64,
  ground? : () -> Int64 = fn() { 0L },
  label? : String = "",
  stroke? : Double = icon_stroke,
  loc~ : SourceLoc,
) -> @view.View {
  let k = side / 24.0
  parent.box(made_for=loc, fn(b) {
    b.width(Is(Some(side))).height(Is(Some(side))).shrink(Is(0.0)) |> ignore
    if label != "" {
      b.says(Is(Some(@view.said(Image, label~)))) |> ignore
    }
    // (strokes: each subpath a round-capped line, its width the screen's whatever the size)
    b
    .lines(By(fn() {
      let scale = b.pixel_scale()
      let out : Array[@paint.Line] = []
      for l in layers {
        if l.fill {
          continue
        }
        let color = if l.cut { ground() } else { ink() }
        for sub in @pixels.svg_path(l.d, k * scale) {
          let (pts, closed) = sub
          let points : Array[(Double, Double)] = []
          let mut j = 0
          while j + 1 < pts.length() {
            points.push((pts[j] * k, pts[j + 1] * k))
            j += 2
          }
          if closed && points.length() > 0 {
            points.push(points[0])
          }
          out.push(@ui.line(points, width=stroke * l.width / 2.0, color~))
        }
      }
      out
    }))
    .shapes(By(fn() {
      let scale = b.pixel_scale()
      let out : Array[@paint.Shape] = []
      for l in layers {
        if !l.fill {
          continue
        }
        let outlines = @pixels.svg_path(l.d, k * scale).map(fn(sub) {
          let (pts, closed) = sub
          (pts.map(fn(v) { v * k }), closed)
        })
        out.push(@paint.shape_of(outlines, fill=if l.cut { ground() } else { ink() }, even_odd=true))
      }
      out
    }))
    |> ignore
  })
}
