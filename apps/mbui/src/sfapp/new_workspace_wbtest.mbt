// The workspaces, a new workspace and the invitations waiting (sfpages' workspace.mbt; Workspaces.kt,
// cloud/workspace.tsx), over the fixture's Home with its workspaces up, the calls kept; and a new workspace from the
// way in of each tier.

///|
fn ws_sheet_core(calls : Array[(String, Json)], invited? : Bool = false) -> @ui.Tester {
  reset()
  let base = fixture("home-sheet")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      let t = (base.topic)(name, params)
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
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.frame()
  t
}

///|
test "the workspaces' sheet: 新建 workspace, named, made by the account (workspace.create), then it is in view" {
  let calls : Array[(String, Json)] = []
  let t = ws_sheet_core(calls)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  t.tap_text("新建 workspace")
  t.frame()
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
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
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(t.find("安娜邀请你加入「开源」") is Some(_))
  let (x, y) = words_node(t, "忽略").unwrap()
  t.tap(x, y)
  assert_eq(calls.length(), 1)
  assert_eq(calls[0].0, "invitation.decline")
  assert_eq(text(Some(calls[0].1), "id"), "inv2")
  t.frame()
  let (x, y) = words_node(t, "加入").unwrap()
  t.tap(x, y)
  assert_eq(calls.length(), 2)
  assert_eq(calls[1].0, "invitation.accept")
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
      t.run_for(@kit.sheet_rest("sf-present") - t.time())
    }
    let (mx, my) = t.find_last("新建 workspace").unwrap()
    t.tap(mx, my)
    t.frame()
    t.run_for(@kit.sheet_rest("sf-present") - t.time())
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
