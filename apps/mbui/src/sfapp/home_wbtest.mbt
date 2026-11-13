///|
/// The app over a fixture, from its start (the pages, the sheet and the filters forgotten).
fn tester(mode : String) -> @ui.Tester {
  new_run()
  let src = fixture(mode)
  @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
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
test "signed out in a desktop's window: 登录或注册 alone, no wider than the desktop app's; a phone's across the page" {
  new_run()
  let pressed = Ref(0)
  let src : Source = { ..fixture("signin"), sign_in: fn() { pressed.val += 1 } }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  // no words but its own
  assert_true(t.find("让 agent 持续工作") is None)
  assert_true(t.find("可同时登录多个账号，随时切换 workspace。") is None)
  let (x, y, w, h) = t.rect_of("登录或注册").unwrap()
  let (mid, at) = (x + w / 2.0, y + h / 2.0)
  // beside it, where it ended when it was as wide as the page: nothing
  t.tap(mid - 160.0, at)
  t.tap(mid + 160.0, at)
  assert_eq(pressed.val, 0)
  // on it, near its end
  t.tap(mid + 140.0, at)
  assert_eq(pressed.val, 1)
  // a phone's: as wide as the page less its sides
  new_run()
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  let (x, y, w, h) = t.rect_of("登录或注册").unwrap()
  t.tap(x + w / 2.0 + 160.0, y + h / 2.0)
  assert_eq(pressed.val, 2)
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
  // 待处理 · …: 待处理 on its own, bold, the rest after it
  assert_true(t.find("待处理") is Some(_))
  // rows are 66 high, under the top bar
  let (_, y1) = t.find("整理发布清单").unwrap()
  let (_, y2) = t.find("首页的列表改成按天分组").unwrap()
  assert_true((y2 - y1 - 66.0).abs() < 0.5)
  assert_true(y1 > 50.0)
}

///|
test "Home: the search tucked under the top bar whole, its rows fewer than the page is tall or not" {
  // (the same rows in a window they overfill, and in one they leave room in: the first heading where it is in both)
  let at = fn(h : Double) {
    new_run()
    let src = fixture("home")
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h~, platform=2)
    t.run_for(@ui.move_most_ms)
    t.find("今天").unwrap().1
  }
  let overfilled = at(500.0)
  let room_left = at(844.0)
  assert_true((room_left - overfilled).abs() < 0.5, msg="\{room_left} against \{overfilled}")
}

///|
test "a row tapped pushes its chat, its title in the bar; back comes home" {
  let t = tester("home")
  t.tap_text("夜里的构建又失败了")
  assert_eq(app.nav.depth(), 2)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("搜索全部内容") is None)
  assert_true(t.find("夜里的构建又失败了") is Some(_))
  assert_true(t.takes_back())
  t.back()
  assert_eq(app.nav.depth(), 1)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("搜索全部内容") is Some(_))
}

///|
/// How many rows are drawn on the ground a row has held (ChatRowBody's: the ink at 5%), and whether one is under `y`.
fn rows_lit(t : @ui.Tester, y? : Double = -1.0) -> Int {
  let ground = @sf.alpha(@sf.theme().p.text, 0.05)
  t
  .drawn_rects()
  .filter(fn(r) {
    let (_, ry, _, rh, color) = r
    color == ground && (rh - @sfpages.touch_row_h).abs() < 0.5 && (y < 0.0 || (ry <= y && y <= ry + rh))
  })
  .length()
}

///|
/// Home on Android (a press in what scrolls shows once it is not the list's: Ctx::pressed).
fn android_home() -> @ui.Tester {
  new_run()
  let src = fixture("home")
  @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
}

///|
test "a row pressed: on the ground it has held once the press is not the list's (the tap timeout)" {
  // one needing the viewer, one offered for archiving
  for title in ["夜里的构建又失败了", "把旧的截图都换成新的"] {
    let t = android_home()
    list_down(t, 12)
    t.draw()
    let (x, y) = t.find(title).unwrap()
    t.press_at(x, y)
    assert_eq(rows_lit(t), 0)
    t.run_for(@ui.tap_indication_ms)
    assert_eq(rows_lit(t, y~), 1)
    assert_eq(rows_lit(t), 1)
    // let go, its chat
    t.release(x, y)
    assert_eq(app.nav.depth(), 2)
  }
}

///|
test "a row a finger scrolls the list from: not lit" {
  let t = android_home()
  let (x, y) = t.find("夜里的构建又失败了").unwrap()
  t.hold_drag(x, y, x, y - 160.0)
  t.run_for(@ui.tap_indication_ms)
  assert_eq(rows_lit(t), 0)
}

///|
test "the workspaces' sheet: another workspace tapped is the one in view" {
  let t = tester("home")
  t.tap_text("星火工作室")
  assert_true(@sf.presenting())
  assert_true(t.find("切换 workspace") is Some(_))
  assert_true(t.find("当前使用") is Some(_))
  assert_true(t.find("其他 workspace") is Some(_))
  t.tap_text("个人")
  assert_true(!@sf.presenting())
  assert_true(t.find("个人") is Some(_))
  // no station there yet: adding the first one is the page
  assert_true(t.find("添加第一台 station") is Some(_))
}

///|
/// Tap the filter by its accessible name, wherever the bar puts it.
fn tap_home_filter(t : @ui.Tester) -> Unit {
  let (x, y, w, h) = t.query(Button, label="筛选会话：全部").unwrap().rect
  t.tap(x + w / 2.0, y + h / 2.0)
}

///|
test "hiding a running chat leaves it in the hidden list, where it can be restored" {
  let t = tester("home-hide")
  let (x, y) = t.find("整理发布清单").unwrap()
  t.press_at(x, y)
  t.run_for(@ui.tap_indication_ms + @sfpages.hold_ms)
  t.release(x, y)
  t.frame()
  t.tap_text("关闭提醒")
  // (its notice gone: over the foot of the menu held open next, where 隐藏 is)
  t.run_for(@sf.toast_ms + @kit.presence_out_ms)
  let (x, y) = t.find("整理发布清单").unwrap()
  t.press_at(x, y)
  t.run_for(@ui.tap_indication_ms + @sfpages.hold_ms)
  t.release(x, y)
  t.frame()
  assert_true(t.find("开启提醒") is Some(_))
  t.tap_text("隐藏")
  // (its notice, with its 撤销, gone: over the foot of the menu held open next, where 取消隐藏 is)
  t.run_for(@sf.toast_action_ms + @kit.presence_out_ms)
  assert_true(t.find("整理发布清单") is None)
  tap_home_filter(t)
  t.tap_text("已隐藏")
  t.run_for(@ui.move_most_ms)
  let (x, y) = t.find("整理发布清单 · 已隐藏").unwrap()
  t.press_at(x, y)
  t.run_for(@ui.tap_indication_ms + @sfpages.hold_ms)
  t.release(x, y)
  t.frame()
  assert_true(t.find("开启提醒") is Some(_))
  t.tap_text("取消隐藏")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("整理发布清单 · 已隐藏") is None)
  let (x, y, w, h) = t.query(Button, label="筛选会话：已隐藏").unwrap().rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.tap_text("全部会话")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("整理发布清单") is Some(_))
}

