// An iPhone Duo's poses over the fixture's chat, as its host says them (@hostapi.system_channel `size_class`, `fold`,
// `bars`): its inner screen (890 x 626 points as it opens, the fold upright in its middle; 626 x 890 turned) regular
// both ways, its outer one (466 x 678) compact in width with its status bar down its right side (84); half open on its
// back half, the fold across the turned inner screen's middle (tabletop.mbt).

///|
/// The fixture's chat on an iPhone, the window `w` × `h`, the size classes and the hinge said as its host says them
/// (`fold`: its message's JSON, "" none; `bars`: the bars' message, "" the status bar and the home indicator round it).
fn duo_chat(w : Double, h : Double, width : String, fold : String, bars? : String = "") -> @ui.Tester {
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform=1)
  t.post(@hostapi.system_channel, if bars != "" {
    bars
  } else {
    "{\"bars\":{\"top\":24,\"bottom\":20,\"left\":0,\"right\":0}}"
  })
  t.post(@hostapi.system_channel, "{\"size_class\":{\"width\":\"\{width}\",\"height\":\"regular\"}}")
  if fold != "" {
    t.post(@hostapi.system_channel, fold)
  }
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The fold across the turned inner screen (626 wide), its division from 430 to 460 (the margins the system keeps
/// round it in), the hinge `hinge`.
fn across(hinge : String) -> String {
  "{\"fold\":{\"hinge\":\"\{hinge}\",\"divisions\":[{\"x\":0,\"y\":430,\"w\":626,\"h\":30}]}}"
}

///|
/// The fold upright in the inner screen as it opens (890 wide), its division from 430 to 460, the hinge `hinge`.
fn upright(hinge : String) -> String {
  "{\"fold\":{\"hinge\":\"\{hinge}\",\"divisions\":[{\"x\":430,\"y\":0,\"w\":30,\"h\":626}]}}"
}

///|
/// Where the words beginning with `s` are drawn (x, y, w, h), the first of them.
fn words_at(t : @ui.Tester, s : String) -> (Double, Double, Double, Double)? {
  for w in t.words() {
    let (text, x, y, ww, h, _) = w
    if text.has_prefix(s) {
      return Some((x, y, ww, h))
    }
  }
  None
}

///|
test "an iPhone Duo opened (regular both ways): the wide frame, the chats' list beside the chat, no bottom bar" {
  let t = duo_chat(890.0, 626.0, "regular", upright("open"))
  assert_true(@sfdesk.is_wide(t.ctx()))
  assert_false(bar_tabs(t))
  // the chats' list beside the chat: another chat's row, and the open one's messages and composer
  assert_true(t.find("首页的列表改成按天分组") is Some(_), msg="\{t.drawn_text()}")
  assert_true(t.find("做完了：列表、跳到最新的按钮") is Some(_))
  // a finger's composer: what it says is the phone's, not the desktop's 按空格输入
  assert_true(t.find("发消息") is Some(_), msg="\{t.drawn_text()}")
}

///|
test "opened as a book (the fold upright): the sidebar ends on the fold, the list on one half, the chat on the other" {
  for hinge in ["open", "half"] {
    let t = duo_chat(890.0, 626.0, "regular", upright(hinge))
    let (lx, _, lw, _) = words_at(t, "首页的列表改成按天分组").unwrap()
    assert_true(lx + lw <= 445.0, msg="\{hinge}: the list's row ends at \{lx + lw}")
    let (cx, _, _, _) = words_at(t, "做完了：列表").unwrap()
    assert_true(cx >= 445.0, msg="\{hinge}: the chat's message starts at \{cx}")
  }
}

///|
test "turned and flat (regular both ways, the fold across): the wide frame, the composer at its foot" {
  let t = duo_chat(626.0, 890.0, "regular", across("open"))
  assert_true(@sfdesk.is_wide(t.ctx()))
  let (_, y) = t.find("发消息").unwrap()
  assert_true(y > 890.0 - 110.0, msg="the composer's words at \{y}")
}

///|
test "a window 700 wide the system calls compact (beside another app): by its width, the tape, not the phone's pages" {
  let t = duo_chat(700.0, 890.0, "compact", "")
  assert_true(@sfdesk.is_wide(t.ctx()))
  assert_true(@sfdesk.wide.tape)
}

///|
test "half open on its back half: the messages over the fold, under it the composer and the latest chats" {
  let t = duo_chat(626.0, 890.0, "regular", across("half"))
  // the chat's page across the window, not the frame
  assert_false(@sfdesk.is_wide(t.ctx()))
  // the last message over the fold
  let (_, my, _, mh) = words_at(t, "做完了：列表").unwrap()
  assert_true(my + mh <= 430.0, msg="the last message ends at \{my + mh}")
  // the composer at the top of the half under the fold
  let (_, words) = t.find("发消息").unwrap()
  assert_true(words > 460.0 && words < 460.0 + 60.0, msg="the composer's words at \{words}")
  // the latest chats under it
  let (_, ry, _, _) = words_at(t, "首页的列表改成按天分组").unwrap()
  assert_true(ry > words, msg="the latest chats' row at \{ry}")
  // one tapped: that chat in this one's place
  t.tap_text("首页的列表改成按天分组")
  t.run_for(@ui.move_most_ms)
  match app.nav.top() {
    Chat(r) => assert_true(r.session != "s-c1", msg="still \{r.session}")
    _ => fail("not a chat")
  }
  // opened flat again: the wide frame, the composer at its foot
  t.post(@hostapi.system_channel, across("open"))
  t.draw()
  assert_true(@sfdesk.is_wide(t.ctx()))
}

///|
test "its outer screen (compact, the status bar down its right side): the phone's pages beside it" {
  let t = duo_chat(
    466.0,
    678.0,
    "compact",
    "{\"fold\":{\"hinge\":\"closed\",\"divisions\":[]}}",
    bars="{\"bars\":{\"top\":0,\"bottom\":20,\"left\":0,\"right\":84}}",
  )
  assert_false(@sfdesk.is_wide(t.ctx()))
  // nothing of the page under the status bar's side
  for w in t.words() {
    let (s, x, _, ww, _, alpha) = w
    if alpha > 0.0 {
      assert_true(x + ww <= 466.0 - 84.0 + 0.5, msg="\{s} ends at \{x + ww}")
    }
  }
  let (_, y) = t.find("发消息").unwrap()
  assert_true(y > 678.0 - 110.0, msg="the composer's words at \{y}")
}

///|
/// The old views of the window's tree as it draws them: where across and how wide.
fn islands_across() -> Array[(Double, Double)] {
  match @ui.view_tree() {
    Some(tree) => tree.drawn().filter(fn(d) { d.hosted }).map(fn(d) { (d.x, d.w) })
    None => []
  }
}

///|
test "the fold half open then, the window the same size: the shell it calls for, as if it had begun so" {
  let opened = duo_chat(626.0, 890.0, "regular", across("open"))
  let open_shell = islands_across()
  let wide_open = @sfdesk.is_wide(opened.ctx())
  opened.post(@hostapi.system_channel, across("half"))
  opened.run_for(@ui.move_most_ms)
  let then_half = (islands_across(), @sfdesk.is_wide(opened.ctx()))
  let begun = duo_chat(626.0, 890.0, "regular", across("half"))
  let begun_half = (islands_across(), @sfdesk.is_wide(begun.ctx()))
  assert_eq(then_half, begun_half)
  assert_true(then_half != (open_shell, wide_open), msg="\{open_shell} \{wide_open}")
}

///|
test "turned sideways for a film, the bars the same: the window's sides given back; upright again, kept again" {
  let t = duo_chat(466.0, 678.0, "compact", "", bars="{\"bars\":{\"top\":0,\"bottom\":20,\"left\":0,\"right\":84}}")
  let upright = islands_across()
  @hostapi.set_sideways(true)
  t.draw()
  let sideways = islands_across()
  @hostapi.set_sideways(false)
  t.draw()
  assert_true(upright.length() > 0 && upright.iter().all(fn(i) { i.1 == 382.0 }), msg="\{upright}")
  assert_true(sideways.length() > 0 && sideways.iter().all(fn(i) { i.1 == 466.0 }), msg="\{sideways}")
  assert_eq(islands_across(), upright)
}
