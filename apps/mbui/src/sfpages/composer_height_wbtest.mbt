///|
test "a retained composer's line limit follows its pane's height in the first layout" {
  @sfbase.reset()
  @sf.set_words(@sfbase.fill)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=800.0, h=900.0, platform=0)
  let pane_height = @signals.signal(300.0)
  let editor : Ref[@view.View?] = Ref(None)
  let draft : Ref[Writing?] = Ref(None)
  let src = @sfbase.made_source()
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(pane) {
      pane.width(Is(Some(500.0))).height(By(fn() { Some(pane_height.get()) })) |> ignore
      let context = pane.height_context()
      pane.lends(composer_height_context, context) |> ignore
      let w = @sfbase.writing_in(pane, src, "height-test")
      draft.val = Some(w)
      editor.val = Some(composer_field_node(
        pane, src, w, fn() { "station" }, fn() { false }, fn() { false }, fn() { "Write" },
        fn() { }, fn() { }, fn() { pane.laid_size_told().map(fn(size) { size.1 }).unwrap_or(pane.window().1) },
      ))
    }) |> ignore
  })
  t.draw()
  let w = draft.val.unwrap()
  w.field.set("one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\neleven\ntwelve\nthirteen\nfourteen\nfifteen")
  w.field.pick(1, 3)
  t.draw()
  let field = editor.val.unwrap()
  let id = field.id()
  let short = field.rect().3
  pane_height.set(800.0)
  t.draw()
  let tall = field.rect().3
  assert_true(tall > short, msg="more of the same words fits as the pane grows: \{short} -> \{tall}")
  assert_eq((field.id(), w.field.selection()), (id, (1, 3)))
  pane_height.set(300.0)
  t.draw()
  assert_eq(field.rect().3, short, msg="the field shrinks back in the first layout")
  assert_eq((field.id(), w.field.selection()), (id, (1, 3)))
}
