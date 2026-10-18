// The still.fail core in an mbui window (scripts/mac.sh with MBUI_CORE=1): the signed-in accounts as the core's
// `accounts` topic has them, and 登录, which signs a person in through the system's browser session (@core.sign_in).
// MBUI_CORE_SIGNIN=1 presses 登录 once the accounts are read (scripted runs; with MBUI_AUTH_DRY=1 the browser
// session is made but not opened).
//
// Signing in on another device (the person's phone, this Mac's screen being locked): MBUI_AUTH_BEGIN=1 prints the
// login page's URL (AUTH_URL …), whose end is a loopback address that page on the phone can't open: the person sends
// back the address it shows, and MBUI_AUTH_COMPLETE=<that URL> finishes the sign-in (AUTH_DONE … or AUTH_FAILED …).
// Both runs on the same MBUI_CORE_DATA: the core keeps the sign-in it began there.
//
// MBUI_AUTH_LOGIN=1 (`scripts/mac.sh login`) signs in the way a command-line tool does (@host.browser_login, which
// knows nothing of still.fail): the app listens on 127.0.0.1, hands the login page to $BROWSER (else `open`), and
// exits 0 once the browser has come back and the sign-in is done (1 when it failed). A station's remote login runs it as its login command: the page goes
// to the person's phone, whose still.fail app relays the browser's way back here (ember docs/remote-login.md).
//
// On Android there is no browser session: 登录 signs in that same way, the page in a Custom Tab and the app back in
// front once the browser has come back (scripts/android.sh, APP=coredemo). MBUI_SECURE_TEST=1 round-trips secure.set,
// secure.get and secure.delete through the host's own answers to the core (the Android Keystore) and logs SECURE_TEST ….

///|
struct App {
  mut status : String
  mut signing_in : Bool
  mut auto_sign_in : Bool
  /// by hand: "begin", or the URL the browser was sent back to
  mut by_hand : String
  /// the shelf over the core's media module (shelf.mbt) rather than the accounts
  mut shelf : Bool
  /// the photos over it (photos.mbt)
  mut photos : Bool
  /// films and series (videos.mbt)
  mut videos : Bool
  /// MBUI_AUTH_LOGIN: sign in as a login command
  mut login : Bool
}

///|
let app : App = {
  status: "",
  signing_in: false,
  auto_sign_in: false,
  by_hand: "",
  shelf: false,
  photos: false,
  videos: false,
  login: false,
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
          app.status = "已登录：\{str(m.get("account"), "email")}"
          @host.log("AUTH_DONE " + str(m.get("account"), "email"))
        }
        Ok(_) => @host.log("AUTH_DONE")
        Err(e) => @host.log("AUTH_FAILED " + e.stringify())
      }
      @host.request_frame()
    })
  }
}

///|
/// A sign-in on the host's browser login (@host.browser_login, which knows nothing of still.fail): auth.begin with its
/// loopback address, the page to the browser, auth.complete with what comes back. MBUI_AUTH_LOGIN's login command
/// does it, and 登录 where there is no browser session (Android: a Custom Tab, the app back in front after it).
let login : Ref[(@host.BrowserLogin, (Result[String, String]) -> Unit)?] = Ref::new(
  None,
)

///|
/// Starts it; `done` gets the account's email, or why not.
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
      Err(_) => ""
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
  app.status = "正在等浏览器登录…"
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
let grey : Int64 = 0x8E8E93FFL

