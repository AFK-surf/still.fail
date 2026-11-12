// The system's autofill, for an app that fills a login it does not hold itself (still.fail's: a page of a station's
// browser seen and driven from the app): Android's (android_host.c, dev.mbui.Autofills).
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
  if af_ask(host) == 0 {
    return false
  }
  (outside_waits.val)(autofill_told, 1, autofill_took)
  true
}

///|
/// The kind the host's word that the person picked a login is told by (set_outside, id 1: one ask at a time; ui's
/// hostcall.mbt `outside_autofill`, the hosts' OUTSIDE_AUTOFILL).
let autofill_told : Int = 16

///|
/// The login the person picked, as the host's word said it came (autofill_took), till the ask is let go of.
// kept across runs: emptied by autofill_end, and as each Tester starts (autofill_forget)
let autofill_said : @signals.Signal[(String, String, String)?] = @signals.signal(None)

///|
/// What the host keeps of the person's pick taken, as its word comes, in place of one before (the person may pick
/// again in the same offer: one for another site than the one asked is not what the app takes). Waited on still, till
/// the ask is let go of (autofill_end): false, whatever it took.
fn autofill_took() -> Bool {
  let s = af_take()
  if s == "" {
    return false
  }
  // (from the host: the host asked for, the account and the password, each ended by a unit separator)
  let parts = s.split("\u{1f}").map(fn(p) { p.to_owned() }).to_array()
  autofill_said.set(Some((parts.get(0).unwrap_or(""), parts.get(1).unwrap_or(""), parts.get(2).unwrap_or(""))))
  false
}

///|
/// The login the person picked: its site's host (the one asked for), account and password; None until the host's
/// word says one came, and once the ask is let go of (autofill_end). A signal's read: what reads it (a node's binding
/// or `reacts`, an old view's build) is told as it comes, and reads the same however often.
pub fn autofill_take() -> (String, String, String)? {
  autofill_said.get()
}

///|
/// Lets go of the ask: the service's offer withdrawn, the form gone, nothing it gave kept.
pub fn autofill_end() -> Unit {
  (outside_lets_go.val)(autofill_told, 1)
  autofill_said.set(None)
  af_end()
}

///|
/// What the person picked forgotten, nothing asked of the host: a run starting anew (ui's Tester).
pub fn autofill_forget() -> Unit {
  autofill_said.set(None)
}
