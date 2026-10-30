// The chats' lists, one in every tier (sfpages' sidebar.mbt, chat_row.mbt): at a width of each tier with a finger and
// with a mouse, the same lists and rows; a finger's the phone's (66 high, held for its menu, swiped to archive), a
// mouse's the web's desktop's (54 high, 2 apart, pointed at for its 归档, right clicked for its menu). And where the
// shell opens a chat pressed in them, on the wide frame: in the page pane in place of what was there.

///|
/// The fixture's Home at width `w` with `platform`'s hand (a size class said where `regular`), its calls kept.
fn lists_tester(calls : Array[Made], w : Double, platform : Int, regular : Bool) -> @ui.Tester raise {
  let t = wide_tester(calls, w~, h=900.0, platform~)
  if regular {
    let log = t.drive("system {\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"}}\n")
    assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  }
  t.draw()
  t
}

///|
test "the chats' lists at each width and with either hand: its days and rows; a finger's 66 high, a mouse's 54, 2 apart but a finger's across a phone" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let calls : Array[Made] = []
    let t = lists_tester(calls, w, platform, regular)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("今天") is Some(_), msg=at)
    let (_, y1) = t.find("整理发布清单").unwrap()
    let (_, y2) = t.find("首页的列表改成按天分组").unwrap()
    // (in a side column 2 apart with either hand, @sf.list_more; across a phone's screen a finger's flush)
    let step = if platform != 2 { 56.0 } else if regular { @sfpages.touch_row_h + 2.0 } else { @sfpages.touch_row_h }
    assert_true((y2 - y1 - step).abs() < 0.5, msg="\{at}: \{y2 - y1}")
    // the last thing said, who said it at the line's end, in every tier
    assert_true(t.find("正在核对第三项：安装包的签名") is Some(_), msg=at)
  }
}

///|
test "a row's menu at each width and with either hand: held by a finger, right clicked by a mouse; the same items" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let calls : Array[Made] = []
    let t = lists_tester(calls, w, platform, regular)
    let at = "\{w} platform \{platform}"
    let (x, y) = t.find("夜里的构建又失败了").unwrap()
    if platform == 2 {
      t.press_at(x, y)
      t.run_for(@ui.tap_indication_ms + @sfpages.hold_ms)
      t.release(x, y)
    } else {
      t.right_click(x, y)
    }
    t.frame()
    // not opened by the hold
    assert_false(app.nav.top() is Chat({ title: "夜里的构建又失败了", .. }), msg=at)
    for item in ["重命名", "复制会话链接", "复制 session 文件路径"] {
      assert_true(t.find(item) is Some(_), msg="\{at}: \{item}")
    }
    t.tap_text("复制会话链接")
    assert_true(t.clipboard().has_prefix("[夜里的构建又失败了]("), msg=at)
  }
}

///|
/// How many rows of the list are on a ground of the chat in view (theme's `selected`, at any share): lit.
fn lit_rows(t : @ui.Tester) -> Int {
  let selected = @sf.theme().p.selected & 0xFFFFFF00L
  t
  .boxes()
  .filter(fn(b) {
    b.h == @sfpages.touch_row_h && (b.bg & 0xFFL) != 0L && (b.bg & 0xFFFFFF00L) == selected
  })
  .length()
}

///|
test "a finger's rows gone back from one after another: only the last stays lit, while the chat opened between is in view or after" {
  // (back to the list, the other row pressed while the first is still lit; that chat in view a while, or long)
  for stay in [@ui.move_most_ms, 3000.0] {
    let calls : Array[Made] = []
    let t = lists_tester(calls, 390.0, 2, false)
    let at = "in view \{stay}"
    t.tap_text("夜里的构建又失败了")
    t.run_for(@ui.move_most_ms)
    t.back()
    t.run_for(@ui.move_most_ms)
    assert_eq(lit_rows(t), 1, msg=at)
    t.tap_text("首页的列表改成按天分组")
    t.run_for(stay)
    assert_eq(open_title(), "首页的列表改成按天分组", msg=at)
    t.back()
    t.run_for(@ui.move_most_ms)
    assert_eq(lit_rows(t), 1, msg=at)
    t.run_for(@sfpages.left_lit_ms + @sfpages.left_fade_ms)
    assert_eq(lit_rows(t), 0, msg=at)
  }
}

