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
  c.box(style=side_full.then(@ui.style(h=Fixed(wide.brand_h.get()))), id~, fn() {  }) |> ignore
}

///|
/// The band's first row's height (side_top).
pub fn side_top_h() -> Double {
  wide.brand_h.get()
}

///|
let side_top_inset : Double = 44.0

///|
let side_top_web : Double = 8.0

///|
// kept across runs: a value (no field of it changes)
let side_full : @ui.Style = @ui.css("w=Full")
