// How far the system bars reach in over the app's view (mbui's @ui.system_bars, as the host says them): Android's app
// is edge to edge (its manifest's dev.mbui.edge), its pages running under the status bar and the navigation bar and
// each padded by them where Android's are (WindowInsets.statusBars, navigationBars); over another app too. 0 where the
// host lays the view out inside them, and in a Tester unless a test says them (t.post of the system's `bars`).

///|
/// The status bar's height: what a page's top bar is padded by.
fn status_top() -> Double {
  @ui.system_bars().top
}

///|
/// The navigation bar's height (WindowInsets.navigationBars' bottom): what a page's foot is padded by. The soft keyboard
/// up, the view ends where it starts plus this, so what is padded by it sits on the keyboard
/// (keyboard.union(navigationBars)).
fn nav_foot() -> Double {
  @ui.system_bars().bottom
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
let bars_fill : @ui.Style = @ui.style(w=Full, h=Full)

///|
/// What is between them: the room they leave.
// kept across runs: a value (no field of it changes)
let bars_body : @ui.Style = @ui.style(w=Full, h=@sf.grow)
