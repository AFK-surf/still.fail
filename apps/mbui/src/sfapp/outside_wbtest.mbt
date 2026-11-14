// What a draft refers to, shared before it goes (outside.mbt): over the fake core of composer_wbtest.mbt, whose calls
// the test answers, and over the fixture (its 个人 workspace's chats, chat_fixture.mbt fix_outside).

///|
/// On the frames' clock to where the sharing sheet rests, risen or sunk away: a Move as long as its height makes it
/// (@sf.panel_nodes' sheet), over by the longest a Move is.
fn run_to_outside_rest(t : @ui.Tester) -> Unit {
  t.run_for(@ui.move_most_ms)
}

///|
/// Another workspace's chat as the core's `chat.outsideRefs` names it.
fn outside_chat(id : String, title : String, may : Bool) -> Json {
  {
    "station": "ws2/st9",
    "id": Json::string(id),
    "title": Json::string(title),
    "workspace": "ws2",
    "workspaceName": "个人",
    "may": Json::boolean(may),
  }
}

///|
test "words with no reference go at once: the core is not asked what they refer to" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("没有引用的话")
  tap_send(t)
  assert_eq(named(calls, "chat.outsideRefs").length(), 0)
  assert_eq(named(calls, "chat.send").length(), 1)
  t.run_for(flight_wait_ms + @ui.move_most_ms)
  // (its row under way: said so once it has been a while, sfpages chat_rows.mbt)
  t.run_for(@sfpages.sending_shows_ms)
  t.assert_idle()
}

///|
test "a reference to another workspace's chat: asked first, the sheet says whose, 分享并发送 shares it, then it goes" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("先看 @[季度路线图] 再定")
  tap_send(t)
  // nothing sent yet: the core asked what the words refer to, a second tap meanwhile nothing more
  tap_send(t)
  let asked = named(calls, "chat.outsideRefs")
  assert_eq(asked.length(), 1)
  assert_eq(text(Some(asked[0].params), "text"), "先看 @[季度路线图] 再定")
  assert_eq(text(Some(asked[0].params), "station"), "ws1/st1")
  assert_eq(named(calls, "chat.send").length(), 0)
  (asked[0].done)(Ok({ "chats": [outside_chat("s-p1", "季度路线图", true)] }))
  t.draw()
  run_to_outside_rest(t)
  assert_true(t.find("分享对话") is Some(_))
  assert_true(t.find("季度路线图") is Some(_))
  // whose: 来自, then that workspace's mark (its letter, 个, where it has none) and its name
  assert_true(t.find("来自 ") is Some(_) && t.find("个") is Some(_) && t.find("个人") is Some(_))
  assert_true(t.find("你没有分享权限，需由发起人或管理员分享") is None)
  t.tap_text("分享并发送")
  // (which of them the viewer may share, and with which workspace, the core's: chat.outsideShare)
  let shared = named(calls, "chat.outsideShare")
  assert_eq(shared.length(), 1)
  let p = Some(shared[0].params)
  assert_eq(text(p, "station"), "ws1/st1")
  assert_eq(text(p, "text"), "先看 @[季度路线图] 再定")
  // not sent until it is shared
  assert_eq(named(calls, "chat.send").length(), 0)
  (shared[0].done)(Ok(Json::object({})))
  t.draw()
  let sent = named(calls, "chat.send")
  assert_eq(sent.length(), 1)
  assert_eq(text(Some(sent[0].params), "text"), "先看 @[季度路线图] 再定")
  let (_, words, _, _) = t.ime()
  assert_eq(words, "")
  // the sheet sinks away, the words wait for their row (which this core never gives), the composer's room let go
  run_to_outside_rest(t)
  assert_true(t.find("分享对话") is None)
  t.run_for(flight_wait_ms + @ui.move_most_ms)
  // (its row under way: said so once it has been a while, sfpages chat_rows.mbt)
  t.run_for(@sfpages.sending_shows_ms)
  t.assert_idle()
}