///|
test "small screen home: filter on the left, workspace and settings on the right" {
  for platform in [0, 2] {
    for width in [320.0, 390.0, 599.0] {
      new_run()
      let src = fixture("home")
      let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=width, h=844.0, platform~)
      let (fx, _, fw, _) = t.query(Button, label="筛选会话：全部").unwrap().rect
      let (sx, sy, sw, sh) = t.query(Button, label="设置").unwrap().rect
      let (wx, _, ww, _) = t.rect_of("星火工作室").unwrap()
      let arrows = t.locate("icon:chevron-down")
      assert_eq(arrows.length(), 1)
      assert_true(arrows[0].0 < wx, msg="the workspace arrow is before its name")
      assert_true(fx + fw <= wx && wx + ww <= sx, msg="filter, workspace and settings: \{fx}, \{wx}, \{sx}")
      assert_true(fx >= 0.0 && sx + sw <= width, msg="bar controls fit in \{width}")
      t.tap(sx + sw / 2.0, sy + sh / 2.0)
      t.run_for(@ui.move_most_ms)
      assert_true(t.find("设置") is Some(_))
    }
  }
}

///|
test "small screen home: a long workspace name gives way to syncing and transfers" {
  new_run()
  let long_name = "一个很长的 workspace 名称，需要给顶栏按钮留出足够空间"
  let calls : Array[(String, Json)] = []
  let base = downloads_src("home-syncing", [listed("dist.zip", "going", 1.0, 50.0, "正在下载")], calls)
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "workspaces" {
        {
          value: Some([{
            "account": { "email": "lin@example.com" },
            "workspaces": [{ "id": "ws1", "name": Json::string(long_name), "emoji": "🔥", "stations": 2 }],
            "invitations": [],
            "loaded": true,
          }]),
          error: None,
          version: 1,
        }
      } else {
        base.topic(name, params).get().snapshot()
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=320.0, h=740.0, platform=2)
  t.run_for(@sf.later_ms + @kit.presence_in_ms)
  let (fx, _, fw, _) = t.query(Button, label="筛选会话：全部").unwrap().rect
  let (sync_x, _, sync_w, _) = t.query(Status, label="正在同步 · 还剩 12 个对话").unwrap().rect
  let (tx, _, tw, _) = t.query(Button, label="1 个传输 · 2%").unwrap().rect
  let (sx, _, sw, _) = t.query(Button, label="设置").unwrap().rect
  let (wx, wy, ww, wh) = t.rect_of(long_name).unwrap()
  assert_true(
    fx + fw <= sync_x && sync_x + sync_w <= tx && tx + tw <= wx && wx + ww <= sx && sx + sw <= 320.0,
    msg="filter \{fx}+\{fw}, sync \{sync_x}+\{sync_w}, transfers \{tx}+\{tw}, name \{wx}+\{ww}, settings \{sx}+\{sw}",
  )
  assert_true(ww > 0.0, msg="workspace name stays in the bar: \{wx}, \{ww}")
  t.tap(wx + ww / 2.0, wy + wh / 2.0)
  assert_true(@sf.presenting())
  assert_true(t.find("切换 workspace") is Some(_))
}

///|
test "the filter: 我参与的 shows only the chats the viewer is in" {
  let t = tester("home")
  match t.rect_of("星火工作室") {
    Some(_) => ()
    None => fail("no title")
  }
  tap_home_filter(t)
  t.run_for(@sf.presented_rest() - t.time())
  assert_true(t.find("监控中") is Some(_))
  t.tap_text("我参与的")
  assert_true(t.find("首页的列表改成按天分组") is Some(_))
  assert_true(t.find("夜里的构建又失败了") is Some(_))
  assert_true(t.find("和 Ana 一起看新版的引导页") is Some(_))
}

///|
test "a row archived: it closes where it was, the row under it coming up whole, laid out where it is drawn" {
  // (2026-10-31: a row gone closes its room where it was, the rows under it coming up as it closes, mbui's view/list_motion.mbt;
  // before it, Home.kt's animateItem moved the whole of SwipeToArchive, its clip with it)
  let t = tester("home")
  let under = "把旧的截图都换成新的"
  let (_, y_was, _, h) = t.rect_of(under).unwrap()
  assert_false(t.locate("=Slack 里问的报销流程").is_empty())
  let (_, y_gone, _, _) = t.rect_of("Slack 里问的报销流程").unwrap()
  hold_row(t, "Slack 里问的报销流程")
  // the menu's 归档 (its last item)
  let (lx, ly) = t.find_last("归档").unwrap()
  t.tap(lx, ly)
  // on its way up as the room over it closes, all of it, drawn where it is laid out
  t.run_for(@ui.row_size_ms / 2.0)
  let (_, y1, _, _) = t.rect_of(under).unwrap()
  let (_, d1) = t.drawn_of(under).unwrap()
  assert_true(y1 < y_was - 1.0 && y1 > y_gone - 1.0, msg="\{y1}, from \{y_was}")
  assert_true((d1 - y1).abs() < 0.5, msg="drawn at \{d1}, laid out at \{y1}")
  let (_, _, _, s1) = t.shown_of(under).unwrap()
  assert_true((s1 - h).abs() < 0.5, msg="\{s1} of \{h} shown on its way")
  // closed: the archived row out of the list
  t.run_for(@ui.row_size_ms)
  assert_true(t.locate("=Slack 里问的报销流程").is_empty())
}

///|
test "the list while it is read: no rows, the shapes" {
  let t = tester("loading")
  t.frame()
  // (the first page built as it opens, shown once it has its list, first_page_ms at most: not drawn till then, not
  // its shapes swapped for its rows a frame later)
  // (seen: some of its glyphs drawn and nothing over them, the splash's ground none)
  let drawn = fn(s : String) { words_seen(t, s) }
  assert_true(!drawn("星火工作室"))
  t.run_for(@sf.local_ms)
  assert_true(!drawn("星火工作室"), msg="the first page's wait is not LOCAL_MS")
  t.run_for(first_page_ms - @sf.local_ms)
  assert_true(drawn("星火工作室"))
  assert_true(t.find("整理发布清单") is None)
  assert_true(t.find("星火工作室") is Some(_))
}

///|
test "a state line's lead is the core's: an icon in its words' place with what follows; none, the words as they are" {
  new_run()
  let t = @ui.Tester::new(
    fn(c) {
      c.box(w=Fill(1.0), fn() {
        @sfpages.state_line(c, "a", c.id("a"), "要你帮忙：看一下", lead="need", rest="看一下")
        // (words that look like a lead, said by none: as they are)
        @sfpages.state_line(c, "b", c.id("b"), "要你帮忙看一眼")
        @sfpages.state_line(c, "c", c.id("c"), "待处理 · 用哪个？", lead="decision", lead_text="待处理", rest=" · 用哪个？")
      })
      |> ignore
    },
    w=390.0,
    h=120.0,
    platform=2,
  )
  t.draw()
  assert_true(t.find("看一下") is Some(_))
  assert_true(t.find("要你帮忙：看一下") is None, msg="the lead said by its icon")
  assert_true(t.find("要你帮忙看一眼") is Some(_))
  assert_true(t.find("待处理") is Some(_))
  assert_true(t.find(" · 用哪个？") is Some(_))
}

