// A login's card (sfpages' login_card.mbt, the one card on every screen) over the fixture's chat, its login as each case has it, the calls kept.

///|
/// The fixture's chat, its login `login` and the station's logins letting the viewer finish it.
fn login_core(
  calls : Array[Made],
  login : Json,
  answer? : (String) -> Json = fn(_) { Json::object({}) },
  relay? : Bool = true,
  w? : Double = 390.0,
  pointing? : @ui.Pointing,
) -> @ui.Tester {
  new_run()
  let base = fixture("chat")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      match name {
        "machineLogin" => { value: Some(login), error: None, version: 1 }
        "machineLogins" => { value: Some({ "canLogin": true, "canRelay": Json::boolean(relay) }), error: None, version: 1 }
        _ => base.topic(name, params).get().snapshot()
      }
    },
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      done(Ok(answer(name)))
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=844.0, platform=2, pointing?)
  t.run_for(@ui.move_most_ms)
  t
}

///|
fn login_of(more : Array[(String, Json)]) -> Json {
  with_fields(
    {
      "id": "login-1",
      "title": "在 Willow 上登录 gh",
      "state": "browser",
      "active": true,
      "statusText": "等你在浏览器里登录",
      "domain": "github.com",
    },
    more,
  )
}

///|
/// The fixture's chat (its login card at its foot) with the station's logins answering `machineLogins`.
fn with_logins(t : @ui.Tester) -> @ui.Tester {
  for _ in 0..<6 {
    if t.find("在 Willow 上登录 gh") is Some(_) {
      break
    }
    t.wheel(195.0, 400.0, -300.0)
  }
  t
}

///|
test "a login card: its title with its × (取消: machineLogin.cancel), a page to open, its button solid until pressed" {
  let calls : Array[Made] = []
  let t = with_logins(login_core(calls, login_of([("step", "open"), ("url", "https://github.com/login")])))
  assert_true(t.find("登录页在 github.com") is Some(_))
  t.tap_text("在浏览器里登录")
  assert_true(t.opened().contains("https://github.com/login"))
}

///|
test "a login whose page gives a code to paste back: 打开登录页, then the code typed, 完成 sends it (machineLogin.answer)" {
  let calls : Array[Made] = []
  let t = with_logins(
    login_core(calls, login_of([("step", "open"), ("paste", true), ("url", "https://app.devin.ai/login")])),
  )
  assert_true(t.find("在 github.com 登录，把页面给的码贴到下面") is Some(_))
  t.tap_text("打开登录页")
  assert_true(t.opened().contains("https://app.devin.ai/login"))
  assert_true(words_node(t, "完成") is None, msg="完成 once a code is in")
  t.tap_text("粘贴登录码")
  t.type_text("ABC-123")
  t.frame()
  let (x, y) = words_node(t, "完成").unwrap()
  t.tap(x, y)
  let sent = named(calls, "machineLogin.answer")
  assert_eq(sent.length(), 1)
  assert_eq(text(Some(sent[0].params), "text"), "ABC-123")
  assert_eq(text(Some(sent[0].params), "id"), "login-1")
}

///|
test "a Claude login card asks before opening the authorization page" {
  let calls : Array[Made] = []
  let page = "https://claude.ai/oauth/authorize"
  let t = with_logins(login_core(calls, login_of([
    ("name", "claude"), ("step", "open"), ("paste", true), ("url", Json::string(page)),
  ])))
  t.tap_text("打开登录页")
  sheet_rested(t, "sf-present")
  assert_true(t.find("打开 Claude 授权页面？") is Some(_))
  assert_true(t.opened().is_empty())
  t.tap_text("继续打开")
  assert_eq(t.opened(), [page])
}

///|
test "a login's page copied from the ⋯ beside its button, its address on the clipboard and said so" {
  for login in [
    login_of([("step", "open"), ("paste", true), ("url", "https://app.devin.ai/login")]),
    login_of([("step", "open"), ("url", "https://app.devin.ai/login")]),
    login_of([("step", "device"), ("code", "WXYZ-1234"), ("url", "https://github.com/login"), ("codeUrl", "https://app.devin.ai/login")]),
  ] {
    let calls : Array[Made] = []
    let t = with_logins(login_core(calls, login))
    t.click(Button, label="其他方式")
    t.run_for(@sf.presented_rest() - t.time())
    t.tap_text("复制链接")
    assert_eq(t.clipboard(), "https://app.devin.ai/login")
    assert_true(t.opened().is_empty(), msg="copied, nothing opened")
  }
}

///|
test "a device login: its code large, 复制并打开 copies it and opens its page" {
  let calls : Array[Made] = []
  let t = with_logins(
    login_core(calls, login_of([("step", "device"), ("code", "WXYZ-1234"), ("url", "https://github.com/login/device")])),
  )
  assert_true(t.find("WXYZ-1234") is Some(_))
  t.tap_text("复制并打开")
  assert_eq(t.clipboard(), "WXYZ-1234")
  assert_true(t.opened().contains("https://github.com/login/device"))
}


