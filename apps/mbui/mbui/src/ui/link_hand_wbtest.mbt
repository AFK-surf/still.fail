// The pointer over a node's links (runs_links): a hand over each piece of a link, the arrow over the rest of its words
// and off them, as over an old view's paragraph; worked out as the tree places things, nothing laid out for it.

///|
test "the pointer over a node's link across lines: a hand over each of its pieces, the arrow over the words beside them and off the node" {
  let m = links_made(@signals.signal(linked_runs))
  let glyphs = link_glyphs(m.t)
  let first = glyphs[0]
  let last = glyphs[glyphs.length() - 1]
  assert_true(last.1 > first.1, msg="across lines: \{Repr(first)} \{Repr(last)}")
  let at = fn(x : Double, y : Double) {
    m.t.move_to(x, y)
    m.t.draw()
    m.t.cursor()
  }
  let shapes = [
    at(first.0 + first.2 / 2.0, first.1 + first.3 / 2.0),
    // (the words before it, on its first line: the node's start, moved by (40, 30))
    at(42.0, first.1 + first.3 / 2.0),
    at(last.0 + last.2 / 2.0, last.1 + last.3 / 2.0),
    at(390.0, 390.0),
    at(first.0 + first.2 / 2.0, first.1 + first.3 / 2.0),
  ]
  assert_eq(shapes, [Hand, Arrow, Hand, Arrow, Hand])
}

///|
test "the pointer moved over a node's links and off them: its shape said again, nothing laid out, measured or placed for it" {
  let m = links_made(@signals.signal(linked_runs))
  let glyphs = link_glyphs(m.t)
  let tree = view_app.val.unwrap()
  let before = { ..tree.work() }
  let shapes = []
  for g in glyphs {
    m.t.move_to(g.0 + g.2 / 2.0, g.1 + g.3 / 2.0)
    m.t.draw()
    shapes.push(m.t.cursor())
    m.t.move_to(42.0, g.1 + g.3 / 2.0)
    m.t.draw()
    shapes.push(m.t.cursor())
  }
  let after = tree.work()
  assert_true(shapes.iter().all(fn(s) { s == Hand || s == Arrow }) && shapes.contains(Hand), msg="\{Repr(shapes)}")
  assert_eq(
    (after.computes - before.computes, after.laid - before.laid, after.measured - before.measured, after.composed - before.composed),
    (0, 0, 0, 0),
  )
}

///|
test "the pointer moved off a node's words onto a link of them: the host told the hand once" {
  let m = links_made(@signals.signal(linked_runs))
  let g = link_glyphs(m.t)[0]
  m.t.move_to(42.0, g.1 + g.3 / 2.0)
  m.t.draw()
  let told = m.t.fake.cursors_told
  m.t.move_to(g.0 + g.2 / 2.0, g.1 + g.3 / 2.0)
  m.t.draw()
  assert_eq((m.t.cursor(), m.t.fake.cursors_told - told), (Hand, 1))
}

///|
test "a still pointer over a node whose shape is said anew: the host told it at that change, no frame asked for it" {
  let shape : @signals.Signal[@view.Cursor?] = @signals.signal(Some(@view.Cursor::ResizeX), same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=200.0, h=200.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(n) {
      n
      .width(Is(Some(40.0)))
      .height(Is(Some(40.0)))
      .says(Is(Some(@view.said(Button, label="把手"))))
      .on_press(fn() {  })
      .cursor(By(fn() { shape.get() }))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.move_to(20.0, 20.0)
  t.draw()
  let told = t.fake.cursors_told
  assert_eq((t.cursor(), t.fake.wants), (ResizeX, false))
  view_app.val.unwrap().event(t.time(), fn() { shape.set(Some(@view.Cursor::Grab)) })
  // (before any frame: shown, none asked)
  assert_eq((t.cursor(), t.fake.cursors_told - told, t.fake.wants), (Grab, 1, false))
}
