// The workspace sheet's rows (sfpages workspace.mbt workspaces_list): the one in use on its card, the others, 登录其他账号
// and 新建 workspace: their marks in one column and their words on one line (2026-11-07: the card's row stood 16
// further in, an action's words 4 less far than a workspace's).

///|
test "the workspace sheet: every row's mark in one column and its words on one line, on the card or not" {
  let t = native_chat(466.0, 678.0, true, side=70.0)
  @sfpages.open_workspaces(fixture("chat"), At(32.0, 16.0, 150.0, 38.0))
  t.run_for(@ui.move_most_ms)
  guard t.semantics().iter().find_first(fn(s) { !s.hidden && s.role == @ui.Role::Dialog }) is Some(sheet) else {
    fail("no sheet")
  }
  let (sx, sy, sw, sh) = sheet.rect
  let within = fn(x : Double, y : Double) { x >= sx && x <= sx + sw && y >= sy && y <= sy + sh }
  let names = ["星火工作室", "个人", @sf.t("android-misc.workspace.addAccount"), @sf.t("android-misc.workspace.new")]
  let xs : Array[Double] = []
  for n in names {
    guard t.words().iter().find_first(fn(w) { w.0 == n && within(w.1, w.2) }) is Some(w) else { fail("no \{n} in the sheet") }
    xs.push(w.1)
  }
  for i, x in xs {
    assert_eq(x, xs[0], msg="\{names[i]} at \{x}, \{names[0]} at \{xs[0]}")
  }
  // their marks: the squares before them, one column
  let leads = t.boxes_held().filter(fn(b) { b.w == 24.0 && b.h == 24.0 && within(b.x, b.y) })
  assert_eq(leads.length(), names.length(), msg="\{leads.length()} marks")
  for b in leads {
    assert_eq(b.x, leads[0].x)
  }
}

///|
/// The fixture's core (`mode`'s) as it tells the workspaces: 安娜's invitation to 开源 waiting for its account while
/// `invited` says so, the workspaces `left` names gone from its list; told anew as either changes. The calls the
/// list makes (`invitation.accept`, `invitation.decline`) kept in `calls`, unanswered; 登录其他账号 counted in
/// `signed`; the rest the fixture's.
fn ws_told(
  calls : Array[Made],
  invited : @signals.Signal[Bool],
  left : @signals.Signal[Array[String]],
  signed? : Ref[Int] = Ref(0),
  mode? : String = "home",
) -> Source {
  let base = fixture(mode)
  {
    ..base,
    topic_read: fn(name, params) {
      let t = (base.topic_read)(name, params)
      guard name == "workspaces" && t.value is Some(Array(a)) else { return t }
      let inv = invited.get()
      let out = left.get()
      {
        ..t,
        version: t.version * 100 + (if inv { 1 } else { 0 }) + 2 * out.length(),
        value: Some(
          Json::array(
            a.map(fn(e) {
              let ws = items(Some(e), "workspaces").filter(fn(w) { !out.contains(text(Some(w), "id")) })
              let invitations : Json = if inv {
                [{ "id": "inv2", "name": "开源", "inviter": "安娜", "role": "member" }]
              } else {
                []
              }
              with_fields(e, [("workspaces", Json::array(ws)), ("invitations", invitations)])
            }),
          ),
        ),
      }
    },
    call: fn(name, params, done) {
      match name {
        "invitation.accept" | "invitation.decline" => calls.push({ name, params, bytes: None, done })
        _ => (base.call)(name, params, done)
      }
    },
    sign_in: fn() { signed.val += 1 },
  }
}

///|
/// Home over `src` on a window 390 by 844 with the input `platform` (`wide`: made 1200 by 800 first), the workspaces
/// opened from a point at its top (`compact`: as tall as what they hold), at the frame that opened them.
fn ws_list_over(src : Source, platform~ : Int, wide~ : Bool, compact? : Bool = false) -> @ui.Tester {
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform~)
  if wide {
    t.resize(1200.0, 800.0)
  }
  t.run_for(@ui.move_most_ms)
  @sfpages.open_workspaces(src, At(32.0, 16.0, 150.0, 38.0), compact~)
  t.frame()
  t
}

///|
/// The workspaces' panel as a screen reader finds it, if it is up.
fn ws_panel(t : @ui.Tester) -> @ui.SemNode? {
  t.semantics().iter().find_first(fn(s) { !s.hidden && s.role == @ui.Role::Dialog })
}

///|
/// Where `words` are said in the workspaces' panel (none: not in it, or it is not up).
fn ws_in_panel(t : @ui.Tester, words : String) -> (Double, Double)? {
  guard ws_panel(t) is Some(p) else { return None }
  let (sx, sy, sw, sh) = p.rect
  match t.words().iter().find_first(fn(w) { w.0 == words && w.1 >= sx && w.1 <= sx + sw && w.2 >= sy && w.2 <= sy + sh && w.5 > 0.0 }) {
    Some(w) => Some((w.1, w.2))
    None => None
  }
}

