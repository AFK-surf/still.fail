// An image of a message held in the chat (its menu's 引用, sfpages menus.mbt; MessagePick.kt quoteFile): quoted into the draft,
// its file going again with the message; a quote's own file in its card, not among the files (Chat.kt QuoteCards,
// besideQuotes; Composer.kt DraftExtras).

///|
/// The chat open at its end (on `platform`'s screen: Android's, a finger), then a row up at a time until the image
/// `name` is drawn; where it is.
fn image_in_chat(name : String, platform? : Int = 2) -> (@ui.Tester, Double, Double) {
  reset()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform~)
  nav_rested(t)
  let mut tries = 0
  while t.locate("img:" + name).length() == 0 && tries < 12 {
    let (first, _) = t.visible()
    t.scroll_to(if first > 0 { first - 1 } else { 0 })
    t.draw()
    tries += 1
  }
  let at = t.locate("img:" + name)
  assert_true(at.length() > 0) catch { _ => () }
  let (x, y) = at[0]
  (t, x, y)
}

///|
/// The image at (`x`, `y`) held: its menu (a sheet, a finger's) up, 引用 tapped; its quote taken into the draft.
fn hold_quote(t : @ui.Tester, x : Double, y : Double) -> Unit {
  t.press_at(x, y)
  t.run_for(@ui.long_press_ms + 20.0)
  t.release(x, y)
  t.draw()
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  t.tap_text("引用")
  t.frame()
  t.frame()
}

///|
fn chat_draft() -> @sfbase.Writing {
  @sfbase.writings.get(draft_key(chat_ref("ws1/st1", "s-c1"))).unwrap()
}

///|
test "a person's image held: quoted (whose, the file named), its file once in the draft as the station has it, felt; not opened" {
  let (t, x, y) = image_in_chat("插画参考.png")
  hold_quote(t, x, y)
  assert_true(viewer.val is None)
  assert_eq(t.haptics(), [@ui.Haptic::LongPress])
  // into the chat's draft as the core keeps it (sfpages' composer took it: quote_file_into)
  let d = chat_draft()
  assert_eq(d.quotes.length(), 1)
  let q = Some(d.quotes[0])
  assert_eq(text(q, "author"), "Ana")
  assert_eq(text(q, "role"), "person")
  assert_eq(text(field(q, "own"), "name"), "插画参考.png")
  assert_eq(d.files.length(), 0)
  // held again: another quote
  hold_quote(t, x, y)
  assert_eq(chat_draft().quotes.length(), 2)
}

///|
test "an agent's image held: quoted, not a passage of its words picked; whose it is the agent's" {
  let (t, x, y) = image_in_chat("compare.png")
  hold_quote(t, x, y)
  assert_eq(pk.ts, "")
  let d = chat_draft()
  assert_eq(d.quotes.length(), 1)
  assert_eq(text(Some(d.quotes[0]), "role"), "agent")
  assert_eq(text(field(Some(d.quotes[0]), "own"), "name"), "compare.png")
}

///|
test "an image right clicked: its one menu, again on that menu still the one; in the preview over the chat, the picture's own, never the chat's 引用" {
  // (macOS: a mouse, menus beside what opened them)
  let (t, x, y) = image_in_chat("compare.png", platform=0)
  // (引用 a press reaches: a menu's, not what lies under what is over it)
  let quotes = fn() { t.reachable("引用").length() }
  let before = quotes()
  t.right_click(x, y)
  assert_eq(quotes(), before + 1)
  let menu = @sf.last_presented()
  // on the menu, which opened over the image: the menu's, no second menu of the image's over it
  t.right_click(x + 10.0, y + 10.0)
  t.draw()
  assert_eq(@sf.last_presented(), menu)
  assert_true(@sf.presented_open_of(menu))
  assert_eq(quotes(), before + 1)
  // closed, and the image opened over the whole window
  t.key(@ui.key_escape)
  t.draw()
  t.tap(x, y)
  t.run_for(fly_open_ms)
  assert_true(viewer.val is Some(_))
  // where the chat's image is under it: never that image's menu (its 引用 into the draft the preview covers)
  t.right_click(x, y)
  assert_eq(quotes(), 0)
  // (the picture's own, if it was on the picture there, closed)
  if @sf.presenting() {
    t.key(@ui.key_escape)
    t.draw()
  }
  assert_true(viewer.val is Some(_))
  // on its picture, in the middle: its own menu, 复制图片 (as its bar's 复制)
  t.right_click(195.0, 422.0)
  assert_true(t.reachable("复制图片").length() > 0)
  assert_eq(quotes(), 0)
}
