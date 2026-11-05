// Home's cards at its lists' top and foot (what the last update brought, what the update wants, what is left up long:
// news_node.mbt, open_jobs_node.mbt) are nodes of the window's tree: shown, they host no old view, on a small screen and
// a large one.

///|
test "Home's news, update and long jobs' cards host no old view, on a small screen and a large one" {
  let wrong : Array[String] = []
  for win in [("phone", 360.0, 740.0, 2, ""), ("wide", 1280.0, 800.0, 0, "")] {
    let bare = screen_in("home", win, "zh").old_views_hosted()
    for mode in ["home-news", "home-update", "home-jobs"] {
      let n = screen_in(mode, win, "zh").old_views_hosted()
      if n != bare {
        wrong.push("\{win.0} \{mode}: \{n} old views hosted, \{bare} on Home without it")
      }
    }
  }
  assert_eq(wrong, [])
}

///|
test "Home's catching up and transfers keys host no old view, turning, at rest and with the list open" {
  let wrong : Array[String] = []
  new_run()
  let bare = @ui.Tester::new(fn(c) { view(c, fixture("home")) }, tree=app_tree(fixture("home")), w=360.0, h=740.0, platform=2)
  let none = bare.old_views_hosted()
  new_run()
  let calls : Array[(String, Json)] = []
  let src = downloads_src("home-syncing", [listed("dist.zip", "going", 1.0, 50.0, "正在下载")], calls)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=360.0, h=740.0, platform=2)
  t.run_for(@sf.later_ms + @kit.presence_in_ms)
  if t.query(Status, label="正在同步 · 还剩 12 个对话") is None {
    wrong.push("the catching up key is not there")
  }
  if t.old_views_hosted() != none {
    wrong.push("turning: \{t.old_views_hosted()} old views hosted, \{none} on Home without them")
  }
  let (x, y, w, h) = t.query(Button, label="1 个传输 · 2%").unwrap().rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  if !@sf.presenting() {
    wrong.push("pressed, the transfers' list is not open")
  }
  // (a small screen's: on a medium or large one what comes is the sidebar's, not Home's top bar)
  for win in [("phone", 360.0, 740.0, 2, "")] {
    let n = screen_in("home-transfers", win, "zh").old_views_hosted()
    let b = screen_in("home", win, "zh").old_views_hosted()
    if n != b {
      wrong.push("\{win.0} home-transfers: \{n} old views hosted, \{b} on Home without it")
    }
  }
  assert_eq(wrong, [])
}
