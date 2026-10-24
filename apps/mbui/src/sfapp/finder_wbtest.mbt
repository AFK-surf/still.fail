// The search, one in every tier (sfpages' switcher.mbt): at a width of each tier with a finger and with a mouse, the
// same words find the same; laid out Small its page over Home's list (search.mbt), wider ⌘K's panel (sfdesk's
// switcher.mbt). A row pressed opens its chat where the shell has it: ⌘K closes as it does, the phone's page stays
// under the chat.

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
  if @sfdesk.is_wide(t.ctx()) {
    // (⌘K's panel, as its key opens it: a tablet's finger has the same panel)
    @sfdesk.switcher_toggle(t.ctx())
    t.frame()
  } else {
    t.scroll_to(0)
    t.draw()
    t.tap_text("搜索全部内容")
    t.run_for(search_in_ms)
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
    if wide {
      assert_false(@sfdesk.switcher_open(), msg=at)
    } else {
      assert_true(search.open, msg=at)
    }
  }
}

