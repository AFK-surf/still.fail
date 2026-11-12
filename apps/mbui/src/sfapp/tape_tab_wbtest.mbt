// On the tape (中屏) the keyboard's focus is only in the panel in use (sfdesk's tape_in_use, mbui's View::in_use): the
// rail and the sidebar behind the page brought over (laid out past the window's left edge), and the page behind the
// sidebar (its bar's buttons past the window's right edge, its composer and messages in the strip of it that shows),
// are gone to by no Tab nor read out as able to take the focus, from the moment another is asked over; asked back,
// theirs again from that moment, as on 大屏. What the hand does on what shows of the one behind is as it was (a tap or
// a click brings it over: the tape's own tests hold the rest).

///|
/// Where each stop of Tab is (what has the focus as each Tab is pressed, what it is called and where it is drawn), from
/// the focus as it is round to it again, `most` stops at most.
fn tab_round(t : @ui.Tester, most : Int) -> Array[(String, (Double, Double, Double, Double))] {
  let first = t.focus_said()
  let out = []
  for _ in 0..<most {
    t.tab()
    if t.focus_said() == first {
      break
    }
    match t.focused() {
      Some(s) => out.push((s.label, s.rect))
      None => out.push(("", (0.0, 0.0, 0.0, 0.0)))
    }
  }
  out
}

///|
/// Whether rect `r` is drawn at all in a window `w` × `h`.
fn in_window(r : (Double, Double, Double, Double), w : Double, h : Double) -> Bool {
  let (x, y, rw, rh) = r
  x < w && x + rw > 0.0 && y < h && y + rh > 0.0
}

///|
/// The page's bar's buttons, as they are read out.
// kept across runs: a value
let tab_page : Array[String] = ["归档", "对话信息", "更多", "打开侧栏"]

///|
/// The page's composer as it is read out with the focus in it (发消息), and as Tab comes to it (a keyboard's: 按空格输入,
/// Space to write in it).
// kept across runs: a value
let tab_composer : Array[String] = ["发消息", "按空格输入"]

///|
/// The rail's places of the fixture's workspace, as it reads them out.
// kept across runs: a value
let tab_rail : Array[String] = ["待处理", "对话"]

///|
test "中屏 with a keyboard, the page brought over the sidebar: Tab goes round only what is in the window, none of the rail's; nothing past the window's left edge read out" {
  let t = tape_chat(0, 720.0, 800.0)
  page_over(t, 720.0)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  // (the composer with the focus, as it asked it as the chat opened beside the sidebar: kept asked till the page is in
  // use, given it then)
  assert_eq(t.focused().map(fn(s) { s.label }), Some("发消息"))
  let stops = tab_round(t, 60)
  assert_true(stops.length() > 0)
  for s in stops {
    assert_true(in_window(s.1, 720.0, 800.0), msg="Tab's stop \{Repr(s)} is not in the window; all of them: \{Repr(stops)}")
    assert_false(tab_rail.contains(s.0), msg="Tab's stop \{Repr(s)} is the rail's; all of them: \{Repr(stops)}")
  }
  // (a screen reader: nothing laid out wholly past the window's left edge read out, the rail's none of it)
  for s in t.semantics() {
    let (x, _, w, _) = s.rect
    if !s.hidden {
      assert_false(w > 0.0 && x + w <= 0.0, msg="read out past the window's left edge: \{s.describe()} at \{Repr(s.rect)}")
      assert_false(tab_rail.contains(s.label), msg="the rail's read out: \{s.describe()} at \{Repr(s.rect)}")
    }
  }
}

///|
test "中屏 with a keyboard, the sidebar in use: the rail's places gone to by Tab and read out, where they are in the window; nothing of the page beside it gone to or read out" {
  let t = tape_chat(0, 720.0, 800.0)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  // (where the page's panel begins: what shows of it, at the window's right)
  let col = @sfdesk.tape_col_now(t.time())
  assert_true(col < 720.0, msg="the page shows at \{col}")
  let stops = tab_round(t, 80)
  for r in tab_rail {
    match stops.search_by(fn(s) { s.0 == r }) {
      Some(i) => assert_true(in_window(stops[i].1, 720.0, 800.0), msg="\{r} at \{Repr(stops[i])}")
      None => fail("\{r} gone to by no Tab: \{Repr(stops)}")
    }
    assert_true(t.semantics().iter().any(fn(s) { s.label == r && !s.hidden }), msg="\{r} read out")
  }
  for s in stops {
    assert_true(in_window(s.1, 720.0, 800.0), msg="Tab's stop \{Repr(s)} is not in the window; all of them: \{Repr(stops)}")
    let (x, _, _, _) = s.1
    // (what shows of the page is the tape's stop that brings it over: the next test)
    if s.0 == "收起侧边栏" {
      continue
    }
    assert_true(x < col, msg="Tab's stop \{Repr(s)} is the page's, behind the sidebar; all of them: \{Repr(stops)}")
    assert_false(tab_page.contains(s.0) || tab_composer.contains(s.0), msg="Tab's stop \{Repr(s)} is the page's; all of them: \{Repr(stops)}")
  }
  // (a screen reader: nothing of the page read out as able to take the focus, nor having it, but what brings it over)
  for s in t.semantics() {
    let (x, _, w, _) = s.rect
    if w > 0.0 && x >= col && s.label != "收起侧边栏" && (s.focused || s.actions.contains(Focus)) {
      fail("the page's read out as taking the focus behind the sidebar: \{s.describe()} at \{Repr(s.rect)}, \{Repr(s.actions)}")
    }
  }
}

