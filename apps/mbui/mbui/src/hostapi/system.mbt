// What the system says of the app between frames, posted on the channel `system_channel` (mbui's queue: post.h), for
// the app's handler (`@ui.on_message(@hostapi.system_channel, …)`, set before the first frame: what comes with no handler
// is left), each a JSON object. Posted, it is on a run's tape as any message is (MSG lines: a Tester given the tape
// hands it to the app again at its frame, src/ui/messages.mbt):
//
// - `{"shown": {"away": ms}}`: the app is on screen again after `ms` off it (Android: the activity started again after
//   it stopped, the process's own count of how long: SystemClock.elapsedRealtime, deep sleep counted). Not as it
//   first starts.
// - `{"link": url}`: the system opened the app with one of its links (Android: an http(s) ACTION_VIEW its manifest
//   takes, a link of the app's own tapped in another app, a verified App Link), the app started by it or brought back.
// - `{"over": true|false}`: the app is shown over another app (Android: an OverActivity of the app's, a share sheet
//   over the app something is shared from, its view drawing only what the app puts there), or in its own window again;
//   said as it changes. Over one, the app ends it with @hostapi.over_done. Native views open (@ui's video, page, site)
//   go along to whichever of the two is shown, where they were placed. Over one, the app's view takes the whole window,
//   under the system bars too: what it draws over the app under it (a scrim) from the screen's top, a sheet down to its
//   foot, with `bars` saying how far the bars reach in.
// - `{"bars": {"top": …, "bottom": …, "left": …, "right": …}}`: over another app, how far the system bars (the status
//   bar, the navigation bar, a display cutout) reach in over the app's view from each edge, in points; said as the
//   view is laid out over another app and as they change. The soft keyboard up, the view ends where the keyboard
//   starts plus `bottom`, so a sheet padded by `bottom` sits on the keyboard. In the app's own window the view is
//   inside the bars and nothing is said, unless the app lays itself out round them (its manifest's
//   `<meta-data android:name="dev.mbui.edge" android:value="true">`, as Android's apps edge to edge): then its view is
//   under them too, from the screen's top to its foot, and `bars` says their `top` and `bottom` (Android keeps a cutout
//   at a side out of the view: `left` and `right` 0; iOS's view runs from side to side too, and says them: an iPhone
//   Duo's outer screen has its status bar down its right side, iOS 27.1), the keyboard up as over another app.
// - `{"size_class": {"width": "compact"|"regular", "height": "compact"|"regular"}}`: how much room the app's window
//   has, as the system classes it (not its size in points: what the platform says such a window is, the app's layout
//   chosen by that and nothing it works out from a width of its own). iOS: the window's trait collection
//   (horizontalSizeClass, verticalSizeClass; regular both ways on an opened iPhone Duo, an iPad's whole screen).
//   Android: the window's WindowSizeClass as Jetpack's WindowManager has it (androidx.window.core.layout: compact under
//   600 dp wide or 480 dp high, medium and expanded said as regular). Said as the window is first laid out and as
//   either changes (a foldable opened or closed, the window split, the device turned).
// - `{"fold": {"hinge": "none"|"closed"|"half"|"open", "divisions": [{"x": …, "y": …, "w": …, "h": …}, …]}}`: the
//   device's hinge as the system says it, and where its fold divides the app's view now, in the view's points (a
//   region content should not run across: the fold and the margins round it). iOS 27.1 on: UIHingeInteraction's
//   status (closed, partiallyOpen as `half`, fullyOpen as `open`) and the view's active division regions
//   (reservedRegionsOfKind: divisionRegionKind). Android: Jetpack WindowManager's FoldingFeature in the window
//   (HALF_OPENED as `half`, FLAT as `open`, its bounds a division while it separates the window). `none`: no fold in
//   the window (the outer screen of a folded phone, a phone with no hinge). Said as it changes.
// - `{"network": true}`: the device's default network became another one than the one before (Wi-Fi to mobile data,
//   back online after none: ConnectivityManager's default network callback, with ACCESS_NETWORK_STATE in the app's
//   manifest). Not for the first one seen.
// - `{"install": {"name": …, "allow": true}}`: a package handed to the installer (@hostapi.install_package) was not, as
//   the app may not install apps yet: the system's page for that leave was opened instead.
// - `{"install": {"name": …, "error": …}}`: a package handed to the system's installer could not be installed
//   (written, or the installer said it failed; the person's no is not a failure).
// - `{"menu": action}`: one of the app's items in the menu bar chosen (@hostapi.menu_setup: an item's `action`).
//
// Android's (dev.mbui.MainActivity), iOS's (ios_app.m: `shown`, `link`, `network`, `size_class`, `fold`, `bars`
// where its Info.plist's MBUIEdge lays it out edge to edge, as Android's manifest's dev.mbui.edge) and macOS's (mac_app.m:
// `shown` as its window comes back after it was closed and as the Mac wakes from sleep, `network`, `menu`, `link` of
// the schemes its Info.plist names); Windows's
// posts none. While the app is
// on screen, Android's also holds a Wi-Fi multicast lock when its manifest asks for CHANGE_WIFI_MULTICAST_STATE (Android
// drops the multicast that reaches the phone unless an app holds one: an mDNS lookup would hear no answer on the LAN).

