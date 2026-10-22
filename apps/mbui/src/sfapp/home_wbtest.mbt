///|
/// The app over a fixture, from its start (the pages, the sheet and the filters forgotten).
fn tester(mode : String) -> @ui.Tester {
  reset()
  let src = fixture(mode)
  @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
}

///|
test "signed out: the sign-in page" {
  let t = tester("signin")
  assert_true(t.find("让 agent 持续工作") is Some(_))
  assert_true(t.find("登录或注册") is Some(_))
  assert_true(t.find("可同时登录多个账号，随时切换 workspace。") is Some(_))
  t.assert_idle()
}

///|
test "Home: the workspace's name, the search, the days and their rows" {
  let t = tester("home")
  assert_true(t.find("星火工作室") is Some(_))
  assert_true(t.find("搜索全部内容") is Some(_))
  assert_true(t.find("今天") is Some(_))
  assert_true(t.find("整理发布清单") is Some(_))
  // the last thing said under a row with no state
  assert_true(t.find("正在核对第三项：安装包的签名") is Some(_))
  // a lead said as an icon: its words after it, not the lead
  assert_true(t.find("测试机的磁盘满了，要不要清理旧的缓存？") is Some(_))
  assert_true(t.find("要你帮忙：测试机的磁盘满了，要不要清理旧的缓存？") is None)
  // 奏 · …: 奏 on its own, bold, the rest after it
  assert_true(t.find("奏") is Some(_))
  // rows are 66 high, under the top bar
  let (_, y1) = t.find("整理发布清单").unwrap()
  let (_, y2) = t.find("首页的列表改成按天分组").unwrap()
  assert_true((y2 - y1 - 66.0).abs() < 0.5)
  assert_true(y1 > 50.0)
}

///|
test "a row tapped pushes its chat, its title in the bar; back comes home" {
  let t = tester("home")
  t.tap_text("夜里的构建又失败了")
  assert_eq(app.nav.depth(), 2)
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("搜索全部内容") is None)
  assert_true(t.find("夜里的构建又失败了") is Some(_))
  assert_true(t.takes_back())
  t.back()
  assert_eq(app.nav.depth(), 1)
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("搜索全部内容") is Some(_))
}

///|
test "the workspaces' sheet: another workspace tapped is the one in view" {
  let t = tester("home")
  t.tap_text("星火工作室")
  assert_true(sheet_open())
  assert_true(t.find("切换 workspace") is Some(_))
  assert_true(t.find("当前使用") is Some(_))
  assert_true(t.find("其他 workspace") is Some(_))
  t.tap_text("个人")
  assert_true(!sheet_open())
  assert_true(t.find("个人") is Some(_))
  // no station there yet: adding the first one is the page
  assert_true(t.find("添加第一台 station") is Some(_))
}

///|
test "the filter: 我参与的 shows only the chats the viewer is in" {
  let t = tester("home")
  match t.rect_of("星火工作室") {
    Some(_) => ()
    None => fail("no title")
  }
  // the filter's button, at the bar's right
  t.tap(390.0 - 16.0 - 17.0, 25.0)
  assert_true(t.find("监控中") is Some(_))
  t.tap_text("我参与的")
  assert_true(t.find("首页的列表改成按天分组") is Some(_))
  assert_true(t.find("夜里的构建又失败了") is Some(_))
  assert_true(t.find("和 Ana 一起看新版的引导页") is Some(_))
}

///|
test "归档 at a row's start archives its chat" {
  let t = tester("home")
  t.scroll_to(12)
  t.draw()
  assert_true(t.find("把旧的截图都换成新的") is Some(_))
  t.tap_text("归档")
  assert_true(t.find("把旧的截图都换成新的") is None)
}