///|
test "a share that fails is said in the sheet: nothing goes, the words stay; 取消 leaves them as they were" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("对照 @[季度路线图]")
  tap_send(t)
  (named(calls, "chat.outsideRefs")[0].done)(Ok({ "chats": [outside_chat("s-p1", "季度路线图", true)] }))
  t.draw()
  run_to_outside_rest(t)
  t.tap_text("分享并发送")
  (named(calls, "chat.outsideShare")[0].done)(Err({ "code": "forbidden", "message": "对方工作区不接受" }))
  t.draw()
  assert_true(t.find("分享失败：对方工作区不接受") is Some(_))
  assert_eq(named(calls, "chat.send").length(), 0)
  t.tap_text("取消")
  run_to_outside_rest(t)
  assert_true(t.find("分享对话") is None)
  assert_eq(named(calls, "chat.send").length(), 0)
  let (_, words, _, _) = t.ime()
  assert_eq(words, "对照 @[季度路线图]")
  // sent again: asked again
  tap_send(t)
  assert_eq(named(calls, "chat.outsideRefs").length(), 2)
  // the last tap's ripple shown whole, its way in and out
  t.run_for(@motion.ripple_tap_ms)
  t.assert_idle()
}

///|
test "none of them the viewer may share: each says so, and 仍然发送 sends it as it is" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("参考 @[预算草稿]")
  tap_send(t)
  (named(calls, "chat.outsideRefs")[0].done)(Ok({ "chats": [outside_chat("s-p2", "预算草稿", false)] }))
  t.draw()
  run_to_outside_rest(t)
  assert_true(t.find("你没有分享权限，需由发起人或管理员分享") is Some(_))
  assert_true(t.find("分享并发送") is None)
  t.tap_text("仍然发送")
  assert_eq(named(calls, "chat.outsideShare").length(), 0)
  assert_eq(named(calls, "chat.send").length(), 1)
  run_to_outside_rest(t)
  t.run_for(flight_wait_ms + @ui.move_most_ms)
  // (its row under way: said so once it has been a while, sfpages chat_rows.mbt)
  t.run_for(@sfpages.sending_shows_ms)
  t.assert_idle()
}

///|
test "a core that cannot say what the words refer to: they go as they are" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("看 @[季度路线图]")
  tap_send(t)
  (named(calls, "chat.outsideRefs")[0].done)(Err({ "code": "unknown_call", "message": "chat.outsideRefs" }))
  t.draw()
  assert_eq(named(calls, "chat.send").length(), 1)
  assert_true(t.find("分享对话") is None)
  t.run_for(flight_wait_ms + @ui.move_most_ms)
  // (its row under way: said so once it has been a while, sfpages chat_rows.mbt)
  t.run_for(@sfpages.sending_shows_ms)
  t.assert_idle()
}

///|
test "a new chat's first message is shared before it goes too, over the fixture's core" {
  let t = tester("home")
  let (_, y) = bar_places_at()
  t.tap(195.0, y - 28.0 - 4.0)
  t.run_for(@ui.move_most_ms)
  t.tap_text("做任何事")
  t.type_text("按 @[季度路线图] 排一下")
  tap_send(t)
  // asked first: the page is still the new chat, the sheet over it
  assert_true(!(app.nav.top() is Chat(_)))
  run_to_outside_rest(t)
  // whose: 来自, then that workspace's mark (its letter, 个, where it has none) and its name
  assert_true(t.find("来自 ") is Some(_) && t.find("个") is Some(_) && t.find("个人") is Some(_))
  t.tap_text("分享并发送")
  match app.nav.top() {
    Chat(r) => assert_eq(r.session, "new:1")
    _ => fail("not the chat")
  }
  assert_true(fix_xshared.contains("s-p1"))
}

