// Reusable picture and film components. Their sizes are layout points; the renderer's output scale remains separate.

///|
/// A frame around content: its fill and edge, corner, and the space between the edge and the content.
pub(all) struct FrameStyle {
  fill : Int64
  edge : Int64
  edge_width : Double
  radius : Double
  inset : Double
}

///|
/// A rounded frame. Its content is cut to the outside edge and the edge is drawn last, even when content fills it.
pub fn frame(
  c : @ui.Ctx,
  w : Double,
  h : Double,
  style : FrameStyle,
  body : () -> Unit,
) -> Int {
  c.box(
    w=Px(w),
    h=Px(h),
    pad=style.inset,
    bg=style.fill,
    radius=style.radius,
    border=style.edge_width,
    border_color=style.edge,
    clip=true,
    body,
  )
}
