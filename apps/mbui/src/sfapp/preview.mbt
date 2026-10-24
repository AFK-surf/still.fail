// A file open over the whole screen (the viewer, one for every layout: sfbase viewer.mbt, viewer_frame.mbt).

///|
/// The viewer over the pages, if one is open: call after the pages are drawn.
fn preview(c : @ui.Ctx, src : Source) -> Unit {
  file_viewer(c, src)
}
