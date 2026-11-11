// A row of the chats' lists is what it draws (the core's ListedChat); what only a press, a hold, a swipe or a pointer
// reads of it (its menu's items, its swipe's question, its time in words) is its chat's whole row, `chatRow`, asked as
// the hand comes to it (sfbase whole_row.mbt). Over a core answering that late, what opens waits for it and opens
// whole the frame it is answered, on 小屏 and on a wide screen: never empty, never half, never filled after.

///|
/// The app over made-up core `mode` (its chats' rows cut to what the core's list sends, their whole rows its
/// `chatRow`), each chat's whole row answered `late` ms after it is asked and the rest at once, in a window `w` by `h`
/// on `platform`'s hand, at rest on Home; its calls kept in `calls`.
fn late_rows_tester(calls : Array[Made], mode : String, w : Double, h : Double, platform : Int, late : Double) -> @ui.Tester {
  new_run()
  let base = fixture(mode)
  let made : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      (base.call)(name, params, done)
    },
  }
  let src = round_trip_again(made, 0.0, late=fn(name, _) { if name == "chatRow" { late } else { 0.0 } })
  late_rows_src.val = Some(src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  t.draw()
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The source the last late_rows_tester was made over.
// kept across runs: said by late_rows_tester as its run begins
let late_rows_src : Ref[Source?] = Ref(None)

///|
/// Each frame from now till `upto` ms after `start`: its moment after `start`, and which of `words` it shows.
fn words_over(t : @ui.Tester, start : Double, upto : Double, words : Array[String]) -> Array[(Double, Array[String])] {
  let out : Array[(Double, Array[String])] = []
  while t.time() - start < upto {
    t.run_for(@ui.frame_period_default)
    out.push((t.time() - start, words.filter(fn(w) { t.find(w) is Some(_) })))
  }
  out
}

///|
/// What `frames` (words_over's) say of `words`: none of them before `late` ms; from the first frame that shows any, all
/// of them in each frame; and that one came within a few frames after `due` (the later of `late` and the gesture's own
/// moment: a long press's).
fn whole_from(frames : Array[(Double, Array[String])], words : Array[String], late : Double, due : Double, at : String) -> Unit raise {
  let shown = frames.filter(fn(f) { f.1.length() > 0 })
  guard shown.length() > 0 else { fail("\{at}: never shown") }
  for f in frames {
    if f.0 < late - 1.0 && f.1.length() > 0 {
      fail("\{at}: \{Repr(f.1)} at \{f.0} ms, before its whole row was answered (\{late} ms)")
    }
  }
  let first = shown[0].0
  for f in frames {
    if f.0 >= first && f.1.length() != words.length() {
      fail("\{at}: at \{f.0} ms only \{Repr(f.1)} of \{Repr(words)}")
    }
  }
  if first > due + 4.0 * @ui.frame_period_default {
    fail("\{at}: shown at \{first} ms, due at \{due}")
  }
}

///|
/// The screens and hands a row's gestures are tried with: 小屏 with a finger, a wide screen with a mouse.
let whole_cases : Array[(Double, Double, Int)] = [(390.0, 844.0, 2), (1280.0, 800.0, 0)]

///|
test "a row's menu over a core answering its whole row 1 s late: held on 小屏, right clicked wide, it opens whole as that is answered, every item it has, its 分享… too" {
  let late = 1000.0
  for case in whole_cases {
    let (w, h, platform) = case
    let at = "\{w} platform \{platform}"
    let calls : Array[Made] = []
    let t = late_rows_tester(calls, "home-share", w, h, platform, late)
    let (x, y) = t.find("夜里的构建又失败了").unwrap()
    let start = t.time()
    if platform == 2 {
      t.press_at(x, y)
      t.run_for(@ui.tap_indication_ms + @sfpages.hold_ms)
      t.release(x, y)
    } else {
      t.move_to(x, y)
      t.frame()
      t.right_click(x, y)
    }
    let items = ["重命名", "归档", "分享…"]
    whole_from(words_over(t, start, late + 400.0, items), items, late, late, at)
    // not opened by the hold
    assert_false(app.nav.top() is Chat({ title: "夜里的构建又失败了", .. }), msg=at)
    // what shares it, its whole row's: shared with another workspace, a picture of it, it in Slack
    open_share(t)
    for item in ["复制会话链接", "分享给其他 workspace", "分享图片", "在 Slack 中打开"] {
      assert_true(t.find(item) is Some(_), msg="\{at}: \{item}")
    }
  }
}

///|
test "a row's menu over a late whole row has what only that says: 保留's and 固定's state, 隐藏 and 关闭提醒, on 小屏 and wide" {
  let late = 300.0
  let rows : Array[(String, String, Array[String])] = [
    ("home-pins", "盯着 CI，绿了告诉我", ["取消保留", "固定", "重命名", "归档"]),
    ("home-pins", "给设置页加一个深色模式开关", ["取消固定", "重命名", "归档"]),
    ("home-hide", "整理发布清单", ["隐藏", "关闭提醒", "重命名", "归档"]),
  ]
  for case in whole_cases {
    let (w, h, platform) = case
    for row in rows {
      let (mode, title, items) = row
      let at = "\{w} platform \{platform} \{title}"
      let calls : Array[Made] = []
      let t = late_rows_tester(calls, mode, w, h, platform, late)
      let (x, y) = t.find(title).unwrap()
      let start = t.time()
      // (asked as the finger went down, answered before the hold's menu: opened as it is held; right clicked, the
      // moment it is answered)
      let frames = if platform == 2 {
        t.press_at(x, y)
        let f = words_over(t, start, late + @ui.long_press_ms + 200.0, items)
        t.release(x, y)
        f
      } else {
        t.right_click(x, y)
        words_over(t, start, late + @ui.long_press_ms + 200.0, items)
      }
      whole_from(frames, items, late, if platform == 2 { dmax(late, @ui.long_press_ms) } else { late }, at)
    }
  }
}

///|
test "a finger swiping a row over a late whole row: let go before it is answered, the row stays and asks the moment it is (someone else's); one's own is archived then, asked nothing" {
  let late = 300.0
  let calls : Array[Made] = []
  let t = late_rows_tester(calls, "home", 390.0, 844.0, 2, late)
  let (x, y) = t.find("和 Ana 一起看新版的引导页").unwrap()
  let start = t.time()
  t.drag(x + 190.0, y, x + 10.0, y)
  let asks = ["归档「和 Ana 一起看新版的引导页」？", "这是Ana发起的对话。归档后，workspace 里所有人的列表都不再显示它，agent 也不再接收新消息。"]
  whole_from(words_over(t, start, late + @ui.move_most_ms, asks), asks, late, late, "someone else's")
  assert_eq(named(calls, "chat.archive").length(), 0)
  t.tap_text("取消")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("和 Ana 一起看新版的引导页") is Some(_))
  // one the viewer started, swiped as far: archived once its whole row says nothing to ask
  let (x, y) = t.find("首页的列表改成按天分组").unwrap()
  t.drag(x + 190.0, y, x + 10.0, y)
  t.run_for(late + @ui.move_most_ms * 2.0)
  assert_eq(named(calls, "chat.archive").length(), 1)
  assert_true(t.find("归档「首页的列表改成按天分组」？") is None)
}

