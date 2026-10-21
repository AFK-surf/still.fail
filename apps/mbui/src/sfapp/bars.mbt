// How far the system bars reach in over the app's view (the host's `bars`, @hostapi.system_channel): Android's app is
// edge to edge (its manifest's dev.mbui.edge), its pages running under the status bar and the navigation bar and each
// padded by them where Android's are (WindowInsets.statusBars, navigationBars); over another app too. 0 where the host
// lays the view out inside them, and in a Tester unless a test says them (t.post of the system's `bars`).

///|
/// The status bar's height over the view's top (WindowInsets.statusBars' top).
let bars_top : Ref[Double] = Ref(0.0)

///|
/// The navigation bar's over its foot (WindowInsets.navigationBars' bottom): the soft keyboard up, the view ends where
/// it starts plus this, so what is padded by it sits on the keyboard (keyboard.union(navigationBars)).
let bars_foot : Ref[Double] = Ref(0.0)

///|
/// The status bar's height: what a page's top bar is padded by.
fn status_top() -> Double {
  bars_top.val
}

///|
/// The navigation bar's height: what a page's foot is padded by.
fn nav_foot() -> Double {
  bars_foot.val
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
