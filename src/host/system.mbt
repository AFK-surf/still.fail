// What the system says of the app between frames, posted on the channel `system_channel` (mbui's queue: post.h), for
// the app's handler (`@ui.on_message(@host.system_channel, …)`, set before the first frame: what comes with no handler
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
//   said as it changes. Over one, the app ends it with @host.over_done. Native views open (@ui's video, page, site)
//   go along to whichever of the two is shown, where they were placed. Over one, the app's view takes the whole window,
//   under the system bars too: what it draws over the app under it (a scrim) from the screen's top, a sheet down to its
//   foot, with `bars` saying how far the bars reach in.
// - `{"bars": {"top": …, "bottom": …, "left": …, "right": …}}`: over another app, how far the system bars (the status
//   bar, the navigation bar, a display cutout) reach in over the app's view from each edge, in points; said as the
//   view is laid out over another app and as they change. The soft keyboard up, the view ends where the keyboard
//   starts plus `bottom`, so a sheet padded by `bottom` sits on the keyboard. In the app's own window the view is
//   inside the bars and nothing is said.
// - `{"network": true}`: the device's default network became another one than the one before (Wi-Fi to mobile data,
//   back online after none: ConnectivityManager's default network callback, with ACCESS_NETWORK_STATE in the app's
//   manifest). Not for the first one seen.
// - `{"install": {"name": …, "allow": true}}`: a package handed to the installer (@host.install_package) was not, as
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
