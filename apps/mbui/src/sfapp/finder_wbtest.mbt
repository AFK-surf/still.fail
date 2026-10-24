// The search, one in every tier (sfpages' switcher.mbt): at a width of each tier with a finger and with a mouse, the
// same words find the same; with a finger its page in the lists' box (sfpages' search.mbt), from the field at a list's
// top; with a mouse ⌘K: laid out Medium or Large its panel (sfdesk's switcher.mbt), Small the same page as a finger's,
// over the page open. A row pressed opens its chat where the shell has it: ⌘K's panel closes as it does, the search's
// page stays open in the lists' box.

///|
/// The fixture's Home at width `w` with `platform`'s hand, the search opened as its frame has it, `words` typed.
fn finder_tester(w : Double, platform : Int, regular : Bool, words : String) -> @ui.Tester raise {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w~, h=900.0, platform~)
  if regular {
    let log = t.drive("system {\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"}}\n")
    assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  }
  t.draw()
  if platform == 2 {
    // a finger's: the field at the list's top, in every tier
    t.scroll_to(0)
    t.draw()
    tap_search_field(t)
    t.run_for(@sfpages.search_in_ms)
  } else {
    // a mouse's: ⌘K, in every tier
    t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
    t.frame()
  }
  t.type_text(words)
  t.frame()
  t
}

///|
test "the search at each width and with either hand: the same words find the same chats and messages" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = finder_tester(w, platform, regular, "签名")
    let at = "\{w} platform \{platform}"
    assert_eq(@sfpages.finder_query(), "签名", msg=at)
    // (drawn over the list, the search's own: the last of the words)
    assert_true(t.find_last("签名证书续期") is Some(_), msg="\{at}: \{t.words().map(fn(x) { x.0 }).join("|")}")
    assert_true(t.find("消息") is Some(_), msg=at)
  }
}

///|
test "a chat the search found, pressed: its chat; ⌘K closed as it opens, the phone's page left under it" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = finder_tester(w, platform, regular, "签名")
    let at = "\{w} platform \{platform}"
    let wide = @sfdesk.is_wide(t.ctx())
    guard t.find_last("签名证书续期") is Some((x, y)) else {
      fail("\{at}: not found: \{t.words().map(fn(x) { x.0 }).join("|")}")
    }
    t.tap(x, y)
    t.run_for(@ui.nav_push_ms)
    assert_true(app.nav.top() is Chat(_), msg=at)
    ignore(wide)
    if platform == 2 {
      assert_true(@sfpages.search_opened(), msg=at)
    } else {
      assert_false(@sfdesk.switcher_open(), msg=at)
    }
  }
}


///|
/// The search's field at a list's top pressed (the list's, the leftmost drawn: the search's own page not open yet).
fn tap_search_field(t : @ui.Tester) -> Unit raise {
  guard t.find("搜索全部内容") is Some((x, y)) else { fail("no search field: \{t.words().map(fn(w) { w.0 }).join("|")}") }
  t.tap(x, y)
}

///|
test "the search's way in by the hand: a finger's field at the lists' top in every tier, none with a mouse (⌘K's)" {
  for case in [(390.0, 2, false), (720.0, 2, false), (1280.0, 2, true), (390.0, 0, false), (720.0, 0, false), (1280.0, 0, false)] {
    let (w, platform, regular) = case
    let calls : Array[Made] = []
    let t = wide_tester(calls, w~, h=900.0, platform~)
    if regular {
      let log = t.drive("system {\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"}}\n")
      assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
    }
    t.draw()
    t.scroll_to(0)
    t.draw()
    let at = "\{w} platform \{platform}"
    if platform == 2 {
      assert_true(t.find("搜索全部内容") is Some(_), msg=at)
    } else {
      assert_true(t.find("搜索全部内容") is None, msg=at)
      t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
      t.frame()
      // laid out Small the search's page, else the panel
      let wide = @sfdesk.is_wide(t.ctx())
      assert_eq(@sfdesk.switcher_open(), wide, msg=at)
      assert_eq(@sfpages.search_opened(), !wide, msg=at)
    }
  }
}

///|
test "a finger's search on a wide frame: in the lists' column; a row pressed, its chat beside it, the search still there" {
  let t = finder_tester(1280.0, 2, true, "签名")
  // the results in the sidebar's column, left of the page
  let (x, _) = t.find_last("签名证书续期").unwrap()
  assert_true(x < 400.0, msg=x.to_string())
  assert_true(t.find("取消") is Some(_))
  let (x, y) = t.find_last("签名证书续期").unwrap()
  t.tap(x, y)
  t.run_for(@ui.nav_push_ms)
  assert_true(app.nav.top() is Chat(_))
  assert_true(@sfpages.search_opened())
  assert_true(t.find("取消") is Some(_))
}

///|
/// The fixture's Home in a desktop's window 390 wide (laid out Small, pointed at with a mouse).
fn small_mouse(calls : Array[Made]) -> @ui.Tester {
  let t = wide_tester(calls, w=390.0, h=844.0, platform=0)
  t.draw()
  t
}

