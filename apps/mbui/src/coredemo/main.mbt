// The still.fail core in an mbui window (scripts/mac.sh with MBUI_CORE=1): the signed-in accounts as the core's
// `accounts` topic has them, and 登录, which signs a person in (src/sfcore: through the system's browser session, or
// on Android in a Custom Tab back on a loopback address; MBUI_CORE_SIGNIN, MBUI_AUTH_BEGIN/COMPLETE and
// MBUI_AUTH_LOGIN as it says). MBUI_SECURE_TEST=1 round-trips secure.set, secure.get and secure.delete through the
// host's own answers to the core (the Android Keystore) and logs SECURE_TEST ….

///|
struct App {
  mut status : String
  /// the shelf over the core's media module (shelf.mbt) rather than the accounts
  mut shelf : Bool
  /// the photos over it (photos.mbt)
  mut photos : Bool
  /// films and series (videos.mbt)
  mut videos : Bool
}

///|
let app : App = { status: "", shelf: false, photos: false, videos: false }

///|
let grey : Int64 = 0x8E8E93FFL

///|
fn str(v : Json?, key : String) -> String {
  @sfcore.str(v, key)
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
  @sfcore.frame(accounts)
  dump(accounts)
  let signing_in = @sfcore.state.busy
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
      if c.button(if signing_in { "登录中…" } else { "登录" }, key="sign-in") {
        @sfcore.sign_in()
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
            if !signing_in && c.button("登录 still.fail", key="sign-in-card") {
              @sfcore.sign_in()
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
    let status = if app.status.length() > 0 {
      app.status
    } else {
      @sfcore.state.status
    }
    if status.length() > 0 {
      c.text(status, size=13.0, color=grey) |> ignore
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
  if !@sfcore.start() {
    app.status = "这个版本没有链接内核（MBUI_CORE=1 scripts/mac.sh build）"
  }
  app.shelf = env("MBUI_SHELF") == "1"
  app.photos = env("MBUI_PHOTOS") == "1"
  app.videos = env("MBUI_VIDEOS") == "1"
  if env("MBUI_SECURE_TEST") == "1" && secure_test() == 0 {
    @host.log("SECURE_TEST: not on this host")
  }
  @ui.run("still.fail · mbui", view)
}
