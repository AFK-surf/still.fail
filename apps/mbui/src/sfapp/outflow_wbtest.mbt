// A station page's 数据外流 (sfpages/station_outflow.mbt, docs/data-outflow.md): the programs asking for its data,
// which an admin answers kind by kind, confirming what is given before it is; and those granted it, each with who
// signed it and what it may read; 取消授权 asks first.

///|
test "a station's settings list the programs granted its data, and revoking one asks first" {
  new_run()
  @settings.reset()
  @settings.fixture_outflow(true)
  let src = fixture("settings")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=3200.0, platform=2)
  t.draw()
  // the station's page, at its settings (a login's link opens it there)
  assert_true(open_target(src, link_target({ "opens": "login", "workspace": "ws1", "station": "st1", "login": "login-2" }), false, None))
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(tr("web-main.outflow.title")) is Some(_), msg="the section")
  assert_true(t.find("Comma") is Some(_), msg="the program")
  assert_true(t.find("token 用量和金额、chat 和它们的状态") is Some(_), msg="what it may read")
  // (a window tall enough for the section to be in it, under the logins' card brought into view; its button's words
  // alone, the section's lead says them too)
  let (x, y) = last_words(t, tr("web-main.outflow.revoke")).unwrap()
  t.tap(x, y)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(@sf.presenting(), msg="a question up")
  assert_true(t.find(tr("web-main.outflow.revokeConfirm").replace(old="{program}", new="Comma")) is Some(_), msg="asked first")
}

///|
test "a station's settings with no program granted its data ask nothing of it" {
  new_run()
  @settings.reset()
  let src = fixture("settings")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=2400.0, platform=2)
  t.draw()
  assert_true(open_target(src, link_target({ "opens": "login", "workspace": "ws1", "station": "st1", "login": "login-2" }), false, None))
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(tr("web-main.logins.title")) is Some(_), msg="its settings")
  assert_true(t.find(tr("web-main.outflow.title")) is None, msg="no section")
}

///|
test "an admin allows a program what they leave of what it asks, once the summary of it is confirmed" {
  new_run()
  @settings.reset()
  @settings.fixture_outflow(true)
  let src = fixture("settings")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=3200.0, platform=2)
  t.draw()
  assert_true(open_target(src, link_target({ "opens": "login", "workspace": "ws1", "station": "st1", "login": "login-2" }), false, None))
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("Comma for Teams") is Some(_), msg="the program asking")
  assert_true(t.find("Comma — 按团队算 token 的 ROI") is Some(_), msg="what it says of itself")
  // the whole workspace taken out: this station's alone
  t.tap_text(tr("web-main.outflow.wholeWorkspace"))
  t.frame()
  let (x, y) = last_words(t, tr("web-main.outflow.allow")).unwrap()
  t.tap(x, y)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(@sf.presenting(), msg="asked once more")
  assert_true(t.find(tr("web-main.outflow.whereStation")) is Some(_), msg="the summary says how far it reaches")
  assert_true(@settings.fixture_outflow_answer() is None, msg="nothing given before it is confirmed")
  t.run_for(@kit.presence_in_ms)
  let (x, y) = last_words(t, tr("web-main.outflow.allow")).unwrap()
  t.tap(x, y)
  t.frame()
  let answer = @settings.fixture_outflow_answer()
  assert_eq(text(answer, "id"), "q1")
  assert_eq(text(answer, "station"), "ws1/st1")
  assert_true(flag(answer, "allow"))
  assert_true(!flag(answer, "workspace"), msg="the workspace taken out")
  assert_eq(items(answer, "scopes").map(fn(s) {
      match s {
        String(v) => v
        _ => ""
      }
    }), ["usage", "chats"])
}

///|
/// The last words on screen that are `s` alone (a sheet's, over the page): their middle.
fn last_words(t : @ui.Tester, s : String) -> (Double, Double)? {
  let want = " \"" + s + "\" "
  let mut found = None
  for l in t.dump().split("\n") {
    let l = l.trim_start(chars=" ").to_string()
    if l.has_prefix("text ") && l.contains(want) {
      let parts = l.split(" ").collect()
      let xy = parts[1].split(",").collect()
      let wh = parts[2].split("x").collect()
      found = Some(
        (
          dump_number(xy[0].to_string()) + dump_number(wh[0].to_string()) / 2.0,
          dump_number(xy[1].to_string()) + dump_number(wh[1].to_string()) / 2.0,
        ),
      )
    }
  }
  found
}
