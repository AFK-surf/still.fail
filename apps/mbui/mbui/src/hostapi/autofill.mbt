// The system's autofill, for an app that fills a login it does not hold itself (still.fail's: a page of a station's
// browser seen and driven from the app, ember docs/remote-screens.md): Android's (android_host.c, dev.mbui.Autofills).
// The app says the site the login is for; the host puts a login form of that site before the system's autofill service
// (1Password, Google's, whichever the person chose), which offers its logins there itself; the one the person picks
// comes back here. Nothing of it is kept by the host once taken. None elsewhere (`autofill` is false there).

///|
/// Whether this host has an autofill service to ask (Android, with one chosen in its settings).
pub fn autofill() -> Bool {
  af_able()
}

///|
/// Asks the autofill service for a login of `host` (the site's host): it offers the person its logins there; false
/// where none can be asked.
pub fn autofill_ask(host : String) -> Bool {
  af_ask(host) != 0
}

///|
/// The login the person picked, once: its site's host (the one asked for), account and password; None until then.
/// A frame is asked for as one comes, so a view can look each frame.
pub fn autofill_take() -> (String, String, String)? {
  (polled.val)()
  let s = af_take()
  if s == "" {
    return None
  }
  // (from the host: the host asked for, the account and the password, each ended by a unit separator)
  let parts = s.split("\u{1f}").map(fn(p) { p.to_owned() }).to_array()
  Some((parts.get(0).unwrap_or(""), parts.get(1).unwrap_or(""), parts.get(2).unwrap_or("")))
}

///|
/// Lets go of the ask: the service's offer withdrawn, the form gone, nothing it gave kept.
pub fn autofill_end() -> Unit {
  af_end()
}