///|
test "a pending card's long question gives way to its lead on a narrow row" {
  for (lead, rest) in [
    ("待处理", " · 分组的标题用相对日期还是具体日期？"),
    ("Needs attention", " · Should the group titles use relative or exact dates?"),
  ] {
    for platform in [0, 2] {
      new_run()
      let width = @signals.signal(240.0)
      let t = @ui.Tester::new(
        fn(c) {
          @sf.begin(c) |> ignore
          c.with_theme(@sf.ui_theme(), fn() {
            c.box(w=Px(width.get()), fn() {
              @sfpages.state_line(c, "card", c.id("card"), lead + rest, lead="decision", lead_text=lead, rest~)
            })
            |> ignore
          })
        },
        w=800.0,
        h=120.0,
        platform~,
      )
      t.draw()
      assert_eq(t.lines_of(lead), [lead])
      let narrow = t.lines_of(rest)
      assert_true(narrow.length() == 1 && narrow[0].has_suffix("…"), msg="\{lead}: \{Repr(narrow)}")
      assert_true(t.squeeze_faults().is_empty(), msg=t.squeeze_faults().join("\n"))
      width.set(800.0)
      t.frame()
      assert_eq(t.lines_of(lead), [lead])
      assert_eq(t.lines_of(rest), [rest])
    }
  }
}

///|
test "Java's hashCode" {
  assert_eq(java_hash("a"), 97)
  assert_eq(java_hash("ab"), 97 * 31 + 98)
  // wraps as Java's int does
  assert_eq(java_hash("polygenelubricants"), -2147483648)
}

///|
/// A row held long at `title`'s words, then let go there.
fn hold_row(t : @ui.Tester, title : String) -> Unit {
  let (x, y) = t.find(title).unwrap()
  t.press_at(x, y)
  // (a finger's press in a list shows a moment after it goes down: @ui.tap_indication_ms)
  t.run_for(@ui.tap_indication_ms + @sfpages.hold_ms)
  t.release(x, y)
}

///|
test "a row held long: its menu (固定, 重命名, 归档, 分享…), the chat not opened; 重命名 its sheet" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  hold_row(t, "夜里的构建又失败了")
  assert_eq(app.nav.depth(), 1)
  // felt as it opened, once
  assert_eq(t.haptics(), [@ui.Haptic::LongPress])
  assert_true(t.find("重命名") is Some(_))
  assert_true(t.find("分享…") is Some(_))
  // just below the row
  let (_, row_y) = t.find("夜里的构建又失败了").unwrap()
  let (_, menu_y) = t.find("重命名").unwrap()
  assert_true(menu_y > row_y)
  t.tap_text("重命名")
  assert_true(t.find("保存") is Some(_))
}

///|
/// Whether the row at `ry` is lifted in the last frame: a card of its own casting a shadow there.
fn row_lifted(t : @ui.Tester, ry : Double) -> Bool {
  t.drawn_shadows().iter().any(fn(s) { s.2 > 200.0 && s.1 < ry + 30.0 && s.1 + s.3 > ry - 20.0 && (s.6 & 0xFFL) > 0L })
}

///|
/// The sheets drawn in the last frame (not the tab bar's glass): each its top.
fn sheet_tops(t : @ui.Tester) -> Array[Double] {
  t.drawn_glass().filter(fn(g) { g.3 > 100.0 }).map(fn(g) { g.1 })
}

///|
test "a row held long, its 分享…: the next level in the menu's sheet, one sheet all the way, the row lifted still; back is back to its menu" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  let (_, ry) = t.find("夜里的构建又失败了").unwrap()
  hold_row(t, "夜里的构建又失败了")
  t.run_for(@ui.move_most_ms)
  assert_true(row_lifted(t, ry))
  let top0 = sheet_tops(t)
  assert_eq(top0.length(), 1)
  // (every rule the screen is held to, as the menu has it: its next level adds no fault)
  let held = t.audit()
  t.tap_text("分享…")
  for _ in 0..<40 {
    t.run_for(@ui.frame_period_default)
    assert_eq(sheet_tops(t).length(), 1)
    assert_true(row_lifted(t, ry))
  }
  assert_true(t.find("复制会话链接") is Some(_) && t.find("重命名") is None)
  assert_true(sheet_tops(t)[0] > top0[0] + 20.0, msg="\{Repr(sheet_tops(t))} \{Repr(top0)}")
  let added = t.audit().filter(fn(f) { !held.contains(f) })
  assert_eq(added, [])
  t.back()
  for _ in 0..<40 {
    t.run_for(@ui.frame_period_default)
    assert_eq(sheet_tops(t).length(), 1)
    assert_true(row_lifted(t, ry))
  }
  assert_true(t.find("重命名") is Some(_) && t.find("复制会话链接") is None)
  assert_true((sheet_tops(t)[0] - top0[0]).abs() < 0.5, msg="\{Repr(sheet_tops(t))} \{Repr(top0)}")
  t.back()
  t.run_for(@ui.move_most_ms * 2.0)
  assert_true(!@sf.presenting() && !row_lifted(t, ry))
}

///|
test "a row held long, its 重命名: the question in its menu's place, the row lifted still till that goes" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  let (_, ry) = t.find("夜里的构建又失败了").unwrap()
  hold_row(t, "夜里的构建又失败了")
  t.run_for(@ui.move_most_ms)
  assert_true(row_lifted(t, ry))
  t.tap_text("重命名")
  for _ in 0..<40 {
    t.run_for(@ui.frame_period_default)
    assert_eq(sheet_tops(t).length(), 1)
    assert_true(row_lifted(t, ry))
  }
  assert_true(t.find("保存") is Some(_))
  t.back()
  t.run_for(@ui.move_most_ms * 2.0)
  assert_true(!@sf.presenting() && !row_lifted(t, ry))
}

///|
test "a row held and let down as its menu goes: its shadow fades with its card, none without it" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  let (_, ry) = t.find("夜里的构建又失败了").unwrap()
  hold_row(t, "夜里的构建又失败了")
  t.run_for(@ui.move_most_ms)
  let bare : Ref[String?] = Ref(None)
  t.each_frame(
    Some(fn() {
      let near = fn(y : Double, h : Double) { y < ry + 30.0 && y + h > ry - 20.0 }
      // (the card: a row's height, a row's width; its shadow cast by it, as strong as the card is of its whole)
      let cards = t.drawn_rects().filter(fn(r) { r.2 > 200.0 && r.3 < 100.0 && near(r.1, r.3) })
      let whole = (@sf.held_raised.color & 0xFFL).to_double()
      for s in t.drawn_shadows() {
        if s.2 > 200.0 && near(s.1, s.3) && bare.val is None {
          let a = (s.6 & 0xFFL).to_double()
          if !cards.iter().any(fn(r) { a <= (r.4 & 0xFFL).to_double() / 255.0 * whole + 1.0 }) {
            bare.val = Some("shadow \{Repr(s)} over cards \{Repr(cards)}")
          }
        }
      }
    }),
  )
  t.tap(200.0, 60.0)
  t.run_for(@ui.move_most_ms * 2.0)
  t.each_frame(None)
  assert_eq(bare.val, None)
}

