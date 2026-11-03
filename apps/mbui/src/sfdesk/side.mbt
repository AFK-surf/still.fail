// A sidebar's top row (ember web/src/Sidebar.css.ts brand), the frame's; its rows are the library's (src/sf
// side_rows.mbt).

///|
/// The band's first row (Sidebar.css.ts brand): beside the rail only a margin (8); in a window with its buttons at the
/// left of the app's top row, their row (44), which drags the window; none in the closed bar: where
/// the block's move has got to (frame's --brand).
pub fn side_top(c : @ui.Ctx) -> Unit {
  let id = c.id("side/top")
  if @ui.window_inset() && !side_folded() {
    c.window_drag(id)
  }
  c.box(style=side_full.then(@ui.style(h=Fixed(wide.brand_h))), id~, fn() {  }) |> ignore
}

///|
/// The band's first row's height (side_top).
pub fn side_top_h() -> Double {
  wide.brand_h
}

///|
/// The room the chats' lists leave for the sidebar's top row: as side_top_h says, but on the block's way between open and
/// folded the taller end's all the way, so that their rows are not laid out again each frame (fold_bars).
fn list_top_h() -> Double {
  wide.list_top
}

///|
/// The room the chats' lists leave for the band over them: as tall as band_h, but on the block's way the open band's all
/// the way (list_top_h), the band itself moving as it goes over them.
fn list_band_h(src : Source, w : Workspace) -> Double {
  let band = wide.band
  wide.band = wide.list_band
  let h = band_h(src, w) - side_top_h() + list_top_h()
  wide.band = band
  h
}

///|
let side_top_inset : Double = 44.0

///|
let side_top_web : Double = 8.0

///|
// kept across runs: a value (no field of it changes)
let side_full : @ui.Style = @ui.css("w=Full")
