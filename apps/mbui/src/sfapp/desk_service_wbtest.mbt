// A web service and a visualization beside a chat on the desktop (sfdesk/service_tab.mbt; ember web/src/pages/Chat.tsx's
// side panel, Preview.tsx): asked as a page, the chat's page with it in front among the side panel's tabs, its page
// served from the station; closed, its site view let go.

///|
test "desk: a web service asked as a page is its chat with the service beside it, served from the station; closed, let go" {
  new_run()
  // (its agent's services known to the chat: the core keeps only a tab of one of them)
  let src = fixture("chat-info")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  // (a window whose side panel holds the whole of its bar, a press's room round each key: a 1280's leaves its size and
  // how far it came to its ⋯)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1440.0, h=900.0, platform=0)
  t.run_for(@ui.move_most_ms)
  app.nav.push(Service("ws1/st1", "j-web"))
  t.frame()
  t.frame()
  // the chat's page, in place of the page asked; the service in front beside it
  assert_true(app.nav.top() == Chat(r), msg="the chat's page")
  assert_eq(side_now(r), (["service:j-web"], "service:j-web"))
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Button, label="刷新") is Some(_), msg="its bar")
  // its page's size with keyboard and mouse: the bar's button, its choices in a panel beside it (ViewportSize.tsx), no toolbar
  // under the page as touch has
  assert_true(t.find("自适应") is None, msg="no toolbar under the page")
  let had = t.ctx().focused_id()
  t.click(Button, label="页面尺寸")
  t.frame()
  assert_true(t.find("自适应") is Some(_), msg="its sizes")
  // as the web's (ViewportSize.tsx: the focus not taken as it opens: where it was, the composer's), all of them in the
  // panel's room
  assert_eq(t.ctx().focused_id(), had)
  assert_eq(t.squeeze_faults(), [])
  t.key(@ui.key_escape)
  t.frame()
  // marking it: what to do said in the address's place beside its keys (Marks.tsx mode), all of it in the tab's room
  t.click(Button, label="标注")
  t.frame()
  assert_true(t.find("点选页面上的元素") is Some(_), msg="what to do")
  // (four of its characters at least: what is beside it gives way first)
  let (_, _, said_w, _) = t.rect_of("点选页面上的元素").unwrap()
  assert_true(said_w >= 4.0 * 13.0, msg="what to do, \{said_w} wide")
  assert_eq(t.squeeze_faults(), [])
  assert_true(service_pages.contains(service_key("ws1/st1", "j-web")), msg="its page open")
  t.site_says("{\"req\":1,\"method\":\"GET\",\"path\":\"/\",\"headers\":[[\"Accept\",\"text/html\"]],\"page\":true}")
  t.frame()
  assert_true(t.views().iter().any(fn(s) { s.has_prefix("site head ") && s.contains(" 1 200 ") && s.contains("text/html") }))
  // its tab closed: its page let go
  side_change(r, "close", Some("service:j-web"))
  t.frame()
  assert_eq(side_now(r), ([], ""))
  // (shown as the panel slides out, let go once it is gone)
  t.run_for(@ui.move_most_ms)
  t.frame()
  assert_true(!service_pages.contains(service_key("ws1/st1", "j-web")), msg="let go")
}

///|
test "desk: a visualization opened aside is a tab beside its chat, served from here with its name in the bar" {
  new_run()
  let src = fixture("chat-viz")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  app.nav.push(PreviewFile("ws1/st1", "s-c1", "work/s-c1/release.html", "release.html"))
  t.frame()
  t.frame()
  let tab = @sfdesk.file_tab("s-c1", "work/s-c1/release.html", "release.html")
  assert_true(app.nav.top() == Chat(r), msg="the chat's page")
  assert_eq(side_now(r), ([tab], tab))
  t.run_for(@ui.move_most_ms)
  t.frame()
  let (x, _) = t.find_last("release.html").unwrap()
  assert_true(x > 800.0, msg="its name beside the chat: \{x}")
  side_change(r, "close", Some(tab))
  t.frame()
  assert_eq(side_now(r), ([], ""))
}

///|
test "desk: a service up pressed in 任务 beside the chat opens its own tab in front (JobsTab)" {
  new_run()
  let src = fixture("chat-jobs-side")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
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

///|
test "desk: wherever the pointer shows the side panel's edge's ↔, a drag from there sets its width (its room round it as the pointer lights it)" {
  new_run()
  let src = fixture("chat-info")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1440.0, h=900.0, platform=0)
  t.run_for(@ui.move_most_ms)
  side_change(r, "open", Some("s-c1"))
  t.run_for(@ui.move_most_ms)
  let edge_x = fn() raise {
    for s in t.semantics() {
      if s.label.has_prefix("调整侧栏宽度") && !s.hidden {
        return s.rect.0 + s.rect.2 / 2.0
      }
    }
    fail("no side panel edge")
  }
  let line = edge_x()
  let offsets = [-16.0, -12.0, -8.0, -4.0, -2.0, 0.0, 2.0, 4.0, 8.0, 12.0, 16.0]
  let mut shown = 0
  for y in [300.0, 600.0] {
    for dx in offsets {
      let x = line + dx
      t.move(x, y)
      if t.cursor() != ResizeX {
        continue
      }
      shown += 1
      // (its edge on its left: dragged left, the panel wider, its edge as far left as the pointer went)
      t.drag(x, y, x - 30.0, y)
      assert_eq(edge_x(), line - 30.0, msg="from \{dx} at \{y}")
      t.drag(x - 30.0, y, x, y)
      assert_eq(edge_x(), line, msg="back from \{dx} at \{y}")
    }
  }
  assert_true(shown > 0)
}
