// The workspaces, a new workspace and the invitations waiting (sfpages' workspace.mbt; Workspaces.kt,
// cloud/workspace.tsx), over the fixture's Home with its workspaces up, the calls kept; and a new workspace from the
// way in of each tier.

///|
fn ws_sheet_core(calls : Array[(String, Json)], invited? : Bool = false) -> @ui.Tester {
  new_run()
  let base = fixture("home-sheet")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      let t = base.topic(name, params).get().snapshot()
      match (name, t.value) {
        ("workspaces", Some(Array(a))) if invited =>
          {
            ..t,
            value: Some(
              Json::array(
                a.map(fn(e) {
                  with_fields(e, [("invitations", [{ "id": "inv2", "name": "开源", "inviter": "安娜", "role": "member" }])])
                }),
              ),
            ),
          }
        _ => t
      }
    },
    call: fn(name, params, done) {
      match name {
        "workspace.create" | "invitation.accept" | "invitation.decline" => {
          calls.push((name, params))
          done(Ok({ "id": "ws9" }))
        }
        _ => (base.call)(name, params, done)
      }
    },
  }
  // the workspaces, as the fixture's home-sheet opens them: from Home's top as it first draws
  home_sheet_at_start.val = true
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.frame()
  t
}

///|
test "the workspaces' sheet: 新建 workspace, named, made by the account (workspace.create), then it is in view" {
  let calls : Array[(String, Json)] = []
  let t = ws_sheet_core(calls)
  presented_rested(t)
  t.tap_text("新建 workspace")
  t.frame()
  presented_rested(t)
  assert_true(t.find("workspace 是一组人和他们共用的 station。你会成为它的 owner。") is Some(_))
  t.tap_text("例如：产品团队")
  t.type_text("产品团队")
  t.frame()
  let (x, y) = words_node(t, "新建").unwrap()
  t.tap(x, y)
  assert_eq(calls.length(), 1)
  assert_eq(calls[0].0, "workspace.create")
  assert_eq(text(Some(calls[0].1), "name"), "产品团队")
  assert_eq(text(Some(calls[0].1), "account"), "u1")
}

///|
test "the workspaces' sheet: an invitation waiting, 加入 joins it, 忽略 ignores it" {
  let calls : Array[(String, Json)] = []
  let t = ws_sheet_core(calls, invited=true)
  presented_rested(t)
  assert_true(t.find("安娜邀请你加入「开源」") is Some(_))
  let (x, y) = words_node(t, "忽略").unwrap()
  let felt = t.haptics().length()
  t.tap(x, y)
  assert_eq(calls.length(), 1)
  assert_eq(calls[0].0, "invitation.decline")
  assert_eq(text(Some(calls[0].1), "id"), "inv2")
  assert_eq(t.haptics()[felt:].to_owned(), [@ui.Confirm])
  t.frame()
  let (x, y) = words_node(t, "加入").unwrap()
  t.tap(x, y)
  assert_eq(calls.length(), 2)
  assert_eq(calls[1].0, "invitation.accept")
  assert_eq(t.haptics()[felt:].to_owned(), [@ui.Confirm, @ui.Confirm])
}

