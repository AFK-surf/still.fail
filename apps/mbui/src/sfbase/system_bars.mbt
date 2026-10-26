// How far the system bars reach in over the app's view (mbui's @ui.system_bars, as the host says them): Android's app
// is edge to edge (its manifest's dev.mbui.edge), its pages running under the status bar and the navigation bar and
// each padded by them where Android's are (WindowInsets.statusBars, navigationBars); over another app too. 0 where the
// host lays the view out inside them, and in a Tester unless a test says them (t.post of the system's `bars`).

///|
/// The status bar's height: what a page's top bar is padded by.
pub fn status_top() -> Double {
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
pub fn window_band() -> Double {
  if @ui.window_keys_own() {
    @sf.window_keys_band
  } else {
    window_band_mac
  }
}

///|
let window_band_mac : Double = 28.0

///|
/// The navigation bar's height (WindowInsets.navigationBars' bottom): what a page's foot is padded by. The soft keyboard
/// up, the view ends where it starts plus this, so what is padded by it sits on the keyboard
/// (keyboard.union(navigationBars)).
pub fn nav_foot() -> Double {
  @ui.system_bars().bottom
}