///|
test "a row archived: an archivable row under it closes over it whole, its swipe's clip moving with it" {
  // (Home.kt: the list's animateItem moves the whole of SwipeToArchive. Filmed on a phone: the 归档 rows under one
  // archived gone a moment, then coming up cut off below, the row moved inside a clip left where it is laid out)
  // (the list at its top: the rows under one gone come up; scrolled to its end, the rows over it would come down)
  let t = tester("home")
  let under = "把旧的截图都换成新的"
  let (_, y_was, _, h) = t.rect_of(under).unwrap()
  hold_row(t, "Slack 里问的报销流程")
  // the menu's last item, a row (45) under 复制会话链接
  let (lx, ly) = t.find("复制会话链接").unwrap()
  t.tap(lx, ly + 45.0)
  assert_true(t.find("Slack 里问的报销流程") is None)
  // laid out a row up at once, drawn where it was, all of it
  let (_, y_now, _, _) = t.rect_of(under).unwrap()
  assert_true(y_now < y_was - 1.0, msg="\{y_now} \{y_was}")
  let (_, d0) = t.drawn_of(under).unwrap()
  assert_true((d0 - y_was).abs() < 0.5, msg="drawn at \{d0}, was at \{y_was}")
  let (_, _, _, s0) = t.shown_of(under).unwrap()
  assert_true((s0 - h).abs() < 0.5, msg="\{s0} of \{h} shown where it was")
  // on its way up, all of it still
  t.run_for(@motion.row_spring.duration(y_was - y_now, 0.0, 0.0) / 2.0)
  let (_, d1) = t.drawn_of(under).unwrap()
  assert_true(d1 < y_was - 1.0 && d1 > y_now + 1.0, msg="drawn at \{d1}, from \{y_was} to \{y_now}")
  let (_, _, _, s1) = t.shown_of(under).unwrap()
  assert_true((s1 - h).abs() < 0.5, msg="\{s1} of \{h} shown on its way")
}

///|
test "the list while it is read: no rows, the shapes" {
  let t = tester("loading")
  t.frame()
  assert_true(t.find("整理发布清单") is None)
  assert_true(t.find("星火工作室") is Some(_))
}

///|
test "state leads, in either language" {
  assert_eq(lead_of("要你帮忙：看一下", ["要你帮忙"], ["：", ":"], true), Some(5))
  assert_eq(lead_of("要你帮忙", ["要你帮忙"], ["：", ":"], true), Some(4))
  assert_eq(lead_of("Needs you: look", ["Needs you"], ["：", ":"], true), Some(11))
  assert_eq(lead_of("在等", ["在等"], ["："], false), None)
  assert_eq(lead_of("做完了吗", ["做完了"], ["："], true), None)
}

///|
test "Java's hashCode" {
  assert_eq(java_hash("a"), 97)
  assert_eq(java_hash("ab"), 97 * 31 + 98)
  // wraps as Java's int does
  assert_eq(java_hash("polygenelubricants"), -2147483648)
}

///|
/// A row held long (Home.kt's onLongPress) at `title`'s words, then let go there.
fn hold_row(t : @ui.Tester, title : String) -> Unit {
  let (x, y) = t.find(title).unwrap()
  t.press_at(x, y)
  t.run_for(hold_ms)
  t.release(x, y)
}

///|
test "a row held long: its menu (固定, 重命名, 复制会话链接, 归档), the chat not opened; 重命名 its sheet" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0)
  hold_row(t, "夜里的构建又失败了")
  assert_eq(app.nav.depth(), 1)
  // felt as it opened, once
  assert_eq(t.haptics(), [@ui.Haptic::LongPress])
  assert_true(t.find("重命名") is Some(_))
  assert_true(t.find("复制会话链接") is Some(_))
  // just below the row
  let (_, row_y) = t.find("夜里的构建又失败了").unwrap()
  let (_, menu_y) = t.find("重命名").unwrap()
  assert_true(menu_y > row_y)
  t.tap_text("重命名")
  assert_true(t.find("保存") is Some(_))
}

///|
test "a row's menu: 复制会话链接 copies its link, 固定 pins it (chat.pin)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0)
  hold_row(t, "夜里的构建又失败了")
  t.tap_text("复制会话链接")
  assert_true(t.clipboard().has_prefix("[夜里的构建又失败了]("))
  hold_row(t, "夜里的构建又失败了")
  match t.find("固定") {
    Some(_) => {
      t.tap_text("固定")
      assert_eq(named(calls, "chat.pin").length(), 1)
    }
    // (a fixture row from a station before pins has none)
    None => ()
  }
}

