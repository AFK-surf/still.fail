// A web service and a visualization beside a chat on the desktop (sfdesk/service_tab.mbt; ember web/src/pages/Chat.tsx's
// side panel, Preview.tsx): asked as a page, the chat's page with it in front among the side panel's tabs, its page
// served from the station; closed, its site view let go.

///|
test "desk: a web service asked as a page is its chat with the service beside it, served from the station; closed, let go" {
  reset()
  // (its agent's services known to the chat: the core keeps only a tab of one of them)
  let src = fixture("chat-info")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.nav_push_ms)
  app.nav.push(Service("ws1/st1", "j-web"))
  t.frame()
  t.frame()
  // the chat's page, in place of the page asked; the service in front beside it
  assert_true(app.nav.top() == Chat(r), msg="the chat's page")
  assert_eq(side_now(r), (["service:j-web"], "service:j-web"))
  t.run_for(@sfdesk.side_in_ms)
  assert_true(t.query(Button, label="刷新") is Some(_), msg="its bar")
  // its page's size on a computer: the bar's button, its choices in a panel beside it (ViewportSize.tsx), no toolbar
  // under the page as a touch device has
  assert_true(t.find("自适应") is None, msg="no toolbar under the page")
  t.click(Button, label="页面尺寸")
  t.frame()
  assert_true(t.find("自适应") is Some(_), msg="its sizes")
  assert_true(service_pages.contains(service_key("ws1/st1", "j-web")), msg="its page open")
  t.site_says("{\"req\":1,\"method\":\"GET\",\"path\":\"/\",\"headers\":[[\"Accept\",\"text/html\"]],\"page\":true}")
  t.frame()
  assert_true(t.views().iter().any(fn(s) { s.has_prefix("site head ") && s.contains(" 1 200 ") && s.contains("text/html") }))
  // its tab closed: its page let go
  side_change(r, "close", Some("service:j-web"))
  t.frame()
  assert_eq(side_now(r), ([], ""))
  // (shown as the panel slides out, let go once it is gone)
  t.run_for(@sfdesk.side_out_ms)
  t.frame()
  assert_true(!service_pages.contains(service_key("ws1/st1", "j-web")), msg="let go")
}

///|
test "desk: a visualization opened aside is a tab beside its chat, served from here with its name in the bar" {
  reset()
  let src = fixture("chat-viz")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.nav_push_ms)
  app.nav.push(PreviewFile("ws1/st1", "s-c1", "work/s-c1/release.html", "release.html"))
  t.frame()
  t.frame()
  let tab = @sfdesk.file_tab("s-c1", "work/s-c1/release.html", "release.html")
  assert_true(app.nav.top() == Chat(r), msg="the chat's page")
  assert_eq(side_now(r), ([tab], tab))
  t.run_for(@sfdesk.side_in_ms)
  t.frame()
  let (x, _) = t.find_last("release.html").unwrap()
  assert_true(x > 800.0, msg="its name beside the chat: \{x}")
  side_change(r, "close", Some(tab))
  t.frame()
  assert_eq(side_now(r), ([], ""))
}

///|
test "desk: a service up pressed in 任务 beside the chat opens its own tab in front (JobsTab)" {
  reset()
  let src = fixture("chat-jobs-side")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.nav_push_ms)
  t.run_for(@sfdesk.side_in_ms)
  assert_eq(side_now(r), (["jobs"], "jobs"))
  let (x, y) = t.find_last("web").unwrap()
  assert_true(x > 800.0, msg="its row beside the chat: \{x}")
  t.tap(x, y)
  t.frame()
  t.frame()
  let (tabs, front) = side_now(r)
  assert_eq(front, "service:j-web")
  assert_true(tabs.contains("jobs") && tabs.contains("service:j-web"), msg="\{tabs}")
}
