// What the phone's frame draws inside the system bars (`within_bars`): how high they reach in, sfbase's (status_top,
// nav_foot: system_bars.mbt).

///|
/// Whether the pages have the bottom bar under them: the phone's pages do (laid out Small), the wide frame's not.
fn has_bar() -> Bool {
  !@sfdesk.is_wide(@ui.current())
}

///|
/// What the bottom bar takes at the pages' foot (over the navigation bar): its room with it, nothing without.
fn bar_room_now() -> Double {
  if has_bar() {
    bar_room
  } else {
    0.0
  }
}

///|
/// A top bar's least height, the status bar's and its own (bar_h) as one length (TopGlassBar, Chat.kt BarFrame: the
/// status bar's padding, then heightIn(min = TopBarHeight)).
fn top_bar_h() -> Double {
  status_top() + bar_h
}

///|
/// `body` inside the bars: under the status bar and over the navigation bar (windowInsetsPadding(systemBars)), each
/// where it is asked for, on `ground` (which goes on under the bars).
fn within_bars(
  c : @ui.Ctx,
  body : () -> Unit,
  top? : Bool = true,
  foot? : Bool = true,
  ground? : @ui.Style = bars_fill,
) -> Unit {
  let pt = if top { status_top() } else { 0.0 }
  let pb = if foot { nav_foot() } else { 0.0 }
  c.box(style=ground, fn() {
    bar_room_box(c, pt)
    c.box(style=bars_body, fn() { body() }) |> ignore
    bar_room_box(c, pb)
  })
  |> ignore
}

///|
/// A bar's room, `h` high (none when it is 0).
fn bar_room_box(c : @ui.Ctx, h : Double) -> Unit {
  if h > 0.0 {
    c.box(style=@ui.style(w=Full, h=Fixed(h)), fn() {  }) |> ignore
  }
}

///|
/// What is inside the bars: all of the window.
// kept across runs: a value (no field of it changes)
let bars_fill : @ui.Style = @ui.css("w=Full h=Full")

///|
/// What is between them: the room they leave.
// kept across runs: a value (no field of it changes)
let bars_body : @ui.Style = @ui.style(w=Full, h=@sf.grow)
