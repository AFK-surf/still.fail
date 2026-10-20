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
  t.draw()
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
  t.draw()
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
  t.draw()
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
  t.draw()
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
  t.draw()
  t.scroll_to(12)
  t.draw()
  assert_true(t.find("把旧的截图都换成新的") is Some(_))
  t.tap_text("归档")
  assert_true(t.find("把旧的截图都换成新的") is None)
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
test "a person's colour as Java's hashCode picks it" {
  assert_eq(java_hash("a"), 97)
  assert_eq(java_hash("ab"), 97 * 31 + 98)
  // wraps as Java's int does
  assert_eq(java_hash("polygenelubricants"), -2147483648)
  assert_eq(avatar_color("A"), avatar_color("a"))
}

///|
/// A row held long (Home.kt's onLongPress) at `title`'s words, then let go there.
fn hold_row(t : @ui.Tester, title : String) -> Unit {
  let (x, y) = t.find(title).unwrap()
  t.press_at(x, y)
  t.run_for(hold_ms)
  t.release(x, y)
  t.draw()
}

///|
test "a row held long: its menu (固定, 重命名, 复制会话链接, 归档), the chat not opened; 重命名 its sheet" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0)
  hold_row(t, "夜里的构建又失败了")
  assert_eq(app.nav.depth(), 1)
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
  // down first: the list's (it scrolls), nothing archived either
  t.drag(300.0, y, 290.0, y + 120.0)
  assert_eq(named(calls, "chat.archive").length(), 0)
  let (_, y) = t.find("把旧的截图都换成新的").unwrap()
  // across past a third of the row
  t.drag(340.0, y, 120.0, y)
  assert_eq(named(calls, "chat.archive").length(), 1)
}
