///|
test "a chat header's station disappears and returns while its agent tile is retained" {
  for agents in [true, false] {
    for width in [740.0, 1100.0] {
      let present = Ref(true)
      let epoch = @signals.signal(0)
      let t = edited_core([], "chat", fn(name, value) {
        if name == "stations" && !present.val { Json::array([]) }
        else if name == "chat" && !agents { with_fields(value, [("agents", [])]) }
        else { value }
      }, epoch~, platform=0)
      t.resize(width, 760.0)
      t.run_for(@ui.move_most_ms)
      let title = t.find("整理发布清单")
      assert_true(title is Some(_))
      // A core answer can come between frames, with the host clock ahead of the last frame's.
      t.advance(between_frames_ms)
      present.val = false
      epoch.set(epoch.get() + 1)
      t.frame()
      assert_true(t.find("整理发布清单") is Some(_))
      t.advance(between_frames_ms)
      present.val = true
      epoch.set(epoch.get() + 1)
      t.frame()
      assert_true(t.find("整理发布清单") is Some(_))
    }
  }
}

///|
test "the chat bar keeps its title node when the core renames the chat, and its info action still opens its chat" {
  let title = Ref("整理发布清单")
  let epoch = @signals.signal(0)
  let t = edited_core([], "chat", fn(name, value) {
    if name == "chat" { with_fields(value, [("title", Json::string(title.val))]) } else { value }
  }, epoch~)
  let tree = @ui.view_tree().unwrap()
  let first = tree.drawn().filter(fn(n) { n.words == title.val })
  assert_eq(first.length(), 1, msg="the bar's title is a node of the page")
  assert_true(tree.drawn().filter(fn(n) { n.y < chat_bar_h && (n.words == "你" || n.words == "A") }).is_empty(),
    msg="the people leave before the title is shortened, as in the bar before it moved to the tree")
  let id = first[0].id
  title.val = "再核对一次发布说明"
  epoch.set(epoch.get() + 1)
  t.frame()
  let renamed = tree.drawn().filter(fn(n) { n.words == title.val })
  assert_eq(renamed.length(), 1)
  assert_true(renamed[0].id == id, msg="the same title, with the core's new words")
  t.click(Button, label=tr("android-chat.info.title"))
  t.run_for(@kit.presence_in_ms + @ui.move_most_ms)
  assert_true(t.find("图片、文件和链接") is Some(_), msg="the chat's information")
}

///|
test "a chat's bar on the tape and across the wide pane keeps its title and find field as the chat changes" {
  for width in [740.0, 1280.0] {
    let title = Ref("整理发布清单")
    let epoch = @signals.signal(0)
    let t = edited_core([], "chat", fn(name, value) {
      if name == "chat" { with_fields(value, [("title", Json::string(title.val))]) } else { value }
    }, epoch~, platform=0)
    t.resize(width, 844.0)
    t.run_for(@ui.move_most_ms)
    let tree = @ui.view_tree().unwrap()
    let first = tree.drawn().filter(fn(n) { n.words == title.val && n.x > 300.0 && n.y < 80.0 })
    assert_eq(first.length(), 1, msg="a retained header at \{width}")
    let id = first[0].id
    title.val = "再核对一次发布说明"
    epoch.set(epoch.get() + 1)
    t.frame()
    let renamed = tree.drawn().filter(fn(n) { n.words == title.val && n.x > 300.0 && n.y < 80.0 })
    assert_eq(renamed.length(), 1)
    assert_true(renamed[0].id == id)
    // The tape's page may be beside the sidebar after resizing: bring it into use before typing its shortcut.
    t.tap(renamed[0].x + 8.0, renamed[0].y + 8.0)
    t.run_for(@ui.move_most_ms)
    t.key(@ui.key_of_char('f'), mods=@ui.mod_cmd)
    t.frame()
    assert_true(t.query(TextField, label="在对话中查找") is Some(_), msg="find at \{width}: \{@sfpages.find_chat()}")
    t.type_text("截图")
    t.frame()
    assert_eq(@sfpages.find_query(), "截图")
    t.key(@ui.key_escape)
    t.frame()
    assert_eq(@sfpages.find_chat(), "")
    t.click(Button, label="对话信息")
    t.run_for(@kit.pop_ms + @ui.move_most_ms)
    assert_true(t.find("图片、文件和链接") is Some(_))
    t.key(@ui.key_escape)
    t.run_for(@kit.pop_out_ms)
    assert_true(t.find("图片、文件和链接") is None)
  }
}
