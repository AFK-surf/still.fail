// The still.fail core as an app of it starts it, and signing in to still.fail over it (src/coredemo, src/stillfail).
// The core itself is linked into the app (its native stub includes apple_engine.m or android_engine.c from here);
// this is what the app's MoonBit does with it.
//
// Signing in: where the host has a browser session (Apple's ASWebAuthenticationSession), through it
// (@core.sign_in); elsewhere (Android) as a command-line tool does (@host.browser_login, which knows nothing of
// still.fail): auth.begin with a loopback address, the page in the browser (a Custom Tab), auth.complete with what
// comes back.
//
// The environment's say, read once at `start`:
// - MBUI_CORE_SIGNIN=1 presses 登录 once the accounts are read (scripted runs; with MBUI_AUTH_DRY=1 the browser
//   session is made but not opened).
// - MBUI_AUTH_BEGIN=1 prints the login page's URL (AUTH_URL …), whose end is a loopback address that page on another
//   device (the person's phone, this Mac's screen being locked) can't open: the person sends back the address it shows,
//   and MBUI_AUTH_COMPLETE=<that URL> finishes the sign-in (AUTH_DONE … or AUTH_FAILED …). Both runs on the same
//   MBUI_CORE_DATA: the core keeps the sign-in it began there.
// - MBUI_CLOUD=<origin>: still.fail cloud elsewhere than https://app.still.fail (a local one, scripts/e2e-local.sh).
// - MBUI_CORE_ACCOUNT=<JSON> (or MBUI_CORE_ACCOUNT_B64, base64): signed out, that account taken as signed in (the
//   core's `migrate`: an account as a page kept it, {sub, email, name, picture, access, refresh, accessExpires}), as a
//   local cloud's mock login hands it out (/__dev/account?user=alice). Only with MBUI_CLOUD: never on the real cloud.
// - MBUI_AUTH_LOGIN=1 (`scripts/mac.sh login`) signs in as a login command: the app listens on 127.0.0.1, hands the
//   login page to $BROWSER (else `open`), and exits 0 once the browser has come back and the sign-in is done (1 when
//   it failed). A station's remote login runs it as its login command (ember docs/remote-login.md).

///|
/// How signing in stands: what to say of it, and whether one is under way.
pub(all) struct SignIn {
  mut status : String
  mut busy : Bool
  /// MBUI_CORE_SIGNIN: press 登录 once the accounts are read
  mut auto : Bool
  /// MBUI_AUTH_LOGIN: sign in as a login command
  mut login : Bool
  /// by hand: "begin", or the URL the browser was sent back to
  mut by_hand : String
  /// MBUI_CORE_ACCOUNT: the account to take in once the accounts are read and none is signed in
  mut account : String
}

///|
pub let state : SignIn = {
  status: "",
  busy: false,
  auto: false,
  login: false,
  by_hand: "",
  account: "",
}

///|
/// Starts the core, its changes drawn in the next frame, and reads what the environment asks of signing in. False
/// when this build has no core linked in (the web's, a fixture's).
pub fn start() -> Bool {
  // what the core says is posted to mbui's queue (core_native.c), which hands it here as the next frame begins
  @ui.on_message("core", @core.receive)
  // a screen is settled only once what it asked of the core is in (mbui's effect.mb outside)
  @core.track(what => @ui.runtime().outside_start(what), t => @ui.runtime().outside_end(t))
  let cloud = @ui.env("MBUI_CLOUD")
  let started = if cloud != "" {
    @host.log("still.fail cloud at " + cloud)
    @core.start(cloud~)
  } else {
    @core.start()
  }
  if started {
    // (a run on a clock of its own: the core's timers on it too; not a replay's, which has no engine)
    own_core_clock()
    begin()
  }
  started
}

///|
/// What follows the core's start, its engine's or a replay's (src/sfreplay): the device told (`client.device`), and
/// what the environment asks of signing in read (`started_by`): a local cloud's run's account (MBUI_CORE_ACCOUNT)
/// taken in as signed in (`migrate`) once the accounts are read.
pub fn begin() -> Unit {
  state.account = if @ui.env("MBUI_CLOUD") != "" { env_text("MBUI_CORE_ACCOUNT") } else { "" }
  tell_device()
  state.auto = @ui.env("MBUI_CORE_SIGNIN") == "1"
  state.login = @ui.env("MBUI_AUTH_LOGIN") == "1"
  state.by_hand = if @ui.env("MBUI_AUTH_BEGIN") == "1" {
    "begin"
  } else {
    @ui.env("MBUI_AUTH_COMPLETE")
  }
}

