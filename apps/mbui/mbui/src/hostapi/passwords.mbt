// This device's password manager, for an app that fills a login it does not hold itself (still.fail's: a page of a
// station's browser seen and driven from the app, ember docs/remote-screens.md): 1Password, through its command-line
// tool `op` signed in by its desktop app (1Password › Settings › Developer › Integrate with 1Password CLI), which asks
// the person (Touch ID, Windows Hello) in its own window. The host only runs `op` with the arguments given and gives
// back what it said; what to ask it and what its answers mean is here. macOS (apple_passwords.m) and Windows
// (win_passwords.c); none elsewhere (`passwords` is false there).

///|
/// A run of `op` under way (`op_run`).
pub struct OpRun {
  priv id : Int
}

///|
/// How a run of `op` ended: its exit code (-1: it could not be started, or there is no `op` here), its standard output
/// and its error output.
pub(all) struct OpDone {
  code : Int
  out : String
  err : String
}

///|
/// Whether this host can ask a password manager at all (macOS and Windows; whether `op` is there is said by a run).
pub fn passwords() -> Bool {
  pw_able()
}

///|
/// Runs `op` with `args` (its arguments, none of them the shell's), without a window of its own; None where the host
/// runs none.
pub fn op_run(args : Array[String]) -> OpRun? {
  // (to the host: the arguments one after another, each ended by a unit separator, U+001F)
  let id = pw_run(args.iter().map(fn(a) { a + "\u{1f}" }).join(""))
  if id <= 0 {
    None
  } else {
    Some({ id, })
  }
}

///|
/// How it ended, once it has; None until then. A frame is asked for as it ends, so a view can look each frame.
pub fn OpRun::done(self : OpRun) -> OpDone? {
  // (the host's own state, come with no event: what reads it as it is built, built each frame while it does)
  (polled.val)()
  let s = pw_out(self.id)
  if s == "" {
    return None
  }
  // (from the host: its exit code, its output and its error output, each ended by a unit separator)
  let parts = s.split("\u{1f}").map(fn(p) { p.to_owned() }).to_array()
  let code = @string.parse_int(parts.get(0).unwrap_or("-1")[:]) catch { _ => -1 }
  Some({ code, out: parts.get(1).unwrap_or(""), err: parts.get(2).unwrap_or("") })
}

///|
/// Forgets it (its output, and the process if it still runs).
pub fn OpRun::end(self : OpRun) -> Unit {
  pw_end(self.id)
}

///|
/// A login of the password manager: its id there, its title, its account (not secret: the person picks by it).
pub(all) struct PasswordLogin {
  id : String
  title : String
  username : String
} derive(Eq, Show, Debug)

///|
/// Whether `href` (a login's website, as the password manager keeps it: an address, or a bare host) is `host` or a
/// host under it, or one `host` is under (a login for google.com fills accounts.google.com).
pub fn login_for_host(href : String, host : String) -> Bool {
  let h = host.to_lower()
  let mut rest = href.to_lower()
  match rest.find("://") {
    Some(i) => rest = rest.view(start_offset=i + 3).to_owned()
    None => ()
  }
  let mut end = rest.length()
  for c in ["/", "?", "#", ":"] {
    match rest.find(c) {
      Some(i) => if i < end { end = i }
      None => ()
    }
  }
  let site = rest.view(end_offset=end).to_owned()
  site != "" && (site == h || h.has_suffix("." + site) || site.has_suffix("." + h))
}

///|
/// The logins of `op item list --categories Login --format json`'s answer whose websites are for `host`, in its order.
pub fn logins_for(listed : String, host : String) -> Array[PasswordLogin] {
  let out : Array[PasswordLogin] = []
  let v = @json.parse(listed) catch { _ => return out }
  guard v is Array(items) else { return out }
  for it in items {
    guard it is Object(o) else { continue }
    let hrefs : Array[String] = []
    match o.get("urls") {
      Some(Array(us)) =>
        for u in us {
          match u {
            Object(uo) =>
              match uo.get("href") {
                Some(String(h)) => hrefs.push(h)
                _ => ()
              }
            _ => ()
          }
        }
      _ => ()
    }
    guard hrefs.iter().any(fn(h) { login_for_host(h, host) }) else { continue }
    let str = fn(k : String) {
      match o.get(k) {
        Some(String(v)) => v
        _ => ""
      }
    }
    let username = match o.get("additional_information") {
      Some(String(v)) => v
      _ => ""
    }
    out.push({ id: str("id"), title: str("title"), username })
  }
  out
}

///|
/// The account and password of `op item get <id> --fields label=username,label=password --reveal --format json`'s
/// answer (fields by their label or purpose); either may be "".
pub fn login_fields(got : String) -> (String, String) {
  let mut user = ""
  let mut pass = ""
  let v = @json.parse(got) catch { _ => return (user, pass) }
  let fields = match v {
    Array(a) => a
    Object(_) as one => [one]
    _ => []
  }
  for f in fields {
    guard f is Object(o) else { continue }
    let str = fn(k : String) {
      match o.get(k) {
        Some(String(v)) => v
        _ => ""
      }
    }
    let what = str("purpose").to_lower() + " " + str("label").to_lower() + " " + str("id").to_lower()
    if what.contains("password") && pass == "" {
      pass = str("value")
    } else if what.contains("username") && user == "" {
      user = str("value")
    }
  }
  (user, pass)
}
