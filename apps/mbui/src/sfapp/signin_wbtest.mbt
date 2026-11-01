// An agent's ask to sign in to a site, answered on its card in the chat (sfpages signin_card.mbt, ember docs/vault.md
// 登录态 "Signing in from a card"): on a device with no password manager to ask, on the tab's screen; a code the page
// asks typed on the card; a person's step a tap from the screen, and said done; signed in and to be kept, approved here
// in place, then one line once out of sight.

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
  assert_eq(self[0].params.as_object().unwrap().get("done"), Some(Json::boolean(false)))
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
  assert_eq(fill[0].params.as_object().unwrap().get("login"), Some(Json::object({ "code": Json::string("123456") })))
  // a captcha: the screen a tap away, 我已登录 once done there
  let calls : Array[Made] = []
  let t = cards_core(calls, mode="chat-signin-person")
  assert_true(t.find("网页出现了人机验证，请在画面中完成") is Some(_))
  t.tap_text("我已登录")
  t.draw()
  let self = named(calls, "signin.self")
  assert_eq(self.length(), 1)
  assert_eq(self[0].params.as_object().unwrap().get("done"), Some(Json::boolean(true)))
}

///|
test "signed in and to be kept: approved here once, in place; kept, one line once out of sight" {
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
