// A sign-in in the browser that comes back to this machine, the way command-line tools sign in (OAuth's loopback
// redirect, RFC 8252 §7.3), for any app and any service: the host listens on 127.0.0.1 at a port the system picks, the
// app makes its login page with `redirect` as where to come back, `open` hands it to the browser, and `back` gives
// the address the browser came back to (with its query) once it has. The host answers that browser with a page saying
// it can be closed, and takes nothing else (another path, another host name, a second time). Checking what came back
// (its state) and exchanging it are the app's: the host knows nothing of the service.
//
// Opening is $BROWSER, else `open`, on macOS, so a station's remote login (ember docs/remote-login.md) can run such an
// app as its login command: it takes the page from BROWSER, sees the loopback `redirect_uri`, and the person's phone
// relays the browser's way back to this process. The system opens it on iOS. Not on Android, Windows or the web yet
// (`browser_login` is None there).

///|
/// A sign-in under way in the browser.
pub struct BrowserLogin {
  priv id : Int
  /// Where the browser is to come back to: http://127.0.0.1:<port><path>.
  redirect : String
}

///|
/// Listens for the browser coming back to `path` (with its query): None when this host cannot (or no port is free).
pub fn browser_login(path? : String = "/callback") -> BrowserLogin? {
  let id = bl_start(path)
  if id == 0 {
    return None
  }
  Some({ id, redirect: "http://127.0.0.1:\{bl_port(id)}" + path })
}

///|
/// Opens the login page `url` in the browser; false when no browser could be started (the page can still be opened by
/// hand: `back` waits all the same).
pub fn BrowserLogin::open(self : BrowserLogin, url : String) -> Bool {
  bl_open(self.id, url) != 0
}

///|
/// The address the browser came back to (`redirect` with the service's query), once it has; None until then. A frame
/// is asked for as it comes, so a view can look each frame.
pub fn BrowserLogin::back(self : BrowserLogin) -> String? {
  let s = bl_back(self.id)
  if s.length() == 0 {
    None
  } else {
    Some(s)
  }
}

///|
/// Stops listening (when the sign-in is given up) and forgets it.
pub fn BrowserLogin::end(self : BrowserLogin) -> Unit {
  bl_end(self.id)
}
