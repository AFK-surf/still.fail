// The pointer's shape over a node of the window's tree whose words are picked with the pointer (words_picked,
// view_node_shape): the I-beam over its words alone, the arrow on its padding round them, as the old frame's over a
// page's words picked so (show_cursor's sel_at); the arrow over its words where what is over them says the arrow.

///|
/// A page 400 by 300 whose words are picked (words_picked), padded 20 in and 40 down, holding picked_runs 300 wide at
/// its padding's corner; over its top 60, while `glass`, a band of the tree's said to be the arrow (a glass bar).
fn picked_cursor_tester(glass : @signals.Signal[Bool]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(400.0))).height(Is(Some(300.0))).padding(Is((20.0, 40.0, 0.0, 0.0))).lines_up(Is(Some(Start))) |> ignore
      words_picked(page)
      page.box(fn(n) {
        n
        .width(Is(Some(300.0)))
        .words_runs(Is(picked_runs), ink=0x333333FFL, look={ size: 15.0, weight: 400, line: 22.0, wrap: true, tracking: @view.letters_own, balance: false })
        |> ignore
      })
      |> ignore
      page.show(fn() { glass.get() }, fn(g) {
        g.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(60.0))).cursor(Is(Some(Arrow))).points(Is(true)) |> ignore
      })
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "a page whose words are picked: the I-beam over its words, the arrow on its padding, the arrow where a bar over them says so" {
  let glass = @signals.signal(false)
  let t = picked_cursor_tester(glass)
  // (on its words: the I-beam)
  t.move(60.0, 51.0)
  t.draw()
  assert_eq(t.cursor(), IBeam, msg="over its words")
  // (on its padding, the same node, none of its words under the pointer: the arrow)
  t.move(10.0, 20.0)
  t.draw()
  assert_eq(t.cursor(), Arrow, msg="on its padding")
  // (past its words' line, still in it: the arrow)
  t.move(200.0, 200.0)
  t.draw()
  assert_eq(t.cursor(), Arrow, msg="under its words, in it")
  // (a bar over its words said to be the arrow: the arrow, its words under it as they are)
  glass.set(true)
  t.draw()
  t.move(60.0, 51.0)
  t.draw()
  assert_eq(t.cursor(), Arrow, msg="a bar said the arrow over its words")
  // (the bar gone: the I-beam over them again)
  glass.set(false)
  t.draw()
  t.move(61.0, 51.0)
  t.draw()
  assert_eq(t.cursor(), IBeam, msg="the bar gone")
}
