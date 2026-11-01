// A sign-in card's first action and the choice wrapped over it start at its title's words. A code field over the
// buttons keeps both its ends and its words in line with theirs.

///|
test "a sign-in card's first action starts at its title" {
  let calls : Array[Made] = []
  let t = cards_core(calls, mode="chat-signin")
  @ui.fake_autofill.val = true
  t.draw()
  let (title_x, _, _, _) = t.rect_of("登录 github.com").unwrap()
  let (action_x, _, _, _) = t.rect_of("用密码管理器登录").unwrap()
  assert_true((action_x - title_x).abs() < 0.01, msg="title \{title_x}, action \{action_x}")
}

///|
test "a sign-in card keeps its primary action at the bottom when the choice wraps" {
  let calls : Array[Made] = []
  let t = cards_core(calls, mode="chat-signin")
  @ui.fake_autofill.val = true
  t.draw()
  let (title_x, _, _, _) = t.rect_of("登录 github.com").unwrap()
  let (action_x, action_y, _, _) = t.rect_of("用密码管理器登录").unwrap()
  let (choice_x, choice_y, _, _) = t.rect_of("登录后存入密钥库").unwrap()
  assert_true(choice_y < action_y, msg="the choice wraps above the primary action")
  assert_true((choice_x - title_x).abs() < 0.01, msg="title \{title_x}, choice \{choice_x}, action \{action_x}")
  let action = t.get(Button, label="用密码管理器登录").rect
  let choice = t.get(Button, label="登录后存入密钥库").rect
  assert_true(choice.1 + choice.3 <= action.1 + 0.01, msg="their touch targets do not overlap")
}

///|
test "the sign-in choice has the same button appearance as the primary action" {
  let calls : Array[Made] = []
  let t = cards_core(calls, mode="chat-signin")
  @ui.fake_autofill.val = true
  t.draw()
  let primary = t.words().filter(fn(w) { w.0 == "用密码管理器登录" })[0]
  let choice = t.words().filter(fn(w) { w.0 == "登录后存入密钥库" })[0]
  assert_true((primary.4 - choice.4).abs() < 0.01, msg="the two labels have the same line height")
  let ground_at = fn(w : (String, Double, Double, Double, Double, Double)) {
    t.drawn_rect_corners().iter().find_first(fn(r) {
      r.0 <= w.1 && r.0 + r.2 >= w.1 + w.3 && r.1 <= w.2 && r.1 + r.3 >= w.2 + w.4 && r.3 <= 40.0
    })
  }
  let primary_ground = ground_at(primary).unwrap()
  let choice_ground = ground_at(choice).unwrap()
  assert_eq((choice_ground.3, choice_ground.4), (primary_ground.3, primary_ground.4))
}

///|
test "the wrapped sign-in choice opens and stays aligned after choosing" {
  let calls : Array[Made] = []
  let t = cards_core(calls, mode="chat-signin")
  @ui.fake_autofill.val = true
  t.draw()
  t.click(Button, label="登录后存入密钥库")
  assert_true(t.find("不存入密钥库") is Some(_))
  t.tap_text("不存入密钥库")
  let (title_x, _, _, _) = t.rect_of("登录 github.com").unwrap()
  let (choice_x, _, _, _) = t.rect_of("不存入密钥库").unwrap()
  assert_true((choice_x - title_x).abs() < 0.01, msg="title \{title_x}, choice \{choice_x}")
}

///|
test "a sign-in code's field and action keep their words together at the title" {
  for platform in [0, 2] {
    let calls : Array[Made] = []
    let t = cards_core(calls, mode="chat-signin-code", platform~)
    let (title_x, _, _, _) = t.rect_of("登录 github.com").unwrap()
    let (action_x, _, _, _) = t.rect_of("继续").unwrap()
    let fields = t.words().filter(fn(w) { w.0 == "验证码" })
    assert_eq(fields.length(), 1)
    let field_x = fields[0].1
    assert_true((field_x - action_x).abs() < 0.01, msg="platform \{platform}: field \{field_x}, action \{action_x}")
    assert_true((field_x - title_x).abs() < 0.01, msg="platform \{platform}: title \{title_x}, field \{field_x}")
  }
}