///|
test "a row's menu: 复制会话链接 copies its link, 固定 pins it (chat.pin)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  hold_row(t, "夜里的构建又失败了")
  open_share(t)
  t.tap_text("复制会话链接")
  assert_true(t.clipboard().has_prefix("[夜里的构建又失败了]("))
  hold_row(t, "夜里的构建又失败了")
  match t.find("固定") {
    Some(_) => {
      let felt = t.haptics().length()
      t.tap_text("固定")
      assert_eq(named(calls, "chat.pin").length(), 1)
      assert_eq(t.haptics()[felt:].to_owned(), [@ui.Confirm])
    }
    // (a fixture row from a station before pins has none)
    None => ()
  }
}

///|
test "a chat keeping watch is archived only once asked, in the core's words" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  hold_row(t, "盯着 CI，绿了告诉我")
  // the menu's 归档 (its last item)
  let (lx, ly) = t.find_last("归档").unwrap()
  t.tap(lx, ly)
  assert_eq(named(calls, "chat.archive").length(), 0)
  assert_true(t.find("归档「盯着 CI，绿了告诉我」？") is Some(_))
  assert_true(t.find("「主干构建」仍在监控。归档会停止监控。") is Some(_))
  // its 归档, beside 取消
  let (cx, cy, cw, ch) = t.rect_of("取消").unwrap()
  t.tap(cx + cw + 40.0, cy + ch / 2.0)
  assert_eq(named(calls, "chat.archive").length(), 1)
}

///|
test "a row with nothing left in it, swiped left past a third: off, then archived (chat.archive); a short swipe archives nothing" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  list_down(t, 12)
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
  // across past a third of the row: it goes off, then is archived
  t.drag(340.0, y, 120.0, y)
  assert_eq(named(calls, "chat.archive").length(), 0)
  t.run_for(@ui.move_most_ms)
  assert_eq(named(calls, "chat.archive").length(), 1)
  // its line felt as it was passed, once; archived, as something done (act's 已归档)
  assert_eq(t.haptics(), [@ui.Haptic::TextHandleMove, @ui.Haptic::Confirm])
}

///|
/// A finger down at the first of `at`, moved through the rest a finger's step apart, let go at the last.
fn finger_along(t : @ui.Tester, at : Array[(Double, Double)]) -> Unit {
  t.touch(0, at[0].0, at[0].1)
  for p in at[1:] {
    t.run_for(@ui.input_step_ms)
    t.touch(1, p.0, p.1)
  }
  t.touch(2, at[at.length() - 1].0, at[at.length() - 1].1)
  t.draw()
}

///|
test "a row flicked left a little, quickly, archives nothing; flicked from past half the line, it does" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  list_down(t, 12)
  t.draw()
  let (_, y) = t.find("把旧的截图都换成新的").unwrap()
  // 50 across in two of a finger's steps: fast, short of half the line (390's: 68 of 136)
  t.drag(300.0, y, 250.0, y, steps=2)
  t.run_for(@ui.move_most_ms)
  assert_eq(named(calls, "chat.archive").length(), 0)
  // 90 across as fast: past half the line, flung, archived
  t.drag(320.0, y, 230.0, y, steps=2)
  t.run_for(@ui.move_most_ms)
  assert_eq(named(calls, "chat.archive").length(), 1)
}

///|
test "a row swiped right, however far or fast, archives nothing" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  list_down(t, 12)
  t.draw()
  let (_, y) = t.find("把旧的截图都换成新的").unwrap()
  t.drag(60.0, y, 340.0, y)
  t.run_for(@ui.move_most_ms)
  t.drag(100.0, y, 250.0, y, steps=2)
  t.run_for(@ui.move_most_ms)
  assert_eq(named(calls, "chat.archive").length(), 0)
  assert_eq(t.haptics(), [])
}

///|
test "a finger scrolling the list that sets off a little to the left scrolls it, archiving nothing" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  list_down(t, 12)
  t.draw()
  let (_, y) = t.find("把旧的截图都换成新的").unwrap()
  // its first move more across than down, within the slop; then down, drifting left on
  finger_along(t, [(300.0, y), (296.0, y + 1.0), (292.0, y + 40.0), (288.0, y + 80.0), (284.0, y + 120.0)])
  t.run_for(@ui.move_most_ms)
  let (_, y2) = t.find("把旧的截图都换成新的").unwrap()
  assert_true(y2 > y + 60.0, msg="the list scrolled with the finger: \{y} -> \{y2}")
  assert_eq(named(calls, "chat.archive").length(), 0)
  assert_eq(t.haptics(), [])
}

///|
test "a finger swipes a waiting, failed or unread chat to archive it on both small and large screens" {
  for w in [390.0, 1100.0] {
    for (title, session) in [
      ("首页的列表改成按天分组", "s-c2"),
      ("夜里的构建又失败了", "s-c3"),
      ("给设置页加一个深色模式开关", "s-c4"),
      ("周报的模板", "s-c10"),
    ] {
      let calls : Array[Made] = []
      let t = wide_tester(calls, w~, h=900.0, platform=2)
      if session == "s-c10" {
        list_down(t, 12)
        t.draw()
      }
      let (_, y) = t.find(title).unwrap()
      let start = if w < 600.0 { 340.0 } else { @sfdesk.rail_w + 200.0 }
      let finish = if w < 600.0 { 100.0 } else { @sfdesk.rail_w + 30.0 }
      t.drag(start, y, finish, y)
      t.run_for(@ui.move_most_ms)
      let asked = named(calls, "chat.archive")
      assert_eq(asked.length(), 1, msg="\{w}: \{title}")
      assert_eq(text(Some(asked[0].params), "session"), session, msg="\{w}: \{title}")
      assert_eq(field(Some(asked[0].params), "archived"), Some(Json::boolean(true)))
    }
  }
}

///|
test "a finger swiping a chat at work asks before archiving it, in the core's words; its menu's 归档 does not ask" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  let (x, y) = t.find("整理发布清单").unwrap()
  t.drag(x + 190.0, y, x + 10.0, y)
  t.run_for(@ui.move_most_ms)
  assert_eq(named(calls, "chat.archive").length(), 0)
  assert_true(t.find("归档「整理发布清单」？") is Some(_))
  assert_true(t.find("此对话正在进行中。归档后，agent 完成当前回复即停止，等待中的任务也会停止。") is Some(_))
  let (cx, cy, cw, ch) = t.rect_of("取消").unwrap()
  t.tap(cx + cw + 40.0, cy + ch / 2.0)
  assert_eq(named(calls, "chat.archive").length(), 1)
  // held for its menu, its 归档 archives it at once
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  hold_row(t, "整理发布清单")
  let (lx, ly) = t.find_last("归档").unwrap()
  t.tap(lx, ly)
  assert_eq(named(calls, "chat.archive").length(), 1)
}