///|
/// The channel the system's say is posted on.
pub let system_channel : String = "system"

///|
/// One thing the system said (a message on `system_channel` says one or more: see above).
pub(all) enum SystemSaid {
  /// on screen again after `away` ms off it
  Shown(away~ : Double)
  /// opened with one of the app's links
  Link(String)
  /// shown over another app (true), or in its own window again (false)
  Over(Bool)
  /// how far the system bars reach in over the app's view from each edge, in points
  Bars(top~ : Double, bottom~ : Double, left~ : Double, right~ : Double)
  /// how much room the window has, as the system classes it (width, height)
  SizeClasses(width~ : SizeClass, height~ : SizeClass)
  /// the hinge, and where the fold divides the view (x, y, w, h in the view's points)
  Fold(hinge~ : Hinge, divisions~ : Array[(Double, Double, Double, Double)])
  /// the device's default network became another one
  Network
  /// a package handed to the installer was not, the system's page for that leave opened instead
  InstallAllow(name~ : String)
  /// a package could not be installed
  InstallFailed(name~ : String, error~ : String)
  /// one of the app's items in the menu bar chosen (menu_setup's `action`)
  Menu(String)
} derive(Eq, Show)

///|
/// A window's room one way, as the system classes it (iOS's UIUserInterfaceSizeClass; Android's WindowSizeClass, its
/// medium and expanded both regular).
pub(all) enum SizeClass {
  Compact
  Regular
} derive(Eq, Show)

///|
/// A device's hinge as the system says it.
pub(all) enum Hinge {
  /// no fold in the window (no hinge, or the outer screen of a folded phone)
  NoHinge
  /// closed
  Closed
  /// partly open (a book held open, a laptop's pose)
  Half
  /// open flat, as far as it goes
  Open
} derive(Eq, Show)

///|
/// What a message on `system_channel` says, in this order: the link, over or not, the bars, the size classes, the
/// fold, shown, the installer, the network, the menu bar (what is not well formed left out).
pub fn system_said(json : String) -> Array[SystemSaid] {
  let out : Array[SystemSaid] = []
  let v = @json.parse(json) catch { _ => return out }
  guard v is Object(m) else { return out }
  let number = fn(o : Map[String, Json], k : String) {
    match o.get(k) {
      Some(Number(n, ..)) => n
      _ => 0.0
    }
  }
  let text = fn(o : Map[String, Json], k : String) {
    match o.get(k) {
      Some(String(s)) => s
      _ => ""
    }
  }
  match m.get("link") {
    Some(String(url)) => out.push(Link(url))
    _ => ()
  }
  match m.get("over") {
    Some(True) => out.push(Over(true))
    Some(False) => out.push(Over(false))
    _ => ()
  }
  match m.get("bars") {
    Some(Object(b)) =>
      out.push(Bars(top=number(b, "top"), bottom=number(b, "bottom"), left=number(b, "left"), right=number(b, "right")))
    _ => ()
  }
  match m.get("size_class") {
    Some(Object(k)) => {
      let kind = fn(w : String) { if text(k, w) == "regular" { Regular } else { Compact } }
      out.push(SizeClasses(width=kind("width"), height=kind("height")))
    }
    _ => ()
  }
  match m.get("fold") {
    Some(Object(f)) => {
      let hinge = match text(f, "hinge") {
        "closed" => Closed
        "half" => Half
        "open" => Open
        _ => NoHinge
      }
      let divisions = []
      if f.get("divisions") is Some(Array(list)) {
        for d in list {
          if d is Object(r) {
            divisions.push((number(r, "x"), number(r, "y"), number(r, "w"), number(r, "h")))
          }
        }
      }
      out.push(Fold(hinge~, divisions~))
    }
    _ => ()
  }
  match m.get("shown") {
    Some(Object(s)) => out.push(Shown(away=number(s, "away")))
    _ => ()
  }
  match m.get("install") {
    Some(Object(i)) if i.get("allow") is Some(True) => out.push(InstallAllow(name=text(i, "name")))
    Some(Object(i)) => out.push(InstallFailed(name=text(i, "name"), error=text(i, "error")))
    _ => ()
  }
  if m.get("network") is Some(True) {
    out.push(Network)
  }
  match m.get("menu") {
    Some(String(action)) => out.push(Menu(action))
    _ => ()
  }
  out
}