///|
/// What the device is, to the core (`client.device`, as still.fail's apps tell it): the name the people who approve it
/// in a workspace's safe mode see (and a sign-in's device) is still.fail mbui's, not still.fail's own app's: "still.fail
/// mbui Android · <maker model>" (the model CoreHost.java puts in MBUI_DEVICE_MODEL), "still.fail mbui 桌面版 · macOS".
fn tell_device() -> Unit {
  let facts : Map[String, Json] = { "client": Json::string("still.fail mbui") }
  match @ui.platform() {
    2 => {
      facts["app"] = Json::string("android")
      facts["model"] = Json::string(@ui.env("MBUI_DEVICE_MODEL"))
    }
    0 => {
      facts["app"] = Json::string("desktop")
      facts["userAgent"] = Json::string("Macintosh; Mac OS X")
    }
    3 => {
      facts["app"] = Json::string("desktop")
      facts["userAgent"] = Json::string("Windows")
    }
    // (iOS and the browser: no kind of the core's for them yet)
    _ => return
  }
  let version = @ui.app_version()
  if version > 0 {
    facts["build"] = Json::string("0.1." + version.to_string())
  }
  @core.call("client.device", params=Json::object(facts))
}

///|
/// Each frame, with the `accounts` topic: what the environment asked once the accounts are read, and a browser login
/// come back.
pub fn frame(accounts : @core.Sub) -> Unit {
  // (by the accounts the core says and the environment's: the same in each build of the frame)
  if accounts.value is Some(list) {
    if state.account != "" {
      let account = state.account
      state.account = ""
      if list is Array([]) {
        take_account(account)
      }
    }
    if state.auto {
      state.auto = false
      sign_in()
    }
    if state.login {
      state.login = false
      login_command()
    }
    if state.by_hand.length() > 0 {
      let step = state.by_hand
      state.by_hand = ""
      by_hand(step)
    }
  }
  login_back()
}

///|
/// MBUI_CORE_ACCOUNT: the account taken in as signed in (`migrate`).
fn take_account(account : String) -> Unit {
  let parsed = @json.parse(account) catch {
    _ => {
      @host.log("MBUI_CORE_ACCOUNT is not JSON")
      return
    }
  }
  let params : Map[String, Json] = { "accounts": Json::array([parsed]) }
  @core.call("migrate", params=Json::object(params), on_done=fn(r) {
    match r {
      Ok(_) => @host.log("SIGN_IN taken in: " + str(Some(parsed), "email"))
      Err(e) => @host.log("SIGN_IN migrate failed: " + e.stringify())
    }
  })
}