///|
test "references the core says nothing of: the words go with no sheet" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("同一个工作区的 @[发布清单]")
  tap_send(t)
  (named(calls, "chat.outsideRefs")[0].done)(Ok({ "chats": [] }))
  t.draw()
  assert_eq(named(calls, "chat.send").length(), 1)
  assert_true(t.find("分享对话") is None)
  t.run_for(flight_wait_ms + @ui.move_most_ms)
  // (its row under way: said so once it has been a while, sfpages chat_rows.mbt)
  t.run_for(@sfpages.sending_shows_ms)
  t.assert_idle()
}

// With keyboard and mouse, and on a wide window (a dialog in the middle there): Enter again says yes, Escape and a
// press outside are 取消; where its words stand on each screen.

///|
/// A chat of another workspace as the core's `chat.outsideRefs` says it: `title`, its workspace `name` (its mark
/// `emoji`, "" its letter), whether the viewer may share it.
fn outside_chat_of(title : String, name : String, emoji : String, may : Bool) -> Json {
  {
    "station": "ws2/st9",
    "id": Json::string("s-" + title),
    "title": Json::string(title),
    "workspace": "ws2",
    "workspaceName": Json::string(name),
    "workspaceEmoji": Json::string(emoji),
    "workspaceIcon": "",
    "may": Json::boolean(may),
  }
}

///|
/// Words with a mark written in the fixture's chat and sent, the core answering that they refer to `chats` of other
/// workspaces: the asking up, come to rest.
fn outside_asked(
  calls : Array[Made],
  chats : Array[Json],
  platform? : Int = 2,
  wide? : Bool = false,
  rest? : Bool = true,
) -> @ui.Tester {
  let t = fake_core(calls, platform~)
  if wide {
    t.resize(1200.0, 800.0)
    t.run_for(@ui.move_most_ms)
  }
  t.tap_text("发消息")
  t.type_text("@[首页] 吧")
  t.draw()
  t.draw()
  tap_send(t)
  let asked = named(calls, "chat.outsideRefs")
  guard asked.length() == 1 else { @halt.saying("the core asked \{asked.length()} times") }
  (asked[0].done)(Ok({ "chats": Json::array(chats) }))
  t.draw()
  t.frame()
  if rest {
    t.run_for(@ui.move_most_ms)
  }
  t
}

///|
/// The two chats most of these ask about: one the viewer may share, of a workspace with no mark; one they may not, of
/// one with an emoji.
fn outside_two() -> Array[Json] {
  [outside_chat_of("季度路线图", "个人", "", true), outside_chat_of("发布检查", "开源", "🌲", false)]
}

///|
test "分享对话: which chats and whose, the one that cannot be shared saying so; 分享并发送 shares, then sends" {
  let calls : Array[Made] = []
  let t = outside_asked(calls, outside_two())
  assert_true(t.find("分享对话") is Some(_))
  assert_true(t.find("发送后，此 workspace 中的 agent 可读取以下内容（连续 6 小时未使用即失效）：") is Some(_))
  assert_true(t.find("季度路线图") is Some(_))
  assert_true(t.find("发布检查") is Some(_))
  assert_true(t.find("你没有分享权限，需由发起人或管理员分享") is Some(_))
  // nothing sent while it asks
  assert_eq(named(calls, "chat.send").length(), 0)
  t.tap_text("分享并发送")
  t.draw()
  let shared = named(calls, "chat.outsideShare")
  assert_eq(shared.length(), 1)
  assert_eq(text(Some(shared[0].params), "station"), "ws1/st1")
  assert_eq(text(Some(shared[0].params), "text"), "@[首页] 吧")
  assert_eq(named(calls, "chat.send").length(), 0)
  // pressed again while it shares: asked once
  t.tap_text("分享并发送")
  t.draw()
  assert_eq(named(calls, "chat.outsideShare").length(), 1)
  (shared[0].done)(Ok(Json::object({})))
  t.draw()
  t.draw()
  assert_eq(named(calls, "chat.send").length(), 1)
  assert_eq(text(Some(named(calls, "chat.send")[0].params), "text"), "@[首页] 吧")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("分享对话") is None)
}