///|
test "a new workspace from each tier's way in, on either screen: Home's name laid out Small, the rail's ＋ else; named and made" {
  for case in [(390.0, 2, false), (720.0, 2, false), (1280.0, 2, true), (390.0, 0, false), (720.0, 0, false), (1280.0, 0, false)] {
    let (w, platform, regular) = case
    let at = "\{w} platform \{platform}"
    let calls : Array[Made] = []
    let t = wide_tester(calls, w~, h=844.0, platform~)
    if regular {
      let log = t.drive("system {\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"}}\n")
      assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
    }
    t.draw()
    if @sfdesk.is_wide(t.ctx()) {
      // the rail's ＋, its menu's 新建 workspace
      let (ax, ay, aw, ah) = t.query(Button, label="新建 workspace、添加账号").unwrap().rect
      t.tap(ax + aw / 2.0, ay + ah / 2.0)
      t.frame()
    } else {
      // Home's name: the workspaces, their 新建 workspace
      t.tap_text("星火工作室")
      t.frame()
      presented_rested(t)
    }
    let (mx, my) = t.find_last("新建 workspace").unwrap()
    t.tap(mx, my)
    t.frame()
    presented_rested(t)
    // (the list's own sheet sinking as far as it is tall: any way is over by then)
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("workspace 是一组人和他们共用的 station。你会成为它的 owner。") is Some(_), msg="\{at}: \{t.words().map(fn(x) { x.0 }).join("|")}")
    // in place of the list that opened it, not over it
    assert_true(t.find("切换 workspace") is None, msg=at)
    t.tap_text("例如：产品团队")
    t.type_text("产品团队")
    t.frame()
    let (bx, by, bw, bh) = t.query(Button, label="新建").unwrap().rect
    t.tap(bx + bw / 2.0, by + bh / 2.0)
    t.frame()
    let made = named(calls, "workspace.create")
    assert_eq(made.length(), 1, msg=at)
    assert_eq(text(Some(made[0].params), "name"), "产品团队", msg=at)
  }
}

///|
/// Home of the fixture `mode` on a window 390 by 844 with the input `platform` (`wide`: made 1200 by 800 first), the
/// core's `workspace.create` kept in `calls` unanswered (the rest the fixture's); 新建 workspace opened over it by
/// nothing, at the frame it opened in.
///|
/// Whether the field with the keys holds `words` (what its host was told it holds).
fn name_typed(t : @ui.Tester, words : String) -> Bool {
  let (active, now, _, _) = t.ime()
  active && now == words
}

///|
/// 新建 at 新建 workspace's foot, as a screen reader finds it: the lowest of those so named.
fn create_button(t : @ui.Tester) -> @ui.SemNode {
  let all = t.all(Button, label="新建")
  guard all.length() > 0 else { @halt.saying("no 新建: \{t.semantics_dump()}") }
  let mut low = all[0]
  for b in all {
    if b.rect.1 > low.rect.1 {
      low = b
    }
  }
  low
}

///|
/// Whether `r` lies within `of`.
fn inside(r : (Double, Double, Double, Double), of : (Double, Double, Double, Double)) -> Bool {
  r.0 >= of.0 - 0.5 && r.1 >= of.1 - 0.5 && r.0 + r.2 <= of.0 + of.2 + 0.5 && r.1 + r.3 <= of.1 + of.3 + 0.5
}

///|
/// 新建 pressed where it is.
fn press_create(t : @ui.Tester) -> Unit {
  let (bx, by, bw, bh) = create_button(t).rect
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  t.frame()
}

fn new_ws_over(calls : Array[Made], platform~ : Int, wide~ : Bool, mode? : String = "home") -> @ui.Tester {
  new_run()
  let base = fixture(mode)
  home_sheet_at_start.val = false
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      if name == "workspace.create" {
        calls.push({ name, params, bytes: None, done })
      } else {
        (base.call)(name, params, done)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform~)
  if wide {
    t.resize(1200.0, 800.0)
  }
  t.run_for(@ui.move_most_ms)
  @sfpages.open_new_workspace(src)
  t.frame()
  t
}

///|
/// The three screens 新建 workspace opens on: a sheet with a finger, a small window with a mouse, a wide one (its
/// dialog in the window's middle).
let new_ws_screens : Array[(Int, Bool)] = [(2, false), (0, false), (0, true)]

///|
/// 新建 workspace's dialog (or sheet) as a screen reader finds it, if it is up.
fn new_ws_dialog(t : @ui.Tester) -> @ui.SemNode? {
  t.semantics().iter().find_first(fn(s) { !s.hidden && s.role == @ui.Role::Dialog })
}

