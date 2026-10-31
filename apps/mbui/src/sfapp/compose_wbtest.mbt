// What is written as the core keeps it (sfbase's compose.mbt, the web's draft.ts): over the fixture core's composers
// (compose_fixture.mbt).

///|
test "a draft as the core keeps it: its kept words read back into the field; what is typed told to the core, not taken back from it" {
  new_run()
  let src = fixture("chat-compose")
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  assert_true(w.text.get().has_prefix("把发布清单再过一遍"))
  assert_eq(w.field.text(), w.text.get())
  // typed: the page's at once, the core told; its answer (the same words, no new rev) does not set the field again
  w.field.set("先看第三项")
  @sfbase.writing_text(src, w, "先看第三项")
  let w2 = @sfbase.writing(src, "ws1/st1:s-c1")
  assert_eq(w2.text.get(), "先看第三项")
  assert_eq(text((src.topic)("composer", { "key": Json::string("ws1/st1:s-c1") }).value, "text"), "先看第三项")
  assert_true(w2.ready)
}

///|
test "a draft taken to be sent is empty at once and the core answers what it took; put back, it is there again with why" {
  new_run()
  let src = fixture("chat")
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  @sfbase.writing_text(src, w, "  发一下  ")
  let took : Ref[Json?] = Ref(None)
  @sfbase.writing_take(src, w, fn(a) { took.val = a })
  assert_eq(w.text.get(), "")
  assert_eq(w.field.text(), "")
  assert_eq(text(took.val, "text"), "发一下")
  @sfbase.writing_restore(src, w, "发不出去")
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  assert_eq(w.text.get(), "  发一下  ")
  assert_eq(w.field.text(), "  发一下  ")
  assert_eq(w.error, "发不出去")
}

///|
test "a draft's quotes: added with the focus on its comment line, said about, let go" {
  new_run()
  let src = fixture("chat")
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  @sfbase.writing_quote(src, w, { "author": "Claude", "text": "其余的行按估计的高度占位", "ts": "ts8" })
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  assert_eq(w.quotes.length(), 1)
  let id = text(Some(w.quotes[0]), "id")
  assert_eq(w.focus, id)
  @sfbase.writing_focused(src, w)
  @sfbase.writing_comment(src, w, id, "这里改成量过再记")
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  assert_eq(w.focus, "")
  assert_eq(text(Some(w.quotes[0]), "comment"), "这里改成量过再记")
  @sfbase.writing_unquote(src, w, id)
  assert_eq(@sfbase.writing(src, "ws1/st1:s-c1").quotes.length(), 0)
}

///|
test "an image of a message quoted is its quote's own picture, not among the files, and goes with it" {
  new_run()
  let src = fixture("chat")
  let image : Json = { "name": "shot.png", "path": "/w/uploads/shot.png", "size": 120, "owner": "s-c1" }
  let quote : Json = { "author": "Claude", "text": "shot.png", "ts": "ts8" }
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  @sfbase.writing_quote(src, w, quote, file=image)
  @sfbase.writing_quote(src, w, quote, file=image)
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  assert_eq(w.files.length(), 0)
  assert_eq(w.quotes.map(fn(q) { text(field(Some(q), "own"), "name") }), ["shot.png", "shot.png"])
  @sfbase.writing_unquote(src, w, text(Some(w.quotes[0]), "id"))
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  assert_eq([w.quotes.length(), w.files.length()], [1, 0])
  assert_eq(text(field(Some(w.quotes[0]), "own"), "name"), "shot.png")
}

///|
test "what is written in a new chat goes on into the chat it made (composer.carry), the new chat's left empty" {
  new_run()
  let src = fixture("chat")
  let w = @sfbase.writing(src, "new:ws1")
  @sfbase.writing_text(src, w, "把发布说明写一下")
  @sfbase.writing_carry(src, "new:ws1", "ws1/st1:s-new")
  assert_eq(@sfbase.writing(src, "ws1/st1:s-new").text.get(), "把发布说明写一下")
  assert_eq(@sfbase.writing(src, "new:ws1").text.get(), "")
}