///|
test "a finger swiping a chat keeping watch asks before archiving it" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  let (x, y) = t.find("盯着 CI，绿了告诉我").unwrap()
  t.drag(x + 190.0, y, x + 10.0, y)
  assert_eq(named(calls, "chat.archive").length(), 0)
  assert_true(t.find("归档「盯着 CI，绿了告诉我」？") is Some(_))
  assert_true(t.find("「主干构建」仍在监控。归档会停止监控。") is Some(_))
  let (cx, cy, cw, ch) = t.rect_of("取消").unwrap()
  t.tap(cx + cw + 40.0, cy + ch / 2.0)
  assert_eq(named(calls, "chat.archive").length(), 1)
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
  ignore(item)
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
  new_run()
  // (the theme as the app's frame has it: its palette, and mbui's roles over it)
  let red = Ref(0L)
  let muted = Ref(0L)
  let t = @ui.Tester::new(
    fn(c) {
      red.val = @sf.begin(c).p.red
      c.with_theme(@sf.ui_theme(), fn() { @sfpages.state_line(c, "a", c.id("a"), "有一条消息没发出去", alert=true) })
    },
    w=390.0,
    h=40.0,
    platform=2,
  )
  t.draw()
  assert_true(t.drawn_glyphs().length() > 0)
  assert_true(t.drawn_glyphs().iter().all(fn(g) { g.2 == red.val }))
  let t2 = @ui.Tester::new(
    fn(c) {
      muted.val = @sf.begin(c).p.muted
      c.with_theme(@sf.ui_theme(), fn() { @sfpages.state_line(c, "a", c.id("a"), "有一条消息没发出去") })
    },
    w=390.0,
    h=40.0,
    platform=2,
  )
  t2.draw()
  assert_true(t2.drawn_glyphs().iter().all(fn(g) { g.2 == muted.val }))
}

///|
test "the filter's other lists read once its menu opens; one picked slides in over 240 ms (Home.kt shift)" {
  new_run()
  let base = fixture("home")
  let read : Array[String] = []
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "chats" {
        let k = Json::object(params).stringify()
        if !read.contains(k) {
          read.push(k)
        }
      }
      base.topic(name, params).get().snapshot()
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.draw()
  let mine = fn() { read.iter().any(fn(k) { k.contains("\"mine\":true") }) }
  assert_false(mine())
  tap_home_filter(t)
  // (the menu open, built again from it)
  t.draw()
  t.run_for(@sf.presented_rest() - t.time())
  assert_true(mine())
  t.tap_text("我参与的")
  // half way: the list switched from going out to the left, the one picked coming in from the right (where words
  // are drawn: their lists' looks move them)
  let drawn = fn() { t.words().filter(fn(w) { w.0 == "和 Ana 一起看新版的引导页" }).map(fn(w) { w.1 }) }
  t.run_for(@ui.move_most_ms / 2.0)
  let xs = drawn()
  assert_true(xs.length() == 2)
  assert_true(xs.iter().any(fn(x) { x < 0.0 }) && xs.iter().any(fn(x) { x > 22.0 }))
  t.run_for(@ui.move_most_ms)
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
test "the filter's menu, a finger's: the presenters' sheet of 全部会话, 我参与的, 监控中 and 已归档, the list shown checked" {
  let t = tester("home")
  tap_home_filter(t)
  t.run_for(@sf.presented_rest() - t.time())
  for words in ["全部会话", "我参与的", "监控中", "已归档"] {
    assert_true(t.find(words) is Some(_), msg=words)
  }
  // 已归档: its page
  t.tap_text("已归档")
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Archived)
}

///|
test "a finger swiping a chat someone else started asks first, archiving it being for the whole workspace; one's own does not" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  let (x, y) = t.find("和 Ana 一起看新版的引导页").unwrap()
  t.drag(x + 190.0, y, x + 10.0, y)
  t.run_for(@ui.move_most_ms)
  assert_eq(named(calls, "chat.archive").length(), 0)
  assert_true(t.find("归档「和 Ana 一起看新版的引导页」？") is Some(_))
  assert_true(t.find("这是Ana发起的对话。归档后，workspace 里所有人的列表都不再显示它，agent 也不再接收新消息。") is Some(_))
  // 取消: nothing archived, the row where it rests
  t.tap_text("取消")
  t.run_for(@ui.move_most_ms)
  assert_eq(named(calls, "chat.archive").length(), 0)
  assert_true(t.find("和 Ana 一起看新版的引导页") is Some(_))
  // one the viewer started, swiped as far: archived at once
  let (x, y) = t.find("首页的列表改成按天分组").unwrap()
  t.drag(x + 190.0, y, x + 10.0, y)
  t.run_for(@ui.move_most_ms)
  assert_eq(named(calls, "chat.archive").length(), 1)
  assert_true(t.find("归档「首页的列表改成按天分组」？") is None)
}

///|
test "a chat archived from its row says so with 撤销, which asks it back into the list (chat.archive, archived false)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  hold_row(t, "夜里的构建又失败了")
  let (lx, ly) = t.find_last("归档").unwrap()
  t.tap(lx, ly)
  assert_eq(named(calls, "chat.archive").length(), 1)
  t.draw()
  assert_true(t.locate("=夜里的构建又失败了").is_empty())
  // (said at once: read out as it comes in; its first frame draws it at none of its opacity, as the old view's did,
  // so it is seen, and found, as it has come in)
  assert_true(t.query(Status, label="已归档「夜里的构建又失败了」") is Some(_))
  // (come in)
  t.run_for(@kit.presence_in_ms)
  t.tap_text("撤销")
  let asked = named(calls, "chat.archive")
  assert_eq(asked.length(), 2)
  assert_eq(field(Some(asked[1].params), "archived"), Some(Json::boolean(false)))
  assert_eq(text(Some(asked[1].params), "session"), text(Some(asked[0].params), "session"))
  t.draw()
  // the toast goes, said again once it is done (read out at once; its first frame at none of its opacity, as the old
  // view's, seen as it has come in)
  assert_true(t.find("撤销") is None)
  assert_true(t.query(Status, label="已恢复到列表") is Some(_))
  t.run_for(@kit.presence_in_ms)
  assert_true(t.find("已恢复到列表") is Some(_))
}

///|
test "a toast with 撤销 stays its longer time; one without, its 2.6 s" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  hold_row(t, "夜里的构建又失败了")
  let (lx, ly) = t.find_last("归档").unwrap()
  t.tap(lx, ly)
  t.draw()
  t.run_for(toast_ms + 100.0)
  assert_true(t.find("撤销") is Some(_))
  t.run_for(@sf.toast_action_ms)
  assert_true(t.find("撤销") is None)
  assert_eq(named(calls, "chat.archive").length(), 1)
}