///|
/// Where `words` are said in the workspaces' panel; the test fails where they are not (`at`: which screen), saying
/// what is.
fn ws_at(t : @ui.Tester, words : String, at : String) -> (Double, Double) raise {
  match ws_in_panel(t, words) {
    Some(p) => p
    None => {
      let said = match ws_panel(t) {
        Some(p) => "panel at \{Repr(p.rect)}: " + t.words().map(fn(w) { "\{w.0}@\{w.1},\{w.2} a\{w.5}" }).join("|")
        None => "no panel"
      }
      fail("\{at}: no \{words} in the panel; \{said}")
    }
  }
}

///|
/// The three screens the workspaces open on: a sheet with a finger, a small window with a mouse, a wide one (beside
/// what opened them).
let ws_screens : Array[(Int, Bool)] = [(2, false), (0, false), (0, true)]

///|
test "the workspaces: an invitation that comes while they are up shows under the one in use, before the others; answered, it goes" {
  for screen in ws_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    new_run()
    let invited = @signals.signal(false, same=fn(a, b) { a == b })
    let left : @signals.Signal[Array[String]] = @signals.signal([])
    let calls : Array[Made] = []
    let t = ws_list_over(ws_told(calls, invited, left), platform~, wide~)
    t.run_for(@ui.move_most_ms)
    assert_true(ws_in_panel(t, "安娜邀请你加入「开源」") is None, msg=at)
    invited.set(true)
    t.frame()
    t.run_for(@ui.move_most_ms)
    guard ws_in_panel(t, "安娜邀请你加入「开源」") is Some((_, iy)) else { fail("\{at}: no invitation") }
    let (_, cy) = ws_at(t, "星火工作室", at)
    let (_, oy) = ws_at(t, "个人", at)
    assert_true(cy < iy && iy < oy, msg="\{at}: \{cy} \{iy} \{oy}")
    assert_true(ws_in_panel(t, "邀请") is Some(_), msg=at)
    // 忽略: asked, then answered and told so: gone
    let (x, y) = ws_at(t, "忽略", at)
    t.tap(x, y)
    t.frame()
    assert_eq(calls.length(), 1, msg=at)
    assert_eq(calls[0].name, "invitation.decline", msg=at)
    (calls[0].done)(Ok({}))
    invited.set(false)
    t.frame()
    t.run_for(@ui.move_most_ms)
    assert_true(ws_in_panel(t, "安娜邀请你加入「开源」") is None, msg=at)
    assert_true(ws_in_panel(t, "邀请") is None, msg=at)
    assert_true(ws_in_panel(t, "个人") is Some(_), msg=at)
  }
}

///|
test "the workspaces: one taken out while they are up goes from the list, and 其他 workspace with the last of them" {
  for screen in ws_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    new_run()
    let invited = @signals.signal(false, same=fn(a, b) { a == b })
    let left : @signals.Signal[Array[String]] = @signals.signal([])
    let t = ws_list_over(ws_told([], invited, left), platform~, wide~)
    t.run_for(@ui.move_most_ms)
    assert_true(ws_in_panel(t, "个人") is Some(_), msg=at)
    assert_true(ws_in_panel(t, "其他 workspace") is Some(_), msg=at)
    let (_, foot_was) = ws_at(t, "登录其他账号", at)
    left.set(["ws2"])
    t.frame()
    t.run_for(@ui.move_most_ms)
    assert_true(ws_in_panel(t, "个人") is None, msg=at)
    assert_true(ws_in_panel(t, "其他 workspace") is None, msg=at)
    assert_true(ws_in_panel(t, "星火工作室") is Some(_), msg=at)
    // its foot where it was: the panel a share of the window, whatever the list holds
    let (_, foot) = ws_at(t, "登录其他账号", at)
    assert_eq(foot, foot_was, msg=at)
  }
}

///|
test "the workspaces: the one in use changed while they are up is the one on the card, checked, the one before among the others" {
  for screen in ws_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    new_run()
    let invited = @signals.signal(false, same=fn(a, b) { a == b })
    let left : @signals.Signal[Array[String]] = @signals.signal([])
    let t = ws_list_over(ws_told([], invited, left), platform~, wide~)
    t.run_for(@ui.move_most_ms)
    let (_, a) = ws_at(t, "星火工作室", at)
    let (_, b) = ws_at(t, "个人", at)
    assert_true(a < b, msg=at)
    app.picked.set("ws2")
    t.frame()
    t.run_for(@ui.move_most_ms)
    let (_, a) = ws_at(t, "星火工作室", at)
    let (_, b) = ws_at(t, "个人", at)
    assert_true(b < a, msg="\{at}: 个人 \{b} over 星火工作室 \{a}")
    let (_, label) = ws_at(t, "当前使用", at)
    let (_, others) = ws_at(t, "其他 workspace", at)
    assert_true(label < b && b < others && others < a, msg=at)
  }
}