///|
test "a chat keeping watch is archived only once asked, in the core's words" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0)
  hold_row(t, "盯着 CI，绿了告诉我")
  // the menu's last item, a row (45) under 复制会话链接
  let (lx, ly) = t.find("复制会话链接").unwrap()
  t.tap(lx, ly + 45.0)
  assert_eq(named(calls, "chat.archive").length(), 0)
  assert_true(t.find("归档「盯着 CI，绿了告诉我」？") is Some(_))
  assert_true(t.find("它会在归档里继续盯着。") is Some(_))
  // its 归档, beside 取消
  let (cx, cy, cw, ch) = t.rect_of("取消").unwrap()
  t.tap(cx + cw + 40.0, cy + ch / 2.0)
  assert_eq(named(calls, "chat.archive").length(), 1)
}

///|
test "a row with nothing left in it, swiped left past a third: archived (chat.archive); a short swipe archives nothing" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0)
  t.scroll_to(12)
  t.draw()
  let (_, y) = t.find("把旧的截图都换成新的").unwrap()
  // across a little: let go short of a third, nothing archived
  t.drag(300.0, y, 260.0, y)
  assert_eq(named(calls, "chat.archive").length(), 0)
  // (short of the line: nothing felt)
  assert_eq(t.haptics(), [])
  // down first: the list's (it scrolls), nothing archived either
  t.drag(300.0, y, 290.0, y + 120.0)
  assert_eq(named(calls, "chat.archive").length(), 0)
  let (_, y) = t.find("把旧的截图都换成新的").unwrap()
  // across past a third of the row
  t.drag(340.0, y, 120.0, y)
  assert_eq(named(calls, "chat.archive").length(), 1)
  // its line felt as it was passed, once (Home.kt: TextHandleMove)
  assert_eq(t.haptics(), [@ui.Haptic::TextHandleMove])
}

///|
test "a row's state line tapped while it names a message opens the chat there; its title, or with something unread, not" {
  let item = chat_item({
    "id": "c5",
    "session": "s-c5",
    "title": "盯着 CI，绿了告诉我",
    "station": "ws1/st2",
    "stateText": "监控中：每 5 分钟看一次主干的构建",
    "stateAbout": 12,
  })
  // the row at 100: its title's line, then its state line
  assert_eq(row_opens_at(item, 100.0, 100.0 + chat_line_top + 1.0), Some(12.0))
  assert_eq(row_opens_at(item, 100.0, 100.0 + chat_line_top - 1.0), None)
  assert_eq(row_opens_at({ ..item, unread: true }, 100.0, 100.0 + chat_line_top + 1.0), None)
  assert_eq(row_opens_at({ ..item, state_about: None }, 100.0, 100.0 + chat_line_top + 1.0), None)
  // in Home: tapped on its line, its chat
  let t = tester("home")
  t.tap_text("监控中：每 5 分钟看一次主干的构建")
  match app.nav.top() {
    Chat(r) => assert_eq(r.session, "s-c5")
    _ => fail("not its chat")
  }
}

///|
test "a row's state line in red while a message of the viewer's in it did not go (Home.kt StateLine alert)" {
  reset()
  // (the theme as the frame has it)
  let red = Ref(0L)
  let muted = Ref(0L)
  let t = @ui.Tester::new(
    fn(c) {
      red.val = @sf.theme().p.red
      state_line(c, "有一条消息没发出去", alert=true)
    },
    w=390.0,
    h=40.0,
  )
  t.draw()
  assert_true(t.drawn_glyphs().length() > 0)
  assert_true(t.drawn_glyphs().iter().all(fn(g) { g.2 == red.val }))
  let t2 = @ui.Tester::new(
    fn(c) {
      muted.val = @sf.theme().p.muted
      state_line(c, "有一条消息没发出去")
    },
    w=390.0,
    h=40.0,
  )
  t2.draw()
  assert_true(t2.drawn_glyphs().iter().all(fn(g) { g.2 == muted.val }))
}