///|
test "中屏 with a keyboard, the page brought over: its composer with the focus, its bar's buttons gone to by Tab and read out" {
  let t = tape_chat(0, 720.0, 800.0)
  page_over(t, 720.0)
  assert_eq(t.focused().map(fn(s) { s.label }), Some("发消息"))
  let stops = tab_round(t, 60)
  for r in tab_page {
    match stops.search_by(fn(s) { s.0 == r }) {
      Some(i) => assert_true(in_window(stops[i].1, 720.0, 800.0), msg="\{r} at \{Repr(stops[i])}")
      None => fail("\{r} gone to by no Tab: \{Repr(stops)}")
    }
    assert_true(t.semantics().iter().any(fn(s) { s.label == r && !s.hidden }), msg="\{r} read out")
  }
}

///|
test "中屏 with a keyboard: the composer with the focus as the sidebar is asked over lets it go at that moment; the page asked back, its own take it from that moment" {
  let t = tape_chat(0, 720.0, 800.0)
  page_over(t, 720.0)
  assert_eq(t.focused().map(fn(s) { s.label }), Some("发消息"))
  let side = covers_said(t, "展开侧边栏")
  assert_eq(side.length(), 1)
  t.advance(between_frames_ms)
  t.ctx().ask_action(side[0], Activate)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  assert_false(tab_composer.contains(t.focused().map(fn(s) { s.label }).unwrap_or("")), msg="the focus kept: \{t.focus_said()}")
  for r in tab_page {
    assert_false(t.semantics().iter().any(fn(s) { s.label == r && s.actions.contains(Focus) }), msg="\{r} read out as taking the focus as the sidebar is asked over")
  }
  t.run_for(@ui.move_most_ms)
  // the page asked back: its own read out and taking presses at that moment
  let page = covers_said(t, "收起侧边栏")
  assert_eq(page.length(), 1)
  t.advance(between_frames_ms)
  t.ctx().ask_action(page[0], Activate)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  // (the bar's, the tree's: at that moment)
  for r in tab_page {
    let said = t.semantics().filter(fn(s) { s.label == r && s.actions.contains(Focus) })
    assert_true(said.length() > 0, msg="\{r} as the page is asked back: not read out as taking the focus")
  }
}

///|
test "大屏 with a keyboard: the rail's places gone to by Tab and read out, as ever" {
  let t = tape_chat(0, 1200.0, 800.0)
  assert_false(@sfdesk.wide.tape.get())
  let stops = tab_round(t, 80)
  for r in tab_rail {
    match stops.search_by(fn(s) { s.0 == r }) {
      Some(i) => assert_true(in_window(stops[i].1, 1200.0, 800.0), msg="\{r} at \{Repr(stops[i])}")
      None => fail("\{r} gone to by no Tab: \{Repr(stops)}")
    }
    assert_true(t.semantics().iter().any(fn(s) { s.label == r && !s.hidden }), msg="\{r} read out")
  }
}

///|
test "中屏 with a keyboard: the rail's place with the focus as the page is asked over lets it go at that moment, none of the rail's able to take it as the tape goes; the sidebar asked back, the rail's take it from that moment" {
  let t = tape_chat(0, 720.0, 800.0)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  t.act(Button, Focus, label="待处理")
  assert_eq(t.focused().map(fn(s) { s.label }), Some("待处理"))
  // the page asked over by a screen reader's press of its cover, between frames: at that moment, no frame drawn since
  let page = covers_said(t, "收起侧边栏")
  assert_eq(page.length(), 1)
  t.advance(between_frames_ms)
  t.ctx().ask_action(page[0], Activate)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  assert_false(t.focused().map(fn(s) { s.label }) == Some("待处理"), msg="the focus kept: \{t.focus_said()}")
  // (as the tape goes, none of the rail's able to take the focus; no Tab pressed here: the page's bar, coming with it,
  // is past the window's right edge at this moment, where the Tester stops a key that moves the focus onto it,
  // tester_focus_off.mbt)
  for r in tab_rail {
    assert_false(t.semantics().iter().any(fn(s) { s.label == r && s.actions.contains(Focus) }), msg="\{r} able to take the focus as the tape goes")
  }
  t.run_for(@ui.move_most_ms)
  // the sidebar asked back by its cover's press: the rail's take the focus at that moment, read out
  let side = covers_said(t, "展开侧边栏")
  assert_eq(side.length(), 1)
  t.advance(between_frames_ms)
  t.ctx().ask_action(side[0], Activate)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  for r in tab_rail {
    let said = t.semantics().filter(fn(s) { s.label == r && !s.hidden && s.actions.contains(Focus) })
    assert_true(said.length() > 0, msg="\{r} as the sidebar is asked back: not read out as taking the focus")
  }
  // (no frame at rest drawn with a rail's place holding the focus: its ring breaks the corner rule there, on the
  // window too, a fault of its own not this file's (rt1-2): "a box in 「星 个」 (at 19,33 30×30, node 205) (corner 15) in
  // the top left of 「星 个」 (at 6,6 297×788, node 194) (corner 42): 13 and 27 from its edges")
  t.run_for(@ui.move_most_ms)
  let stops = tab_round(t, 80)
  for r in tab_rail {
    assert_true(stops.iter().any(fn(s) { s.0 == r }), msg="\{r} gone to by no Tab: \{Repr(stops)}")
  }
}

