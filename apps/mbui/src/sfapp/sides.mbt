// What the system has at the window's sides (@ui.system_bars `left` and `right`: iOS's view runs from side to side,
// and an iPhone Duo's outer screen has its status bar down its right side, iOS 27.1; a phone on its side its cutout):
// the app's pages beside it, the page's paper under it (a top bar has no line along its foot to carry under it: its
// frost over the paper alone is the paper). Turned sideways for a film or a screen over all of it
// (@hostapi.turned_sideways) it is over the whole window, its black to the screen's edges as a film app's is, what
// floats over it keeping clear of the sides itself (@sf.sides_clear).

///|
/// `body` (the app) beside what the system has at the window's sides, the page's paper under that; `body` alone when
/// there is nothing there.
fn beside_sides(c : @ui.Ctx, body : () -> Unit) -> Unit {
  // (the system's own bars as this frame wants them: the wide frame's tabs, else none: sfdesk's rail_native.mbt)
  // (where the window is a tree holding the old views, its root keeps the room beside the bars: app_tree)
  @sfdesk.nav_frame(fn() { if @ui.old_islands_around() { body() } else { beside_bars(c, body) } })
}

///|
/// The room kept at the window's left and right beside the system's bars there (none beside the system's tab bar, the
/// frame from side to side under it: what is pressed at a page's top and foot keeps clear of it, @sf.native_clear; none
/// on a phone turned on its side for a film).
fn sides_room() -> (Double, Double) {
  let b = @ui.system_bars()
  let (left, right) = (dmax(0.0, b.left), dmax(0.0, b.right))
  if (@sf.native_on() && left == 0.0) || (left == 0.0 && right == 0.0) || @hostapi.turned_sideways() {
    (0.0, 0.0)
  } else {
    (left, right)
  }
}

///|
fn beside_bars(c : @ui.Ctx, body : () -> Unit) -> Unit {
  let (left, right) = sides_room()
  if left == 0.0 && right == 0.0 {
    body()
    return
  }
  let w = dmax(0.0, c.width - left - right)
  // (beside the cards across of the wide frame, their ground: what the column of the system's glass is over)
  c.box(style=if @sfdesk.on_cards() { sides_row_cards } else { sides_row }, fn() {
    c.box(style=@ui.style(w=Fixed(left), h=Full), fn() {  }) |> ignore
    c.box(style=@ui.style(w=Fixed(w), h=Full, clip=true), fn() { c.sized(w, c.height, body) }) |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let sides_row : @ui.Style = @ui.css("row w=Full h=Full bg=Bg")

///|
// kept across runs: a value (no field of it changes)
let sides_row_cards : @ui.Style = @ui.css("row w=Full h=Full bg=Sidebar")
