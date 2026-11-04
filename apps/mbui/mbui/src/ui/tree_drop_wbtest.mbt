///|
test "a retained page takes dropped words at its editor's caret, while a field under the drop takes its own" {
  let t = Tester::new(fn(_) { }, w=300.0, h=250.0, platform=0)
  let draft = Field::new(text="ab")
  let other = Field::new(text="other")
  let available = @signals.signal(true)
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.height(Is(Some(200.0))) |> ignore
      let editor = field(page, draft, placeholder="draft", font_size=10.0)
      field(page, other, placeholder="other", font_size=10.0) |> ignore
      page.box(fn(button) {
        button.words(Is("Attach")).height(Is(Some(30.0))).on_press(fn() { }) |> ignore
      }) |> ignore
      words_into_node(page, editor, when=fn() { available.get() })
    }) |> ignore
  })
  t.draw()
  draft.set("ab", caret=1)
  let (x, y) = t.find("Attach").unwrap()
  t.drop_words(x, y, "cd")
  t.frame()
  assert_eq(draft.text(), "acdb")
  assert_eq(t.ime().1, "acdb")
  t.key(key_of_char('z'), mods=mod_cmd)
  assert_eq(draft.text(), "ab")
  // Empty space in the page also belongs to its editor; outside the page does not.
  t.drop_words(270.0, 180.0, "ef")
  t.frame()
  assert_eq(draft.text(), "aefb")
  t.drop_words(270.0, 230.0, "outside")
  t.frame()
  assert_eq(draft.text(), "aefb")
  let (ox, oy, _, oh) = t.rect_of("other").unwrap()
  t.drop_words(ox + 1.0, oy + oh / 2.0, "new ")
  t.frame()
  assert_eq(other.text(), "new other")
  assert_eq(draft.text(), "aefb")
  available.set(false)
  t.drop_words(x, y, "locked")
  t.frame()
  available.set(true)
  t.frame()
  assert_eq(draft.text(), "aefb")
}

///|
test "a modal's contents and its ground keep drops from a retained page underneath" {
  let t = Tester::new(fn(_) { }, w=300.0, h=250.0, platform=0)
  let draft = Field::new(text="draft")
  let modal = @signals.signal(false)
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.height(Is(Some(250.0))) |> ignore
      let editor = field(page, draft, placeholder="draft")
      words_into_node(page, editor)
    }) |> ignore
    root.show(fn() { modal.get() }, fn(layer) {
      layer.over(Is(true)).modal(Is(true)).height(Is(Some(100.0))).width(Is(Some(150.0))) |> ignore
      layer.box(fn(button) { button.words(Is("Modal")).on_press(fn() { }) |> ignore }) |> ignore
    })
  })
  t.draw()
  modal.set(true)
  t.draw()
  t.drop_words(20.0, 20.0, "inside")
  t.frame()
  t.drop_words(270.0, 230.0, "outside")
  t.frame()
  assert_eq(draft.text(), "draft")
  modal.set(false)
  t.draw()
  t.drop_words(270.0, 230.0, " open")
  t.frame()
  assert_eq(draft.text(), "draft open")
}

///|
test "retained drops use the editor's large-paste callback and take file paths once without reading their bytes" {
  let t = Tester::new(fn(_) { }, w=300.0, h=250.0, platform=0)
  let draft = Field::new()
  let pasted : Array[String] = []
  let paths : Array[String] = []
  let take = @signals.signal(true)
  set_view_app(fn(root) {
    let editor = field(root, draft, placeholder="draft", paste_limit=20, pasted=fn(s) { pasted.push(s) })
    words_into_node(root, editor, paths=fn(ps) {
      if !take.get() { return false }
      for p in ps { paths.push(p.path) }
      true
    })
  })
  t.draw()
  let text = "a long piece of text becomes a file"
  t.drop_words(270.0, 230.0, text)
  t.frame()
  t.frame()
  assert_eq(pasted, [text])
  assert_eq(draft.text(), "")
  t.drop_files(270.0, 230.0, [("a.txt", b"a")], paths=["/a.txt"])
  t.frame()
  t.frame()
  assert_eq(paths, ["/a.txt"])
  assert_eq(draft.text(), "")
  take.set(false)
  t.drop_files(270.0, 230.0, [("b.txt", b"b")], paths=["/b.txt"])
  t.frame()
  assert_eq(draft.text(), "/b.txt")
  assert_eq(paths, ["/a.txt"])
}