///|
test "分享对话 with keyboard and mouse on a small window: Enter says yes, once" {
  let calls : Array[Made] = []
  let t = outside_asked(calls, outside_two(), platform=0)
  assert_true(t.find("分享对话") is Some(_))
  t.enter()
  t.draw()
  assert_eq(named(calls, "chat.outsideShare").length(), 1)
  assert_eq(named(calls, "chat.send").length(), 0)
  // (Enter again while it shares: asked once)
  t.enter()
  t.draw()
  assert_eq(named(calls, "chat.outsideShare").length(), 1)
  (named(calls, "chat.outsideShare")[0].done)(Ok(Json::object({})))
  t.draw()
  t.draw()
  assert_eq(named(calls, "chat.send").length(), 1)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("分享对话") is None)
}

///|
test "分享对话 with keyboard and mouse: Escape is 取消" {
  let calls : Array[Made] = []
  let t = outside_asked(calls, outside_two(), platform=0)
  t.key(@ui.key_escape)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("分享对话") is None)
  assert_eq(named(calls, "chat.outsideShare").length(), 0)
  assert_eq(named(calls, "chat.send").length(), 0)
  let (_, words, _, _) = t.ime()
  assert_eq(words, "@[首页] 吧")
}

///|
test "分享对话 on a wide window: a dialog in the middle; Enter says yes, once" {
  let calls : Array[Made] = []
  let t = outside_asked(calls, outside_two(), platform=0, wide=true)
  // in the middle of the window: its title neither at its foot nor at its side
  let (x, y, _, _) = t.rect_of("分享对话").unwrap()
  assert_true(x > 200.0 && x < 800.0 && y > 150.0 && y < 500.0, msg="its title at \{x},\{y}")
  t.enter()
  t.draw()
  assert_eq(named(calls, "chat.outsideShare").length(), 1)
  assert_eq(named(calls, "chat.send").length(), 0)
  t.enter()
  t.draw()
  assert_eq(named(calls, "chat.outsideShare").length(), 1)
  (named(calls, "chat.outsideShare")[0].done)(Ok(Json::object({})))
  t.draw()
  t.draw()
  assert_eq(named(calls, "chat.send").length(), 1)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("分享对话") is None)
}

///|
test "分享对话: the focus on 分享并发送 as it opens in the middle of a wide window, never on it on a sheet (by touch or with keyboard and mouse)" {
  for screen in [(2, false), (0, false), (0, true)] {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let calls : Array[Made] = []
    let t = outside_asked(calls, outside_two(), platform~, wide~)
    let said = t.focus_said()
    if wide {
      assert_true(said.contains("分享并发送"), msg="\{at}: \{said}")
    } else {
      assert_true(!said.contains("分享并发送"), msg="\{at}: \{said}")
    }
  }
}

///|
test "分享对话 on a wide window: 取消, Escape and a press outside it send nothing" {
  let calls : Array[Made] = []
  let t = outside_asked(calls, outside_two(), platform=0, wide=true)
  t.tap_text("取消")
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("分享对话") is None)
  let calls2 : Array[Made] = []
  let t = outside_asked(calls2, outside_two(), platform=0, wide=true)
  t.key(@ui.key_escape)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("分享对话") is None)
  let calls3 : Array[Made] = []
  let t = outside_asked(calls3, outside_two(), platform=0, wide=true)
  t.tap(20.0, 780.0)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("分享对话") is None)
  for c in [calls, calls2, calls3] {
    assert_eq(named(c, "chat.outsideShare").length(), 0)
    assert_eq(named(c, "chat.send").length(), 0)
  }
}

///|
/// Where the first of the words `words` is drawn: its left, top, width and height.
fn outside_word(t : @ui.Tester, words : String) -> (Double, Double, Double, Double) {
  match t.words().iter().find_first(fn(w) { w.0 == words }) {
    Some(w) => (w.1, w.2, w.3, w.4)
    None => @halt.saying("\{words} is not drawn")
  }
}

