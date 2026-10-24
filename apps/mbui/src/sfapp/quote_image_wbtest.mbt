// An image of a message held in the chat (its menu's 引用, sfpages menus.mbt; MessagePick.kt quoteFile): quoted into the draft,
// its file going again with the message; a quote's own file in its card, not among the files (Chat.kt QuoteCards,
// besideQuotes; Composer.kt DraftExtras).

///|
/// The chat open at its end, then a row up at a time until the image `name` is drawn; where it is.
fn image_in_chat(name : String) -> (@ui.Tester, Double, Double) {
  reset()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
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
fn chat_draft() -> Draft {
  drafts.get(draft_key(chat_ref("ws1/st1", "s-c1"))).unwrap()
}

///|
test "a person's image held: quoted (whose, the file named), its file once in the draft as the station has it, felt; not opened" {
  let (t, x, y) = image_in_chat("插画参考.png")
  hold_quote(t, x, y)
  assert_true(viewer.val is None)
  assert_eq(t.haptics(), [@ui.Haptic::LongPress])
  let d = chat_draft()
  assert_eq(d.quotes.length(), 1)
  let q = d.quotes[0]
  assert_eq(q.author, "Ana")
  assert_eq(q.role, "person")
  assert_eq(q.file, "插画参考.png")
  assert_eq(d.files.length(), 1)
  // the station has it: nothing goes up, it goes again with the message, through the session keeping it
  let f = d.files[0]
  assert_true(f.done is Some(_) && f.core_id == "")
  assert_eq(text(f.done, "name"), "插画参考.png")
  assert_true(text(f.done, "owner") != "")
  // shown in the quote's card, not in the files' row
  assert_true(quote_file_of(d, q).map(fn(x) { x.id }) == Some(f.id))
  assert_eq(draft_items(d).length(), 0)
  // held again: another quote, the file still once
  hold_quote(t, x, y)
  assert_eq(d.quotes.length(), 2)
  assert_eq(d.files.length(), 1)
  // one quote taken out: the file stays for the other; the last taken out, the file goes with it
  draft_unquote(fixture("chat"), d, d.quotes[0])
  assert_eq(d.files.length(), 1)
  draft_unquote(fixture("chat"), d, d.quotes[0])
  assert_eq(d.files.length(), 0)
}

///|
test "an agent's image held: quoted, not a passage of its words picked; whose it is the agent's" {
  let (t, x, y) = image_in_chat("compare.png")
  hold_quote(t, x, y)
  assert_eq(pk.ts, "")
  let d = chat_draft()
  assert_eq(d.quotes.length(), 1)
  assert_eq(d.quotes[0].role, "agent")
  assert_eq(d.quotes[0].file, "compare.png")
}

///|
test "a message's quote naming one of its files: that file in the quote's card, the rest as they were" {
  let a = fn(name : String) -> Attachment {
    { name, path: "/w/" + name, size: 1.0, width: 0.0, height: 0.0, thumbhash: "", owner: "", upload: "" }
  }
  let files = [a("shot.png"), a("notes.txt")]
  let quotes : Array[Quote] = [
    { author: "你", text: "shot.png", comment: "", ts: "1", role: "person", file: "shot.png" },
    { author: "Ana", text: "一段话", comment: "", ts: "2", role: "person", file: "" },
  ]
  assert_eq(beside_quotes(quotes, files).map(fn(x) { x.name }), ["notes.txt"])
  assert_eq(quote_file(quotes[0], files).map(fn(x) { x.name }), Some("shot.png"))
  assert_true(quote_file(quotes[1], files) is None)
  // none naming a file: all of them
  assert_eq(beside_quotes([quotes[1]], files).length(), 2)
}