///|
fn str(v : Json?, key : String) -> String {
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
fn sign_in() -> Unit {
  if !@core.has_browser_session() {
    // Android: in the browser, back on a loopback address (a second press starts again: the tab may have been closed)
    if login.val is Some((l, _)) {
      l.end()
      login.val = None
    }
    app.signing_in = true
    app.status = "正在浏览器里登录…"
    loopback_sign_in(fn(r) {
      app.signing_in = false
      app.status = match r {
        Ok(email) => "已登录：\{email}"
        Err(why) => "没有登录：\{why}"
      }
      @host.log("SIGN_IN " + app.status)
      @host.request_frame()
    })
    return
  }
  if app.signing_in {
    return
  }
  app.signing_in = true
  app.status = "正在打开登录页…"
  @core.sign_in(fn(r) {
    app.signing_in = false
    app.status = match r {
      Ok(Object(m)) => "已登录：\{str(m.get("account"), "email")}"
      Ok(_) => "已登录"
      Err(e) => str(Some(e), "message")
    }
    @host.request_frame()
  })
}

///|
fn initial(s : String) -> String {
  for ch in s {
    return ch.to_string()
  }
  "?"
}

///|
fn account_row(c : @ui.Ctx, a : Json) -> Unit {
  let name = str(Some(a), "name")
  let email = str(Some(a), "email")
  c.row(gap=12.0, fn() {
    c.box(
      w=Px(36.0),
      h=Px(36.0),
      radius=18.0,
      bg=0x0A84FFFFL,
      align=ACenter,
      justify=JCenter,
      fn() {
        c.text(
          initial(if name.length() > 0 { name } else { email }),
          size=15.0,
          weight=600,
          color=0xFFFFFFFFL,
          wrap=false,
        )
        |> ignore
      },
    )
    |> ignore
    c.column(gap=2.0, fn() {
      c.text(name, size=15.0, weight=600, wrap=false) |> ignore
      c.text(email, size=13.0, color=grey, wrap=false) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// MBUI_CORE_DUMP=1 prints the accounts and each workspace's stations as the
/// core has them (DUMP accounts …, DUMP stations <workspace> …), for seeing
/// the topics' shapes.
let dumped : Map[String, Int] = {}

///|
fn dump_one(name : String, s : @core.Sub) -> Unit {
  if dumped.get(name) != Some(s.version) {
    dumped[name] = s.version
    match (s.value, s.error) {
      (Some(v), _) => @host.log("DUMP \{name} \{v.stringify()}")
      (_, Some(e)) => @host.log("DUMP \{name} error \{e.stringify()}")
      _ => ()
    }
  }
}

///|
fn dump(accounts : @core.Sub) -> Unit {
  if env("MBUI_CORE_DUMP") != "1" {
    return
  }
  dump_one("accounts", accounts)
  let ws = @core.subscribe("workspaces")
  dump_one("workspaces", ws)
  // each workspace's stations
  match ws.value {
    Some(Array(accounts)) =>
      for a in accounts {
        match a {
          Object(am) =>
            match am.get("workspaces") {
              Some(Array(list)) =>
                for w in list {
                  let id = str(Some(w), "id")
                  if id.length() > 0 {
                    let s = @core.subscribe("stations", params={
                      "scope": Json::string(id),
                    })
                    dump_one("stations " + id, s)
                    // reading it makes this device ask to be let in, when the
                    // workspace's security mode doesn't have it yet
                    let l = @core.subscribe("lock", params={
                      "workspace": Json::string(id),
                    })
                    dump_one("lock " + id, l)
                  }
                }
              _ => ()
            }
          _ => ()
        }
      }
    _ => ()
  }
}

///|
fn view(c : @ui.Ctx) -> Unit {
  if app.shelf {
    @shelf.view(c, core_source)
    return
  }
  if app.videos {
    @videos.view(c, video_source)
    return
  }
  if app.photos {
    @gallery.view(c, photo_source)
    flush_thumbs()
    return
  }
  let accounts = @core.subscribe("accounts")
  if app.auto_sign_in && accounts.value is Some(_) {
    app.auto_sign_in = false
    sign_in()
  }
  dump(accounts)
  if app.login && accounts.value is Some(_) {
    app.login = false
    login_command()
  }
  login_back()
  if app.by_hand.length() > 0 && accounts.value is Some(_) {
    let step = app.by_hand
    app.by_hand = ""
    by_hand(step)
  }
  c.box(w=Fill(1.0), h=Fill(1.0), bg=0xF5F5F7FFL, padx=28.0, pady=24.0, gap=18.0, fn() {
    // The title on a line of its own, the buttons under it: on a phone the five did not fit on one line (登录 went
    // off the screen's edge).
    c.row(gap=12.0, fn() {
      c.text("still.fail", size=22.0, weight=700, wrap=false) |> ignore
      c.text("内核 · " + engine_name(), size=13.0, color=grey, wrap=false)
      |> ignore
    })
    |> ignore
    c.row(gap=10.0, fn() {
      if c.button("书架", key="shelf", bg=0xE5E5EAFFL, color=0x1D1D1FFFL) {
        app.shelf = true
      }
      if c.button("照片", key="photos", bg=0xE5E5EAFFL, color=0x1D1D1FFFL) {
        app.photos = true
      }
      if c.button("影视", key="videos", bg=0xE5E5EAFFL, color=0x1D1D1FFFL) {
        app.videos = true
      }
      if c.button(if app.signing_in { "登录中…" } else { "登录" }, key="sign-in") {
        sign_in()
      }
    })
    |> ignore
    c.box(bg=0xFFFFFFFFL, radius=14.0, pad=16.0, gap=12.0, shadow=3.0, fn() {
      c.row(gap=8.0, fn() {
        c.text("账号", size=13.0, weight=600, color=grey, wrap=false) |> ignore
        c.spacer()
        c.text(
          "accounts · 第 \{accounts.version} 次更新",
          size=12.0,
          color=grey,
          wrap=false,
        )
        |> ignore
      })
      |> ignore
      match (accounts.value, accounts.error) {
        (Some(Array(list)), _) =>
          if list.length() == 0 {
            c.text("还没有登录的账号", size=15.0) |> ignore
            if !app.signing_in && c.button("登录 still.fail", key="sign-in-card") {
              sign_in()
            }
          } else {
            for a in list {
              account_row(c, a)
            }
          }
        (_, Some(e)) =>
          c.text("读不到账号：\{str(Some(e), "message")}", size=15.0, color=0xFF3B30FFL)
          |> ignore
        _ => c.text("正在读取…", size=15.0, color=grey) |> ignore
      }
    })
    |> ignore
    if app.status.length() > 0 {
      c.text(app.status, size=13.0, color=grey) |> ignore
    }
    match @core.fatal() {
      Some(why) =>
        c.text("内核停了：\{why}", size=13.0, color=0xFF3B30FFL) |> ignore
      None => ()
    }
  })
  |> ignore
}

///|
fn main {
  // The redraw hook: whatever the core changed is drawn in the next frame.
  @core.on_change(fn() { @host.request_frame() })
  if !@core.start() {
    app.status = "这个版本没有链接内核（MBUI_CORE=1 scripts/mac.sh build）"
  }
  app.auto_sign_in = env("MBUI_CORE_SIGNIN") == "1"
  app.shelf = env("MBUI_SHELF") == "1"
  app.photos = env("MBUI_PHOTOS") == "1"
  app.videos = env("MBUI_VIDEOS") == "1"
  app.login = env("MBUI_AUTH_LOGIN") == "1"
  app.by_hand = if env("MBUI_AUTH_BEGIN") == "1" {
    "begin"
  } else {
    env("MBUI_AUTH_COMPLETE")
  }
  if env("MBUI_SECURE_TEST") == "1" && secure_test() == 0 {
    @host.log("SECURE_TEST: not on this host")
  }
  @ui.run("still.fail · mbui", view)
}
