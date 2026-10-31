// Signed in with no workspace yet (landing.mbt; Workspaces.kt Landing, Blocked), over the fixture's landing modes, the
// calls kept and answered by `answer`.

///|
fn landing_core(
  calls : Array[(String, Json)],
  mode : String,
  answer? : (String, Json) -> Result[Json, Json] = fn(_, _) { Ok(Json::object({})) },
) -> @ui.Tester {
  new_run()
  let base = fixture(mode)
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      match name {
        "workspace.create" | "invitation.accept" | "auth.signOut" => {
          calls.push((name, params))
          done(answer(name, params))
        }
        _ => (base.call)(name, params, done)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.frame()
  t
}

///|
test "no workspace yet: 创建 workspace makes one named after the account; asked for a code, its form, then with it" {
  let calls : Array[(String, Json)] = []
  let t = landing_core(calls, "landing", answer=fn(name, params) {
    if name == "workspace.create" && text(Some(params), "invite_code") == "" {
      Err({ "code": "invite_code_required", "message": "invite code required" })
    } else {
      Ok({ "id": "ws9" })
    }
  })
  assert_true(t.find("尚未加入任何 workspace") is Some(_))
  assert_true(t.find("用邀请链接加入") is Some(_))
  t.tap_text("创建 workspace")
  t.frame()
  assert_eq(calls.length(), 1)
  assert_eq(text(Some(calls[0].1), "name"), "林 的 workspace")
  assert_eq(text(Some(calls[0].1), "account"), "u1")
  // still.fail cloud wants a code: why, and its form
  assert_true(t.find("免费版 workspace 额度已用完") is Some(_))
  t.tap_text("XXXX-XXXX-XXXX")
  t.type_text("ABCD-EFGH-IJKL")
  t.frame()
  t.tap_text("创建 workspace")
  t.frame()
  assert_eq(calls.length(), 2)
  assert_eq(text(Some(calls[1].1), "invite_code"), "ABCD-EFGH-IJKL")
}

///|
test "no workspace yet, an invitation waiting: who invited whom as what, 加入 accepts it" {
  let calls : Array[(String, Json)] = []
  let t = landing_core(calls, "landing-invited")
  assert_true(t.find("你收到一个邀请") is Some(_))
  assert_true(t.find("星火工作室") is Some(_))
  assert_true(t.find("安娜邀请 lin@example.com") is Some(_))
  // (the button's own words: the line above says 加入 too)
  let (x, y) = words_node(t, "加入").unwrap()
  t.tap(x, y)
  assert_eq(calls.length(), 1)
  assert_eq(calls[0].0, "invitation.accept")
  assert_eq(text(Some(calls[0].1), "id"), "inv1")
  assert_eq(text(Some(calls[0].1), "account"), "u1")
}

///|
test "an account not let in: why, its email, 退出此账号 signs it out" {
  let calls : Array[(String, Json)] = []
  let t = landing_core(calls, "blocked")
  assert_true(t.find("此账号暂未开放测试版") is Some(_))
  assert_true(t.find("lin@example.com") is Some(_))
  assert_true(t.find("切换账号") is Some(_))
  t.tap_text("退出此账号")
  assert_eq(calls.length(), 1)
  assert_eq(calls[0].0, "auth.signOut")
  assert_eq(text(Some(calls[0].1), "account"), "u1")
}