///|
test "中屏 with a finger: what shows of the page tapped brings it over, what shows of the sidebar tapped brings it back, nothing under either pressed" {
  let t = tape_chat(2, 750.0, 830.0, width="medium", height="medium")
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  assert_true(on_first_chat())
  page_over(t, 750.0)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  assert_true(on_first_chat())
  t.tap(@sfdesk.tape_shows / 2.0, 400.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  assert_true(on_first_chat(), msg="what was under the sidebar's strip pressed")
}

///|
test "中屏 with a keyboard, the sidebar in use: what shows of the page is a stop of Tab's after the sidebar's own, in the window; Enter brings the page over, the composer with the focus; ⌘[ the sidebar back, the focus none, Tab's first stop the sidebar's" {
  let t = tape_chat(0, 720.0, 800.0)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  // (one round: from the first stop Tab came to, the focus none at first, to it again)
  let all = tab_round(t, 80)
  let stops = []
  for s in all {
    if stops.length() > 0 && s == stops[0] {
      break
    }
    stops.push(s)
  }
  let at = stops.search_by(fn(s) { s.0 == "收起侧边栏" })
  guard at is Some(k) else { fail("收起侧边栏 gone to by no Tab: \{Repr(stops)}") }
  assert_true(in_window(stops[k].1, 720.0, 800.0), msg="\{Repr(stops[k])}")
  // (after the sidebar's own: the last of them before it, none of theirs after it in the round)
  let col = @sfdesk.tape_col_now(t.time())
  for i, s in stops {
    let (x, _, _, _) = s.1
    if i > k && x < col {
      fail("the sidebar's \{Repr(s)} after 收起侧边栏 in the round: \{Repr(stops)}")
    }
  }
  assert_true(stops[:k].iter().any(fn(s) { s.0 == "新建对话" }), msg="the sidebar's before it: \{Repr(stops)}")
  // (gone to again, Enter: the page over, its composer with the focus, in the window)
  while t.focused().map(fn(s) { s.label }) != Some("收起侧边栏") {
    t.tab()
  }
  t.enter()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  assert_eq(t.focused().map(fn(s) { s.label }), Some("发消息"), msg="the focus: \{t.focus_said()}")
  assert_true(in_window(t.focused().unwrap().rect, 720.0, 800.0), msg="the composer: \{t.focus_said()}")
  // ⌘[: the sidebar back, the focus none; Tab's first stop the sidebar's, in the window
  t.key_named("cmd+[") |> ignore
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  assert_eq(t.focus_said(), "none")
  t.tab()
  match t.focused() {
    Some(s) => {
      let (x, _, _, _) = s.rect
      assert_true(in_window(s.rect, 720.0, 800.0) && x < @sfdesk.tape_col_now(t.time()), msg="Tab's first stop: \{t.focus_said()}")
    }
    None => fail("Tab went to nothing")
  }
}

///|
test "中屏 with a keyboard, the page in use: ⌥↓ the chat after it in the page, the tape where it was, the new chat's composer with the focus" {
  let t = tape_chat(0, 720.0, 800.0)
  page_over(t, 720.0)
  t.key_named("alt+down") |> ignore
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  assert_false(on_first_chat(), msg="the chat after it not opened")
  assert_eq(t.focused().map(fn(s) { s.label }), Some("发消息"), msg="the focus: \{t.focus_said()}")
}

///|
test "中屏 with a keyboard, the sidebar in use, a chat open: Space (按空格输入) brings the page over at that moment, its composer with the focus, in the window; nothing of the sidebar keeps it" {
  let t = tape_chat(0, 720.0, 800.0)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  t.key(@ui.key_space)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  t.run_for(@ui.move_most_ms)
  assert_eq(t.focused().map(fn(s) { s.label }), Some("发消息"), msg="the focus: \{t.focus_said()}")
  assert_true(in_window(t.focused().unwrap().rect, 720.0, 800.0), msg="the composer: \{t.focus_said()}")
  for s in t.semantics() {
    if s.focused && s.label != "发消息" {
      fail("the focus kept by \{s.describe()} at \{Repr(s.rect)}")
    }
  }
}