///|
test "small with a mouse, ⌘K: the search's page in the lists' box, the keys in its field; Enter opens the line chosen, Esc closes it" {
  let calls : Array[Made] = []
  let t = small_mouse(calls)
  assert_false(@sfdesk.is_wide(t.ctx()))
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  t.frame()
  assert_true(@sfpages.search_opened())
  assert_false(@sfdesk.switcher_open())
  // what can be done here among what it finds: 设置 with its keys, Enter runs it
  t.type_text("设置")
  t.frame()
  assert_true(t.find("⌘,") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  t.enter()
  t.frame()
  assert_true(app.nav.top() is Setting(_))
  // a chat found: Enter opens it
  let t = small_mouse(calls)
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  t.frame()
  t.type_text("签名")
  t.frame()
  assert_true(t.find_last("签名证书续期") is Some(_))
  // Enter: the line chosen (the first) opened
  t.enter()
  t.frame()
  t.run_for(@ui.nav_push_ms)
  assert_true(app.nav.top() is Chat(_))
  // Esc on Home's: closed, the lists as they were
  let t = small_mouse(calls)
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  t.frame()
  assert_true(@sfpages.search_opened())
  t.key(@ui.key_escape)
  t.frame()
  assert_false(@sfpages.search_opened())
  assert_true(app.nav.top() == Home)
  assert_true(t.find("整理发布清单") is Some(_))
}

///|
test "small with a mouse, ⌘K in a chat: the search's page over it; Esc back to that chat, a row found its chat instead" {
  let calls : Array[Made] = []
  let t = small_mouse(calls)
  t.tap_text("夜里的构建又失败了")
  t.run_for(@ui.nav_push_ms)
  assert_eq(app.nav.depth(), 2)
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  t.frame()
  assert_true(@sfpages.search_opened())
  t.type_text("签名")
  t.frame()
  assert_true(t.find_last("签名证书续期") is Some(_))
  // Esc: closed, the chat under it as it was
  t.key(@ui.key_escape)
  t.frame()
  assert_false(@sfpages.search_opened())
  assert_eq(app.nav.depth(), 2)
  assert_true(app.nav.top() is Chat({ title: "夜里的构建又失败了", .. }))
  // again, a row pressed: its chat over this one, the search gone
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  t.frame()
  t.type_text("签名")
  t.frame()
  let (x, y) = t.find_last("签名证书续期").unwrap()
  t.tap(x, y)
  t.run_for(@ui.nav_push_ms)
  assert_false(@sfpages.search_opened())
  assert_true(app.nav.top() is Chat({ title: "签名证书续期", .. }))
}

///|
test "small with a mouse, the app's keys: ⌘N a new chat; ⌘, settings; ⌘/ the shortcuts" {
  let calls : Array[Made] = []
  // ⌘N: a new chat, risen on the stack
  let t = small_mouse(calls)
  t.key(@ui.key_of_char('n'), mods=@ui.mod_cmd)
  t.frame()
  assert_true(app.nav.top() == NewChat)
  // ⌘,: settings
  let t = small_mouse(calls)
  t.key(@ui.key_of_char(','), mods=@ui.mod_cmd)
  t.frame()
  assert_true(app.nav.top() is Setting(_))
  // ⌘/: the shortcuts
  let t = small_mouse(calls)
  t.key(@ui.key_of_char('/'), mods=@ui.mod_cmd)
  t.frame()
  assert_true(@sfdesk.wide.keys_open)
}

///|
test "⌘K laid out Medium and Large: its panel, room round it on every side" {
  for w in [600.0, 1280.0] {
    let calls : Array[Made] = []
    let t = wide_tester(calls, w~, h=800.0, platform=0)
    t.draw()
    assert_true(@sfdesk.is_wide(t.ctx()), msg=w.to_string())
    t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
    t.frame()
    assert_true(@sfdesk.switcher_open(), msg=w.to_string())
    assert_false(@sfpages.search_opened(), msg=w.to_string())
    let c = t.ctx()
    let (x, y, pw, _) = c.rect_of(c.id("switcher")).unwrap()
    assert_true(x >= 16.0 && x + pw <= w - 16.0 && y > 0.0, msg="\{w}: \{x} \{pw}")
  }
}

///|
test "small with a mouse: back (⌘[, the Mac's host's own back) goes back one page only, the app's keys taking none of it" {
  let calls : Array[Made] = []
  let t = small_mouse(calls)
  t.tap_text("夜里的构建又失败了")
  t.run_for(@ui.nav_push_ms)
  assert_eq(app.nav.depth(), 2)
  // (⌘[ is the host's back, mac_app.m go_back: as the system's back reaches the app)
  t.key(@ui.key_of_char('['), mods=@ui.mod_cmd)
  t.frame()
  assert_eq(app.nav.depth(), 2)
  t.back()
  t.frame()
  t.run_for(@ui.nav_push_ms)
  assert_eq(app.nav.depth(), 1)
}
