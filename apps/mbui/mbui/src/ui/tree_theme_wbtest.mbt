// The theme the window's tree's nodes are drawn in (tree_theme): the one the frame picks for the window's width, read
// so in the first frame drawn at another width, what read it told.

///|
test "a node drawn in the tree's theme: the wide one's, then in the first frame at a narrow width the narrow one's" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  let wide = { ..Theme::light(), focus: 0x112233FFL }
  let narrow = { ..Theme::light(), focus: 0x445566FFL }
  let id : Ref[@view.NodeId?] = Ref(None)
  set_view_app(fn(root) {
    root.box(fn(n) {
      id.val = Some(n.id())
      n.width(Is(Some(40.0))).height(Is(Some(40.0))).ground(By(fn() { tree_theme().focus })) |> ignore
    })
    |> ignore
  })
  t.ctx().set_theme(wide, narrow~, narrow_below=300.0)
  t.draw()
  let tree = view_app.val.unwrap()
  assert_eq(tree.drawn_of(id.val.unwrap()).unwrap().ground, 0x112233FFL, msg="wide")
  t.resize(250.0, 200.0)
  assert_eq(tree.drawn_of(id.val.unwrap()).unwrap().ground, 0x445566FFL, msg="the first frame at the narrow width")
}

///|
test "words set as the tree's theme says: in the first frame at a narrow width, as big and as tall a line as the narrow one's, laid out and drawn so; wrapped where they no longer fit" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  let base = Theme::light()
  let wide = { ..base, text: { ..base.text, meta: (12.0, 16.0) } }
  let narrow = { ..base, text: { ..base.text, meta: (24.0, 30.0) } }
  let id : Ref[@view.NodeId?] = Ref(None)
  set_view_app(fn(root) {
    root.box(fn(n) {
      id.val = Some(n.id())
      n
      .width(Is(Some(120.0)))
      .words(Is("ab cd ef gh ij"))
      .words_look(By(fn() {
        let (size, line) = tree_theme().text_size(Meta)
        { size, weight: 400, line, wrap: true }
      }))
      |> ignore
    })
    |> ignore
  })
  t.ctx().set_theme(wide, narrow~, narrow_below=300.0)
  t.draw()
  let tree = view_app.val.unwrap()
  let d = tree.drawn_of(id.val.unwrap()).unwrap()
  assert_eq((d.words_look.size, d.h), (12.0, 16.0), msg="wide: one line of its")
  t.resize(250.0, 200.0)
  let d = tree.drawn_of(id.val.unwrap()).unwrap()
  assert_eq(d.words_look.size, 24.0, msg="narrow: its size")
  assert_true(d.h >= 60.0, msg="narrow: its lines, wrapped (\{d.h})")
}
