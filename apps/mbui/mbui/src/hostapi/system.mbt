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
//   under them too, from the screen's top to its foot, and `bars` says their `top` and `bottom` (a cutout at a side is
//   kept out of the view: `left` and `right` 0), the keyboard up as over another app.
// - `{"network": true}`: the device's default network became another one than the one before (Wi-Fi to mobile data,
//   back online after none: ConnectivityManager's default network callback, with ACCESS_NETWORK_STATE in the app's
//   manifest). Not for the first one seen.
// - `{"install": {"name": …, "allow": true}}`: a package handed to the installer (@hostapi.install_package) was not, as
//   the app may not install apps yet: the system's page for that leave was opened instead.
// - `{"install": {"name": …, "error": …}}`: a package handed to the system's installer could not be installed
//   (written, or the installer said it failed; the person's no is not a failure).
//
// Android's alone so far (dev.mbui.MainActivity); the other hosts post none. While the app is on screen, Android's
// also holds a Wi-Fi multicast lock when its manifest asks for CHANGE_WIFI_MULTICAST_STATE (Android drops the multicast
// that reaches the phone unless an app holds one: an mDNS lookup would hear no answer on the LAN).

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
  /// the device's default network became another one
  Network
  /// a package handed to the installer was not, the system's page for that leave opened instead
  InstallAllow(name~ : String)
  /// a package could not be installed
  InstallFailed(name~ : String, error~ : String)
} derive(Eq, Show)

///|
/// What a message on `system_channel` says, in this order: the link, over or not, the bars, shown, the installer,
/// the network (what is not well formed left out).
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
  out
}