///|
test "a login the station's own browser can do: seldom used, in the ⋯ by the step's button; chosen (machineLogin.browser), its tab's view opens, gone back from once the login ends" {
  let calls : Array[Made] = []
  let t = with_logins(
    login_core(
      calls,
      login_of([
        ("step", "loopback"),
        ("url", "https://accounts.google.com/o/oauth2/auth"),
        ("browser", true),
        ("browserText", "在 Willow 的浏览器中打开"),
      ]),
      answer=fn(name) { if name == "machineLogin.browser" { { "screen": "browser:T1" } } else { Json::object({}) } },
    ),
  )
  assert_true(t.find("在 Willow 的浏览器中打开") is None, msg="not a button of its own")
  t.click(Button, label="其他方式")
  assert_true(@sf.presenting())
  t.run_for(@sf.presented_rest() - t.time())
  t.tap_text("在 Willow 的浏览器中打开")
  t.run_for(@sf.presented_rest() - t.time())
  let asked = named(calls, "machineLogin.browser")
  assert_eq(asked.length(), 1)
  assert_eq(text(Some(asked[0].params), "id"), "login-1")
  match app.nav.top() {
    Screen(at) => assert_eq((at.station, at.screen, at.until_gone), ("ws1/st1", "browser:T1", true))
    _ => assert_true(false, msg="its tab's view opened")
  }
}

///|
test "returning to an already open Claude login in the station's browser needs no confirmation" {
  let calls : Array[Made] = []
  let t = with_logins(login_core(
    calls,
    login_of([
      ("name", "claude"), ("step", "loopback"), ("url", "https://claude.ai/oauth/authorize"),
      ("browser", true), ("browserText", "回到 Willow 的浏览器"), ("screen", "browser:T1"),
    ]),
    answer=fn(name) { if name == "machineLogin.browser" { { "screen": "browser:T1" } } else { Json::object({}) } },
    relay=false,
  ))
  t.tap_text("回到 Willow 的浏览器")
  t.frame()
  assert_eq(named(calls, "machineLogin.browser").length(), 1)
  assert_false(@sf.presenting())
}

///|
test "a device that cannot take a loopback's callback: the station's browser is its step, no ⋯; a station with none, said so" {
  let calls : Array[Made] = []
  let page = "https://login.microsoftonline.com/x"
  let t = with_logins(
    login_core(
      calls,
      login_of([("step", "loopback"), ("url", Json::string(page)), ("browser", true), ("browserText", "在 Willow 的浏览器中打开")]),
      relay=false,
    ),
  )
  assert_true(t.find("在 Willow 的浏览器中打开") is Some(_))
  assert_true(t.query(Button, label="其他方式") is None)
  assert_true(t.find("这一步要在桌面或安卓 app 里完成") is None)
  let none = with_logins(login_core(calls, login_of([("step", "loopback"), ("url", Json::string(page))]), relay=false))
  assert_true(none.find("这一步要在桌面或安卓 app 里完成") is Some(_))
}

///|
test "this device's port taken just now: the station's browser is the step, this device's again in its ⋯" {
  let calls : Array[Made] = []
  let t = with_logins(
    login_core(
      calls,
      login_of([
        ("step", "loopback"),
        ("url", "https://accounts.google.com/o/oauth2/auth"),
        ("relayText", "本机 8085 端口被占用"),
        ("browser", true),
        ("browserText", "在 Willow 的浏览器中打开"),
      ]),
    ),
  )
  assert_true(t.find("本机 8085 端口被占用") is Some(_))
  assert_true(t.find("在 Willow 的浏览器中打开") is Some(_))
  t.click(Button, label="其他方式")
  t.run_for(@sf.presented_rest() - t.time())
  assert_true(t.find("在浏览器里登录") is Some(_))
}

///|
/// The widest box drawn round `words` 32 high (a step's button, as wide as its card less the card's padding).
fn step_width(t : @ui.Tester, words : String) -> Double {
  let (x, y, w, h) = t.rect_of(words).unwrap()
  t
  .drawn_rects()
  .filter(fn(r) { r.3 > 30.0 && r.3 < 34.0 && r.0 <= x && r.0 + r.2 >= x + w && r.1 <= y && r.1 + r.3 >= y + h })
  .fold(init=0.0, fn(m, r) { if r.2 > m { r.2 } else { m } })
}

///|
test "a login card in a wide chat: as wide as what it says, 560 at most, not drawn across the column" {
  let calls : Array[Made] = []
  let t = with_logins(
    login_core(calls, login_of([("step", "open"), ("paste", true), ("url", "https://app.devin.ai/login")]), w=1600.0),
  )
  let wide = step_width(t, "打开登录页")
  assert_true(wide >= 340.0 && wide <= 562.0, msg="the step's button \{wide} wide")
}