///|
test "新建 workspace on each screen: its name's field has the keys as it opens (the input method up for it with a finger too), what is typed goes in it, Enter makes it" {
  for screen in new_ws_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let calls : Array[Made] = []
    let t = new_ws_over(calls, platform~, wide~)
    t.run_for(@ui.move_most_ms)
    // as it opens, on every screen: its name's field the keys', the input method asked for
    assert_true(t.focus_said().has_prefix("TextField \"例如：产品团队\""), msg="\{at}: \{t.focus_said()}")
    assert_true(t.ime().0, msg=at)
    t.type_text("产品团队")
    t.frame()
    assert_true(name_typed(t, "产品团队"), msg=at)
    t.key(@ui.key_code_enter)
    t.frame()
    assert_eq(calls.length(), 1, msg=at)
    assert_eq(text(Some(calls[0].params), "name"), "产品团队", msg=at)
    assert_eq(text(Some(calls[0].params), "account"), "u1", msg=at)
  }
}

///|
test "新建 workspace: nothing named, 新建 makes nothing; named, made once however often it is pressed while it is made" {
  let calls : Array[Made] = []
  let t = new_ws_over(calls, platform=2, wide=false)
  t.run_for(@ui.move_most_ms)
  t.tap_text("例如：产品团队")
  let press = fn() {
    let (bx, by, bw, bh) = create_button(t).rect
    t.tap(bx + bw / 2.0, by + bh / 2.0)
    t.frame()
  }
  press()
  assert_eq(calls.length(), 0)
  t.type_text("   ")
  t.frame()
  press()
  assert_eq(calls.length(), 0)
  t.type_text("产品团队")
  t.frame()
  press()
  press()
  assert_eq(calls.length(), 1)
  assert_eq(text(Some(calls[0].params), "name"), "产品团队")
}

///|
test "新建 workspace made: what showed it closed, the workspace made the one in view" {
  for screen in new_ws_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let calls : Array[Made] = []
    let t = new_ws_over(calls, platform~, wide~)
    t.run_for(@ui.move_most_ms)
    t.tap_text("例如：产品团队")
    t.type_text("产品团队")
    t.frame()
    press_create(t)
    assert_eq(calls.length(), 1, msg=at)
    // (being made: still up)
    t.run_for(@ui.move_most_ms)
    assert_true(new_ws_dialog(t) is Some(_), msg=at)
    (calls[0].done)(Ok({ "id": "ws9" }))
    t.frame()
    t.run_for(@ui.move_most_ms)
    assert_true(new_ws_dialog(t) is None, msg=at)
    assert_true(t.find("workspace 是一组人和他们共用的 station。你会成为它的 owner。") is None, msg=at)
    assert_eq(app.picked.get(), "ws9", msg=at)
  }
}

///|
test "新建 workspace not made: it stays up, why said under what it holds, 新建 pressed again makes it again" {
  for screen in new_ws_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let calls : Array[Made] = []
    let t = new_ws_over(calls, platform~, wide~)
    t.run_for(@ui.move_most_ms)
    t.tap_text("例如：产品团队")
    t.type_text("产品团队")
    t.frame()
    press_create(t)
    (calls[0].done)(Err({ "code": "too_many_workspaces", "message": "too many" }))
    t.frame()
    t.run_for(@ui.move_most_ms)
    assert_true(new_ws_dialog(t) is Some(_), msg=at)
    guard t.find("每个账号最多新建 5 个 workspace") is Some((_, ey)) else { fail("\{at}: no error") }
    let (_, ny, _, _) = t.get(TextField, label="例如：产品团队").rect
    assert_true(ey > ny, msg="\{at}: the error under the name")
    // no code asked for: no field for one
    assert_true(t.find("邀请码") is None, msg=at)
    assert_true(app.picked.get() != "ws9", msg=at)
    let (bx, by, bw, bh) = create_button(t).rect
    t.tap(bx + bw / 2.0, by + bh / 2.0)
    t.frame()
    assert_eq(calls.length(), 2, msg=at)
  }
}