///|
/// The toast saying `words` (with a button of `action`'s words, "" none) as it rests in tester `t`: its rect, its
/// button's.
fn rested_toast(t : @ui.Tester, words : String, action : String) -> ((Double, Double, Double, Double), (Double, Double, Double, Double)?) raise {
  @sfbase.toast_later(words, action~)
  t.frame()
  t.run_for(@kit.presence_in_ms)
  let toast = match t.query(Status, label=words) {
    Some(n) => n.rect
    None => fail("no toast saying \{words}")
  }
  (toast, t.query(Button, label=action).map(fn(n) { n.rect }))
}

///|
test "a toast is a capsule while its words fit a line; its 撤销 a capsule in its end concentric with it, every frame's" {
  for wide in [false, true] {
    let calls : Array[Made] = []
    let t = if wide { wide_tester(calls) } else { wide_tester(calls, w=390.0, h=844.0, platform=2) }
    let (bare, _) = rested_toast(t, "已复制", "")
    assert_true((bare.3 - 2.0 * @sf.toast_r).abs() < 0.5, msg="\{wide} \{Repr(bare)}")
    t.run_for(@sf.toast_ms + @kit.presence_out_ms)
    let ((x, y, w, h), button) = rested_toast(t, "已归档", "撤销")
    let (bx, by, bw, bh) = button.unwrap()
    // as high as one without; its button as far from its top, foot and end as its corner has a capsule that high
    assert_true((h - 2.0 * @sf.toast_r).abs() < 0.5, msg="\{wide} \{h}")
    let inset = @ui.capsule_in(@sf.toast_r, bh, room=@sf.toast_r)
    for gap in [by - y, y + h - (by + bh), x + w - (bx + bw)] {
      assert_true((gap - inset).abs() < 0.5, msg="\{wide} \{gap} \{inset}")
    }
  }
}

///|
test "a chat archived from its row: said at once by its title, its station not answered yet; why not once it says no" {
  let calls : Array[Made] = []
  new_run()
  let base = fixture("home")
  // (chat.archive left waiting: its station's answer not come)
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      if name != "chat.archive" {
        (base.call)(name, params, done)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  hold_row(t, "夜里的构建又失败了")
  let (lx, ly) = t.find_last("归档").unwrap()
  t.tap(lx, ly)
  t.draw()
  // (said at once: read out as it comes in; its first frame draws it at none of its opacity, as the old view's did,
  // so it is seen, and found, as it has come in)
  assert_true(t.query(Status, label="已归档「夜里的构建又失败了」") is Some(_))
  assert_true(t.query(Button, label="撤销") is Some(_))
  t.run_for(@kit.presence_in_ms)
  assert_true(t.find("已归档「夜里的构建又失败了」") is Some(_) && t.find("撤销") is Some(_))
  // no: why, in its place
  (named(calls, "chat.archive")[0].done)(Err({ "message": "坏了" }))
  t.draw()
  assert_true(app.toast.get().words.contains("坏了"), msg=app.toast.get().words)
}

///|
test "a toast naming a long title with its 撤销: inside the screen, its 撤销 inside it" {
  for wide in [false, true] {
    let calls : Array[Made] = []
    let w = if wide { 1280.0 } else { 390.0 }
    let t = if wide { wide_tester(calls) } else { wide_tester(calls, w~, h=844.0, platform=2) }
    let words = "已归档「把首页对话列表改成按天分组并且在每一组的标题里写上那天的日期和星期几，再把置顶的对话单独放在最上面」"
    let ((x, y, tw, th), button) = rested_toast(t, words, "撤销")
    let (bx, by, bw, bh) = button.unwrap()
    assert_true(x >= 0.0 && x + tw <= w, msg="\{wide} \{x} \{tw}")
    assert_true(bx >= x && bx + bw <= x + tw && by >= y && by + bh <= y + th, msg="\{wide} \{Repr(button)}")
    t.run_for(@sf.toast_action_ms + @kit.presence_out_ms)
  }
}

///|
test "a toast clear of the system's bars over the window: over its foot's, beside its sides' (a tablet's navigation bar, an iPhone Duo's column down its side), in the middle of the room they leave" {
  // (2026-11-13 「不光是浮层，你看看那个 toast 之类的呢？」: on 中屏 and 大屏 a toast stood toast_bottom over the
  // window's own foot, under a tablet's navigation bar or the home indicator, and in the middle of the whole window)
  // (wide, then: top, right, foot, left)
  for case in [(true, (24.0, 0.0, 48.0, 0.0)), (true, (24.0, 84.0, 20.0, 0.0)), (true, (0.0, 0.0, 0.0, 120.0)), (false, (40.0, 0.0, 34.0, 0.0))] {
    let (wide, (top, right, foot, left)) = case
    let calls : Array[Made] = []
    let (w, h) = if wide { (1280.0, 800.0) } else { (390.0, 844.0) }
    let t = if wide { wide_tester(calls) } else { wide_tester(calls, w~, h~, platform=2) }
    t.post(@hostapi.system_channel, "{\"bars\":{\"top\":\{top},\"bottom\":\{foot},\"left\":\{left},\"right\":\{right}}}")
    t.run_for(@ui.move_most_ms)
    let ((x, y, tw, th), _) = rested_toast(t, "已复制", "")
    let msg = "\{Repr(case)}: toast \{Repr((x, y, tw, th))}"
    assert_true(y + th <= h - foot - @sf.toast_bottom + 0.5, msg~)
    assert_true(x >= left - 0.5 && x + tw <= w - right + 0.5, msg~)
    // (in the middle of what the bars leave)
    assert_true((x - left - (w - right - (x + tw))).abs() < 1.0, msg~)
    t.run_for(@sf.toast_ms + @kit.presence_out_ms)
  }
}

///|
test "a toast naming a long title with its 撤销, the system's bars down the window's sides: as wide as what they leave less 16 each side at most, its 撤销 inside it" {
  // (2026-11-13 「toast的宽度有考虑到safe area吗」: a phone on its side, its cutout and the home indicator at its
  // sides; a wide window the bars leave 424 of)
  for case in [(false, 390.0, 844.0, (0.0, 40.0, 21.0, 40.0)), (true, 1024.0, 768.0, (24.0, 300.0, 20.0, 300.0))] {
    let (wide, w, h, (top, right, foot, left)) = case
    let calls : Array[Made] = []
    let t = if wide { wide_tester(calls, w~, h~) } else { wide_tester(calls, w~, h~, platform=2) }
    t.post(@hostapi.system_channel, "{\"bars\":{\"top\":\{top},\"bottom\":\{foot},\"left\":\{left},\"right\":\{right}}}")
    t.run_for(@ui.move_most_ms)
    let words = "已归档「把首页对话列表改成按天分组并且在每一组的标题里写上那天的日期和星期几，再把置顶的对话单独放在最上面」"
    let ((x, y, tw, th), button) = rested_toast(t, words, "撤销")
    let (bx, by, bw, bh) = button.unwrap()
    let msg = "\{Repr(case)}: toast \{Repr((x, y, tw, th))}"
    // (held to its most: the room the bars leave less 16 each side, narrower than toast_max)
    assert_true(w - left - right - 32.0 < @sf.toast_max, msg~)
    assert_true(x >= left + 16.0 - 0.5 && x + tw <= w - right - 16.0 + 0.5, msg~)
    assert_true(bx >= x && bx + bw <= x + tw && by >= y && by + bh <= y + th, msg="\{msg} \{Repr(button)}")
    t.run_for(@sf.toast_action_ms + @kit.presence_out_ms)
  }
}

///|
test "a toast naming a title that wraps: its 撤销 whole, as wide as beside a short one, the title giving way" {
  // (2026-10-28 「归档某个 session 时出现撤销按钮变成了点点点」: on the phone a two-line title squeezed the button, its
  // words cut to their ellipsis; the row shrank both by their width, the button's least only its padding)
  for wide in [false, true] {
    let calls : Array[Made] = []
    let t = if wide { wide_tester(calls) } else { wide_tester(calls, w=390.0, h=844.0, platform=2) }
    let (_, short) = rested_toast(t, "已归档", "撤销")
    let (_, _, short_w, _) = short.unwrap()
    let short_words = t.words().filter(fn(w) { w.0 == "撤销" })[0].3
    t.run_for(@sf.toast_action_ms + @kit.presence_out_ms)
    for words in [
        "已归档「office-mac-host-2 卡顿排查」",
        "已归档「把首页对话列表改成按天分组并且在每一组的标题里写上那天的日期和星期几，再把置顶的对话单独放在最上面」",
      ] {
      let ((x, y, tw, th), button) = rested_toast(t, words, "撤销")
      let (bx, by, bw, bh) = button.unwrap()
      assert_true((bw - short_w).abs() < 0.5, msg="\{wide} \{words} \{bw} \{short_w}")
      assert_true(bx >= x && bx + bw <= x + tw && by >= y && by + bh <= y + th, msg="\{wide} \{Repr(button)}")
      // its words whole too, as laid out
      let drawn = t.words().filter(fn(w) { w.0 == "撤销" })
      assert_eq(drawn.length(), 1)
      assert_true((drawn[0].3 - short_words).abs() < 0.5, msg="\{wide} \{words} \{drawn[0].3} \{short_words}")
      t.run_for(@sf.toast_action_ms + @kit.presence_out_ms)
    }
  }
}

///|
test "wide: a chat archived from its row with a mouse says so with 撤销 too, which asks it back (archived false)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  let (x, y) = t.find("夜里的构建又失败了").unwrap()
  t.move_to(x, y)
  t.frame()
  let (bx, by, bw, bh) = t.query(Button, label="归档「夜里的构建又失败了」").unwrap().rect
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  assert_eq(named(calls, "chat.archive").length(), 1)
  t.draw()
  // (said at once: read out as it comes in; its first frame draws it at none of its opacity, as the old view's did,
  // so it is seen, and found, as it has come in)
  assert_true(t.query(Status, label="已归档「夜里的构建又失败了」") is Some(_))
  // (come in)
  t.run_for(@kit.presence_in_ms)
  t.tap_text("撤销")
  let asked = named(calls, "chat.archive")
  assert_eq(asked.length(), 2)
  assert_eq(field(Some(asked[1].params), "archived"), Some(Json::boolean(false)))
  assert_eq(text(Some(asked[1].params), "session"), text(Some(asked[0].params), "session"))
}