///|
test "分享对话: a chat and whose it is on one line, why it cannot be shared in what is left of that line; its buttons" {
  // (touch on a small window, a sheet; keyboard and mouse there, a sheet too; a wide window, a dialog in its middle)
  for screen in [(2, false), (0, false), (0, true)] {
    let calls : Array[Made] = []
    let t = outside_asked(calls, outside_two(), platform=screen.0, wide=screen.1)
    let about = "platform \{screen.0}, wide \{screen.1}"
    let mid = fn(r : (Double, Double, Double, Double)) { r.1 + r.3 / 2.0 }
    let lead = outside_word(t, "发送后，此 workspace 中的 agent 可读取以下内容（连续 6 小时未使用即失效）：")
    // whose each is: 来自, the workspace's mark (its letter where it has none, its emoji), its name
    // (its letter the one on its name's line: a wide window's rail draws the workspace in view's too)
    let name = outside_word(t, "个人")
    let letter = t.words().iter().find_first(fn(w) { w.0 == "个" && (w.2 + w.4 / 2.0 - mid(name)).abs() < 1.0 })
    assert_true(letter is Some(w) && w.1 + w.3 <= name.0, msg="\{about}: 个 \{Repr(letter)}, 个人 \{Repr(name)}")
    let (emoji, open) = (outside_word(t, "🌲"), outside_word(t, "开源"))
    // (an emoji on the baseline its line's face gives it: within a point or two of the words' middle)
    assert_true(emoji.0 + emoji.2 <= open.0 && (mid(emoji) - mid(open)).abs() < 2.0, msg="\{about}: 🌲 \{Repr(emoji)}, 开源 \{Repr(open)}")
    // the one that cannot be shared: its title, whose it is and why not on one line, why not after them out to
    // where the panel's words end
    let title = outside_word(t, "发布检查")
    let no = outside_word(t, "你没有分享权限，需由发起人或管理员分享")
    assert_true((mid(title) - mid(open)).abs() < 1.0 && (mid(title) - mid(no)).abs() < 1.0, msg="\{about}: \{Repr(title)}, \{Repr(open)}, \{Repr(no)}")
    assert_true(no.0 > open.0 + open.2, msg="\{about}: \{Repr(open)}, \{Repr(no)}")
    assert_true((no.0 + no.2 - (lead.0 + lead.2)).abs() < 1.0, msg="\{about}: \{Repr(no)}, the lead \{Repr(lead)}")
    // 取消 before 分享并发送: across a sheet, a half each; at a dialog's end
    let (cancel, yes) = (outside_word(t, "取消"), outside_word(t, "分享并发送"))
    let half = lead.0 + lead.2 / 2.0
    assert_true((mid(cancel) - mid(yes)).abs() < 1.0, msg="\{about}: \{Repr(cancel)}, \{Repr(yes)}")
    if screen.1 {
      assert_true(cancel.0 > half && cancel.0 + cancel.2 < yes.0, msg="\{about}: \{Repr(cancel)}, \{Repr(yes)}")
    } else {
      assert_true(cancel.0 + cancel.2 < half && yes.0 > half, msg="\{about}: \{Repr(cancel)}, \{Repr(yes)}")
    }
  }
}

///|
test "分享对话 on a sheet by touch: 分享并发送, drawn less tall than a press's room, is pressed from 3 over it and 3 under it" {
  // (the window's tree reaching what is drawn smaller than its room from round it, as an old view's hit test does:
  // mbui's view/reach.mbt)
  for dy in [-3.0, 3.0] {
    let calls : Array[Made] = []
    let t = outside_asked(calls, outside_two())
    let (x, y, w, h) = t.get(Button, label="分享并发送").rect
    assert_true(h < @ui.room_least(), msg="drawn \{h} tall")
    t.tap(x + w / 2.0, if dy < 0.0 { y + dy } else { y + h + dy })
    t.draw()
    assert_eq(named(calls, "chat.outsideShare").length(), 1, msg="\{dy} from it: \{Repr((x, y, w, h))}")
  }
}
