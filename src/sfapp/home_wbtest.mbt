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
  t.settle() |> ignore
  assert_true(t.find("让 agent 持续工作") is Some(_))
  assert_true(t.find("登录或注册") is Some(_))
  assert_true(t.find("可同时登录多个账号，随时切换 workspace。") is Some(_))
}

///|
test "Home: the workspace's name, the search, the days and their rows" {
  let t = tester("home")
  t.settle() |> ignore
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
  t.settle() |> ignore
  t.tap_text("夜里的构建又失败了")
  t.settle() |> ignore
  assert_eq(app.nav.depth(), 2)
  assert_true(t.find("搜索全部内容") is None)
  assert_true(t.find("夜里的构建又失败了") is Some(_))
  assert_true(t.takes_back())
  t.back()
  t.settle() |> ignore
  assert_eq(app.nav.depth(), 1)
  assert_true(t.find("搜索全部内容") is Some(_))
}

///|
test "the workspaces' sheet: another workspace tapped is the one in view" {
  let t = tester("home")
  t.settle() |> ignore
  t.tap_text("星火工作室")
  t.settle() |> ignore
  assert_true(t.find("切换 workspace") is Some(_))
  assert_true(t.find("当前使用") is Some(_))
  assert_true(t.find("其他 workspace") is Some(_))
  t.tap_text("个人")
  t.settle() |> ignore
  assert_true(t.find("切换 workspace") is None)
  assert_true(t.find("个人") is Some(_))
  // no station there yet: adding the first one is the page
  assert_true(t.find("添加第一台 station") is Some(_))
}

///|
test "the filter: 我参与的 shows only the chats the viewer is in" {
  let t = tester("home")
  t.settle() |> ignore
  match t.rect_of("星火工作室") {
    Some(_) => ()
    None => fail("no title")
  }
  // the filter's button, at the bar's right
  t.tap(390.0 - 16.0 - 17.0, 25.0)
  t.settle() |> ignore
  assert_true(t.find("监控中") is Some(_))
  t.tap_text("我参与的")
  t.settle() |> ignore
  assert_true(t.find("首页的列表改成按天分组") is Some(_))
  assert_true(t.find("夜里的构建又失败了") is Some(_))
  assert_true(t.find("和 Ana 一起看新版的引导页") is Some(_))
}

///|
test "归档 at a row's start archives its chat" {
  let t = tester("home")
  t.settle() |> ignore
  t.scroll_to(12)
  t.settle() |> ignore
  assert_true(t.find("把旧的截图都换成新的") is Some(_))
  t.tap_text("归档")
  t.settle() |> ignore
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
