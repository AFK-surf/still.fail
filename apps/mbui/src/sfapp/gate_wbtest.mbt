// The way in, one in every tier (sfpages' gate.mbt and cloud_app.mbt): signed out the sign-in page, signed in with no
// workspace yet the landing, an account not let in why; at a width of each tier on a phone or a tablet and on a
// desktop, drawn in the box the frame gives them, what they offer pressed doing the same.

///|
/// The widths and screens the way in is drawn at: a phone's, a tablet's on its side and a large one's (said regular,
/// as a tablet's system says it); a desktop's window at the same widths.
let gate_cases : Array[(Double, Int, Bool)] = [
  (390.0, 2, false),
  (720.0, 2, false),
  (1280.0, 2, true),
  (390.0, 0, false),
  (720.0, 0, false),
  (1280.0, 0, false),
]

///|
/// The app over the fixture's `mode` at width `w` on `platform`'s screen, its calls of the landing's kept and answered
/// by `answer`, the sign-in's counted in `signed`.
fn gate_tester(
  mode : String,
  w : Double,
  platform : Int,
  regular : Bool,
  calls : Array[(String, Json)],
  signed : Ref[Int],
  answer? : (String, Json) -> Result[Json, Json] = fn(_, _) { Ok(Json::object({})) },
  step? : Ref[@sfbase.SignInStep] = Ref::new(Idle),
) -> @ui.Tester raise {
  reset()
  let base = fixture(mode)
  let src : Source = {
    ..base,
    sign_in: fn() { signed.val += 1 },
    sign_in_step: fn() { step.val },
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
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=844.0, platform~)
  if regular {
    let log = t.drive("system {\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"}}\n")
    assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  }
  t.frame()
  t
}

///|
test "signed out, at each width on either screen: 登录或注册 signs in; a phone's or a tablet's says what still.fail is for, a desktop's the button alone" {
  for case in gate_cases {
    let (w, platform, regular) = case
    let at = "\{w} platform \{platform}"
    let signed = Ref::new(0)
    let t = gate_tester("signin", w, platform, regular, [], signed)
    let touch = platform == 2
    assert_eq(t.find("让 agent 持续工作") is Some(_), touch, msg=at)
    assert_eq(t.find("可同时登录多个账号，随时切换 workspace。") is Some(_), touch, msg=at)
    let (x, y, bw, bh) = t.rect_of("登录或注册").unwrap()
    // in the middle of the page
    assert_true((x + bw / 2.0 - w / 2.0).abs() <= 1.0, msg="\{at}: \{x} \{bw}")
    t.tap(x + bw / 2.0, y + bh / 2.0)
    assert_eq(signed.val, 1, msg=at)
  }
}

///|
test "signed out: the button across a phone's page less its sides, no wider than 420 on a tablet, 300 on a desktop" {
  for case in gate_cases {
    let (w, platform, regular) = case
    let at = "\{w} platform \{platform}"
    let signed = Ref::new(0)
    let t = gate_tester("signin", w, platform, regular, [], signed)
    let (_, y, _, h) = t.rect_of("登录或注册").unwrap()
    // the button's ends found by pressing: where it is pressed it signs in, past its end nothing
    let wide = if platform == 0 { 300.0 } else if w - 60.0 < 420.0 { w - 60.0 } else { 420.0 }
    t.tap(w / 2.0 + wide / 2.0 - 8.0, y + h / 2.0)
    assert_eq(signed.val, 1, msg=at)
    t.tap(w / 2.0 + wide / 2.0 + 8.0, y + h / 2.0)
    assert_eq(signed.val, 1, msg=at)
  }
}