///|
test "新建 workspace asked for an invite code: its field under the name, its hint while empty, why once one is typed; Enter in it makes it with the code" {
  for screen in new_ws_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let calls : Array[Made] = []
    let t = new_ws_over(calls, platform~, wide~)
    t.run_for(@ui.move_most_ms)
    t.tap_text("例如：产品团队")
    t.type_text("产品团队")
    t.frame()
    press_create(t)
    (calls[0].done)(Err({ "code": "invite_code_required", "message": "code" }))
    t.frame()
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("邀请码") is Some(_), msg=at)
    let hint = "免费版仅可创建 1 个 workspace，此账号已创建。输入邀请码升级到标准版即可创建更多。"
    assert_true(t.find(hint) is Some(_), msg=at)
    // (why it was not made said under the code's field, not on its own as well)
    assert_true(t.find("免费版仅可创建 1 个 workspace，继续创建需要邀请码") is None, msg=at)
    // Enter in the code's field while it is empty: nothing
    t.tap_text("XXXX-XXXX-XXXX")
    t.frame()
    t.key(@ui.key_code_enter)
    t.frame()
    assert_eq(calls.length(), 1, msg=at)
    t.type_text("AAAA-BBBB-CCCC")
    t.frame()
    // a code typed: why it was refused in the hint's place
    assert_true(t.find("免费版仅可创建 1 个 workspace，继续创建需要邀请码") is Some(_), msg=at)
    assert_true(t.find(hint) is None, msg=at)
    t.key(@ui.key_code_enter)
    t.frame()
    assert_eq(calls.length(), 2, msg=at)
    assert_eq(text(Some(calls[1].params), "invite_code"), "AAAA-BBBB-CCCC", msg=at)
    assert_eq(text(Some(calls[1].params), "name"), "产品团队", msg=at)
  }
}

///|
test "新建 workspace with two accounts signed in: 所属账号 lists both, the first chosen; the other pressed, made by it" {
  for screen in new_ws_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let calls : Array[Made] = []
    let t = new_ws_over(calls, platform~, wide~, mode="home-accounts")
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("所属账号") is Some(_), msg=at)
    assert_eq(t.all(Radio).length(), 2, msg=at)
    assert_true(t.query(Radio, label="lin@example.com", checked=On) is Some(_), msg=at)
    let (rx, ry, rw, rh) = t.get(Radio, label="lin@work.example").rect
    t.tap(rx + rw / 2.0, ry + rh / 2.0)
    t.frame()
    t.run_for(@ui.move_most_ms)
    assert_true(t.query(Radio, label="lin@work.example", checked=On) is Some(_), msg=at)
    assert_true(t.query(Radio, label="lin@example.com", checked=Off) is Some(_), msg=at)
    t.tap_text("例如：产品团队")
    t.type_text("产品团队")
    t.frame()
    press_create(t)
    assert_eq(calls.length(), 1, msg=at)
    assert_eq(text(Some(calls[0].params), "account"), "u2", msg=at)
  }
}

///|
test "新建 workspace with one account: no 所属账号" {
  let t = new_ws_over([], platform=2, wide=false)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("所属账号") is None)
  assert_eq(t.all(Radio).length(), 0)
}

///|
test "新建 workspace: 取消 closes it, what was typed let go of; opened again, empty" {
  for screen in new_ws_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let calls : Array[Made] = []
    let t = new_ws_over(calls, platform~, wide~)
    t.run_for(@ui.move_most_ms)
    t.tap_text("例如：产品团队")
    t.type_text("产品团队")
    t.frame()
    let (bx, by, bw, bh) = t.get(Button, label="取消").rect
    t.tap(bx + bw / 2.0, by + bh / 2.0)
    t.frame()
    t.run_for(@ui.move_most_ms)
    assert_true(new_ws_dialog(t) is None, msg=at)
    assert_eq(calls.length(), 0, msg=at)
    @sfpages.open_new_workspace(fixture("home"))
    t.frame()
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("例如：产品团队") is Some(_), msg=at)
    assert_false(name_typed(t, "产品团队"), msg=at)
  }
}

///|
test "新建 workspace closed while it is being made: made, the workspace in view all the same" {
  let calls : Array[Made] = []
  let t = new_ws_over(calls, platform=0, wide=true)
  t.run_for(@ui.move_most_ms)
  t.tap_text("例如：产品团队")
  t.type_text("产品团队")
  t.frame()
  press_create(t)
  t.key(@ui.key_escape)
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(new_ws_dialog(t) is None)
  (calls[0].done)(Ok({ "id": "ws9" }))
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_eq(app.picked.get(), "ws9")
  assert_true(new_ws_dialog(t) is None)
}