///|
test "the wide frame's first page: shown once its pane has landed on what the core says was open, not the list beside an empty pane before it" {
  new_run()
  let base = fixture("home")
  // the core's marks of the workspaces (the chat last open in it among them) not come while `slow`
  let slow = @signals.signal(true)
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if slow.get() && name == "workspaceMarks" {
        return { value: None, error: None, version: 0 }
      }
      base.topic(name, params).get().snapshot()
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  // (seen: some of its glyphs drawn and nothing over them, the splash's ground none)
  let drawn = fn(s : String) { words_seen(t, s) }
  t.frame()
  assert_true(t.find("整理发布清单") is Some(_), msg="the list built")
  t.run_for(@sf.local_ms)
  assert_true(!drawn("整理发布清单"), msg="not shown with nothing beside it")
  slow.set(false)
  t.frame()
  t.frame()
  assert_true(app.nav.top() == NewChat, msg="landed")
  assert_true(drawn("整理发布清单"), msg="shown with what it landed on")
}

///|
test "a row swiped off and archived, then asked back with 撤销, is back where it rests, not off to the left" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  list_down(t, 12)
  t.draw()
  let before = t.locate("=把旧的截图都换成新的")
  let (_, y) = before[0]
  t.drag(340.0, y, 120.0, y)
  t.run_for(@ui.move_most_ms)
  assert_eq(named(calls, "chat.archive").length(), 1)
  t.draw()
  assert_true(t.locate("=把旧的截图都换成新的").is_empty())
  t.run_for(@kit.presence_in_ms)
  t.tap_text("撤销")
  assert_eq(named(calls, "chat.archive").length(), 2)
  list_down(t, 12)
  t.draw()
  // where it rests, its 归档 under it covered: nothing of the swipe left
  let after = t.locate("=把旧的截图都换成新的")
  assert_eq(after.length(), 1)
  assert_eq(after[0].0, before[0].0)
  assert_true(t.locate("=归档").is_empty())
}

///|
/// Whether words with `s` in them are seen: some of their glyphs drawn, nothing drawn over them (Tester::glyphs_seen).
fn words_seen(t : @ui.Tester, s : String) -> Bool {
  let seen = t.glyphs_seen()
  t
  .words()
  .iter()
  .any(fn(w) {
    w.0.contains(s) &&
    w.5 > 0.0 &&
    seen.iter().any(fn(g) { g.0 < w.1 + w.3 && g.2 > w.1 && g.1 < w.2 + w.4 && g.3 > w.2 })
  })
}

///|
test "the workspaces' sheet: more workspaces than it holds are reached by scrolling it, the last one switched to" {
  new_run()
  let base = fixture("home")
  let many : Array[Json] = []
  for i = 1; i <= 20; i = i + 1 {
    many.push({ "id": Json::string("ws\{i}"), "name": Json::string("工作区 \{i}"), "stations": 1 })
  }
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "workspaces" {
        {
          value: Some([{ "account": { "email": "lin@example.com" }, "workspaces": Json::array(many), "invitations": [], "loaded": true }]),
          error: None,
          version: 1,
        }
      } else {
        (base.topic_read)(name, params)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@sf.later_ms + @kit.presence_in_ms)
  t.tap_text("工作区 1")
  presented_rested(t)
  assert_true(@sf.presenting())
  let last = "工作区 20"
  let (_, foot_y) = t.find("登录其他账号").unwrap()
  let in_view = fn() {
    match t.find(last) {
      Some((_, y)) => y < foot_y
      None => false
    }
  }
  assert_true(!in_view(), msg="the last workspace starts out of the sheet's room")
  // (the sheet dragged up through the list, held still before it is let go (nothing flung), until the list's end is in the sheet)
  // (a row's height or so at a time, so the list's end is not pulled past, bouncing back as it is pressed)
  let (x, from_y) = t.find("工作区 4").unwrap()
  for _ in 0..<40 {
    if in_view() {
      break
    }
    held_drag(t, x, from_y, from_y - 60.0)
    presented_rested(t)
  }
  assert_true(in_view(), msg="the last workspace scrolled into the sheet")
  t.tap_text(last)
  assert_true(!@sf.presenting())
  let (_, bar_y) = t.find(last).unwrap()
  assert_true(bar_y < 100.0, msg="the workspace in view is the last one: \{bar_y}")
}

