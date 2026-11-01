// What is drawn, as data (mbui/paint: shapes, lines, glass, corners), taken in here by name: what the old views and the
// app say of it as ever (@ui.Shape, @ui.Line, @ui.Glass, @ui.CornerOf, @ui.concentric …), one type with what the window's
// tree says.

pub using @paint {
  type Shape,
  type Line,
  line,
  arc,
  shape_of,
  vector_shapes,
  dashed_outlines,
  type Glass,
  type CornerOf,
  type CornerFit,
  type CornerRoots,
  smooth_scale,
  smooth_exponent,
  smoothness,
  concentric,
  concentric_out,
  smooth_round,
  round_like,
  round_like_out,
  smooth_middle,
  corner_middle,
  sd_corner,
  sd_clip,
  sd_box,
  det_pow,
}