///|
test "signed out, at each width on either screen: where signing in stands said under the button, why it failed in the red" {
  for case in gate_cases {
    let (w, platform, regular) = case
    let at = "\{w} platform \{platform}"
    let signed = Ref::new(0)
    let step : Ref[@sfbase.SignInStep] = Ref::new(Failed("登录已取消"))
    let t = gate_tester("signin", w, platform, regular, [], signed, step~)
    t.run_for(1000.0)
    // the core's words under the button, the button as it was
    assert_true(t.find("登录已取消") is Some(_), msg=at)
    assert_true(t.find("登录或注册") is Some(_), msg=at)
    // none of the core's: that it failed
    step.val = Failed("")
    t.run_for(1000.0)
    assert_true(t.find("登录失败") is Some(_), msg=at)
    assert_true(t.find("登录已取消") is None, msg=at)
    // the page out in the browser: said so, the button opening it again
    step.val = InBrowser
    t.run_for(1000.0)
    assert_true(t.find("在浏览器中完成登录") is Some(_), msg=at)
    assert_true(t.find("登录失败") is None, msg=at)
    t.tap_text("重新打开登录页")
    assert_eq(signed.val, 1, msg=at)
    // what the browser brought being checked: 正在登录, not pressed again, nothing said under it
    step.val = Verifying
    t.run_for(1000.0)
    assert_true(t.find("正在登录") is Some(_), msg=at)
    assert_true(t.find("在浏览器中完成登录") is None, msg=at)
    t.tap_text("正在登录")
    assert_eq(signed.val, 1, msg=at)
  }
}

///|
test "no workspace yet, at each width on either screen: 创建 workspace makes one; 用邀请链接加入 its sheet, one to paste" {
  for case in gate_cases {
    let (w, platform, regular) = case
    let at = "\{w} platform \{platform}"
    let calls : Array[(String, Json)] = []
    let t = gate_tester("landing", w, platform, regular, calls, Ref::new(0))
    assert_true(t.find("尚未加入任何 workspace") is Some(_), msg="\{at}: \{t.words().map(fn(x) { x.0 }).join("|")}")
    t.tap_text("创建 workspace")
    t.frame()
    assert_eq(calls.length(), 1, msg=at)
    assert_eq(calls[0].0, "workspace.create", msg=at)
    assert_eq(text(Some(calls[0].1), "account"), "u1", msg=at)
    let t = gate_tester("landing", w, platform, regular, calls, Ref::new(0))
    t.tap_text("用邀请链接加入")
    t.frame()
    t.frame()
    assert_true(sheet_open(), msg=at)
    let said = t.words().map(fn(x) { x.0 }).join("")
    assert_true(said.contains("邀请链接粘贴到下方"), msg="\{at}: \{said}")
  }
}

///|
test "no workspace yet, an invitation waiting, at each width on either screen: 加入 accepts it" {
  for case in gate_cases {
    let (w, platform, regular) = case
    let at = "\{w} platform \{platform}"
    let calls : Array[(String, Json)] = []
    let t = gate_tester("landing-invited", w, platform, regular, calls, Ref::new(0))
    assert_true(t.find("你收到一个邀请") is Some(_), msg=at)
    // (the button's own words: the line above says 加入 too)
    let (x, y) = words_node(t, "加入").unwrap()
    t.tap(x, y)
    assert_eq(calls.length(), 1, msg=at)
    assert_eq(calls[0].0, "invitation.accept", msg=at)
    assert_eq(text(Some(calls[0].1), "id"), "inv1", msg=at)
  }
}

///|
test "an account not let in, at each width on either screen: why, its email; 退出此账号 signs it out, 切换账号 signs another in" {
  for case in gate_cases {
    let (w, platform, regular) = case
    let at = "\{w} platform \{platform}"
    let calls : Array[(String, Json)] = []
    let signed = Ref::new(0)
    let t = gate_tester("blocked", w, platform, regular, calls, signed)
    assert_true(t.find("此账号暂未开放测试版") is Some(_), msg=at)
    assert_true(t.find("lin@example.com") is Some(_), msg=at)
    t.tap_text("退出此账号")
    assert_eq(calls.length(), 1, msg=at)
    assert_eq(calls[0].0, "auth.signOut", msg=at)
    t.tap_text("切换账号")
    assert_eq(signed.val, 1, msg=at)
  }
}
