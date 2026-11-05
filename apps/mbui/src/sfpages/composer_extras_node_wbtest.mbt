///|
test "a retained attachment keeps its card as the upload changes and a quote keeps its editable comment" {
  @sfbase.reset()
  composing_reset()
  @sf.set_words(@sfbase.fill)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=390.0, h=600.0)
  let calls : Array[String] = []
  let picture = @signals.signal("preview")
  let src = { ..@sfbase.made_source(call=fn(name, _, done) { calls.push(name); done(Ok({})) }),
    draft_picture: fn(_, _) { picture.get() } }
  let writing : Ref[Writing?] = Ref(None)
  let extras : Ref[ComposerExtrasNode?] = Ref(None)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    let w = @sfbase.writing_in(root, src, "extras-test")
    writing.val = Some(w)
    extras.val = Some(composer_extras_node(root, src, w, fn() { "station" }, fn() { 18.0 }, fn() { 18.0 },
      fn(p, _, wide, high, _, radius) {
        p.width(By(fn() { Some(wide()) })).height(By(fn() { Some(high()) })).radius(By(radius)).ground(Is(0xFFFFFFFFL)) |> ignore
      }))
  })
  let w = writing.val.unwrap()
  w.files.set([{ "id": "f1", "name": "notes.txt", "size": 100, "sent": 10 }])
  w.quotes.set([{ "id": "q1", "author": "林", "text": "quoted words", "comment": "first" }])
  t.draw()
  let e = extras.val.unwrap()
  let file_id = e.files["f1"].id()
  let quote_id = e.quotes["q1"].words.id()
  let f = e.comments["q1"]
  f.focus()
  f.pick(5, 5)
  t.type_text("!")
  assert_eq(text(Some(w.quotes.get()[0]), "comment"), "first!")
  assert_eq(calls.filter(fn(s) { s == "composer.comment" }).length(), 1)
  w.files.set([{ "id": "f1", "name": "notes.txt", "size": 100, "sent": 90 }])
  t.draw()
  assert_eq((e.files["f1"].id(), e.quotes["q1"].words.id(), f.selection()), (file_id, quote_id, (6, 6)))
  w.quotes.set([{ "id": "q1", "author": "林", "text": "quoted words", "comment": "core comment" }])
  t.draw()
  assert_eq(f.text(), "core comment")
  assert_eq(calls.filter(fn(s) { s == "composer.comment" }).length(), 1)
  w.files.set([])
  t.draw()
  assert_true(!e.files.contains("f1"))
  assert_eq(e.quotes["q1"].words.id(), quote_id)
  w.files.set([{ "id": "image", "name": "image.png", "size": 100 }])
  t.draw()
  let image_id = e.files["image"].id()
  picture.set("!")
  t.draw()
  assert_true(e.files.contains("image") && e.files["image"].id() != image_id)
  picture.set("preview-again")
  t.draw()
  w.files.set([])
  t.draw()
  assert_true(!e.files.contains("image"))
}

///|
/// A waiting file's card as wide as a card is (file_card_w) at most, or as the row of what waits leaves it (its end,
/// `file_end`, kept clear) where that is less, from the first frame that draws it: held to that as it is laid out, not
/// read back from the row's laid size a frame on.
test "a waiting file's card is held to the row's room from the first frame that draws it" {
  for room in [390.0, 200.0] {
    @sfbase.reset()
    composing_reset()
    @sf.set_words(@sfbase.fill)
    let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=room, h=600.0)
    let src = @sfbase.made_source(call=fn(_, _, done) { done(Ok({})) })
    let writing : Ref[Writing?] = Ref(None)
    let extras : Ref[ComposerExtrasNode?] = Ref(None)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      let w = @sfbase.writing_in(root, src, "extras-room")
      writing.val = Some(w)
      extras.val = Some(composer_extras_node(root, src, w, fn() { "station" }, fn() { 18.0 }, fn() { 18.0 },
        fn(p, _, wide, high, _, radius) {
          p.width(By(fn() { Some(wide()) })).height(By(fn() { Some(high()) })).radius(By(radius)).ground(Is(0xFFFFFFFFL)) |> ignore
        }))
    })
    writing.val.unwrap().files.set([{ "id": "f1", "name": "notes.txt", "size": 100, "sent": 10 }])
    t.draw()
    let (_, _, wide, _) = extras.val.unwrap().files["f1"].rect()
    assert_eq(wide, dmin(@sf.file_card_w, room - 18.0), msg="room \{room}")
  }
}