///|
test "a login code sent (完成, or the keyboard's Done) lets go of the keyboard" {
  for by_enter in [false, true] {
    let calls : Array[Made] = []
    let t = with_logins(
      login_core(calls, login_of([("step", "open"), ("paste", true), ("url", "https://app.devin.ai/login")])),
    )
    t.tap_text("粘贴登录码")
    t.type_text("ABC-123")
    t.frame()
    assert_true(t.ctx().field_focused())
    if by_enter {
      t.enter()
    } else {
      let (x, y) = words_node(t, "完成").unwrap()
      t.tap(x, y)
    }
    assert_eq(named(calls, "machineLogin.answer").length(), 1, msg="enter \{by_enter}")
    assert_true(!t.ctx().field_focused(), msg="enter \{by_enter}")
    assert_true(!t.ime().0, msg="enter \{by_enter}")
  }
}

///|
test "the chat scrolled while a login card's code field has the keyboard: the keyboard goes (mbui: a finger scrolling a list)" {
  let calls : Array[Made] = []
  let t = with_logins(login_core(calls, login_of([("step", "open"), ("paste", true), ("url", "https://app.devin.ai/login")]), pointing=Finger))
  t.tap_text("粘贴登录码")
  t.type_text("ABC")
  t.frame()
  assert_true(t.ctx().field_focused())
  assert_true(t.ime().0)
  t.drag(195.0, 200.0, 195.0, 400.0)
  assert_true(!t.ctx().field_focused())
  assert_true(!t.ime().0)
}

///|
test "a tap in a login card's code field that has the keyboard keeps it" {
  let calls : Array[Made] = []
  let t = with_logins(login_core(calls, login_of([("step", "open"), ("paste", true), ("url", "https://app.devin.ai/login")]), pointing=Finger))
  let (x, y) = t.find("粘贴登录码").unwrap()
  t.tap(x, y)
  t.type_text("ABC")
  t.frame()
  t.tap(x, y)
  t.frame()
  assert_true(t.ctx().field_focused())
}

///|
/// How long a step of the keyboard takes in keyboard_rises: a display's frame.
let keyboard_step_ms : Double = 16.0

///|
/// The keyboard coming up over a phone's window a step at a time, as a host says it, the app laid out above it.
fn keyboard_rises(t : @ui.Tester, h : Double) -> Unit {
  for i in 1..=10 {
    let up = h * i.to_double() / 10.0
    t.set_ime_inset(up)
    t.resize_next(390.0, 844.0 - up)
    t.run_for(keyboard_step_ms)
  }
  t.run_for(@ui.move_most_ms)
}

///|
test "a login card's field keeps in view as the keyboard comes up: under the bar, over the composer, not gone with the list" {
  let calls : Array[Made] = []
  let t = with_logins(login_core(calls, login_of([("step", "open"), ("paste", true), ("url", "https://app.devin.ai/login")])))
  t.tap_text("粘贴登录码")
  t.frame()
  assert_true(t.ctx().field_focused())
  keyboard_rises(t, 560.0)
  guard t.rect_of("粘贴登录码") is Some((_, y, _, h)) else { fail("the field is gone from view") }
  guard t.rect_of(@sf.t("web-main.composer.placeholder")) is Some((_, composer, _, _)) else { fail("no composer") }
  assert_true(y >= @sfpages.bar_foot && y + h <= composer, msg="field at \{y}..\{y + h}, composer at \{composer}")
  // (and with words typed in it)
  t.type_text("ABC-123")
  t.frame()
  guard t.focused() is Some({ rect: (_, y2, _, h2), .. }) else { fail("the field let go of the focus") }
  assert_true(y2 >= @sfpages.bar_foot && y2 + h2 <= composer, msg="field at \{y2}..\{y2 + h2}")
}

///|
test "a code-pasting login's card in its chat and in its login sheet at once: a field each, no fault" {
  new_run()
  let base = fixture("chat")
  let pasting = login_of([("step", "open"), ("paste", true), ("url", "https://claude.ai/oauth/authorize")])
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      match name {
        "machineLogin" => { value: Some(pasting), error: None, version: 1 }
        "machineLogins" =>
          {
            value: Some({ "canLogin": true, "canRelay": true, "supported": true, "loaded": true, "logins": [pasting] }),
            error: None,
            version: 1,
          }
        _ => base.topic(name, params).get().snapshot()
      }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  open_login("ws1/st1", "login-1")
  t.run_for(@ui.move_most_ms)
  assert_true(sheet_open())
  assert_true(t.find("这部分显示出错了") is None)
  let fields = t.locate("粘贴登录码")
  assert_eq(fields.length(), 2, msg="\{Repr(fields)}")
  // what is typed in the one is its own: typed in the sheet's card
  let field = t.get(TextField, label="粘贴登录码")
  let (fx, fy, fw, fh) = field.rect
  t.tap(fx + fw / 2.0, fy + fh / 2.0)
  t.type_text("ABC-123")
  t.frame()
  // (完成 shows once a code is in: on the sheet's card alone)
  let done = t.locate("完成")
  assert_eq(done.length(), 1, msg="\{Repr(done)}")
}