///|
/// A string field of an object (`""` when there is none).
pub fn str(v : Json?, key : String) -> String {
  match v {
    Some(Object(m)) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
/// Where the cloud sends the browser back: a loopback address it accepts for apps (nothing listens there; the
/// address is what we want).
let loopback = "http://127.0.0.1:43025/oauth/callback"

///|
fn by_hand(step : String) -> Unit {
  if step == "begin" {
    let params : Map[String, Json] = {
      "redirect_uri": Json::string(loopback),
      "return_to": Json::string("/"),
    }
    @core.call("auth.begin", params=Json::object(params), on_done=fn(r) {
      match r {
        Ok(ok) => @host.log("AUTH_URL " + str(Some(ok), "url"))
        Err(e) => @host.log("AUTH_FAILED " + e.stringify())
      }
    })
  } else {
    let params : Map[String, Json] = { "query": Json::string(@core.query_of(step)) }
    @core.call("auth.complete", params=Json::object(params), on_done=fn(r) {
      match r {
        Ok(Object(m)) => {
          state.status = "已登录：\{str(m.get("account"), "email")}"
          @host.log("AUTH_DONE " + str(m.get("account"), "email"))
        }
        Ok(_) => @host.log("AUTH_DONE")
        Err(e) => @host.log("AUTH_FAILED " + e.stringify())
      }
    })
  }
}

///|
/// The browser login waiting to come back, and who to tell.
let login : Ref[(@host.BrowserLogin, (Result[String, String]) -> Unit)?] = Ref::new(
  None,
)

///|
/// A sign-in on the host's browser login: `done` gets the account's email, or why not.
fn loopback_sign_in(done : (Result[String, String]) -> Unit) -> Unit {
  guard @host.browser_login(path="/oauth/callback") is Some(l) else {
    done(Err("this host cannot take a browser coming back"))
    return
  }
  let params : Map[String, Json] = {
    "redirect_uri": Json::string(l.redirect),
    "return_to": Json::string("/"),
    "device_name": Json::string("mbui"),
  }
  @core.call("auth.begin", params=Json::object(params), on_done=fn(r) {
    let url = match r {
      Ok(ok) => str(Some(ok), "url")
      Err(e) => {
        @host.log("auth.begin failed: " + e.stringify())
        ""
      }
    }
    if url == "" {
      l.end()
      done(Err("auth.begin gave no page"))
      return
    }
    @host.log("Sign in to still.fail in a browser: " + url)
    if !l.open(url) {
      @host.log("No browser opened: open the address above")
    }
    login.val = Some((l, done))
  })
}

///|
/// Each frame while it waits: the browser back, the sign-in finished with what it brought.
fn login_back() -> Unit {
  guard login.val is Some((l, done)) else { return }
  guard l.back() is Some(back) else { return }
  login.val = None
  l.end()
  // (not the query: its code is the sign-in's)
  @host.log("Back from the browser at " + l.redirect + ": auth.complete")
  let params : Map[String, Json] = { "query": Json::string(@core.query_of(back)) }
  @core.call("auth.complete", params=Json::object(params), on_done=fn(r) {
    match r {
      Ok(ok) => {
        let email = match ok {
          Object(m) => str(m.get("account"), "email")
          _ => ""
        }
        done(Ok(email))
      }
      Err(e) => {
        @host.log("auth.complete failed: " + e.stringify())
        done(Err(str(Some(e), "message")))
      }
    }
  })
}

///|
/// MBUI_AUTH_LOGIN: the sign-in as a login command. What it prints is for whoever runs it (a station's login reads the
/// page's address from $BROWSER, or from here); its exit code says how it went.
fn login_command() -> Unit {
  state.status = "正在等浏览器登录…"
  loopback_sign_in(fn(r) {
    match r {
      Ok(email) => {
        @host.log("Signed in to still.fail as " + email)
        @host.exit(0)
      }
      Err(why) => {
        @host.log("Sign-in failed: " + why)
        @host.exit(1)
      }
    }
  })
}

///|
/// 登录: through the host's browser session where it has one, else the browser login (a second press starts that
/// again: the tab may have been closed).
pub fn sign_in() -> Unit {
  if !@core.has_browser_session() {
    if login.val is Some((l, _)) {
      l.end()
      login.val = None
    }
    state.busy = true
    state.status = "正在浏览器里登录…"
    loopback_sign_in(fn(r) {
      state.busy = false
      state.status = match r {
        Ok(email) => "已登录：\{email}"
        Err(why) => "没有登录：\{why}"
      }
      @host.log("SIGN_IN " + state.status)
    })
    return
  }
  if state.busy {
    return
  }
  state.busy = true
  state.status = "正在打开登录页…"
  @core.sign_in(fn(r) {
    state.busy = false
    state.status = match r {
      Ok(Object(m)) => "已登录：\{str(m.get("account"), "email")}"
      Ok(_) => "已登录"
      Err(e) => str(Some(e), "message")
    }
  })
}

///|
/// What the app's start reads of its environment (begin): what a run's trace keeps it was started with, for a
/// replay's app to be started with the same (src/stillfail's CORETRACE env, src/sfreplay's Flow::start).
pub let started_by : Array[String] = [
  "MBUI_CLOUD", "MBUI_CORE_ACCOUNT", "MBUI_CORE_SIGNIN", "MBUI_AUTH_LOGIN", "MBUI_AUTH_BEGIN", "MBUI_AUTH_COMPLETE",
]

///|
/// An environment variable (a Tester's, as its test gives it, the host's else), or the same name with `_B64` given as
/// base64 ("" when neither is set): @host.env_text, through @ui.env.
pub fn env_text(name : String) -> String {
  let plain = @ui.env(name)
  if plain != "" {
    plain
  } else {
    @host.from_base64(@ui.env(name + "_B64"))
  }
}