///|
test "新建 workspace on each screen: what it is for over 名称, its field under that, 所属账号's two under it, 取消 before 新建 at its foot, all of it in it" {
  for screen in new_ws_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let t = new_ws_over([], platform~, wide~, mode="home-accounts")
    t.run_for(@ui.move_most_ms)
    guard new_ws_dialog(t) is Some(d) else { fail("\{at}: not up") }
    let (_, lead_y) = t.find("workspace 是一组人和他们共用的 station。你会成为它的 owner。").unwrap()
    let (_, name_y) = t.find("名称").unwrap()
    let field = t.get(TextField, label="例如：产品团队").rect
    let (_, owner_y) = t.find("所属账号").unwrap()
    let radios = t.all(Radio)
    assert_eq(radios.length(), 2, msg=at)
    let cancel = t.all(Button, label="取消")
    assert_eq(cancel.length(), 1, msg=at)
    let create = create_button(t)
    assert_true(inside(field, d.rect), msg="\{at}: \{Repr(field)} in \{Repr(d.rect)}")
    assert_true(lead_y < name_y && name_y < field.1 && field.1 + field.3 <= owner_y, msg="\{at}: \{lead_y} \{name_y} \{Repr(field)} \{owner_y}")
    assert_true(owner_y < radios[0].rect.1 && radios[0].rect.1 < radios[1].rect.1, msg=at)
    assert_true(radios[1].rect.1 + radios[1].rect.3 <= cancel[0].rect.1, msg=at)
    // its foot: 取消 then 新建, on one line
    assert_eq(cancel[0].rect.1, create.rect.1, msg=at)
    assert_true(cancel[0].rect.0 + cancel[0].rect.2 <= create.rect.0, msg=at)
    // the rows across as the field is
    assert_eq(radios[0].rect.0 <= field.0, true, msg="\{at}: \{Repr(radios[0].rect)} \{Repr(field)}")
  }
}

///|
test "新建 workspace's sheet closed by 取消 two frames into its invite code's field opening: it sinks on from as fast as its top went, frame by frame" {
  // (judged frame to frame on frame()'s, the display's own: the default run's alone, @ui.test_at_a_rate)
  if @ui.test_at_a_rate() {
    return
  }
  let calls : Array[Made] = []
  let t = new_ws_over(calls, platform=2, wide=false)
  t.run_for(@ui.move_most_ms)
  t.tap_text("例如：产品团队")
  t.type_text("产品团队")
  t.frame()
  press_create(t)
  (calls[0].done)(Err({ "code": "invite_code_required", "message": "code" }))
  t.frame()
  // (two frames of the field opening, the sheet's top going up with it)
  t.frame()
  t.frame()
  let (bx, by, bw, bh) = t.get(Button, label="取消").rect
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  let till = t.time() + @ui.move_most_ms
  while t.time() < till {
    t.frame()
  }
  assert_true(new_ws_dialog(t) is None)
}

///|
test "新建 workspace's sheet closed by 取消 three frames into its invite code's field opening: the field turned back as it sinks, its height slowing and gaining again without a step" {
  // (judged frame to frame on frame()'s, the display's own: the default run's alone, @ui.test_at_a_rate)
  if @ui.test_at_a_rate() {
    return
  }
  let calls : Array[Made] = []
  let t = new_ws_over(calls, platform=2, wide=false)
  t.run_for(@ui.move_most_ms)
  t.tap_text("例如：产品团队")
  t.type_text("产品团队")
  t.frame()
  press_create(t)
  (calls[0].done)(Err({ "code": "invite_code_required", "message": "code" }))
  t.frame()
  // (three frames of 60 a second of the field opening, 取消 then letting go of the error: the field called back as it
  // opens, its room turned back as the sheet sinks)
  let a_frame = 1000.0 / 60.0
  let opened = t.time() + 3.0 * a_frame
  while t.time() < opened - 0.001 {
    t.run_for(a_frame)
  }
  let (bx, by, bw, bh) = t.get(Button, label="取消").rect
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  let till = t.time() + @ui.move_most_ms
  while t.time() < till {
    t.run_for(a_frame)
  }
  assert_true(new_ws_dialog(t) is None)
}