///|
test "a row's time over a late whole row: pointed at wide, held a while on 小屏, it shows as that is answered, never empty before" {
  let late = 300.0
  for case in whole_cases {
    let (w, h, platform) = case
    let at = "\{w} platform \{platform}"
    let calls : Array[Made] = []
    let t = late_rows_tester(calls, "home", w, h, platform, late)
    let (x, y) = t.find("首页的列表改成按天分组").unwrap()
    assert_true(t.find("8 分钟前") is None, msg=at)
    let start = t.time()
    let frames = if platform == 2 {
      t.press_at(x, y)
      let f = words_over(t, start, late + @ui.long_press_ms + 200.0, ["8 分钟前"])
      t.release(x, y)
      f
    } else {
      t.move_to(x, y)
      words_over(t, start, late + 200.0, ["8 分钟前"])
    }
    whole_from(frames, ["8 分钟前"], late, if platform == 2 { dmax(late, @ui.long_press_ms) } else { late }, at)
  }
}

///|
test "the chat's page's … over a late whole row: asked as the page opens, opened whole as it is answered, what a row's menu has" {
  let late = 300.0
  for case in whole_cases {
    let (w, h, platform) = case
    let at = "\{w} platform \{platform}"
    let calls : Array[Made] = []
    let t = late_rows_tester(calls, "home-pins", w, h, platform, late)
    let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
    let start = t.time()
    @ui.view_tree().unwrap().event(t.time(), fn() { open_page(Chat(r)) })
    t.frame()
    let src = late_rows_src.val.unwrap()
    @ui.view_tree().unwrap().event(t.time(), fn() { @sfpages.open_chat_menu(src, "ws1", r, [], from=@sf.at_point(w / 2.0, h / 2.0)) })
    let items = ["固定", "重命名", "归档"]
    whole_from(words_over(t, start, late + @ui.move_most_ms, items), items, late, late, at)
  }
}

///|
test "an iPhone Duo: the chat's … in the system's bars chosen before its whole row is answered opens whole as that is answered" {
  // (the system's … is chosen as a frame is read (sfdesk rail_native.mbt): what waits for the row was let go by the
  // next frame till 2026-11-12, and nothing opened)
  let late = 3000.0
  new_run()
  let src = round_trip_again(fixture("chat"), 0.0, late=fn(name, _) { if name == "chatRow" { late } else { 0.0 } })
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=951.0, h=669.0, platform=1, nav_able=true)
  let start = t.time()
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":20,\"left\":0,\"right\":84}}")
  t.run_for(@ui.move_most_ms)
  // (its rows not handed yet: the system's … is the app's to open)
  let said = t.nav_said()
  assert_true(said.contains("\"id\":\"page/chat/more\"") && !said.contains("page/chat/more/0"), msg=said)
  t.post(@hostapi.system_channel, "{\"nav\":\"page/chat/more\"}")
  let items = ["重命名", "归档"]
  whole_from(words_over(t, start, late + @ui.move_most_ms, items), items, late, late, "duo")
  @sf.close_all_presented()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("归档") is None)
}
