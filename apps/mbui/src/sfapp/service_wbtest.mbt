// A service's page (service.mbt) over the fixture (service_fixture.mbt): its bar, its page's requests answered from the
// station (the fake host's site says them), redirects and cookies as the Android app's PreviewLink has them.

///|
fn service_tester(mode : String) -> @ui.Tester {
  reset()
  let src = fixture(mode)
  open_drive_fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  // the page opened slid in
  t.run_for(@ui.nav_push_ms)
  t
}

///|
test "a service's page: its name and station in the bar, where it is, the sizes under it, its resources' ring" {
  let t = service_tester("service")
  t.frame()
  assert_true(t.find("web") is Some(_))
  assert_true(t.find("对话") is Some(_))
  assert_true(t.find("自适应") is Some(_))
  assert_true(t.find("手机") is Some(_))
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
test "the sizes' bar held still half a second: folded away, felt once (Preview.kt: LongPress)" {
  let t = service_tester("service")
  t.frame()
  let (x, y) = t.find("自适应").unwrap()
  t.press_at(x, y)
  t.run_for(@sfpages.svc_fold_hold_ms + 100.0)
  t.release(x, y)
  assert_eq(svc_folded.val, Some(true))
  assert_eq(t.haptics(), [@ui.Haptic::LongPress])
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
test "a size chosen and the toolbar folded: kept on the device (prefs), read as a page opens in a later run" {
  reset()
  let kept : Array[Json] = []
  svc_keep.val = fn(patch) { kept.push(patch) }
  keep_size(service_key("ws1/st1", "j-a"), Some({ width: 390, height: Some(844) }))
  keep_size(service_key("ws1/st1", "j-b"), Some({ width: 1280, height: None }))
  keep_size(service_key("ws1/st1", "j-c"), None)
  keep_folded(true)
  assert_eq(text(field(Some(kept[0]), "previewSizes"), "ws1/st1\nj-a"), "390x844")
  assert_eq(text(field(Some(kept[1]), "previewSizes"), "ws1/st1\nj-b"), "1280")
  assert_true(field(field(Some(kept[2]), "previewSizes"), "ws1/st1\nj-c") == Some(Json::null()))
  assert_true(flag(Some(kept[3]), "previewFolded"))
  // a later run: nothing chosen since it started, the pages open as the core kept them
  reset()
  let prefs : Json = {
    "previewSizes": { "ws1/st1\nj-a": "390x844", "ws1/st1\nj-b": "1280", "ws1/st1\nj-d": "wide" },
    "previewFolded": true,
  }
  let a = service_page_for("ws1/st1", "j-a", prefs=Some(prefs))
  assert_true(a.viewport == Some({ width: 390, height: Some(844) }))
  assert_true(a.folded)
  let b = service_page_for("ws1/st1", "j-b", prefs=Some(prefs))
  assert_true(b.viewport == Some({ width: 1280, height: None }))
  // one that does not read: as big as the preview
  let d = service_page_for("ws1/st1", "j-d", prefs=Some(prefs))
  assert_true(d.viewport is None)
}
