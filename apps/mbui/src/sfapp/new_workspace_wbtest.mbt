// The workspaces' sheet's new workspace and its invitations waiting (new_workspace.mbt; Workspaces.kt), over the
// fixture's Home with its sheet up, the calls kept.

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
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  // the workspaces' sheet, as its name on Home opens it
  raise_sheet(Workspaces)
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
