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
  step? : @signals.Signal[@sfbase.SignInStep] = @signals.signal(Idle, same=fn(a, b) { a == b }),
) -> @ui.Tester raise {
  new_run()
  let base = fixture(mode)
  let src : Source = {
    ..base,
    sign_in: fn() { signed.val += 1 },
    sign_in_step: fn() { step.get() },
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
    let step : @signals.Signal[@sfbase.SignInStep] = @signals.signal(Failed("登录已取消"), same=fn(a, b) { a == b })
    let t = gate_tester("signin", w, platform, regular, [], signed, step~)
    t.run_for(@ui.move_most_ms)
    // the core's words under the button, the button as it was
    assert_true(t.find("登录已取消") is Some(_), msg=at)
    assert_true(t.find("登录或注册") is Some(_), msg=at)
    // none of the core's: that it failed
    step.set(Failed(""))
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("登录失败") is Some(_), msg=at)
    assert_true(t.find("登录已取消") is None, msg=at)
    // the page out in the browser: said so, the button opening it again
    step.set(InBrowser)
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("在浏览器中完成登录") is Some(_), msg=at)
    assert_true(t.find("登录失败") is None, msg=at)
    t.tap_text("重新打开登录页")
    assert_eq(signed.val, 1, msg=at)
    // what the browser brought being checked: 正在登录, not pressed again, nothing said under it
    step.set(Verifying)
    t.run_for(@ui.move_most_ms)
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

///|
test "signed out: where signing in stands, changed with no frame drawn since, is what its button does at once: at work not pressed, out in the browser pressed to open it again" {
  let signed = Ref::new(0)
  let step : @signals.Signal[@sfbase.SignInStep] = @signals.signal(Idle, same=fn(a, b) { a == b })
  let t = gate_tester("signin", 390.0, 2, false, [], signed, step~)
  let (x, y, bw, bh) = t.rect_of("登录或注册").unwrap()
  let (bx, by) = (x + bw / 2.0, y + bh / 2.0)
  // (no frame drawn from here: each told as a host tells it, between frames)
  step.set(Verifying)
  t.touch(0, bx, by)
  t.touch(2, bx, by)
  let at_work = signed.val
  step.set(InBrowser)
  t.touch(0, bx, by)
  t.touch(2, bx, by)
  assert_eq((at_work, signed.val), (0, 1))
}

///|
/// The app signed out as it is first made, 390 wide to touch: no words of the app's said yet (a key said as it is,
/// sf's words_of as a run starts), the fixture's prefs saying `lang` where given, its device's locale `locale`; the
/// Tester as made, its first frame drawn and none after. Its sign-in step.
fn gate_cold(
  lang? : String = "",
  locale? : String = "zh-CN",
) -> (@ui.Tester, @signals.Signal[@sfbase.SignInStep]) {
  new_run()
  // (as a run starts: no words told, each key said as it is)
  @sf.set_words(fn(key, _) { key })
  let base = fixture("signin")
  let step : @signals.Signal[@sfbase.SignInStep] = @signals.signal(Idle, same=fn(a, b) { a == b })
  let src : Source = {
    ..base,
    sign_in_step: fn() { step.get() },
    topic: fn(name, params) {
      let got = (base.topic)(name, params)
      if name == "prefs" && lang != "" {
        let prefs = match got.value {
          Some(Object(m)) => m.copy()
          _ => {}
        }
        prefs["lang"] = Json::string(lang)
        { ..got, value: Some(Json::object(prefs)) }
      } else {
        got
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2, env=[("MBUI_LOCALE", locale)])
  (t, step)
}

///|
/// The middle across of the words `s` as the tree draws them, and whether the tree reads the clock (something going).
fn gate_words_at(s : String) -> (Double, Bool) {
  let tree = @ui.view_tree().unwrap()
  match tree.drawn().iter().find_first(fn(d) { d.words == s }) {
    Some(d) => (d.x + d.w / 2.0, tree.clock_read())
    None => (-1.0, tree.clock_read())
  }
}

///|
test "signed out, its words told as the app's tree is made: its button's words in its middle from the first frame the page is drawn, nothing going; changed then (重新打开登录页), going to their new place" {
  let (t, step) = gate_cold()
  let first = gate_words_at("登录或注册")
  step.set(InBrowser)
  t.frame_at(t.time() + 40.0)
  let (on_way, going) = gate_words_at("重新打开登录页")
  t.run_for(@ui.move_most_ms)
  let (there, still_going) = gate_words_at("重新打开登录页")
  assert_eq((first, going, on_way != there, still_going), ((195.0, false), true, true, false), msg="\{first} \{on_way} \{there}")
}

///|
test "signed out, the prefs saying English, the device Chinese: its button's English words in its middle from the first frame the page is drawn, nothing going" {
  let (_t, _) = gate_cold(lang="en", locale="zh-CN")
  assert_eq(gate_words_at("Sign in or sign up"), (195.0, false))
}
