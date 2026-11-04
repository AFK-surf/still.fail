// Opening the composer reorders its existing editor and controls. The editor's identity, focus, selection and text
// survive both directions; the controls keep their old positions in either arrangement.

///|
test "the composer's capsule and box keep one editor, focus and selection while their parts exchange places" {
  for (width, platform) in [(390.0, 2), (600.0, 2), (840.0, 0), (1280.0, 0)] {
    @sfbase.reset()
    @sf.set_words(@sfbase.fill)
    let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=width, h=900.0, platform~)
    let open = @signals.signal(false)
    let field = @ui.Field::new(text="one line")
    let editor : Ref[@view.View?] = Ref(None)
    let plus : Ref[@view.View?] = Ref(None)
    let send : Ref[@view.View?] = Ref(None)
    let made = Ref(0)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      root.lines_up(Is(None)) |> ignore
      composer_box_node(
        root,
        fn() { open.get() },
        fn() { false },
        fn() { composer_alone },
        fn() { open.get().to_string() },
        fn(_, _) {  },
        fn(p) {
          made.val += 1
          let n = @ui.field(p, field, words=true, trim=true, font_size=15.0, line=22.0)
          editor.val = Some(n)
          n
        },
        fn(p) {
          p.width(By(fn() { Some(@sf.theme().round.side) })).height(By(fn() { Some(@sf.theme().round.side) })) |> ignore
          plus.val = Some(p)
        },
        fn(_) {  },
        fn(p) {
          p.width(By(fn() { Some(@sf.theme().round.side) })).height(By(fn() { Some(@sf.theme().round.side) })) |> ignore
          send.val = Some(p)
          [p]
        },
      )
      |> ignore
    })
    t.draw()
    let e = editor.val.unwrap()
    let id = e.id()
    let before = (plus.val.unwrap().rect(), e.rect(), send.val.unwrap().rect())
    assert_true(before.0.0 + before.0.2 <= before.1.0, msg="plus before words: \{before}")
    assert_true(before.1.0 + before.1.2 <= before.2.0, msg="words before send: \{before}")
    field.focus()
    field.pick(1, 4)
    open.set(true)
    t.draw()
    let expanded = (plus.val.unwrap().rect(), e.rect(), send.val.unwrap().rect())
    assert_true(expanded.1.1 + expanded.1.3 <= expanded.0.1, msg="words above controls: \{expanded}")
    assert_eq(expanded.0.1, expanded.2.1)
    assert_eq((made.val, editor.val.unwrap().id(), field.selection(), field.text()), (1, id, (1, 4), "one line"))
    assert_true(e.focused())
    open.set(false)
    t.draw()
    assert_eq((plus.val.unwrap().rect(), e.rect(), send.val.unwrap().rect()), before)
    assert_eq((made.val, editor.val.unwrap().id(), field.selection()), (1, id, (1, 4)))
    assert_true(e.focused())
  }
}

///|
test "the retained composer's local edits, remote revisions and restrictions reach the same field" {
  @sfbase.reset()
  @sf.set_words(@sfbase.fill)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=390.0, h=900.0, platform=0)
  let rev = @signals.signal((1, "first words"))
  let locked = @signals.signal(false)
  let calls : Array[String] = []
  let changed = Ref(0)
  let submitted = Ref(0)
  let src : Source = {
    ..@sfbase.made_source(call=fn(name, _, done) {
      calls.push(name)
      if name == "paste.info" { done(Ok({ "threshold": 800 })) } else { done(Ok({})) }
    }),
    topic: fn(name, _) {
      if name == "composer" {
        let (n, s) = rev.get()
        { value: Some({ "text": Json::string(s), "rev": Json::number(n.to_double()), "version": Json::number(n.to_double()) }), error: None, version: n }
      } else {
        { value: None, error: None, version: 0 }
      }
    },
  }
  let draft : Ref[Writing?] = Ref(None)
  let editor : Ref[@view.View?] = Ref(None)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    let w = @sfbase.writing_in(root, src, "field-test")
    draft.val = Some(w)
    editor.val = Some(composer_field_node(
      root, src, w, fn() { "station" }, fn() { locked.get() }, fn() { false }, fn() { "Write" },
      fn() { submitted.val += 1 }, fn() { changed.val += 1 }, fn() { 900.0 },
    ))
  })
  t.draw()
  let w = draft.val.unwrap()
  let id = editor.val.unwrap().id()
  assert_eq(w.field.text(), "first words")
  w.field.focus()
  w.field.pick(11, 11)
  t.type_text("!")
  assert_eq((w.text.get(), changed.val), ("first words!", 1))
  assert_eq(calls.filter(fn(n) { n == "composer.text" }).length(), 1)
  t.draw()
  assert_eq(changed.val, 1)
  // The core's own draft is adopted, with no second edit sent back or agent warm caused by that adoption.
  rev.set((2, "remote words"))
  t.draw()
  assert_eq((w.field.text(), changed.val, editor.val.unwrap().id()), ("remote words", 1, id))
  locked.set(true)
  t.draw()
  assert_true(!editor.val.unwrap().focused())
  locked.set(false)
  t.draw()
  w.field.focus()
  t.enter()
  assert_eq(submitted.val, 1)
}
