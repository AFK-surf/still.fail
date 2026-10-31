// A service's page (service.mbt) over the fixture (service_fixture.mbt): its bar, its page's requests answered from the
// station (the fake host's site says them), redirects and cookies as the Android app's PreviewLink has them.

///|
fn service_tester(mode : String) -> @ui.Tester {
  new_run()
  let src = fixture(mode)
  open_drive_fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  // the page opened slid in
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "a service's page: its name and station in the bar, under the page one row (where it is, its ⋯); no toolbar" {
  let t = service_tester("service")
  t.frame()
  assert_true(t.find("web") is Some(_))
  assert_true(t.find("对话") is Some(_))
  // back, forward, where it is with reload at its end, marking, its ⋯ (its size, how far its resources came): one row
  for key in ["后退", "前进", "刷新", "标注", "更多操作"] {
    assert_true(t.query(Button, label=key) is Some(_), msg=key)
  }
  let reload = t.query(Button, label="刷新").unwrap().rect
  let more = t.query(Button, label="更多操作").unwrap().rect
  assert_true((reload.1 + reload.3 / 2.0 - (more.1 + more.3 / 2.0)).abs() < 1.0, msg="one row")
  assert_true(t.query(Button, label="页面尺寸") is None, msg="its size in its ⋯")
  // (its sizes are chosen in one place on every screen: none under the page)
  assert_true(t.find("自适应") is None, msg="no toolbar under the page")
  assert_true(t.views().iter().any(fn(s) { s.has_prefix("open ") && s.contains(" 3 ") }))
  t.assert_idle()
}

///|
test "the address tapped: typed in with the keyboard for addresses, its action key a go key (Preview.kt: ImeAction.Go)" {
  let t = service_tester("service")
  t.frame()
  let (x, y) = t.find_last("web").unwrap()
  t.tap(x, y)
  t.frame()
  let (active, _, _, _) = t.ime()
  assert_true(active)
  assert_eq(t.ime_action(), @hostapi.ime_action_go)
}

///|
test "a phone's size, in its ⋯: its sizes in a sheet; 移动页面 on, said on its key in the ⋯'s place, pressed it stops" {
  let t = service_tester("service-sized")
  t.frame()
  t.click(Button, label="更多操作")
  t.frame()
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  t.tap_text("页面尺寸")
  t.frame()
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(t.find("自适应") is Some(_), msg="its sizes")
  assert_true(t.find("自定义") is Some(_), msg="any size")
  // moving the page by a finger, from the sheet (the sheet goes: what it changes is the page under it)
  t.click(Switch, label="移动页面")
  t.frame()
  let p = service_pages.get(service_key("ws1/st1", "j-web")).unwrap()
  assert_true(p.moving, msg="moving")
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  // said on the size key in the ⋯'s place, which stops it at once
  assert_true(t.query(Button, label="停止移动页面") is Some(_), msg="the key says it")
  assert_true(t.query(Button, label="更多操作") is None, msg="in the ⋯'s place")
  t.click(Button, label="停止移动页面")
  t.frame()
  assert_true(!p.moving, msg="stopped")
  assert_true(t.query(Button, label="更多操作") is Some(_))
}

///|
test "the page's requests answered from the station through the core: the head, the body, the end; not found said" {
  let t = service_tester("service")
  t.frame()
  t.site_says("{\"req\":1,\"method\":\"GET\",\"path\":\"/\",\"headers\":[[\"Accept\",\"text/html\"]],\"page\":true}")
  t.frame()
  let v = t.views()
  assert_true(v.iter().any(fn(s) { s.has_prefix("site head ") && s.contains(" 1 200 ") && s.contains("text/html") }))
  assert_true(v.iter().any(fn(s) { s.has_prefix("site chunk ") && s.contains(" 1 ") }))
  assert_true(v.iter().any(fn(s) { s.has_prefix("site end ") && s.has_suffix(" 1 ") }))
  t.site_says("{\"req\":2,\"method\":\"GET\",\"path\":\"/nothing\",\"headers\":[],\"page\":false}")
  t.frame()
  assert_true(t.views().iter().any(fn(s) { s.has_prefix("site head ") && s.contains(" 2 404 ") }))
  t.assert_idle()
}

///|
test "a service being started again is said over its page; one stopped in its place" {
  let t = service_tester("service-restart")
  t.frame()
  assert_true(t.find("web正在重启") is Some(_))
  assert_true(t.find("第 2 次") is Some(_))
  let s = service_tester("service-stopped")
  s.frame()
  assert_true(s.find("「web」已停止") is Some(_))
  s.assert_idle()
}

///|
test "redirects: to the service's own paths only; relative ones from the path's folder" {
  assert_eq(service_redirect("/a/b?x=1", "/login"), Ok("/login"))
  assert_eq(service_redirect("/a/b", "c?d=1"), Ok("/a/c?d=1"))
  assert_eq(service_redirect("/a/b?x=1", "?y=2"), Ok("/a/b?y=2"))
  assert_eq(service_redirect("/", "http://localhost:5173/next"), Ok("/next"))
  assert_true(service_redirect("/", "https://example.com/x") is Err(_))
  assert_true(service_redirect("/", "//example.com/x") is Err(_))
}

///|
test "cookies: several in one header apart (an Expires date's comma kept), each kept by name, an expired one let go" {
  let parts = split_cookies("a=1; Path=/, b=2; Expires=Wed, 21 Oct 2026 07:28:00 GMT; HttpOnly")
  assert_eq(parts.length(), 2)
  assert_true(parts[1].has_prefix("b=2"))
  let p = service_page_for("ws1/st1", "j-test")
  service_keep_cookie(p, "a=1; Path=/, b=2; Expires=Wed, 21 Oct 2026 07:28:00 GMT")
  assert_eq(p.cookies.get("a"), Some("1"))
  assert_eq(p.cookies.get("b"), Some("2"))
  service_keep_cookie(p, "a=; Max-Age=0")
  assert_eq(p.cookies.get("a"), None)
}

///|
test "a size chosen: kept on the device (prefs), read as a page opens in a later run" {
  new_run()
  let kept : Array[Json] = []
  svc_keep.val = fn(patch) { kept.push(patch) }
  keep_size(service_key("ws1/st1", "j-a"), Some({ width: 390, height: Some(844) }))
  keep_size(service_key("ws1/st1", "j-b"), Some({ width: 1280, height: None }))
  keep_size(service_key("ws1/st1", "j-c"), None)
  assert_eq(text(field(Some(kept[0]), "previewSizes"), "ws1/st1\nj-a"), "390x844")
  assert_eq(text(field(Some(kept[1]), "previewSizes"), "ws1/st1\nj-b"), "1280")
  assert_true(field(field(Some(kept[2]), "previewSizes"), "ws1/st1\nj-c") == Some(Json::null()))
  // a later run: nothing chosen since it started, the pages open as the core kept them
  new_run()
  let prefs : Json = {
    "previewSizes": { "ws1/st1\nj-a": "390x844", "ws1/st1\nj-b": "1280", "ws1/st1\nj-d": "wide" },
  }
  let a = service_page_for("ws1/st1", "j-a", prefs=Some(prefs))
  assert_true(a.viewport == Some({ width: 390, height: Some(844) }))
  let b = service_page_for("ws1/st1", "j-b", prefs=Some(prefs))
  assert_true(b.viewport == Some({ width: 1280, height: None }))
  // one that does not read: as big as the preview
  let d = service_page_for("ws1/st1", "j-d", prefs=Some(prefs))
  assert_true(d.viewport is None)
}

///|
test "how far the resources came, from a phone's ⋯: their list in a sheet as tall as they are, not a share of the window" {
  let t = service_tester("service")
  t.frame()
  t.click(Button, label="更多操作")
  t.frame()
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  t.tap_text("资源加载 75% · 3/4")
  t.frame()
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(t.find("/app.css") is Some(_), msg="its rows")
  // the last of them where the sheet ends: under it only the sheet's own foot (its padding, the home bar's room)
  let (_, y, _, h) = t.rect_of("/api/builds").unwrap()
  assert_true(844.0 - (y + h) < 80.0, msg="room left under the list: \{844.0 - (y + h)}")
  assert_eq(t.squeeze_faults(), [])
}
