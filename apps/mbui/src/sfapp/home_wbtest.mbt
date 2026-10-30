///|
/// The app over a fixture, from its start (the pages, the sheet and the filters forgotten).
fn tester(mode : String) -> @ui.Tester {
  reset()
  let src = fixture(mode)
  @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
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
  reset()
  let pressed = Ref::new(0)
  let src : Source = { ..fixture("signin"), sign_in: fn() { pressed.val += 1 } }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
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
  reset()
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
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
  reset()
  let src = fixture("home")
  @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
}

///|
test "a row pressed: on the ground it has held once the press is not the list's (the tap timeout)" {
  // one that cannot be archived, one that can (swiped left)
  for title in ["夜里的构建又失败了", "把旧的截图都换成新的"] {
    let t = android_home()
    t.scroll_to(12)
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
test "the filter: 我参与的 shows only the chats the viewer is in" {
  let t = tester("home")
  match t.rect_of("星火工作室") {
    Some(_) => ()
    None => fail("no title")
  }
  // the filter's button, at the bar's right
  t.tap(390.0 - 16.0 - 17.0, 25.0)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(t.find("监控中") is Some(_))
  t.tap_text("我参与的")
  assert_true(t.find("首页的列表改成按天分组") is Some(_))
  assert_true(t.find("夜里的构建又失败了") is Some(_))
  assert_true(t.find("和 Ana 一起看新版的引导页") is Some(_))
}

///|
test "a row archived: an archivable row under it closes over it whole, its swipe's clip moving with it" {
  // (Home.kt: the list's animateItem moves the whole of SwipeToArchive. Filmed on a phone: the 归档 rows under one
  // archived gone a moment, then coming up cut off below, the row moved inside a clip left where it is laid out)
  // (the list at its top: the rows under one gone come up; scrolled to its end, the rows over it would come down)
  let t = tester("home")
  let under = "把旧的截图都换成新的"
  let (_, y_was, _, h) = t.rect_of(under).unwrap()
  assert_false(t.locate("=Slack 里问的报销流程").is_empty())
  hold_row(t, "Slack 里问的报销流程")
  // the menu's 归档 (its last item)
  let (lx, ly) = t.find_last("归档").unwrap()
  t.tap(lx, ly)
  assert_true(t.locate("=Slack 里问的报销流程").is_empty())
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
  // (the first page built as it opens, shown once it has its list, first_page_ms at most: not drawn till then, not
  // its shapes swapped for its rows a frame later)
  let drawn = fn(s : String) { t.words().iter().any(fn(w) { w.0.contains(s) && w.5 > 0.0 }) }
  assert_true(!drawn("星火工作室"))
  t.run_for(page_local_ms)
  assert_true(!drawn("星火工作室"), msg="a page opening's wait is not the first page's")
  t.run_for(first_page_ms - page_local_ms)
  assert_true(drawn("星火工作室"))
  assert_true(t.find("整理发布清单") is None)
  assert_true(t.find("星火工作室") is Some(_))
}

///|
test "a state line's lead is the core's: an icon in its words' place with what follows; none, the words as they are" {
  reset()
  let t = @ui.Tester::new(
    fn(c) {
      c.box(w=Fill(1.0), fn() {
        @sfpages.state_line(c, "a", c.id("a"), "要你帮忙：看一下", lead="need", rest="看一下")
        // (words that look like a lead, said by none: as they are)
        @sfpages.state_line(c, "b", c.id("b"), "要你帮忙看一眼")
        @sfpages.state_line(c, "c", c.id("c"), "奏 · 用哪个？", lead="decision", lead_text="奏", rest=" · 用哪个？")
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
  assert_true(t.find("奏") is Some(_))
  assert_true(t.find(" · 用哪个？") is Some(_))
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
  // (a finger's press in a list shows a moment after it goes down: @ui.tap_indication_ms)
  t.run_for(@ui.tap_indication_ms + @sfpages.hold_ms)
  t.release(x, y)
}

///|
test "a row held long: its menu (固定, 重命名, 复制会话链接, 归档), the chat not opened; 重命名 its sheet" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
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
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
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
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  hold_row(t, "盯着 CI，绿了告诉我")
  // the menu's 归档 (its last item)
  let (lx, ly) = t.find_last("归档").unwrap()
  t.tap(lx, ly)
  assert_eq(named(calls, "chat.archive").length(), 0)
  assert_true(t.find("归档「盯着 CI，绿了告诉我」？") is Some(_))
  assert_true(t.find("它会在归档里继续盯着。") is Some(_))
  // its 归档, beside 取消
  let (cx, cy, cw, ch) = t.rect_of("取消").unwrap()
  t.tap(cx + cw + 40.0, cy + ch / 2.0)
  assert_eq(named(calls, "chat.archive").length(), 1)
}

///|
test "a row with nothing left in it, swiped left past a third: off, then archived (chat.archive); a short swipe archives nothing" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
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
  // across past a third of the row: it goes off, then is archived (Home.kt: the call once it has gone)
  t.drag(340.0, y, 120.0, y)
  assert_eq(named(calls, "chat.archive").length(), 0)
  t.run_for(@ui.move_most_ms)
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
  reset()
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
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.draw()
  let mine = fn() { read.iter().any(fn(k) { k.contains("\"mine\":true") }) }
  assert_false(mine())
  // the filter's button, at the bar's right
  t.tap(390.0 - 16.0 - 17.0, 25.0)
  // (the menu open, built again from it)
  t.draw()
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
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
  t.tap(390.0 - 16.0 - 17.0, 25.0)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  for words in ["全部会话", "我参与的", "监控中", "已归档"] {
    assert_true(t.find(words) is Some(_), msg=words)
  }
  // 已归档: its page
  t.tap_text("已归档")
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Archived)
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
  assert_true(t.find("已归档「夜里的构建又失败了」") is Some(_))
  // (come in)
  t.run_for(@kit.presence_in_ms)
  t.tap_text("撤销")
  let asked = named(calls, "chat.archive")
  assert_eq(asked.length(), 2)
  assert_eq(field(Some(asked[1].params), "archived"), Some(Json::boolean(false)))
  assert_eq(text(Some(asked[1].params), "session"), text(Some(asked[0].params), "session"))
  t.draw()
  // the toast goes, said again once it is done
  assert_true(t.find("撤销") is None)
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
  app.toast.set(words)
  app.toast_action.set(action)
  app.toast_n.set(app.toast_n.get() + 1)
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
    assert_true((bare.3 - 2.0 * @sf.toast_r).abs() < 0.5, msg="\{wide} \{bare}")
    t.run_for(@sf.toast_ms + @kit.presence_out_ms)
    let ((x, y, w, h), button) = rested_toast(t, "已归档", "撤销")
    let (bx, by, bw, bh) = button.unwrap()
    // as high as one without; its button as far from its top, foot and end as its corner has a capsule that high
    assert_true((h - 2.0 * @sf.toast_r).abs() < 0.5, msg="\{wide} \{h}")
    let inset = @sf.capsule_in(@sf.toast_r, bh, room=@sf.toast_r)
    for gap in [by - y, y + h - (by + bh), x + w - (bx + bw)] {
      assert_true((gap - inset).abs() < 0.5, msg="\{wide} \{gap} \{inset}")
    }
  }
}

///|
test "a chat archived from its row: said at once by its title, its station not answered yet; why not once it says no" {
  let calls : Array[Made] = []
  reset()
  let base = fixture("home")
  // (chat.archive left waiting: its station's answer not come)
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      if name != "chat.archive" {
        (base.call)(name, params, done)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  hold_row(t, "夜里的构建又失败了")
  let (lx, ly) = t.find_last("归档").unwrap()
  t.tap(lx, ly)
  t.draw()
  assert_true(t.find("已归档「夜里的构建又失败了」") is Some(_))
  assert_true(t.find("撤销") is Some(_))
  // no: why, in its place
  (named(calls, "chat.archive")[0].done)(Err({ "message": "坏了" }))
  t.draw()
  assert_true(app.toast.get().contains("坏了"), msg=app.toast.get())
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
    assert_true(bx >= x && bx + bw <= x + tw && by >= y && by + bh <= y + th, msg="\{wide} \{button}")
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
      assert_true(bx >= x && bx + bw <= x + tw && by >= y && by + bh <= y + th, msg="\{wide} \{button}")
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
  t.move(x, y)
  t.frame()
  let (bx, by, bw, bh) = t.query(Button, label="归档「夜里的构建又失败了」").unwrap().rect
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  assert_eq(named(calls, "chat.archive").length(), 1)
  t.draw()
  assert_true(t.find("已归档「夜里的构建又失败了」") is Some(_))
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
  reset()
  let base = fixture("home")
  // the core's marks of the workspaces (the chat last open in it among them) not come while `slow`
  let slow = Ref(true)
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if slow.val && name == "workspaceMarks" {
        return { value: None, error: None, version: 0 }
      }
      (base.topic)(name, params)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  let drawn = fn(s : String) { t.words().iter().any(fn(w) { w.0.contains(s) && w.5 > 0.0 }) }
  t.frame()
  assert_true(t.find("整理发布清单") is Some(_), msg="the list built")
  t.run_for(page_local_ms)
  assert_true(!drawn("整理发布清单"), msg="not shown with nothing beside it")
  slow.val = false
  t.frame()
  t.frame()
  assert_true(app.nav.top() == NewChat, msg="landed")
  assert_true(drawn("整理发布清单"), msg="shown with what it landed on")
}

///|
test "a row swiped off and archived, then asked back with 撤销, is back where it rests, not off to the left" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  t.scroll_to(12)
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
  t.scroll_to(12)
  t.draw()
  // where it rests, its 归档 under it covered: nothing of the swipe left
  let after = t.locate("=把旧的截图都换成新的")
  assert_eq(after.length(), 1)
  assert_eq(after[0].0, before[0].0)
  assert_true(t.locate("=归档").is_empty())
}