///|
test "a mouse pointing at a row: its time and 归档 at its top right; a finger's row with nothing left in it has no 归档 of its own" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let calls : Array[Made] = []
    let t = lists_tester(calls, w, platform, regular)
    let at = "\{w} platform \{platform}"
    t.scroll_to(12)
    t.draw()
    if platform == 2 {
      // (swiped left, or held for its menu's)
      assert_true(t.query(Button, label="归档「把旧的截图都换成新的」") is None, msg=at)
    } else {
      assert_true(t.query(Button, label="归档「夜里的构建又失败了」") is None, msg=at)
      let (x, y) = t.find("夜里的构建又失败了").unwrap()
      t.move(x, y)
      t.frame()
      match t.query(Button, label="归档「夜里的构建又失败了」") {
        Some(b) => {
          let (bx, by, bw, bh) = b.rect
          t.tap(bx + bw / 2.0, by + bh / 2.0)
          assert_eq(named(calls, "chat.archive").length(), 1, msg=at)
        }
        None => fail("\{at}: no 归档 on the row pointed at")
      }
    }
  }
}

///|
test "a row pinned, renamed or archived: no spinner while its station answers (the core has it so at once); failed, its red mark" {
  for case in one_page_cases {
    let (w, platform, _, _) = case
    let at = "\{w} platform \{platform}"
    let on : Json = { "station": "ws1/st2", "session": "s-c3" }
    for stage in ["running", "rechecking", "failed"] {
      reset()
      let base = fixture("home")
      let doing = Json::array(
        ["chat.pin", "chat.rename", "chat.archive"].map(fn(call) {
          { "call": call, "params": on, "since": 0, "stage": stage, "error": "station 拒绝了" }
        }),
      )
      let src : Source = {
        ..base,
        topic: fn(name, params) {
          let got = (base.topic)(name, params)
          if name == "doing" {
            { ..got, value: Some({ "doing": doing }) }
          } else {
            got
          }
        },
      }
      let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h=900.0, platform~)
      t.draw()
      assert_true(t.find("夜里的构建又失败了") is Some(_), msg=at)
      assert_eq(t.locate("=" + @sf.t("common.saving")).length(), 0, msg="\{at} \{stage}")
      let failed = t.semantics().filter(fn(s) { s.label == "station 拒绝了" })
      assert_eq(failed.length(), if stage == "failed" { 1 } else { 0 }, msg="\{at} \{stage}")
    }
  }
}

///|
/// The chat in the page pane now, by its title ("" none).
fn open_title() -> String {
  match app.nav.top() {
    Chat(r) => r.title
    _ => ""
  }
}

///|
test "wide: rows pressed one after another, one chat open in place of the other; back from it to the list, not through them" {
  for w in [720.0, 1280.0] {
    let calls : Array[Made] = []
    let t = lists_tester(calls, w, 0, false)
    for title in ["夜里的构建又失败了", "首页的列表改成按天分组", "整理发布清单"] {
      @sfbase.open_page(Chat({ station: "", session: "", title: "", station_name: "" }))
      app.nav.pop() |> ignore
      t.draw()
      // (on the tape the rows are the sidebar's, pressed with it in use: the page the last one brought over sent back)
      if @sfdesk.wide.tape && @sfdesk.wide.tape_at.get() != @sfdesk.TapePane::Side {
        @sfdesk.wide.tape_ask.set(Some(@sfdesk.TapePane::Side))
        t.draw()
        t.run_for(@ui.move_most_ms)
      }
      t.tap_text(title)
      assert_eq(open_title(), title, msg="\{w}")
      assert_eq(app.nav.depth(), 2, msg="\{w}: \{title}")
    }
  }
}

///|
test "wide: a chat opened while settings are in view is opened in the chats; the chat open already, nothing changes" {
  let calls : Array[Made] = []
  let t = lists_tester(calls, 1280.0, 0, false)
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  app.nav.push(Settings)
  t.draw()
  assert_eq(@sfdesk.lit_place(), "settings")
  @sfbase.open_page(Chat(r))
  t.draw()
  assert_eq(@sfdesk.lit_place(), "chats")
  assert_true(app.nav.pages() == [Home, Chat(r)])
  // again: nothing
  @sfbase.open_page(Chat(r))
  assert_true(app.nav.pages() == [Home, Chat(r)])
  // from a search (⌘K's, a found message): the same rule
  @sfbase.open_chat_found({ ..r, session: "s-c2", title: "" }, 3.0, [])
  assert_eq(app.nav.depth(), 2)
  match app.nav.top() {
    Chat(o) => assert_eq(o.session, "s-c2")
    _ => fail("no chat open")
  }
}