///|
/// A finger down at (`x`, `y0`), moved to `y1` a step a frame and held there still before it is let go: nothing flung.
fn held_drag(t : @ui.Tester, x : Double, y0 : Double, y1 : Double) -> Unit {
  t.touch(0, x, y0)
  for i = 1; i <= 12; i = i + 1 {
    t.advance(@ui.drag_step_ms)
    t.touch(1, x, y0 + (y1 - y0) * i.to_double() / 12.0)
    t.draw()
  }
  for _ in 0..<12 {
    t.advance(@ui.drag_step_ms)
    t.touch(1, x, y1)
    t.draw()
  }
  t.touch(2, x, y1)
  t.draw()
}

///|
test "a phone's Home: the bell opens 待处理, 全部已读 reads the unread and leaves the rest" {
  let t = tester("home-attention")
  t.frame()
  let (x, y, w, h) = named_at(t, "待处理").unwrap()
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  t.frame()
  assert_true(t.find("整理发布清单") is Some(_))
  assert_true(t.find("夜里的备份") is Some(_))
  assert_true(t.find("周报草稿") is Some(_))
  assert_true(t.find("全部已读") is Some(_))
  let (x, y, w, h) = t.rect_of("全部已读").unwrap()
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  t.frame()
  assert_true(t.find("周报草稿") is None)
  assert_true(t.find("全部已读") is None)
  assert_true(t.find("整理发布清单") is Some(_))
  assert_true(t.find("夜里的备份") is Some(_))
}

///|
/// A made-up core whose chats' list of ws1 says it has 10 more rows than it gives, till it is told a window past those it
/// gives: what it is told of the list's window (`chats.window`'s rows) and what of it is let go of put in `told`, `left`.
fn more_source(told : Array[Int], left : Array[String]) -> Source {
  let base = fixture("home")
  let windowed = @signals.signal(false)
  {
    ..base,
    topic_read: fn(name, params) {
      let t = base.topic(name, params).get().snapshot()
      guard name == "chats" && !windowed.get() else { return t }
      match t.value {
        Some(Object(v)) => {
          let more = v.copy()
          more["more"] = Json::number(10.0)
          { ..t, value: Some(Json::object(more)) }
        }
        _ => t
      }
    },
    call: fn(name, params, done) {
      if name == "chats.window" {
        match field(Some(params), "rows") {
          Some(Number(n, ..)) => told.push(n.to_int())
          _ => ()
        }
        windowed.set(true)
      }
      (base.call)(name, params, done)
    },
    leave: fn(name, params, reason) {
      if name == "chats" {
        left.push(Json::object(params).stringify())
      }
      (base.leave)(name, params, reason)
    },
  }
}

///|
test "Home's list near its end while the core has more is told a window past what it holds, once, its list let go of never" {
  // (the whole list of 1400 chats went to the app as it opened, a screen of them shown: 2026-11-08; a page more was
  // another topic, the list whole again: 2026-11-11)
  new_run()
  let told : Array[Int] = []
  let left : Array[String] = []
  let src = more_source(told, left)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  let shown = @signals.untracked(fn() {
    match chats_of(src, "ws1", "all").0 {
      Some(v) => v.days.fold(init=0, fn(n, d) { n + d.items.length() })
      None => 0
    }
  })
  // its few rows end within the screen: more asked for at once (a step past them, or the screen's first window, whichever
  // came first: one), none after it
  assert_eq(told.length(), 1)
  assert_true(told[0] >= shown + @sfbase.window_step(844.0) || told[0] == @sfbase.first_window(844.0))
  assert_true(told[0] > shown)
  assert_eq(left, [])
}

///|
test "Home's rows stay while its window grows, not its skeleton" {
  // (the list went to its skeleton for the core's round trip each time a page more was asked: 2026-11-08)
  new_run()
  let told : Array[Int] = []
  let left : Array[String] = []
  let src = more_source(told, left)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  assert_eq(told.length(), 1)
  assert_true(t.find("整理发布清单") is Some(_))
  assert_eq(t.bones_drawn(), 0)
  assert_eq(left, [])
}

///|
test "Home's long list held and dragged: a frame moves the list's header alone, nothing built, laid out or painted, but where a row comes in or goes or a mark in one steps" {
  // (2026-11-09: each such frame laid out, placed and painted all of the window, the list moved as a placement)
  new_run()
  let src = fixture("long")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.set_rows_on_pixels(true)
  t.run_for(@ui.move_most_ms)
  let (_, y0) = t.find("整理发布清单").unwrap()
  // (down on the list and up past the slop: the hold the list's)
  t.hold_drag(195.0, 600.0, 195.0, 580.0, steps=2)
  // (then on 3 points a move: each frame of the looks alone drawn whole after it as well and the two compared, as in
  // every test; each painted for its cause: the list's rows come in or gone or measured (list_window.mbt), a mark's
  // step on the resident clock, its bar's coming in over once (a moment said as it was first scrolled, its thumb no
  // more drawn by the time: scroll_bar.mbt's BarState::rested_at), or, the frame after one of these, the paint before
  // it having drawn otherwise)
  let others = []
  let mut looks = 0
  let mut caused = false
  let mut bar_in = false
  for i in 0..<40 {
    let was = t.looks_alone()
    let step = (t.time() / @view.resident_step_ms).floor()
    t.hold_move(195.0, 580.0 - 3.0 * (i + 1).to_double())
    if t.looks_alone() > was {
      looks = looks + 1
      caused = false
      continue
    }
    let why = t.built_why() + t.painted_why()
    let bar_came = !bar_in && why.contains("scroll_bar.mbt")
    bar_in = bar_in || bar_came
    caused = why.contains("list_window.mbt") ||
      (t.time() / @view.resident_step_ms).floor() != step ||
      bar_came ||
      (caused && why == "the paint before it drew otherwise")
    if !caused {
      others.push("move \{i}: \{why}")
    }
  }
  let (_, y1) = t.find("整理发布清单").unwrap()
  t.release(195.0, 460.0)
  assert_true(y1 < y0 - 100.0, msg="the list moved from \{y0} to \{y1}")
  assert_eq(others, [], msg="\{looks} of 40 frames of the looks alone; \{Repr(others)}")
}
