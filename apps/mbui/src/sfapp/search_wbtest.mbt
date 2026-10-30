// The search over Home (search.mbt; Search.kt) over the made-up chats (search_fixture.mbt).

///|
/// Home with the search open, its field come up (the list scrolled to it first: it starts out of view).
fn search_tester() -> @ui.Tester {
  reset()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.scroll_to(0)
  t.draw()
  t.tap_text("搜索全部内容")
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "Home's list starts at its first row, the search above it out of view under the bar" {
  let t = tester("home")
  t.draw()
  match t.rect_of("搜索全部内容") {
    Some((_, y, _, h)) => assert_true(y + h <= bar_h + 8.0)
    None => ()
  }
  let (_, y) = t.find("整理发布清单").unwrap()
  assert_true(y > bar_h)
  t.assert_idle()
}

///|
test "the field tapped: the search opens over Home, its field focused, the bars away; 取消 puts it back" {
  let t = tester("home")
  t.scroll_to(0)
  t.draw()
  let (_, from) = t.find("搜索全部内容").unwrap()
  t.tap_text("搜索全部内容")
  assert_true(@sfpages.search_opened())
  // the bottom bar goes out of its way at once
  assert_true(@sfpages.search_bar_away())
  t.run_for(@ui.move_most_ms)
  let (active, _, _, _) = t.ime()
  assert_true(active)
  // the keyboard's action key a search key (Search.kt: ImeAction.Search)
  assert_eq(t.ime_action(), @hostapi.ime_action_search)
  // its field at the top now (8 under the page's top), 取消 beside it
  let (_, to) = t.find("取消").unwrap()
  assert_true(to < from)
  t.type_text("签名")
  assert_eq(@sfpages.finder_query(), "签名")
  assert_true(t.find("对话") is Some(_))
  assert_true(t.find("签名证书续期") is Some(_))
  assert_true(t.find("消息") is Some(_))
  t.tap_text("取消")
  assert_true(@sfpages.search_leaving())
  assert_true(!@sfpages.search_bar_away())
  t.run_for(@ui.move_most_ms)
  t.draw()
  assert_true(!@sfpages.search_opened())
  assert_true(t.find("取消") is None)
  assert_eq(@sfpages.finder_query(), "")
  t.run_for(@sf.strokes_ms(4))
  t.assert_idle()
}

///|
test "what the words find: chats, messages, then each kind, the words bold in their lines" {
  let t = search_tester()
  t.type_text("签名")
  // a chat by its title (as Home lists it), one by a line of it with its title under it
  assert_true(t.find("签名证书续期") is Some(_))
  assert_true(t.find("正在核对第三项") is Some(_))
  // the messages: the line that has them, who said it and when
  assert_true(t.find("安装包的签名对上了") is Some(_))
  // (who, a part of the line under it that leaves it before where it is is cut short; when)
  assert_true(t.find("Claude ·") is Some(_) && t.find("5 分钟前") is Some(_))
  assert_true(t.find("查看更多") is Some(_))
  // a kind: its heading, what was found
  assert_true(t.find("文件") is Some(_))
  assert_true(t.find("签名说明.md") is Some(_))
  assert_true(t.find("签名检查页") is Some(_))
  // the words found are a bold run of their own
  match t.rich_of("安装包的签名对上了") {
    Some((rl, _, _)) => assert_true(rl.run_at(4) >= 1)
    None => fail("no line")
  }
  // their strokes drawn in, one after another, and done
  t.run_for(@sf.strokes_ms(4))
  t.assert_idle()
}

///|
test "查看更多 lists that kind alone, from the top; 全部结果 and back go back to every kind" {
  let t = search_tester()
  t.type_text("签名")
  t.tap_text("查看更多")
  assert_eq(@sfpages.finder_kind(), "message")
  t.draw()
  assert_true(t.find("全部结果") is Some(_))
  assert_true(t.find("我先把签名脚本跑一遍看看") is Some(_))
  assert_true(t.find("签名说明.md") is None)
  t.tap_text("全部结果")
  assert_eq(@sfpages.finder_kind(), "")
  t.draw()
  assert_true(t.find("签名说明.md") is Some(_))
  // back: one kind first, then the search away
  t.tap_text("查看更多")
  assert_true(t.takes_back())
  t.back()
  assert_eq(@sfpages.finder_kind(), "")
  assert_true(@sfpages.search_opened())
  t.back()
  assert_true(@sfpages.search_leaving())
  t.run_for(@ui.move_most_ms)
  t.draw()
  assert_true(!@sfpages.search_opened())
  t.run_for(@sf.strokes_ms(4))
  t.assert_idle()
}

///|
test "a message found opens its chat at it, with the words to mark there" {
  let t = search_tester()
  t.type_text("签名")
  t.tap_text("安装包的签名对上了")
  assert_eq(app.nav.depth(), 2)
  match app.nav.top() {
    Chat(r) => {
      assert_eq(r.session, "s-c1")
      t.run_for(@ui.move_most_ms)
      // gone to (seq 5), its words to mark there, nothing flashing
      let rd = reading_of("ws1/st1\u{1}s-c1")
      assert_eq(rd.found_at, "ts5")
      assert_eq(rd.found_words, ["签名"])
      assert_eq(rd.flash, "")
    }
    _ => fail("not a chat")
  }
}

///|
test "a chat opened from the search, read a while, back: the search as it was left, its field up, what it found" {
  let t = search_tester()
  t.type_text("签名")
  let cancel_at = t.shown_of("取消")
  t.tap_text("签名证书续期")
  assert_eq(app.nav.depth(), 2)
  t.run_for(@ui.move_most_ms)
  // (long enough in the chat that what Home moves by, not drawn meanwhile, is let go)
  for _ in 0..<200 {
    t.draw()
  }
  t.back()
  t.run_for(@ui.move_most_ms)
  t.draw()
  assert_eq(app.nav.depth(), 1)
  assert_true(@sfpages.search_opened())
  assert_eq(@sfpages.finder_query(), "签名")
  // its field still up with 取消 beside it, not back in the list with the words left in it (the list under the page
  // then, the page taking its touches)
  assert_eq(t.shown_of("取消"), cancel_at)
  assert_eq(t.look_of("取消").map(fn(l) { l.2 }), Some(1.0))
}

///|
test "what else was found opens where it is: a file its reader, a service its chat and its page" {
  let t = search_tester()
  t.type_text("签名")
  t.tap_text("签名说明.md")
  match app.nav.top() {
    DriveRead(at) => {
      assert_eq(at.station, "ws1/st1")
      assert_eq(at.root, Some("/Users/lin/docs"))
      assert_eq(at.path, "签名说明.md")
    }
    _ => fail("not the reader")
  }
  app.nav.pop() |> ignore
  t.run_for(@ui.move_most_ms)
  t.tap_text("签名检查页")
  assert_eq(app.nav.depth(), 3)
  assert_true(app.nav.top() == Service("ws1/st1", "job-1"))
}

///|
test "nothing found; still being looked for, what could not be, what the core says" {
  let t = search_tester()
  t.type_text("没有")
  assert_true(t.find("未找到结果") is Some(_))
  for _ in 0..<2 {
    t.backspace()
  }
  t.type_text("等等")
  assert_true(t.find("未找到结果") is None)
  assert_true(t.find("MBA 无法搜索：它的版本太旧") is Some(_))
  assert_true(t.find("还有 1 台 station 离线，没有搜它上面的内容") is Some(_))
}

///|
test "what was found opens where the core says (SearchItem.open): a file read, a service its chat and its page, a station its page" {
  reset()
  let base : FoundItem = {
    kind: "file",
    key: "f",
    station: "s",
    station_name: "S",
    station_emoji: "",
    station_icon: "",
    title: "",
    text: "",
    marks: [],
    chat_title: "那个对话",
    dir: false,
    ago: "",
    open: Some({ to: "files", station: "s", chat: None, job: None, root: Some("/a/b"), path: "c.txt", how: "read" }),
  }
  open_found(base)
  assert_true(app.nav.top() == DriveRead({ station: "s", root: Some("/a/b"), path: "c.txt" }))
  open_found({ ..base, open: Some({ to: "files", station: "s", chat: None, job: None, root: Some("/a"), path: "b", how: "" }) })
  assert_true(app.nav.top() == Drive({ station: "s", root: Some("/a"), path: "b" }))
  open_found({ ..base, open: Some({ to: "service", station: "s", chat: Some("k"), job: Some("j"), root: None, path: "", how: "" }) })
  assert_true(app.nav.top() == Service("s", "j"))
  open_found({ ..base, open: Some({ to: "station", station: "s", chat: None, job: None, root: None, path: "", how: "" }) })
  assert_true(app.nav.top() == Setting(@settings.Station("s")))
  // opening nowhere: where it was
  open_found({ ..base, open: None })
  assert_true(app.nav.top() == Setting(@settings.Station("s")))
}

///|
test "a stroke is drawn in over 520 ms, the next 180 ms after" {
  assert_eq(@sf.stroke_part(0.0, 0), 0.0)
  assert_eq(@sf.stroke_part(@sf.stroke_ms, 0), 1.0)
  assert_eq(@sf.stroke_part(@sf.stroke_gap_ms, 1), 0.0)
  assert_eq(@sf.stroke_part(@sf.stroke_gap_ms + @sf.stroke_ms / 2.0, 1), @ui.InOut.at(0.5))
  assert_eq(@sf.strokes_ms(2), 520.0 + 360.0)
}

///|
test "a chat opened from a found message: the words bold in it, stroked under, nothing flashing" {
  let t = search_tester()
  t.type_text("虚拟列表")
  t.tap_text("帮我把聊天页的列表做成")
  t.run_for(@ui.move_most_ms)
  let rd = reading_of("ws1/st1\u{1}s-c1")
  assert_eq(rd.found_at, "ts2")
  assert_eq(rd.flash, "")
  assert_eq(rd.found_words, ["虚拟列表"])
  // bold where they are in the bubble
  match t.rich_of("帮我把聊天页的列表做成虚拟列表") {
    Some((rl, _, _)) => {
      let k = rl.run_at(13)
      assert_true(k >= 0)
    }
    None => fail("no bubble")
  }
  t.run_for(found_draw_ms)
  // still marked once drawn in: for as long as the chat shows
  assert_eq(rd.found_at, "ts2")
  assert_eq(rd.found_words, ["虚拟列表"])
  t.assert_idle()
}

///|
test "a search's words: where they are, case aside; runs cut and bold there" {
  assert_eq(@sf.find_words("Abc abc ABC", ["abc"]), [(0, 3), (4, 7), (8, 11)])
  assert_eq(@sf.find_words("做成虚拟列表了", ["虚拟", "列表"]), [(2, 4), (4, 6)])
  let runs = @sf.found_weight([@ui.plain("ab"), @ui.plain("cde")], ["bcd"])
  assert_eq(runs.map(fn(r) { r.text }), ["a", "b", "cd", "e"])
  assert_eq(runs.map(fn(r) { r.weight }), [0, 600, 600, 0])
}

///|
/// The app as src/sffix opens `mode`, for a Tester (search-results, search-jobs).
fn search_mode(mode : String) -> @ui.Tester {
  let src = fixture_app(mode)
  // (a phone's: a finger's search, in the lists)
  @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
}

///|
test "as the Android app's SearchResultsTest: each kind, 查看更多 only where there is more, the station and time beside each" {
  let t = search_mode("search-results")
  t.draw()
  assert_true(t.find("服务和任务") is Some(_))
  assert_true(t.find("成员") is Some(_))
  assert_true(t.find("Safari 17 上点了登录没有任何反应") is Some(_))
  // two stations: each found thing says which it is on, with when
  // (which, a part of the line under it that leaves it before what was found is cut short; when)
  assert_true(t.find("studio ·") is Some(_) && t.find("10 分钟前") is Some(_))
  assert_true(t.find("mac ·") is Some(_) && t.find("80 分钟前") is Some(_))
  // a member: no station
  assert_true(t.find("登录组 · 王五") is Some(_))
  assert_true(t.find("mini 离线，其上的内容未搜索") is Some(_))
  t.tap_text("查看更多")
  t.draw()
  assert_eq(@sfpages.finder_kind(), "job")
  assert_true(t.find("全部结果") is Some(_))
  assert_true(t.find("node mock/登录.js :4000") is Some(_))
  assert_true(t.find("成员") is None)
  assert_true(t.find("查看更多") is None)
  t.tap_text("全部结果")
  t.draw()
  assert_true(t.find("成员") is Some(_))
  // a service: its chat, and its page over it
  t.tap_text("登录页预览")
  assert_true(app.nav.top() == Service("ws1/st1", "j-1"))
  let pages = app.nav.pages()
  match pages[pages.length() - 2] {
    Chat(r) => assert_eq(r.session, "ember:c-2")
    _ => fail("no chat under the service")
  }
}

///|
/// The ripples drawn over (x, y) (@motion.ripple's discs: black, faint).
fn ripples_at(t : @ui.Tester, x : Double, y : Double) -> Int {
  t
  .drawn_shadows()
  .filter(fn(s) {
    let (sx, sy, sw, sh, _, _, color) = s
    (color & 0xFFFFFF00L) == 0L &&
    (color & 0xFFL) <= (@motion.ripple_ink & 0xFFL) &&
    sx <= x &&
    x <= sx + sw &&
    sy <= y &&
    y <= sy + sh
  })
  .length()
}

///|
test "a chat the search found, pressed: rippled (Search.kt: ChatRowBody's clickable)" {
  let t = search_tester()
  t.type_text("签名")
  // (the search's row, drawn over Home's, faded away under it)
  let (x, y) = t.find_last("签名证书续期").unwrap()
  assert_eq(ripples_at(t, x, y), 0)
  t.press_at(x, y)
  t.run_for(@ui.tap_indication_ms + 100.0)
  assert_true(ripples_at(t, x, y) > 0)
  t.release(x, y)
  assert_eq(app.nav.depth(), 2)
}
