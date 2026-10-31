// How far the system bars reach in over the app's view (mbui's @ui.system_bars, as the host says them), as the shell
// keeps room for them: Android's app is edge to edge (its manifest's dev.mbui.edge), its pages running under the status
// bar and the navigation bar and each padded by them where Android's are (WindowInsets.statusBars, navigationBars);
// over another app too. 0 where the host lays the view out inside them, and in a Tester unless a test says them (t.post
// of the system's `bars`). The shell gives a page what of them is its to keep room for (PageFrame's `top` and `foot`).

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

///|
/// The status bar's height: what a page's top bar is padded by.
fn status_top() -> Double {
  let top = @ui.system_bars().top
  // a desktop's window with its buttons in the app's top row (macOS: its title bar the app's; Windows: the app's
  // own buttons, @sf.window_keys), a phone's page in it: the buttons' band over the page, as a status bar is
  if top == 0.0 && @sf.layout(@ui.current().window_size().0) is Small && @ui.window_inset() {
    window_band()
  } else {
    top
  }
}

///|
/// The band a window's buttons take at the top of a phone's page in it: macOS's title bar's 28; where they are the
/// app's (Windows'), a bar's line's (@sf.window_keys_band).
fn window_band() -> Double {
  if @ui.window_keys_own() {
    @sf.window_keys_band
  } else {
    dmax(window_band_mac, @ui.window_points_to_content(window_band_mac))
  }
}

///|
/// window_band for a node of the window's tree: as the frame began, followed (whether the window's buttons are the
/// app's, the zoom it is drawn at).
fn window_band_now() -> Double {
  if @ui.window_keys_own_now() {
    @sf.window_keys_band
  } else {
    dmax(window_band_mac, @ui.window_points_to_content_now(window_band_mac))
  }
}

///|
let window_band_mac : Double = 28.0

///|
/// The navigation bar's height (WindowInsets.navigationBars' bottom): what a page's foot is padded by. The soft keyboard
/// up, the view ends where it starts plus this, so what is padded by it sits on the keyboard
/// (keyboard.union(navigationBars)).
fn nav_foot() -> Double {
  @ui.system_bars().bottom
}

///|
/// What a page drawn over the whole window keeps room for (a screen's: under the status bar, over the navigation bar),
/// the shell's to say (PageFrame).
fn system_frame() -> PageFrame {
  { back: None, top: status_top(), foot: nav_foot(), named: false }
}
