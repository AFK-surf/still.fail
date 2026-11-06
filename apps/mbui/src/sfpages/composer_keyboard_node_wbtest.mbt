///|
test "only the active retained chat receives a requested cursor and its empty draft's arrow keys" {
  @sfbase.reset()
  composing_reset()
  @sf.set_words(@sfbase.fill)
  let active = @signals.signal(false)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=390.0, h=900.0, platform=2)
  let n : Ref[ComposerNode?] = Ref(None)
  let other = @ui.Field::new()
  let src = @sfbase.made_source(call=fn(_, _, done) { done(Ok({})) })
  let moved : Array[Int] = []
  let before = @sfbase.neighbour_go.val
  @sfbase.neighbour_go.val = fn(_, _, by) { moved.push(by) }
  defer { @sfbase.neighbour_go.val = before }
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    @ui.field(root, other) |> ignore
    n.val = Some(composer_node(root, src, "focus-draft", fn() {
      { station: "workspace/station", draft: "focus-draft", session: "chat", placeholder: "Write",
        toolbar: None, toolbar_node: None, note: [], tail: None, roomy: false, locked: false, offline: false, warm_agent: true }
    }, fn(_) {  }, (root, fn(_, _) { 900.0 }), fn(_, _, _, _) {  }, active=fn() { active.get() }, neighbour=fn(by) { moved.push(by) }))
  })
  t.draw()
  let c = n.val.unwrap()
  composer_take_focus()
  t.draw()
  assert_false(c.field.focused())
  assert_true(composing.wanted.get())
  active.set(true)
  t.draw()
  assert_true(c.field.focused())
  assert_false(composing.wanted.get())
  t.key(@ui.key_code_up)
  t.key(@ui.key_code_down)
  assert_eq(moved, [-1, 1])
  t.type_text("words")
  t.key(@ui.key_code_up)
  assert_eq(moved, [-1, 1])
  other.focus()
  t.draw()
  assert_false(c.field.focused())
  active.set(false)
  composer_take_focus()
  t.draw()
  assert_false(c.field.focused())
  active.set(true)
  t.draw()
  assert_true(c.field.focused())
  assert_eq(n.val.unwrap().field.id(), c.field.id())
}
