// An agent's ask to sign in to a site, answered on its card in the chat (sfpages signin_card.mbt
// 登录态 "Signing in from a card"): on a device with no password manager to ask, on the tab's screen; a code the page
// asks typed on the card; a person's step a tap from the screen, and said done; signed in and to be kept, approved here
// in place, then one line in the card's place.

///|
test "a sign-in's card: on screen where there is no password manager here, a code typed on it, a person's step said done" {
  let calls : Array[Made] = []
  let t = cards_core(calls, mode="chat-signin")
  assert_true(t.find("登录 github.com") is Some(_))
  assert_true(t.find("查看 PR #512 的 Actions 日志") is Some(_))
  t.tap_text("在画面中登录")
  t.draw()
  let self = named(calls, "signin.self")
  assert_eq(self.length(), 1)
  assert_eq(text(Some(self[0].params), "id"), "g-1")
  assert_eq((if self[0].params is Object(o) { Some(o) } else { None }).unwrap().get("done"), Some(Json::boolean(false)))
  // the page asks a code: typed on the card, 继续 sends it alone
  let calls : Array[Made] = []
  let t = cards_core(calls, mode="chat-signin-code")
  assert_true(t.find("github.com 要求输入验证码") is Some(_))
  // (the field: the last words with 验证码 in them, the line above says it too)
  let (x, y) = t.find_last("验证码").unwrap()
  t.tap(x, y)
  t.type_text("123456")
  t.frame()
  t.tap_text("继续")
  t.draw()
  let fill = named(calls, "signin.fill")
  assert_eq(fill.length(), 1)
  assert_eq((if fill[0].params is Object(o) { Some(o) } else { None }).unwrap().get("login"), Some(Json::object({ "code": Json::string("123456") })))
  // a captcha: the screen a tap away, 我已登录 once done there
  let calls : Array[Made] = []
  let t = cards_core(calls, mode="chat-signin-person")
  assert_true(t.find("网页出现了人机验证，请在画面中完成") is Some(_))
  t.tap_text("我已登录")
  t.draw()
  let self = named(calls, "signin.self")
  assert_eq(self.length(), 1)
  assert_eq((if self[0].params is Object(o) { Some(o) } else { None }).unwrap().get("done"), Some(Json::boolean(true)))
}

///|
test "signed in and to be kept: approved here once, in place; kept, one line in the card's place" {
  let calls : Array[Made] = []
  let t = cards_core(calls, mode="chat-signin-done")
  t.draw()
  let approve = named(calls, "vault.approve")
  assert_eq(approve.length(), 1)
  assert_eq(text(Some(approve[0].params), "request"), "r-save")
  // (the card stays while it is kept: its title, how the keeping goes under it)
  assert_true(t.find("登录 github.com") is Some(_))
  let calls : Array[Made] = []
  let t = cards_core(calls, mode="chat-signin-kept")
  out_of_sight(t)
  assert_true(t.find("已登录 github.com · 已存入密钥库") is Some(_))
  assert_eq(named(calls, "vault.approve").length(), 0)
}

///|
test "1Password slow to answer: the card says it is asked, and the screen is there to sign in on instead" {
  let calls : Array[Made] = []
  let t = cards_core(calls, mode="chat-signin", op=Some(fn(_) { (0, "[]", "") }), op_pending=true)
  t.tap_text("用 1Password 登录")
  t.draw()
  assert_true(t.find("正在问 1Password…") is Some(_))
  assert_false(t.get(Button, label="在画面中登录").disabled)
  t.tap_text("在画面中登录")
  t.draw()
  let self = named(calls, "signin.self")
  assert_eq(self.length(), 1)
  assert_eq((if self[0].params is Object(o) { Some(o) } else { None }).unwrap().get("done"), Some(Json::boolean(false)))
  // (1Password let go of: what it would have said no more taken)
  assert_true(t.find("正在问 1Password…") is None)
}

///|
test "1Password allowed but its servers not reached: the card says so, in no words of op's own" {
  let calls : Array[Made] = []
  let t = cards_core(
    calls,
    mode="chat-signin",
    op=Some(fn(_) {
      (1, "", "[ERROR] 2026/11/03 16:43:31 Get \"https://my.1password.com/api/v2/account/keysets?__t=1793695358.038\": unexpected EOF\n")
    }),
  )
  t.tap_text("用 1Password 登录")
  t.draw()
  t.draw()
  t.draw()
  assert_true(t.find("1Password 没连上它的服务器，再试一次") is Some(_))
  assert_true(t.find("unexpected EOF") is None)
  assert_false(t.get(Button, label="用 1Password 登录").disabled)
}