///|
test "the filter's other lists read once its menu opens; one picked slides in over 240 ms (Home.kt shift)" {
  reset()
  let base = fixture("home")
  let read : Array[String] = []
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if name == "chats" {
        let k = Json::object(params).stringify()
        if !read.contains(k) {
          read.push(k)
        }
      }
      (base.topic)(name, params)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  t.draw()
  let mine = fn() { read.iter().any(fn(k) { k.contains("\"mine\":true") }) }
  assert_false(mine())
  // the filter's button, at the bar's right
  t.tap(390.0 - 16.0 - 17.0, 25.0)
  // (the menu open, built again from it)
  t.draw()
  assert_true(mine())
  t.tap_text("我参与的")
  // half way: the list switched from going out to the left, the one picked coming in from the right (where words
  // are drawn: their lists' looks move them)
  let drawn = fn() { t.words().filter(fn(w) { w.0 == "和 Ana 一起看新版的引导页" }).map(fn(w) { w.1 }) }
  t.run_for(home_filter_ms / 2.0)
  let xs = drawn()
  assert_true(xs.length() == 2)
  assert_true(xs.iter().any(fn(x) { x < 0.0 }) && xs.iter().any(fn(x) { x > 22.0 }))
  t.run_for(home_filter_ms)
  // at rest: only the list picked, where a list is
  let xs = drawn()
  assert_eq(xs.length(), 1)
  assert_true(xs[0] > 0.0 && xs[0] < 195.0)
}

///|
test "under it all the page's own ground, dark too (the host cleared to blue there: a colour read the other way)" {
  for dark in [false, true] {
    let t = tester("home")
    @sf.set_dark(Some(dark))
    t.draw()
    let bg = @sf.theme().p.bg
    let want = [(bg >> 24) & 0xFFL, (bg >> 16) & 0xFFL, (bg >> 8) & 0xFFL].map(fn(v) { v.to_double() })
    let line = t.drawlist().split("\n").find_first(fn(l) { l.has_prefix("clear ") }).unwrap().to_owned()
    let nums = line.split(" ").drop(1).map(fn(v) { v.to_owned() }).to_array()
    let parsed = @json.parse("[" + nums.join(",") + "]") catch { _ => Json::null() }
    let got : Array[Double] = []
    match parsed {
      Array(a) =>
        for j in a {
          if j is Number(n, ..) {
            got.push(n)
          }
        }
      _ => ()
    }
    assert_eq(got.length(), 3)
    for k in 0..<3 {
      assert_true((got[k] * 255.0 - want[k]).abs() < 0.5)
    }
  }
}

///|
test "the filter's menu as MenuHost: rows of 45, 6 over and under them; going, its scrim fades with it" {
  let t = tester("home")
  let scrim = fn() { t.drawn_rects().filter(fn(r) { r.2 == 390.0 && r.3 == 844.0 && (r.4 & 0xFFFFFF00L) == 0L && (r.4 & 0xFFL) > 0L }) }
  t.tap(390.0 - 16.0 - 17.0, 25.0)
  t.run_for(@kit.menu_in_ms + 200.0)
  // under the button (8 down, 34 high) by 6, the rows 6 in (MENU_PAD), 45 each, their words 12 down in them
  let top = 8.0 + 34.0 + 6.0
  assert_eq(t.rect_of("我参与的").map(fn(r) { r.1 }), Some(top + 6.0 + 45.0 + 12.0))
  let watching_row = fn() { t.rect_of("监控中").map(fn(r) { r.1 }) == Some(top + 6.0 + 45.0 * 2.0 + 12.0) }
  assert_true(watching_row())
  assert_eq(scrim().length(), 1)
  // a tap beside it: the menu and its scrim leave together (MenuHost keeps both until both have gone)
  t.tap(40.0, 700.0)
  t.run_for(@kit.menu_out_ms)
  assert_true(watching_row())
  assert_eq(scrim().length(), 1)
  // (its scale goes back on the menu's spring: drawn until that has ended too)
  t.run_for(@motion.menu_spring.duration(1.0, 0.9, 0.0))
  assert_false(watching_row())
  assert_eq(scrim().length(), 0)
}
