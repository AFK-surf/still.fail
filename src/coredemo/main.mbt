// The still.fail core in an mbui window (scripts/mac.sh with MBUI_CORE=1): the signed-in accounts as the core's
// `accounts` topic has them, and 登录, which signs a person in through the system's browser session (@core.sign_in).
// MBUI_CORE_SIGNIN=1 presses 登录 once the accounts are read (scripted runs; with MBUI_AUTH_DRY=1 the browser
// session is made but not opened).

///|
struct App {
  mut status : String
  mut signing_in : Bool
  mut auto_sign_in : Bool
}

///|
let app : App = { status: "", signing_in: false, auto_sign_in: false }

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
fn view(c : @ui.Ctx) -> Unit {
  let accounts = @core.subscribe("accounts")
  if app.auto_sign_in && accounts.value is Some(_) {
    app.auto_sign_in = false
    sign_in()
  }
  c.box(w=Fill(1.0), h=Fill(1.0), bg=0xF5F5F7FFL, padx=28.0, pady=24.0, gap=18.0, fn() {
    c.row(gap=12.0, fn() {
      c.text("still.fail", size=22.0, weight=700, wrap=false) |> ignore
      c.text("内核 · JavaScriptCore", size=13.0, color=grey, wrap=false)
      |> ignore
      c.spacer()
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
  @ui.run("still.fail · mbui", view)
}