///|
test "the workspaces: 加入 pressed, both its buttons wait, a second press nothing; joined, they close, its workspace in view" {
  new_run()
  let invited = @signals.signal(true, same=fn(a, b) { a == b })
  let left : @signals.Signal[Array[String]] = @signals.signal([])
  let calls : Array[Made] = []
  let t = ws_list_over(ws_told(calls, invited, left), platform=2, wide=false)
  t.run_for(@ui.move_most_ms)
  let at = "a sheet"
  let (x, y) = ws_at(t, "加入", at)
  t.tap(x, y)
  t.frame()
  assert_eq(calls.length(), 1)
  assert_eq(calls[0].name, "invitation.accept")
  let (x, y) = ws_at(t, "忽略", at)
  t.tap(x, y)
  t.frame()
  assert_eq(calls.length(), 1)
  (calls[0].done)(Ok({ "id": "ws2" }))
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(ws_panel(t) is None)
  assert_eq(app.picked.get(), "ws2")
}

///|
test "the workspaces: the one in use pressed closes them; 登录其他账号 closes them and signs in another" {
  for screen in ws_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    new_run()
    let invited = @signals.signal(false, same=fn(a, b) { a == b })
    let left : @signals.Signal[Array[String]] = @signals.signal([])
    let signed = Ref(0)
    let src = ws_told([], invited, left, signed~)
    let t = ws_list_over(src, platform~, wide~)
    t.run_for(@ui.move_most_ms)
    let (x, y) = ws_at(t, "星火工作室", at)
    t.tap(x, y)
    t.frame()
    t.run_for(@ui.move_most_ms)
    assert_true(ws_panel(t) is None, msg=at)
    assert_eq(app.picked.get() == "ws2", false, msg=at)
    @sfpages.open_workspaces(src, At(32.0, 16.0, 150.0, 38.0))
    t.frame()
    t.run_for(@ui.move_most_ms)
    let (x, y) = ws_at(t, "登录其他账号", at)
    t.tap(x, y)
    t.frame()
    t.run_for(@ui.move_most_ms)
    assert_true(ws_panel(t) is None, msg=at)
    assert_eq(signed.val, 1, msg=at)
  }
}

///|
test "the workspaces, compact: as tall as what they hold, shorter than the share of the window they take else" {
  for screen in ws_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let tall = fn(compact : Bool) raise {
      new_run()
      let invited = @signals.signal(false, same=fn(a, b) { a == b })
      let left : @signals.Signal[Array[String]] = @signals.signal([])
      let t = ws_list_over(ws_told([], invited, left), platform~, wide~, compact~)
      t.run_for(@ui.move_most_ms)
      let p = ws_panel(t).unwrap()
      // its foot under its list, in it
      let (_, foot) = ws_at(t, "新建 workspace", at)
      let (_, others) = ws_at(t, "个人", at)
      assert_true(foot > others, msg=at)
      p.rect.3
    }
    let compact = tall(true)
    let share = tall(false)
    assert_true(compact < share, msg="\{at}: compact \{compact}, else \{share}")
  }
}

///|
test "the workspaces on each screen: 当前使用 over the card of the one in use, 邀请 and its invitation under it, 其他 workspace and the others, then 登录其他账号 and 新建 workspace at its foot, all in it" {
  for screen in ws_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    new_run()
    let invited = @signals.signal(true, same=fn(a, b) { a == b })
    let left : @signals.Signal[Array[String]] = @signals.signal([])
    let t = ws_list_over(ws_told([], invited, left), platform~, wide~)
    t.run_for(@ui.move_most_ms)
    let ys = ["当前使用", "星火工作室", "邀请", "安娜邀请你加入「开源」", "其他 workspace", "个人", "登录其他账号", "新建 workspace"].map(fn(w) {
      ws_in_panel(t, w).map(fn(p) { p.1 }).unwrap_or(-1.0)
    })
    for i in 1..<ys.length() {
      assert_true(ys[i - 1] >= 0.0 && ys[i - 1] < ys[i], msg="\{at}: \{Repr(ys)}")
    }
    // the invitation's buttons beside its words, 加入 before 忽略
    let (jx, jy) = ws_in_panel(t, "加入").unwrap()
    let (ix, iy) = ws_in_panel(t, "忽略").unwrap()
    assert_true(jy == iy && jx < ix, msg=at)
    // the one in use checked: its card's ground under its row
    let (_, cy) = ws_in_panel(t, "星火工作室").unwrap()
    let (_, oy) = ws_in_panel(t, "个人").unwrap()
    assert_true(cy < oy, msg=at)
  }
}
