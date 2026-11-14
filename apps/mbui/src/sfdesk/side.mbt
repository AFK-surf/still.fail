// A sidebar's top row (still.fail web/src/Sidebar.css.ts brand), the frame's; its rows are the library's (src/sf
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
/// The band's first row (side_top's) as a node in `parent`: `brand()` tall (where the block's move has got: the frame's
/// --brand), the window's buttons' row where they are in the app's top row, which drags the window while the sidebar is
/// open.
fn side_top_node(parent : @view.View, brand : () -> Double) -> Unit {
  parent.box(fn(top) {
    top.height(By(fn() { Some(brand()) })).moves_window(By(fn() { @ui.window_inset_now() && !side_folded() })) |> ignore
  })
  |> ignore
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
/// What the lists' room over them is worked out from, as the frame last said it (its top row's height, the room left for
/// it, the band's held, whether on the tape, the band's where it is now: list_room_told): read by the lists' nodes,
/// laid out again as it changes, not as they happen to be built again.
let lists_room : @signals.Signal[(Double, Double, Double, Bool, Double)] = @signals.signal((0.0, 0.0, 0.0, false, 0.0), same=fn(a, b) {
  a == b
})

///|
/// The lists' room told as the frame has just worked it out (lists_room).
fn list_room_told() -> Unit {
  lists_room.set((wide.brand_h, wide.list_top, wide.list_band, wide.tape.get(), wide.band))
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
